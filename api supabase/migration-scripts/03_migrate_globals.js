#!/usr/bin/env node
/**
 * Migrate Firestore global/platform-level collections → Supabase.
 *
 * Collections:
 *   collab_global_network  → collab_tasks
 *   mail                   → mail_queue
 *   global_staff           → global_staff (cross-tenant uniqueness)
 *   admin_announcements    → admin_announcements
 *   app_feedback           → app_feedback
 *   aduan_sistem           → system_complaints
 *   database_bateri_admin  → platform_config id='battery_db'
 *   lcd_admin              → platform_config id='lcd_db'
 *   config/courier         → platform_config id='courier'
 *   config/toyyibpay       → platform_config id='toyyibpay'
 *   config/pdf_templates   → platform_config id='pdf_templates'
 *   system_settings/pengumuman → system_settings id='pengumuman'
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

const toIso = (v) => {
  if (!v) return null;
  if (typeof v === 'object' && typeof v.toDate === 'function') return v.toDate().toISOString();
  if (typeof v === 'number') return new Date(v).toISOString();
  return null;
};
const str = (v) => (v === null || v === undefined ? null : String(v));

async function tenantIdByOwner(ownerId) {
  const { data } = await sb.from('tenants').select('id').eq('owner_id', ownerId).maybeSingle();
  return data ? data.id : null;
}

async function migrateCollab() {
  const snap = await fs.collection('collab_global_network').get();
  if (snap.empty) return 0;
  const rows = [];
  for (const doc of snap.docs) {
    const d = doc.data();
    // sender format: "{state}-{shopcode}" e.g. "KEL-IZI19" — shop_code = IZI19
    const senderRaw = String(d.sender || d.posterShopID || '').trim();
    let ownerTenantId = null;
    if (senderRaw) {
      const { data: br } = await sb.from('branches').select('tenant_id').eq('shop_code', senderRaw).maybeSingle();
      if (br) ownerTenantId = br.tenant_id;
    }
    if (!ownerTenantId) {
      ownerTenantId = await tenantIdByOwner(d.posterOwnerID || d.ownerID || '');
    }
    if (!ownerTenantId) continue;
    rows.push({
      owner_tenant_id: ownerTenantId,
      poster_shop_id: senderRaw,
      poster_name: str(d.sender_name),
      nama: str(d.namaCust),
      tel: str(d.tel),
      model: str(d.model),
      kerosakan: str(d.kerosakan),
      harga: Number(d.harga || 0),
      status: str(d.status || 'OPEN'),
      archived: d.status === 'ARCHIVED',
      payload: d,
      created_at: toIso(d.timestamp || d.createdAt),
    });
  }
  const { error } = await sb.from('collab_tasks').upsert(rows, { onConflict: 'id' });
  if (error) console.error(`collab_tasks: ${error.message}`);
  return rows.length;
}

async function migrateMail() {
  const snap = await fs.collection('mail').get();
  if (snap.empty) return 0;
  const rows = snap.docs.map((doc) => {
    const d = doc.data();
    return {
      recipient: Array.isArray(d.to) ? d.to.join(',') : str(d.to),
      subject: str(d.message?.subject),
      html: str(d.message?.html),
      text_body: str(d.message?.text),
      delivery_state: str(d.delivery?.state || 'PENDING'),
      created_at: toIso(d.timestamp),
    };
  });
  const { error } = await sb.from('mail_queue').upsert(rows, { onConflict: 'id' });
  if (error) console.error(`mail_queue: ${error.message}`);
  return rows.length;
}

async function migrateGlobalStaff() {
  const snap = await fs.collection('global_staff').get();
  if (snap.empty) return 0;
  const rows = [];
  for (const doc of snap.docs) {
    const d = doc.data();
    const tenantId = await tenantIdByOwner(d.ownerID);
    rows.push({
      tel: str(doc.id),
      nama: str(d.name),
      role: str(d.role || 'staff'),
      tenant_id: tenantId,
      owner_id: str(d.ownerID),
      shop_id: str(d.shopID),
      payload: { pin: d.pin, status: d.status || 'active' },
    });
  }
  const { error } = await sb.from('global_staff').upsert(rows, { onConflict: 'tel' });
  if (error) console.error(`global_staff: ${error.message}`);
  return rows.length;
}

async function migrateAnnouncements() {
  const snap = await fs.collection('admin_announcements').get();
  if (snap.empty) return 0;
  const rows = snap.docs.map((doc) => {
    const d = doc.data();
    return {
      id: doc.id,
      title: str(d.title || d.tajuk),
      body: str(d.body || d.mesej),
      posted_at: toIso(d.timestamp || d.postedAt),
    };
  });
  const { error } = await sb.from('admin_announcements').upsert(rows, { onConflict: 'id' });
  if (error) console.error(`admin_announcements: ${error.message}`);
  return rows.length;
}

async function migrateAppFeedback() {
  const snap = await fs.collection('app_feedback').get();
  if (snap.empty) return 0;
  const rows = [];
  for (const doc of snap.docs) {
    const d = doc.data();
    const tenantId = d.ownerID ? await tenantIdByOwner(d.ownerID) : null;
    rows.push({
      tenant_id: tenantId,
      owner_id: str(d.ownerID),
      subject: str(d.subject || d.tajuk),
      body: str(d.body || d.mesej),
      status: str(d.status || 'OPEN'),
      rating: d.rating ?? null,
      created_at: toIso(d.timestamp || d.createdAt),
    });
  }
  const { error } = await sb.from('app_feedback').upsert(rows, { onConflict: 'id' });
  if (error) console.error(`app_feedback: ${error.message}`);
  return rows.length;
}

async function migrateComplaints() {
  const snap = await fs.collection('aduan_sistem').get();
  if (snap.empty) return 0;
  const rows = [];
  for (const doc of snap.docs) {
    const d = doc.data();
    const tenantId = d.ownerID ? await tenantIdByOwner(d.ownerID) : null;
    rows.push({
      tenant_id: tenantId,
      subject: str(d.subject || d.tajuk),
      description: str(d.description || d.mesej),
      assigned_to: str(d.assignedTo),
      status: str(d.status || 'OPEN'),
      created_at: toIso(d.timestamp || d.createdAt),
    });
  }
  const { error } = await sb.from('system_complaints').upsert(rows, { onConflict: 'id' });
  if (error) console.error(`system_complaints: ${error.message}`);
  return rows.length;
}

async function migratePlatformConfig() {
  const map = [
    ['database_bateri_admin', null, 'battery_db'],
    ['lcd_admin', null, 'lcd_db'],
    ['config', 'courier', 'courier'],
    ['config', 'toyyibpay', 'toyyibpay'],
    ['config', 'pdf_templates', 'pdf_templates'],
  ];
  const rows = [];
  for (const [col, docId, key] of map) {
    if (docId) {
      const snap = await fs.collection(col).doc(docId).get();
      if (snap.exists) rows.push({ id: key, value: snap.data() });
    } else {
      const snap = await fs.collection(col).get();
      if (!snap.empty) rows.push({ id: key, value: { items: snap.docs.map((d) => ({ id: d.id, ...d.data() })) } });
    }
  }
  if (!rows.length) return 0;
  const { error } = await sb.from('platform_config').upsert(rows, { onConflict: 'id' });
  if (error) console.error(`platform_config: ${error.message}`);
  return rows.length;
}

async function migrateSystemSettings() {
  const doc = await fs.collection('system_settings').doc('pengumuman').get();
  if (!doc.exists) return 0;
  const { error } = await sb
    .from('system_settings')
    .upsert([{
      id: 'pengumuman',
      title: str(doc.data().title || doc.data().tajuk),
      message: str(doc.data().message || doc.data().mesej || doc.data().body),
      severity: str(doc.data().severity || 'info'),
      enabled: doc.data().enabled !== false,
    }], { onConflict: 'id' });
  if (error) console.error(`system_settings: ${error.message}`);
  return 1;
}

async function main() {
  console.log('▶ Global collections → Supabase');
  const tasks = [
    ['collab_tasks', migrateCollab],
    ['mail_queue', migrateMail],
    ['global_staff', migrateGlobalStaff],
    ['admin_announcements', migrateAnnouncements],
    ['app_feedback', migrateAppFeedback],
    ['system_complaints', migrateComplaints],
    ['platform_config', migratePlatformConfig],
    ['system_settings', migrateSystemSettings],
  ];
  for (const [name, fn] of tasks) {
    try {
      const n = await fn();
      console.log(`  ✓ ${name}: ${n}`);
    } catch (e) {
      console.error(`  ✗ ${name}: ${e.message}`);
    }
  }
  console.log('✓ Done');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
