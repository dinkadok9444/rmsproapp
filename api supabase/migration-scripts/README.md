# Migration Scripts — Firebase → Supabase

Scripts di folder ni dijalankan **manually** oleh Abe Din (bukan masa runtime app).

## Prasyarat

1. `node` >= 18
2. Firebase service account JSON — download dari Firebase Console → Project Settings → Service Accounts → Generate new private key. Simpan sebagai `firebase-sa.json` (di-gitignore).
3. Supabase service_role key — dari Supabase Dashboard → Settings → API → `service_role` (secret).
4. `.env.migration` dalam folder ni:

```
FIREBASE_SA_PATH=./firebase-sa.json
SUPABASE_URL=https://lpurtgmqecabgwwenikb.supabase.co
SUPABASE_SERVICE_ROLE_KEY=<paste-service-role-here>
```

5. Install deps: `npm install firebase-admin @supabase/supabase-js dotenv`

## Urutan jalankan

1. `npm run auth`    → `01_migrate_auth.js` — saas_dealers + staffList + global_branches → Supabase Auth + `tenants` + `users` + `branches` + `branch_staff`
2. `npm run data`    → `02_migrate_data.js` — per-tenant collections (repairs, inventory, accessories, phone_stock, phone_sales, expenses, jualan_pantas, bookings, losses, refunds, claims, referrals, feedback, trackings, pro_walkin, pro_dealers, dealers). Optional: `node 02_migrate_data.js <ownerId>` untuk satu tenant sahaja.
3. `npm run globals` → `03_migrate_globals.js` — cross-tenant/platform (collab_global_network, mail, global_staff, admin_announcements, app_feedback, aduan_sistem, platform_config keys, system_settings/pengumuman)
4. `npm run verify`  → `04_verify_counts.js` — side-by-side Firestore vs Supabase count per tenant + globals. Exit 0 kalau semua padan.
5. *(Fasa 7.5)* `05_migrate_storage.js` — Firebase Storage → Supabase Storage (belum ditulis)

Semua script idempotent — selamat re-run (upsert on natural keys).

## Synthetic email convention

Supabase Auth perlu email format. Kita guna domain dalaman `@rmspro.internal`:

| Jenis akaun | Email | Password |
|---|---|---|
| Admin (Abe Din) | `admin@rmspro.internal` | dari `saas_dealers/admin.pass` |
| Owner (pemilik kedai) | `{owner_id}@rmspro.internal` | dari `saas_dealers/{id}.pass` |
| Branch (owner@BRANCH) | `owner.{owner_id}.{branch}@rmspro.internal` | dari `global_branches/{id}.pass` |
| Staff (no. telefon) | `staff.{clean_phone}@rmspro.internal` | dari `global_staff/{phone}.pin` |

⚠️ **Password dalam Firestore clear-text** — script ni set sama di Supabase Auth. User dipesan ubah password di Settings lepas migrate.
