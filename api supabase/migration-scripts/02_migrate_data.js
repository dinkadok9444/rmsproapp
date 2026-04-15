#!/usr/bin/env node
/**
 * Migrate per-tenant Firestore collections → Supabase tables.
 *
 * Prasyarat: 01_migrate_auth.js dah jalan (tenants + branches + users wujud).
 *
 * Usage:
 *   node 02_migrate_data.js             # all tenants
 *   node 02_migrate_data.js <ownerId>   # satu tenant je
 *
 * Idempotent via composite natural keys — boleh re-run.
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

const only = process.argv[2] || null;

// ─── Helpers ──────────────────────────────────────────────────────────────────

const toIso = (v) => {
  if (!v) return null;
  if (typeof v === 'object' && typeof v.toDate === 'function') return v.toDate().toISOString();
  if (typeof v === 'number') return new Date(v).toISOString();
  if (typeof v === 'string') {
    const d = new Date(v);
    return isNaN(d.getTime()) ? null : d.toISOString();
  }
  return null;
};
const num = (v, d = 0) => (v === null || v === undefined || v === '' ? d : Number(v) || d);
const str = (v) => (v === null || v === undefined ? null : String(v));
const chunk = (arr, n) => {
  const out = [];
  for (let i = 0; i < arr.length; i += n) out.push(arr.slice(i, i + n));
  return out;
};

async function bulkUpsert(table, rows, onConflict) {
  if (!rows.length) return 0;
  let inserted = 0;
  for (const batch of chunk(rows, 500)) {
    const q = sb.from(table).upsert(batch, { onConflict, ignoreDuplicates: false });
    const { error } = await q;
    if (error) {
      console.error(`  ! ${table} batch fail: ${error.message}`);
      // try row-by-row to isolate
      for (const r of batch) {
        const { error: e2 } = await sb.from(table).upsert(r, { onConflict });
        if (e2) console.error(`    row fail [${JSON.stringify(r).slice(0, 120)}]: ${e2.message}`);
        else inserted++;
      }
    } else {
      inserted += batch.length;
    }
  }
  return inserted;
}

async function getBranchMap(tenantId) {
  const { data, error } = await sb
    .from('branches')
    .select('id, shop_code')
    .eq('tenant_id', tenantId);
  if (error) throw error;
  const m = new Map();
  for (const b of data) m.set(String(b.shop_code).toUpperCase(), b.id);
  return m;
}

async function resolveDefaultBranchId(tenantId, branchMap, shopField) {
  if (shopField) {
    const key = String(shopField).toUpperCase();
    if (branchMap.has(key)) return branchMap.get(key);
  }
  // fallback: pertama branch tenant ini
  const first = branchMap.values().next();
  return first.done ? null : first.value;
}

// ─── Per-collection migrators ─────────────────────────────────────────────────

async function migrateJobs(ownerId, tenantId, branchMap) {
  const snap = await fs.collection(`repairs_${ownerId}`).get();
  if (snap.empty) return 0;
  const rows = [];
  for (const doc of snap.docs) {
    const d = doc.data();
    const branchId = await resolveDefaultBranchId(tenantId, branchMap, d.shopID || d.shop);
    if (!branchId) continue;
    const catatanText = d.catatan
      ? String(d.catatan)
      : d.notes
        ? (typeof d.notes === 'string' ? d.notes : JSON.stringify(d.notes))
        : null;
    rows.push({
      tenant_id: tenantId,
      branch_id: branchId,
      siri: doc.id,
      nama: str(d.nama || d.pelanggan || d.customerName),
      tel: str(d.tel || d.telefon || d.phone || d.no_tel || d.noTel || d.hp),
      model: str(d.model || d.device),
      kerosakan: str(d.kerosakan || d.masalah || d.issue || d.fault || d.problem),
      status: str(d.status || 'IN PROGRESS'),
      payment_status: str(d.paymentStatus || 'PENDING'),
      harga: num(d.harga),
      deposit: num(d.deposit),
      total: num(d.total || d.harga),
      baki: num(d.baki),
      catatan: catatanText,
      created_at: toIso(d.timestamp || d.createdAt),
      updated_at: toIso(d.updatedAt),
    });
  }
  return bulkUpsert('jobs', rows, 'tenant_id,siri');
}

async function migrateStockParts(ownerId, tenantId, branchMap) {
  const snap = await fs.collection(`inventory_${ownerId}`).get();
  if (snap.empty) return 0;
  const rows = [];
  for (const doc of snap.docs) {
    const d = doc.data();
    const branchId = await resolveDefaultBranchId(tenantId, branchMap, d.shopID);
    if (!branchId) continue;
    rows.push({
      tenant_id: tenantId,
      branch_id: branchId,
      sku: str(d.kod || doc.id),
      part_name: str(d.nama),
      qty: num(d.qty),
      price: num(d.jual),
      cost: num(d.kos),
      category: str(d.kategori),
      created_at: toIso(d.createdAt),
    });
  }
  return bulkUpsert('stock_parts', rows, 'id');
}

async function migrateAccessories(ownerId, tenantId, branchMap) {
  const snap = await fs.collection(`accessories_${ownerId}`).get();
  if (snap.empty) return 0;
  const rows = [];
  for (const doc of snap.docs) {
    const d = doc.data();
    const branchId = await resolveDefaultBranchId(tenantId, branchMap, d.shopID);
    if (!branchId) continue;
    rows.push({
      tenant_id: tenantId,
      branch_id: branchId,
      sku: str(d.kod || doc.id),
      item_name: str(d.nama),
      qty: num(d.qty),
      price: num(d.jual),
      cost: num(d.kos),
      created_at: toIso(d.createdAt),
    });
  }
  return bulkUpsert('accessories', rows, 'id');
}

async function migratePhoneStock(ownerId, tenantId, branchMap) {
  const snap = await fs.collection(`phone_stock_${ownerId}`).get();
  if (snap.empty) return 0;
  const rows = [];
  for (const doc of snap.docs) {
    const d = doc.data();
    const branchId = await resolveDefaultBranchId(tenantId, branchMap, d.shopID);
    if (!branchId) continue;
    rows.push({
      tenant_id: tenantId,
      branch_id: branchId,
      device_name: str(d.nama),
      price: num(d.jual),
      cost: num(d.kos),
      qty: num(d.qty, 1),
      status: str(d.status || 'AVAILABLE'),
      condition: str(d.condition || 'NEW'),
      added_by: str(d.addedBy || d.supplier),
      created_at: toIso(d.createdAt),
    });
  }
  return bulkUpsert('phone_stock', rows, 'id');
}

async function migratePhoneSales(ownerId, tenantId, branchMap) {
  const active = await fs.collection(`phone_sales_${ownerId}`).get();
  const trash = await fs.collection(`phone_sales_trash_${ownerId}`).get();
  const docs = [...active.docs.map((d) => ({ d, deleted: false })), ...trash.docs.map((d) => ({ d, deleted: true }))];
  if (!docs.length) return 0;
  const rows = [];
  for (const { d: doc, deleted } of docs) {
    const d = doc.data();
    const branchId = await resolveDefaultBranchId(tenantId, branchMap, d.shopID);
    if (!branchId) continue;
    rows.push({
      tenant_id: tenantId,
      branch_id: branchId,
      device_name: str(d.nama),
      customer_name: str(d.pembeli || d.customerName),
      customer_phone: str(d.tel),
      price_per_unit: num(d.harga),
      total_price: num(d.total || d.harga),
      sold_at: toIso(d.tarikh || d.timestamp),
      deleted_at: deleted ? toIso(d.deletedAt) || new Date().toISOString() : null,
      notes: JSON.stringify({ imei: d.imei, kod: d.kod, siri: d.siri, kos: d.kos }),
    });
  }
  return bulkUpsert('phone_sales', rows, 'id');
}

async function migrateExpenses(ownerId, tenantId, branchMap) {
  const snap = await fs.collection(`expenses_${ownerId}`).get();
  if (snap.empty) return 0;
  const rows = [];
  for (const doc of snap.docs) {
    const d = doc.data();
    const branchId = await resolveDefaultBranchId(tenantId, branchMap, d.shopID);
    if (!branchId) continue;
    rows.push({
      tenant_id: tenantId,
      branch_id: branchId,
      description: str(d.perkara || d.description),
      amount: num(d.jumlah || d.amount),
      paid_by: str(d.staff || d.paidBy),
      status: str(d.status || 'ACTIVE'),
      created_at: toIso(d.tarikh || d.timestamp),
    });
  }
  return bulkUpsert('expenses', rows, 'id');
}

async function migrateQuickSales(ownerId, tenantId, branchMap) {
  const snap = await fs.collection(`jualan_pantas_${ownerId}`).get();
  if (snap.empty) return 0;
  const rows = [];
  for (const doc of snap.docs) {
    const d = doc.data();
    const branchId = await resolveDefaultBranchId(tenantId, branchMap, d.shopID);
    if (!branchId) continue;
    rows.push({
      tenant_id: tenantId,
      branch_id: branchId,
      kind: str(d.kind || 'SALE'),
      description: str(d.siri || d.perkara),
      amount: num(d.harga || d.jumlah),
      sold_by: str(d.staff || d.soldBy),
      sold_at: toIso(d.tarikh || d.timestamp),
      payment_method: str(d.cara || d.paymentMethod),
      created_at: toIso(d.tarikh || d.timestamp),
    });
  }
  return bulkUpsert('quick_sales', rows, 'id');
}

async function migrateBookings(ownerId, tenantId, branchMap) {
  const rows = [];
  for (const coll of [`customer_forms_${ownerId}`, `bookings_${ownerId}`]) {
    const snap = await fs.collection(coll).get();
    for (const doc of snap.docs) {
      const d = doc.data();
      const branchId = await resolveDefaultBranchId(tenantId, branchMap, d.shopID);
      if (!branchId) continue;
      rows.push({
        tenant_id: tenantId,
        branch_id: branchId,
        nama: str(d.nama) || 'UNKNOWN',
        tel: str(d.tel) || '-',
        model: str(d.model),
        kerosakan: str(d.kerosakan || d.issue),
        status: str(d.status || 'PENDING'),
        notes: JSON.stringify({ siri: d.siriBooking || doc.id, raw: d }),
        created_at: toIso(d.timestamp || d.createdAt),
      });
    }
  }
  return bulkUpsert('bookings', rows, 'id');
}

async function migrateLosses(ownerId, tenantId, branchMap) {
  const snap = await fs.collection(`losses_${ownerId}`).get();
  if (snap.empty) return 0;
  const rows = [];
  for (const doc of snap.docs) {
    const d = doc.data();
    const branchId = await resolveDefaultBranchId(tenantId, branchMap, d.shopID);
    if (!branchId) continue;
    rows.push({
      tenant_id: tenantId,
      branch_id: branchId,
      item_type: str(d.jenis),
      item_name: str(d.nama || d.item),
      quantity: num(d.qty, 1),
      estimated_value: num(d.jumlah),
      reason: str(d.keterangan),
      reported_by: str(d.staff || d.reportedBy),
      status: str(d.status || 'REPORTED'),
      notes: str(d.siri),
      created_at: toIso(d.tarikh || d.timestamp),
    });
  }
  return bulkUpsert('losses', rows, 'id');
}

async function migrateRefunds(ownerId, tenantId, branchMap) {
  const snap = await fs.collection(`refunds_${ownerId}`).get();
  if (snap.empty) return 0;
  const rows = [];
  for (const doc of snap.docs) {
    const d = doc.data();
    const branchId = await resolveDefaultBranchId(tenantId, branchMap, d.shopID);
    if (!branchId) continue;
    rows.push({
      tenant_id: tenantId,
      branch_id: branchId,
      siri: str(d.siri || doc.id),
      nama: str(d.nama),
      refund_amount: num(d.amount || d.jumlah),
      refund_status: str(d.status || 'PENDING'),
      reason: str(d.reason || d.sebab),
      processed_by: str(d.staff || d.processedBy),
      created_at: toIso(d.tarikh || d.timestamp),
    });
  }
  return bulkUpsert('refunds', rows, 'id');
}

async function migrateClaims(ownerId, tenantId, branchMap) {
  const snap = await fs.collection(`claims_${ownerId}`).get();
  if (snap.empty) return 0;
  const rows = [];
  for (const doc of snap.docs) {
    const d = doc.data();
    const branchId = await resolveDefaultBranchId(tenantId, branchMap, d.shopID);
    if (!branchId) continue;
    rows.push({
      tenant_id: tenantId,
      branch_id: branchId,
      claim_code: str(doc.id),
      siri: str(d.siri),
      nama: str(d.nama),
      claim_status: str(d.status || 'PENDING'),
      catatan: typeof d.catatan === 'string' ? d.catatan : JSON.stringify(d),
      created_at: toIso(d.tarikh || d.timestamp),
    });
  }
  return bulkUpsert('claims', rows, 'id');
}

async function migrateReferrals(ownerId, tenantId, branchMap) {
  const snap = await fs.collection(`referrals_${ownerId}`).get();
  if (snap.empty) return 0;
  const rows = [];
  for (const doc of snap.docs) {
    const d = doc.data();
    rows.push({
      tenant_id: tenantId,
      code: str(d.refCode || doc.id),
      used_count: num(d.usedCount),
      created_by: JSON.stringify({
        bank: d.bank,
        accNo: d.accNo,
        commission: d.commission,
        nama: d.nama,
        tel: d.tel,
      }),
      created_at: toIso(d.createdAt),
    });
  }
  return bulkUpsert('referrals', rows, 'tenant_id,code');
}

async function migrateCustomerFeedback(ownerId, tenantId, branchMap) {
  const snap = await fs.collection(`feedback_${ownerId}`).get();
  if (snap.empty) return 0;
  const rows = [];
  for (const doc of snap.docs) {
    const d = doc.data();
    const branchId = await resolveDefaultBranchId(tenantId, branchMap, d.shopID);
    if (!branchId) continue;
    rows.push({
      tenant_id: tenantId,
      branch_id: branchId,
      siri: str(d.siri || doc.id),
      nama: str(d.nama),
      tel: str(d.tel),
      rating: num(d.rating),
      komen: str(d.komen),
      payload: d,
      created_at: toIso(d.timestamp || d.createdAt),
    });
  }
  return bulkUpsert('customer_feedback', rows, 'id');
}

async function migratePosTrackings(ownerId, tenantId, branchMap) {
  const snap = await fs.collection(`trackings_${ownerId}`).get();
  if (snap.empty) return 0;
  const rows = [];
  for (const doc of snap.docs) {
    const d = doc.data();
    const branchId = await resolveDefaultBranchId(tenantId, branchMap, d.shopID);
    if (!branchId) continue;
    rows.push({
      tenant_id: tenantId,
      branch_id: branchId,
      tarikh: str(d.tarikh),
      item: str(d.item || d.nama),
      kurier: str(d.kurier || d.courier),
      track_no: str(d.trackNo || d.trackingNo || doc.id),
      status_track: str(d.status || d.statusTrack || 'DIPOS'),
      payload: d,
      created_at: toIso(d.timestamp || d.createdAt),
    });
  }
  return bulkUpsert('pos_trackings', rows, 'id');
}

async function migrateProWalkin(ownerId, tenantId, branchMap) {
  const snap = await fs.collection(`pro_walkin_${ownerId}`).get();
  if (snap.empty) return 0;
  const rows = [];
  for (const doc of snap.docs) {
    const d = doc.data();
    const branchId = await resolveDefaultBranchId(tenantId, branchMap, d.shopID);
    if (!branchId) continue;
    rows.push({
      tenant_id: tenantId,
      branch_id: branchId,
      payload: d,
      status: str(d.status || 'PENDING'),
      created_at: toIso(d.timestamp || d.createdAt),
    });
  }
  return bulkUpsert('pro_walkin', rows, 'id');
}

async function migrateProDealers(ownerId, tenantId, branchMap) {
  const snap = await fs.collection(`pro_dealers_${ownerId}`).get();
  if (snap.empty) return 0;
  const rows = [];
  for (const doc of snap.docs) {
    const d = doc.data();
    const branchId = await resolveDefaultBranchId(tenantId, branchMap, d.shopID);
    if (!branchId) continue;
    rows.push({
      tenant_id: tenantId,
      branch_id: branchId,
      nama: str(d.nama),
      tel: str(d.tel),
      payload: d,
    });
  }
  return bulkUpsert('pro_dealers', rows, 'id');
}

async function migrateDealers(ownerId, tenantId, branchMap) {
  const snap = await fs.collection(`dealers_${ownerId}`).get();
  if (snap.empty) return 0;
  const rows = [];
  for (const doc of snap.docs) {
    const d = doc.data();
    const branchId = await resolveDefaultBranchId(tenantId, branchMap, d.shopID);
    if (!branchId) continue;
    rows.push({
      tenant_id: tenantId,
      branch_id: branchId,
      nama_pemilik: str(d.namaPemilik),
      nama_kedai: str(d.namaKedai),
      no_ssm: str(d.noSSM),
      cawangan: d.cawangan || [],
    });
  }
  return bulkUpsert('dealers', rows, 'id');
}

// ─── Per-tenant pipeline ─────────────────────────────────────────────────────

const TASKS = [
  ['jobs', migrateJobs],
  ['stock_parts', migrateStockParts],
  ['accessories', migrateAccessories],
  ['phone_stock', migratePhoneStock],
  ['phone_sales', migratePhoneSales],
  ['expenses', migrateExpenses],
  ['quick_sales', migrateQuickSales],
  ['bookings', migrateBookings],
  ['losses', migrateLosses],
  ['refunds', migrateRefunds],
  ['claims', migrateClaims],
  ['referrals', migrateReferrals],
  ['customer_feedback', migrateCustomerFeedback],
  ['pos_trackings', migratePosTrackings],
  ['pro_walkin', migrateProWalkin],
  ['pro_dealers', migrateProDealers],
  ['dealers', migrateDealers],
];

async function migrateTenant(ownerId) {
  const { data: tenant, error } = await sb
    .from('tenants')
    .select('id')
    .eq('owner_id', ownerId)
    .single();
  if (error || !tenant) {
    console.error(`[skip] ${ownerId}: tenant row tak wujud (run 01_migrate_auth.js dulu)`);
    return;
  }
  const tenantId = tenant.id;
  const branchMap = await getBranchMap(tenantId);
  if (!branchMap.size) {
    console.warn(`[warn] ${ownerId}: tiada branch — skip`);
    return;
  }

  console.log(`\n▶ ${ownerId} (tenant=${tenantId}, branches=${branchMap.size})`);
  for (const [name, fn] of TASKS) {
    try {
      const n = await fn(ownerId, tenantId, branchMap);
      if (n > 0) console.log(`  ✓ ${name}: ${n}`);
    } catch (e) {
      console.error(`  ✗ ${name}: ${e.message}`);
    }
  }
}

async function main() {
  console.log('▶ Firestore per-tenant data → Supabase');
  let ownerIds;
  if (only) {
    ownerIds = [only];
  } else {
    const snap = await fs.collection('saas_dealers').get();
    ownerIds = snap.docs.map((d) => d.id).filter((id) => id !== 'admin');
  }
  console.log(`Tenants to migrate: ${ownerIds.length}`);
  for (const id of ownerIds) await migrateTenant(id);
  console.log('\n✓ Done');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
