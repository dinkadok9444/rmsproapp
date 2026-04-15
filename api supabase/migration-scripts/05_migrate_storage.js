#!/usr/bin/env node
/**
 * Migrate Firebase Storage files → Supabase Storage.
 *
 * Strategy:
 *   Firebase Storage folders → Supabase buckets (same folder name):
 *     inventory/{ownerID}/...      → inventory/{ownerID}/...
 *     accessories/{ownerID}/...    → accessories/{ownerID}/...
 *     phone_stock/{ownerID}/...    → phone_stock/{ownerID}/...
 *     repairs/{ownerID}/{siri}/... → repairs/{ownerID}/{siri}/...
 *     booking_settings/...         → booking_settings/...
 *     pdf_templates/...            → pdf_templates/...
 *     staff_avatars/...            → staff_avatars/...
 *     pos_settings/...             → pos_settings/...
 *
 * Download stream dari FB Storage, upload terus ke Supabase (no local temp).
 * Idempotent — upsert: true.
 *
 * Optional: ganti `phone_receipts.invoice_url` dan field lain yang store URL lama
 *   — script ni tak touch DB, cuma copy files + print URL mapping ke stdout.
 */

require('dotenv').config({ path: '.env.migration' });
const admin = require('firebase-admin');
const { createClient } = require('@supabase/supabase-js');

const sa = require(process.env.FIREBASE_SA_PATH);
admin.initializeApp({
  credential: admin.credential.cert(sa),
  storageBucket: process.env.FIREBASE_STORAGE_BUCKET || `${sa.project_id}.appspot.com`,
});

const bucket = admin.storage().bucket();

const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

const BUCKETS = [
  'inventory',
  'accessories',
  'phone_stock',
  'repairs',
  'booking_settings',
  'pdf_templates',
  'staff_avatars',
  'pos_settings',
];

async function streamToBuffer(stream) {
  const chunks = [];
  for await (const c of stream) chunks.push(c);
  return Buffer.concat(chunks);
}

async function migrateBucket(prefix) {
  const [files] = await bucket.getFiles({ prefix: `${prefix}/` });
  if (!files.length) {
    console.log(`  (kosong) ${prefix}`);
    return { ok: 0, fail: 0 };
  }
  let ok = 0, fail = 0;
  for (const f of files) {
    const path = f.name.substring(prefix.length + 1); // strip "prefix/"
    if (!path) continue;
    try {
      const buf = await streamToBuffer(f.createReadStream());
      const contentType = f.metadata.contentType || 'application/octet-stream';
      const { error } = await sb.storage
        .from(prefix)
        .uploadBinary
        ? await sb.storage.from(prefix).uploadBinary(path, buf, { contentType, upsert: true })
        : await sb.storage.from(prefix).upload(path, buf, { contentType, upsert: true });
      if (error) {
        console.error(`    ✗ ${f.name}: ${error.message}`);
        fail++;
      } else {
        ok++;
      }
    } catch (e) {
      console.error(`    ✗ ${f.name}: ${e.message}`);
      fail++;
    }
  }
  console.log(`  ✓ ${prefix}: ok=${ok} fail=${fail}`);
  return { ok, fail };
}

async function main() {
  console.log('▶ Firebase Storage → Supabase Storage');
  let totalOk = 0, totalFail = 0;
  for (const b of BUCKETS) {
    const { ok, fail } = await migrateBucket(b);
    totalOk += ok;
    totalFail += fail;
  }
  console.log(`\n✓ Done — migrated=${totalOk} failed=${totalFail}`);
  process.exit(totalFail === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
