#!/usr/bin/env node
/**
 * Verify row counts: Firestore vs Supabase side-by-side per tenant.
 *
 * Output CSV-ish table so Abe Din nampak mana yang short.
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

const PER_TENANT = [
  ['repairs', 'jobs'],
  ['inventory', 'stock_parts'],
  ['accessories', 'accessories'],
  ['phone_stock', 'phone_stock'],
  ['phone_sales', 'phone_sales'],
  ['expenses', 'expenses'],
  ['jualan_pantas', 'quick_sales'],
  ['bookings', 'bookings'],
  ['losses', 'losses'],
  ['refunds', 'refunds'],
  ['claims', 'claims'],
  ['referrals', 'referrals'],
  ['feedback', 'customer_feedback'],
  ['trackings', 'pos_trackings'],
  ['pro_walkin', 'pro_walkin'],
  ['pro_dealers', 'pro_dealers'],
  ['dealers', 'dealers'],
];

const GLOBALS = [
  ['collab_global_network', 'collab_tasks'],
  ['mail', 'mail_queue'],
  ['global_staff', 'global_staff'],
  ['admin_announcements', 'admin_announcements'],
  ['app_feedback', 'app_feedback'],
  ['aduan_sistem', 'system_complaints'],
];

async function fsCount(coll) {
  const s = await fs.collection(coll).count().get();
  return s.data().count;
}

async function sbCount(table, filter) {
  let q = sb.from(table).select('*', { count: 'exact', head: true });
  if (filter) q = q.eq(filter.col, filter.val);
  const { count, error } = await q;
  if (error) return `ERR:${error.message.slice(0, 20)}`;
  return count;
}

async function main() {
  console.log('▶ Verify counts Firestore vs Supabase\n');

  const dealerSnap = await fs.collection('saas_dealers').get();
  const tenants = [];
  for (const d of dealerSnap.docs) {
    if (d.id === 'admin') continue;
    const { data } = await sb.from('tenants').select('id').eq('owner_id', d.id).maybeSingle();
    if (data) tenants.push({ ownerId: d.id, tenantId: data.id });
  }

  console.log(`─── Per-tenant (${tenants.length} tenants) ───`);
  console.log('ownerId\ttable\tfs\tsb\tdiff');
  let mismatches = 0;
  for (const { ownerId, tenantId } of tenants) {
    for (const [fsColl, sbTable] of PER_TENANT) {
      const fsN = await fsCount(`${fsColl}_${ownerId}`);
      const sbN = await sbCount(sbTable, { col: 'tenant_id', val: tenantId });
      const diff = typeof sbN === 'number' ? fsN - sbN : '?';
      if (diff !== 0) mismatches++;
      const mark = diff === 0 ? '✓' : '✗';
      if (fsN > 0 || (typeof sbN === 'number' && sbN > 0)) {
        console.log(`${ownerId}\t${sbTable}\t${fsN}\t${sbN}\t${diff}\t${mark}`);
      }
    }
  }

  console.log('\n─── Globals ───');
  console.log('table\tfs\tsb\tdiff');
  for (const [fsColl, sbTable] of GLOBALS) {
    const fsN = await fsCount(fsColl);
    const sbN = await sbCount(sbTable, null);
    const diff = typeof sbN === 'number' ? fsN - sbN : '?';
    if (diff !== 0) mismatches++;
    console.log(`${sbTable}\t${fsN}\t${sbN}\t${diff}`);
  }

  console.log(`\n${mismatches === 0 ? '✓ ALL MATCH' : `✗ ${mismatches} mismatch(es)`}`);
  process.exit(mismatches === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
