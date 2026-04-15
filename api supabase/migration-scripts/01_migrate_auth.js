#!/usr/bin/env node
/**
 * Migrate Firestore dealers + staff → Supabase Auth + tenants/users/branches/branch_staff.
 *
 * Usage:
 *   cd "api supabase/migration-scripts"
 *   npm install firebase-admin @supabase/supabase-js dotenv
 *   node 01_migrate_auth.js
 *
 * Idempotent: boleh jalan berulang — skip kalau auth user dah wujud.
 */

require('dotenv').config({ path: '.env.migration' });
const admin = require('firebase-admin');
const { createClient } = require('@supabase/supabase-js');

const sa = require(process.env.FIREBASE_SA_PATH);
admin.initializeApp({ credential: admin.credential.cert(sa) });
const fs = admin.firestore();

const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

const DOMAIN = 'rmspro.internal';

async function ensureAuthUser(email, password, meta) {
  // Check if already exists via admin.listUsers (paginate) — simpler: try create, catch duplicate
  const { data, error } = await sb.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: meta,
  });
  if (error) {
    if (error.message && error.message.toLowerCase().includes('already')) {
      // Fetch existing
      const { data: list } = await sb.auth.admin.listUsers({ page: 1, perPage: 1000 });
      const existing = list.users.find((u) => u.email === email);
      if (existing) return existing.id;
    }
    throw new Error(`Auth create failed for ${email}: ${error.message}`);
  }
  return data.user.id;
}

async function upsertTenant(ownerId, dealerData) {
  const payload = {
    owner_id: ownerId,
    nama_kedai: dealerData.namaKedai || ownerId,
    domain: dealerData.domain || null,
    domain_status: dealerData.domainStatus || 'PENDING_DNS',
    dns_records: dealerData.dnsRecords || [],
    status: dealerData.status || 'Aktif',
    single_staff_mode: !!dealerData.singleStaffMode,
    expire_date: dealerData.expireDate ? new Date(dealerData.expireDate).toISOString() : null,
    addon_gallery: !!dealerData.addonGallery,
    gallery_expire: dealerData.galleryExpire
      ? new Date(dealerData.galleryExpire).toISOString()
      : null,
    bot_whatsapp: dealerData.botWhatsapp || {},
    total_sales: dealerData.totalSales || 0,
    ticket_count: dealerData.ticketCount || 0,
    last_sale_at: dealerData.lastSaleAt ? new Date(dealerData.lastSaleAt).toISOString() : null,
    config: dealerData.config || {},
  };
  const { data, error } = await sb
    .from('tenants')
    .upsert(payload, { onConflict: 'owner_id' })
    .select('id')
    .single();
  if (error) throw new Error(`tenant upsert ${ownerId}: ${error.message}`);
  return data.id;
}

async function upsertUserRow(authId, tenantId, role, extra = {}) {
  const { error } = await sb.from('users').upsert(
    {
      id: authId,
      tenant_id: tenantId,
      role,
      ...extra,
    },
    { onConflict: 'id' }
  );
  if (error) throw new Error(`users upsert ${authId}: ${error.message}`);
}

async function upsertBranch(tenantId, shopCode, shopData) {
  const payload = {
    tenant_id: tenantId,
    shop_code: shopCode,
    nama_kedai: shopData.shopName || shopData.namaKedai || shopCode,
    alamat: shopData.address || shopData.alamat,
    phone: shopData.phone || shopData.ownerContact,
    email: shopData.email || shopData.emel,
    logo_base64: shopData.logoBase64,
    enabled_modules: shopData.enabledModules || {},
    single_staff_mode: !!shopData.singleStaffMode,
    expire_date: shopData.expireDate ? new Date(shopData.expireDate).toISOString() : null,
  };
  const { data, error } = await sb
    .from('branches')
    .upsert(payload, { onConflict: 'tenant_id,shop_code' })
    .select('id')
    .single();
  if (error) throw new Error(`branch upsert ${shopCode}: ${error.message}`);
  return data.id;
}

async function migrateDealers() {
  const snap = await fs.collection('saas_dealers').get();
  console.log(`[dealers] ${snap.size} docs`);

  for (const doc of snap.docs) {
    const ownerId = doc.id;
    const d = doc.data();
    const password = d.pass || d.password;
    if (!password) {
      console.warn(`[skip] ${ownerId}: no password`);
      continue;
    }

    try {
      // 1. Auth user for owner
      const ownerEmail =
        ownerId === 'admin' ? `admin@${DOMAIN}` : `${ownerId.toLowerCase()}@${DOMAIN}`;
      const role = ownerId === 'admin' ? 'admin' : 'owner';
      const authId = await ensureAuthUser(ownerEmail, password, { owner_id: ownerId, role });

      // 2. Tenant row (skip for admin)
      let tenantId = null;
      if (ownerId !== 'admin') {
        tenantId = await upsertTenant(ownerId, d);
      }

      // 3. users row linking auth → tenant
      await upsertUserRow(authId, tenantId, role, {
        email: d.email || d.emel || null,
        nama: d.ownerName || d.namaKedai || null,
      });

      // 4. Migrate shops_{ownerID} → branches
      if (tenantId) {
        const shopsSnap = await fs.collection(`shops_${ownerId}`).get();
        for (const shopDoc of shopsSnap.docs) {
          const branchId = await upsertBranch(tenantId, shopDoc.id, shopDoc.data());

          // 5. Branch login (global_branches/{ownerId}@{shopId}) — separate auth user
          const branchKey = `${ownerId}@${shopDoc.id}`;
          const branchLogin = await fs
            .collection('global_branches')
            .doc(branchKey)
            .get();
          if (branchLogin.exists && branchLogin.data().pass) {
            const branchEmail = `owner.${ownerId.toLowerCase()}.${shopDoc.id.toUpperCase()}@${DOMAIN}`;
            const bAuthId = await ensureAuthUser(branchEmail, branchLogin.data().pass, {
              owner_id: ownerId,
              shop_code: shopDoc.id,
              role: 'owner',
            });
            await upsertUserRow(bAuthId, tenantId, 'owner', {
              current_branch_id: branchId,
            });
          }

          // 6. staffList embedded array → branch_staff rows
          const staffList = shopDoc.data().staffList || [];
          for (const s of staffList) {
            if (!s.phone || !s.pin) continue;
            const clean = String(s.phone).replace(/[\s\-()]/g, '');
            const staffEmail = `staff.${clean}@${DOMAIN}`;
            const sAuthId = await ensureAuthUser(staffEmail, s.pin, {
              owner_id: ownerId,
              shop_code: shopDoc.id,
              phone: clean,
              role: s.role || 'staff',
            });
            await upsertUserRow(sAuthId, tenantId, s.role || 'staff', {
              phone: clean,
              nama: s.name,
              status: s.status || 'active',
              current_branch_id: branchId,
            });
            await sb.from('branch_staff').upsert(
              {
                tenant_id: tenantId,
                branch_id: branchId,
                user_id: sAuthId,
                nama: s.name,
                phone: clean,
                pin: s.pin,
                role: s.role || 'staff',
                status: s.status || 'active',
              },
              { onConflict: 'id' }
            );
          }
        }
      }

      console.log(`[ok] ${ownerId}`);
    } catch (e) {
      console.error(`[fail] ${ownerId}:`, e.message);
    }
  }
}

async function main() {
  console.log('▶ Firestore → Supabase Auth migration');
  await migrateDealers();
  console.log('✓ Done');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
