# API Supabase — Rujukan & Migration Plan

Folder ni simpan credentials, rujukan, dan **full task plan** untuk migrasi Firestore → Supabase projek **rms-pro-flutter**.
Tujuan: Claude (assistant) atau agent lain boleh rujuk balik pada future conversation.

⚠️ **PENTING**: Repo ni **PRIVATE**. Jangan tukar ke public selagi file ni ada credentials.

---

## 📌 Project Info

- **Project Ref**: `lpurtgmqecabgwwenikb`
- **Project URL**: `https://lpurtgmqecabgwwenikb.supabase.co`
- **Region**: (isi bila tahu)
- **Created**: 2026-04-15
- **Owner**: Abe Din (dinkadok9444)

## 🏢 Multi-Tenant SaaS Architecture

**Projek ni SaaS multi-tenant** — tiap customer (kedai) boleh bawa **custom domain sendiri** (e.g. `profixmobile.my`, `repairshop.com`).

### Current (Firebase)
- Firebase Functions: `getDomains`, `getDealers` endpoints
- Firestore collection `domains` / `dealers` store mapping
- Firebase Hosting multi-site handle tenant

### Target (Post-Migration)
- **Cloudflare for SaaS** — Custom Hostname feature, unlimited tenants
- SSL auto-provisioned per tenant domain
- Cost: **FREE ≤ 1000 hostname**, $0.10/hostname lepas tu
- Tenant data: Supabase table `tenants`

### Flow
```
profixmobile.my (tenant custom domain)
  ↓ CNAME → rmspro.pages.dev (atau Cloudflare SaaS hostname)
Cloudflare for SaaS resolve → Pages project `rmspro-web`
  ↓
Frontend baca window.location.hostname
  ↓
Query Supabase: SELECT * FROM tenants WHERE domain = ?
  ↓
Inject tenant branding/config/data
```

### Schema (Fasa 2)
```sql
CREATE TABLE tenants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  domain text UNIQUE NOT NULL,        -- profixmobile.my
  subdomain text UNIQUE,              -- profixmobile (for rmspro.net/profixmobile fallback)
  nama_kedai text NOT NULL,
  config jsonb DEFAULT '{}',          -- branding, settings
  cloudflare_hostname_id text,        -- from CF API
  ssl_status text DEFAULT 'pending',
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX tenants_domain_idx ON tenants(domain);
CREATE INDEX tenants_subdomain_idx ON tenants(subdomain);
```

### Code Changes
- Migrate `rmsproapp/lib/screens/admin_modules/domain_management_screen.dart` → Supabase query table `tenants`
- Migrate Firebase Functions `getDomains`/`getDealers` → Supabase RPC atau direct query
- Tenant domain add/remove → call Cloudflare Custom Hostname API (dari admin panel)
- Tiap query data app → filter by `tenant_id` (foreign key dalam semua table)

---

## 🌐 Domain & Hosting

- **Domain**: `rmspro.net`
- **Registrar + DNS**: **Cloudflare**
- **Current hosting**: Firebase Hosting (project `rmspro-2f454`, IP `199.36.158.100`)
- **Target hosting**: **Cloudflare Pages** — ONE project serve semua

### URL Structure (Final)

| URL | Serve | Auth | Source folder |
|---|---|---|---|
| `rmspro.net/` | Staff login + dashboard | Public login, protected dalam | `web_app/` |
| `rmspro.net/tracking` | Customer check status repair | ❌ Public | `rmsproapp/public/tracking.html` |
| `rmspro.net/booking` | Customer borang booking online | ❌ Public | `rmsproapp/public/borang_booking.html` |
| `rmspro.net/catalog` | Customer browse catalog | ❌ Public | `rmsproapp/public/catalog/` |
| `rmspro.net/promote` | Landing page promosi | ❌ Public | `rmsproapp/public/promote/` |
| `rmspro.net/form` | Borang pelanggan | ❌ Public | `rmsproapp/public/borangpelanggan/` |
| `rmspro.net/link` | Link shortener | ❌ Public | `rmsproapp/public/link.html` |

**Flutter mobile app (Android/iOS)** — takde URL, access Supabase API terus.

### Flutter Web — DROP
- `rmsproapp/build/web` + `rmsproapp/firebase.json` hosting config → **remove**.
- Flutter = mobile platform sahaja (Android + iOS).

### Public Pages Strategy
- Public pages (tracking, booking, catalog) akses Supabase guna **anon key**.
- **RLS policies khas** untuk public access:
  - `tracking`: read job status by `job_id + phone` (no list all)
  - `booking`: insert-only, no select/update (customer takleh baca booking orang lain)
  - `catalog`: read-only product list (public)
  - Rate limit via Cloudflare (kalau perlu)

## 🔑 Credentials

### Anon (public) key
Guna dalam Flutter (`rmsproapp`) dan web_app. Selamat client-side **kalau RLS enabled**.

```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxwdXJ0Z21xZWNhYmd3d2VuaWtiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYxODQ2MTUsImV4cCI6MjA5MTc2MDYxNX0.7FiqQwNJC6XXv0r8Emmt9KyygOnHfSrXVirsJBIsdhU
```

- Role: `anon`
- Issued: 1776184615 (2026-04-15)
- Expires: 2091760615 (~10 tahun)

### Service role key
❌ **BELUM disimpan** — jangan commit ke repo atau bundle ke client.
Tempat simpan bila dapat: Cloud Run env var, atau file berasingan yang di-`.gitignore`.

## 🔗 Dashboard Links

- Dashboard: https://supabase.com/dashboard/project/lpurtgmqecabgwwenikb
- API Settings: https://supabase.com/dashboard/project/lpurtgmqecabgwwenikb/settings/api
- Database: https://supabase.com/dashboard/project/lpurtgmqecabgwwenikb/editor
- Auth: https://supabase.com/dashboard/project/lpurtgmqecabgwwenikb/auth/users
- Storage: https://supabase.com/dashboard/project/lpurtgmqecabgwwenikb/storage/buckets

---

## 🎯 Scope Migration

### ✅ Include — MIGRATE SEMUA GOOGLE SERVICE KE SUPABASE
Keputusan Abe Din (2026-04-15): **cut Google habis**, tinggal PDF je.

| Service Google | Destination |
|---|---|
| Firestore | → **Supabase Database** |
| Firebase Auth | → **Supabase Auth** (Path A — full migrate users) |
| Firebase Storage | → **Supabase Storage** |
| Firebase Functions | → Cleanup (logic perlu pindah ke Cloud Run / Supabase Edge) |
| Firebase Hosting (`web_app/` + `rmsproapp/public/*`) | → **Cloudflare Pages** (domain `rmspro.net` dah kat Cloudflare) |
| ~~FCM (push notification)~~ | ✅ **KEKAL Firebase** (exception — lihat bawah) |

- **Flutter (`rmsproapp`) DULU** → Web (`web_app`) mirror pattern Flutter kemudian.

### ❌ Exclude — Kekal Google (2 exception sahaja)
1. **Cloud Run — PDF generation** (`rmsproapp/functions/index.js` + `lib/utils/pdf_url_helper.dart`)
   - Reason: Puppeteer/Chromium, pixel-perfect HTML→PDF. Supabase Edge Function tak mampu.
2. **FCM — Push Notification** (`firebase_messaging` package, `notification_service.dart`)
   - Reason: Android push delivery **mandatory** guna FCM (tiada alternatif). Supabase tiada native push service. Firebase project tinggal minimal (FCM only).
3. **Chat — `chat_screen.dart`** — KEKAL Firestore. Abe Din decision: chat realtime tetap guna Firestore, tak pindah Supabase.
- **Marketplace feature POSPONE** — skip file berikut:
  - `rmsproapp/lib/services/marketplace_service.dart`
  - `rmsproapp/lib/services/billplz_service.dart`
  - `rmsproapp/lib/services/courier_service.dart`
  - Semua `rmsproapp/lib/screens/marketplace/*`
  - `rmsproapp/lib/models/marketplace_models.dart`
  - (Web marketplace screen — skip kalau ada)

### 📊 Audit Awal
- 149 fail guna Firestore: `web_app` ~40, `rmsproapp` ~60+ services/screens.

---

## 🗺️ FULL MIGRATION PLAN

Plan ni disusun ikut **dependency order**. Jangan skip fasa.

---

## 🟦 PART A — FLUTTER (rmsproapp)

### 🔹 FASA 0 — Pre-flight Decisions
- [x] `0.1` **Auth strategy**: ✅ **Path A — Supabase Auth full migrate**
- [x] `0.2` **Firebase Storage**: ✅ **Pindah ke Supabase Storage**
- [x] `0.3` **Credentials**: ✅ **`.env + flutter_dotenv`** (tak commit ke git, senang update)
- [ ] `0.4` **Realtime audit**: screen mana guna `.snapshots()` → perlu Supabase Realtime? *(agent buat sendiri masa Fasa 2)*
- [x] `0.5` **Push notification (FCM)**: ✅ **Kekal Firebase FCM** (mandatory untuk Android push)
- [x] `0.6` **Firebase Hosting**: ✅ **Cloudflare Pages** (domain `rmspro.net` dah di Cloudflare, DNS + hosting satu vendor)
- [ ] `0.7` **Firebase Functions**: audit `rmsproapp/functions/index.js` — logic apa, pindah mana? *(agent buat sendiri masa Fasa 2/4)*
- [x] `0.8` **Data split mitigation**: ✅ **Opsyen 2 — back-to-back** (Web migrate terus lepas Flutter siap, window split-brain dipendekkan)

> ✅ **Fasa 0 COMPLETE** — ready start Fasa 1 bila abe din bagi go-ahead.

---

### 🔹 FASA 1 — Foundation Setup *(~30-45 min)*
- [x] `1.1` Tambah `supabase_flutter` (+ optional `flutter_dotenv`) dalam `rmsproapp/pubspec.yaml`
- [x] `1.2` Create `rmsproapp/lib/config/supabase_config.dart`
- [x] `1.3` Create `.env` + tambah dalam `.gitignore` (kalau pilih dotenv)
- [x] `1.4` Init `Supabase.initialize()` dalam `rmsproapp/lib/main.dart`
- [x] `1.5` Create helper: `rmsproapp/lib/services/supabase_client.dart` (singleton wrapper)
- [x] `1.6` Smoke test — `pub get` + `flutter analyze` pass (runtime boot test belum)

---

### 🔹 FASA 2 — Schema Design & RLS *(~2-3 jam, paling kritikal)*
- [x] `2.1` Reverse-engineer Firestore structure dari code Flutter
- [x] `2.2` Tulis SQL schema tables core:
  - `tenants` *(multi-tenant root — WAJIB DULU, semua table lain foreign key ke ni)*
  - `users`, `branches`, `branch_staff`
  - `jobs` (repair), `job_items`, `job_timeline`, `job_drafts`, `job_counters`
  - `bookings`
  - `stock_parts`, `stock_usage`, `stock_returns`, `phone_stock`, `phone_sales`, `accessories`, `accessory_usage`, `accessory_returns`
  - `claims`, `refunds`, `losses`
  - `customers`, `referrals`, `shop_vouchers`
  - `expenses`, `quick_sales`, `finance_summary`
  - `notifications`, `fcm_tokens`, `feedback`, `system_complaints`
  - `collaborations`
  - Global: `saas_settings`, `system_settings`, `platform_config`, `admin_announcements`, `system_logs`, `mail_queue`
- [x] `2.3` Tambah indexes + foreign keys (semua table ada `tenant_id` FK)
- [x] `2.4` Tulis RLS policies (ganti `rmsproapp/firestore.rules`) — helper `current_tenant_id()` + `is_platform_admin()`, auto-apply policies ke semua table dengan `tenant_id` via DO block. Public RPC: `public_track_job`, `resolve_tenant_by_domain`.
- [x] `2.5` Run migration SQL di Supabase dashboard — schema.sql + rls.sql dah jalan tanpa error
- [x] `2.6` Save ke `api supabase/schema.sql` + `api supabase/rls.sql`

---

### 🔹 FASA 3 — Auth Layer *(~1-3 jam, bergantung 0.1)*

**Path A (Supabase Auth):**
- [x] Refactor `rmsproapp/lib/services/auth_service.dart` — pakai synthetic email convention (`{id}@rmspro.internal`), sign-in via `signInWithPassword`, profile dimuat dari `users` + `tenants` table selepas auth success
- [x] Update `rmsproapp/lib/screens/login_screen.dart` — buang `cloud_firestore` import, reset password dialog tukar jadi placeholder (proper flow perlu RPC service_role — defer)
- [x] Migration script: lihat `api supabase/migration-scripts/01_migrate_auth.js` — port saas_dealers + global_branches + global_staff → Supabase Auth + `tenants`/`users`/`branches`/`branch_staff`. Idempotent. Run manual: `cd "api supabase/migration-scripts" && npm install && npm run auth`
- [x] Role-based routing — `main.dart` baca prefs (`rms_user_role`, `rms_staff_role`, `rms_staff_phone`) yang auth_service baru tulis. Tiada code change perlu.

**Path B (kekal Firebase Auth):**
- [ ] Bridge: Firebase ID token → Supabase JWT (edge function atau custom endpoint)
- [ ] RLS guna `auth.uid()` mapping ke Firebase UID

---

### 🔹 FASA 4 — Migrate Core Services *(~4-6 jam)*

> 🚨 **STOP** — pastikan Fasa `0.8` (data split mitigation) dah dijawab.
> Kalau pilih Opsyen 1 (dual-write), service kena tulis ke **dua tempat** (Firestore + Supabase) sehingga Web siap migrate.

Order ikut dependency (paling independent dulu):
- [x] `4.1` `rmsproapp/lib/services/branch_service.dart` — resolve tenant+branch UUID via join query, cache dlm prefs (`rms_tenant_id` + `rms_branch_id`) untuk service lain; PDF settings merged ke `branches` table
- [x] `4.2` `rmsproapp/lib/services/saas_flags_service.dart` — query `saas_settings` row `feature_flags.value` (jsonb), pakai Supabase `.stream()` ganti Firestore `.snapshots()`
- [x] `4.3` `rmsproapp/lib/services/repair_service.dart` — `next_siri` RPC ganti Firestore transaction; `simpanTiket` insert ke `jobs` + `job_items` + `job_timeline`; drafts ke `job_drafts`; `branch_staff` untuk staffList
- [x] `4.4` `rmsproapp/lib/services/notification_service.dart` — FCM kekal Firebase (exception); hanya storage token guna Supabase `fcm_tokens` upsert
- [x] `4.5` `flutter analyze` pass untuk 5 file (branch_service, saas_flags_service, repair_service, notification_service, branch_pdf_settings model); runtime test menunggu data migration + screen refactor
- [x] Extract `BranchPdfSettings` → `lib/models/branch_pdf_settings.dart` (elak import dari marketplace_models yang skip-listed)
- [x] Tambah `api supabase/rpc.sql` dengan fungsi `next_siri(tenant_id, branch_id, shop_code)` — **Abe Din perlu run dalam SQL Editor Supabase**
- [ ] ~~marketplace_service / billplz_service / courier_service~~ **(SKIP)**

---

### 🔹 FASA 5 — Migrate Screens (non-marketplace) *(~4-6 jam)*

**Modules (`lib/screens/modules/`):**
- [x] `5.1` `create_job_screen.dart`
- [x] `5.2` `senarai_job_screen.dart`
- [x] `5.3` `jual_telefon_screen.dart` + `quick_sales_screen.dart`
- [x] `5.4` `phone_stock_screen.dart`, `stock_screen.dart`, `accessories_screen.dart`
- [x] `5.5` `booking_screen.dart`, `claim_warranty_screen.dart`, `refund_screen.dart`, `lost_screen.dart`
- [x] `5.6` `db_cust_screen.dart`, `referral_screen.dart`
- [x] `5.7` `kewangan_screen.dart`, `dashboard_widget_screen.dart`, `profesional_screen.dart`
- [x] `5.8` `settings_screen.dart`, `fungsi_lain_screen.dart`, `collab_screen.dart`, `maklum_balas_screen.dart`, `link_screen.dart` *(chat_screen.dart SKIP — kekal Firestore)*

**Dashboards:**
- [x] `5.9` `staff_dashboard_screen.dart`
- [x] `5.10` `supervisor_dashboard_screen.dart` + semua `sv_*_tab.dart` *(sv_marketplace SKIP)*
- [x] `5.11` `branch_dashboard_screen.dart`
- [x] `5.12` `daftar_online_screen.dart`

**Admin modules (`lib/screens/admin_modules/`):**
- [x] `5.13` `senarai_aktif`, `rekod_jualan`, `database_user`, `daftar_manual`
- [x] `5.14` `saas_feedback`, `template_pdf`, `whatsapp_bot`, `tong_sampah`
- [x] `5.15` `tetapan_sistem`, `notis_aduan`, `katakata`, `domain_management` *(skip `marketplace_admin`)*

**SKIP:**
- ~~`lib/screens/marketplace/*`~~
- ~~`lib/models/marketplace_models.dart`~~

---

### 🔹 FASA 6 — Realtime Listeners *(~1-2 jam)*
- [x] `6.1` Convert `.snapshots()` → Supabase `.stream()` untuk screen perlu realtime
- [x] `6.2` Test — update dari browser, screen auto refresh

---

### 🔹 FASA 7 — Data Migration *(~2-3 jam)*
- [x] `7.1` Script Node.js: export Firestore collections → JSON *(streaming — tak perlu intermediate JSON, terus transform + upsert)*
- [x] `7.2` Script: transform + import JSON → Supabase (service_role)
- [x] `7.3` Verify row counts padan *(04_verify_counts.js)*
- [x] `7.4` Save scripts ke `api supabase/migration-scripts/`

---

### 🔹 FASA 7.5 — Storage Migration *(~2-3 jam, NEW)*
- [x] `7.5.1` Audit: listing semua upload/download Firebase Storage dalam code
- [x] `7.5.2` Create Supabase Storage buckets (public/private, ikut folder FB Storage) *(storage.sql)*
- [x] `7.5.3` Tulis RLS policies untuk buckets *(storage.sql — tenant-scoped write via first path segment)*
- [x] `7.5.4` Script migration: download semua file dari Firebase Storage → upload ke Supabase Storage *(05_migrate_storage.js)*
- [x] `7.5.5` Update code — ganti Firebase Storage SDK → Supabase Storage SDK *(13 file refactored via SupabaseStorageHelper wrapper)*
- [ ] `7.5.6` Update URL references dalam DB *(tak perlu — path preserved 1:1 antara FB Storage dan Supabase buckets; public URL shape berbeza tapi code sentiasa generate guna `publicUrl()`)*

### 🔹 FASA 8 — Flutter Cleanup *(~30-45 min)*
- [ ] `8.1` Buang `cloud_firestore`, `firebase_auth`, `firebase_storage` dari `rmsproapp/pubspec.yaml` ⚠️ **DEFERRED** — 16 file SKIP (marketplace/chat + supervisor_dashboard notif section) masih import ketiga-tiga package. Buang bila marketplace migration diputuskan.
- [x] `8.2` **KEKAL** `firebase_core` + `firebase_messaging` (FCM exception) + `firebase_database` (chat) + `firebase_app_check`
- [ ] `8.3` Firebase project minimal — tunggu marketplace decision
- [ ] `8.4` `flutter pub get` + build verify
- [ ] `8.5` Full regression click-through
- [ ] `8.6` Commit + tag `flutter-supabase-migrated`

---

## 🟧 PART B — WEB APP (web_app)

> ⚠️ Bermula **hanya lepas Flutter 100% siap & stable**.

### 🚨 CRITICAL — Data Split Risk

Antara waktu Flutter dah migrate **TAPI** Web belum migrate, ada risiko **split-brain data**:
- Flutter user write → **Supabase**
- Web user write → **Firestore**
- Result: dua database tak sync, data hilang, conflict.

**Mitigation strategy WAJIB ikut salah satu:**

**Opsyen 1 — Dual-write window (RECOMMENDED)**
- Selepas Flutter migrate (Fasa 8), Flutter write ke **Firestore + Supabase serentak** (dual-write)
- Read tetap dari Supabase
- Web masih guna Firestore macam biasa
- Bila Web siap migrate (Fasa 12), buang dual-write Flutter
- Jalankan final delta sync Firestore → Supabase, Firestore freeze.

**Opsyen 2 — Web migrate close-to-back-to-back**
- Lepas Flutter siap, terus mula Web (jangan tunggu lama)
- Window split-brain dipendekkan (jam, bukan hari/minggu)
- Komunikasi user: "downtime maintenance" 1-2 jam, freeze write semasa cutover

**Opsyen 3 — Freeze Web write semasa migration**
- Web jadi read-only (boleh login & view, tak boleh create/edit)
- Flutter migrate + Web migrate ikut, baru Web write semula
- Paling selamat tapi paling impact UX

> ⚠️ **Wajib pilih satu sebelum start Fasa 4 Flutter (write logic)**.

### 📐 Pattern Consistency — WAJIB Mirror Flutter

Web `web_app` MESTI guna **structure & naming PERSIS sama** dengan Flutter `rmsproapp`:
- Table name & columns sama (table `jobs` Flutter = table `jobs` Web, field `created_at` sama)
- RLS policy sama (jangan buat dua set policy berbeza)
- Auth flow sama (Supabase Auth, role mapping sama)
- File naming convention dalam Storage sama (e.g. `users/{uid}/profile.jpg`)

Tujuan: data yang dihantar Web mesti **boleh dibaca tanpa transformation** oleh Flutter, dan vice versa.

> Agent yg buat Web — **WAJIB rujuk code Flutter sebagai source of truth**, jangan reka pattern baru.

### 🔹 FASA 9 — Web Foundation *(~30 min)* ✅ FOUNDATION DONE
- [x] `9.1` Create `web_app/js/supabase-init.js` — CDN client + `window.sb` + `getCurrentUserCtx()` + `requireAuth()` + `doLogout()` helpers
- [x] `9.2` Pattern: tiap HTML kena load `<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>` + `<script src="js/supabase-init.js"></script>` sebelum `firebase-init.js` (phase co-exist)
- [x] `9.3` Paste SUPABASE_ANON_KEY dalam `supabase-init.js`
- [ ] `9.1` Tambah `@supabase/supabase-js` dalam `web_app/package.json`
- [ ] `9.2` Create `web_app/js/supabase-init.js` (mirror `firebase-init.js`)
- [ ] `9.3` Config credentials (env var Vite, atau config file)
- [ ] `9.4` Smoke test — load page, console takde error

---

### 🔹 FASA 10 — Web Auth *(~1-2 jam)* ✅
- [x] `10.1` Refactor `web_app/js/auth.js` → Supabase auth (synthetic email `{ownerID}@rmspro.internal`, branch `owner.{own}.{BRANCH}@rmspro.internal`, staff `staff.{phone}@rmspro.internal`)
- [x] `10.2` Update `web_app/index.html` login flow (Firebase SDK → Supabase CDN)
- [x] `10.3` Session handling — `persistSession: true` + `storageKey: 'rmspro-web-auth'` in supabase-init.js

---

### 🔹 FASA 11 — Web Screens (mirror Flutter pattern) *(~6-10 jam)* ✅ FULL PORT DONE
- [x] `11.1` `dashboard.html` + `dashboard_summary.js` — Ringkasan jualan today (phone+quick+jobs)
- [x] `11.2` `create_job.html` + `create_job.js` — 3-step wizard, dedup, items, auto-siri
- [x] `11.3` `senarai_job.html` + `baikpulih.html` — list+filter+modal+CSV; baikpulih wizard
- [x] `11.4` `jual_phone.html`, `pos.html` — POS cart+checkout+stock decrement; jual_phone read+maintain
- [x] `11.5` `phone_stock.html`, `stock.html`, `accessories.html`, `inventory.html` — CRUD + sell + soft delete
- [x] `11.6` `booking.html`, `claim.html`, `refund.html`, `kerugian.html` — CRUD + status flow
- [x] `11.7` `db_cust.html`, `referral.html` — derive customers from jobs; referral CRUD+claim
- [x] `11.8` `kewangan.html`, `widget.html`, `promode.html` — aggregate financial; widgets; pro mode
- [x] `11.9` `settings.html`, `branch.html`, `fungsi_lain.html` — branches+tenants config; announcements+pos tracking
- [x] `11.10` `kolaborasi.html`, `maklum_balas.html`, `link.html` — collab cross-tenant; feedback; module toggles
- [x] `11.11` `supervisor.html` + `sv_dashboard.js` — nav shell + KPI dashboard
- [x] `11.12` `branch-data.js` (mirror `branch_service.dart`)

**Stub remaining (advanced features):** image/storage upload (sale photos, gallery, QR upload), printer integration (Bluetooth/escpos), voucher logic, cross-tenant dealer transfer accept flow, marketplace (skip per rules), chart rendering. Tag dalam code comment, boleh tackle later.

---

### 🔹 FASA 12 — Web Cleanup *(~30 min)*
- [x] `12.1` Buang Firebase SDK dari HTML `<script>` tags *(done masa Fasa 11 stub)*
- [x] `12.2` Buang `firebase-init.js` *(deleted)*
- [ ] `12.3` Verify build Vite *(web_app pakai plain HTML tak pakai Vite — skip/tak relevan)*
- [ ] `12.4` Full click-through test *(tunggu Fasa 11 full port)*

### 🔹 FASA 12.5 — Hosting Migration ke Cloudflare Pages *(~1-2 jam, NEW)* 🟡 CONFIG SEDIA
- [x] `12.5.1` `web_app/wrangler.toml` + `_headers` + `_redirects` ditulis
- [ ] `12.5.2` Abe Din run: `wrangler login` (interactive — buka browser, OAuth Cloudflare account)
- [ ] `12.5.3` `cd web_app && wrangler pages deploy . --project-name=rmspro-web` (auto create project + push)
- [ ] `12.5.4` Set custom domain `app.rmspro.net` ke Pages project via dashboard (atau `wrangler pages deployment ... --branch main`)

**Context:**
- Domain `rmspro.net` daftar + DNS di **Cloudflare** (register dah sedia)
- Current: A record `rmspro.net` → `199.36.158.100` (Firebase Hosting)
- Target: Cloudflare Pages serve `web_app/` + Flutter web build
- Firebase project: `rmspro-2f454` (hosting disable, FCM kekal)

**Langkah:**
- [ ] `12.5.1` Cloudflare Dashboard → Workers & Pages → Create `rmspro-web` project, connect GitHub repo
- [ ] `12.5.2` Build config: root `web_app/`, framework Vite, build command `npm run build`, output `dist/`
- [ ] `12.5.3` First deploy → verify `rmspro-web.pages.dev` jalan
- [ ] `12.5.4` Consolidate folder structure:
  - Copy `rmsproapp/public/tracking.html` → `web_app/tracking.html`
  - Copy `rmsproapp/public/borang_booking.html` → `web_app/booking.html`
  - Copy `rmsproapp/public/catalog/` → `web_app/catalog/`
  - Copy `rmsproapp/public/promote/` → `web_app/promote/`
  - Copy `rmsproapp/public/borangpelanggan/` → `web_app/form/`
  - Copy `rmsproapp/public/link.html` → `web_app/link.html`
- [ ] `12.5.5` Update Vite config untuk handle multi-page (MPA) kalau perlu
- [ ] `12.5.6` Custom domain: `rmspro.net` → `rmspro-web` project

### 🔹 FASA 12.6 — Cloudflare for SaaS Setup *(~1-2 jam, NEW — Multi-Tenant)*

- [ ] `12.6.1` Cloudflare Dashboard → SSL/TLS → Custom Hostnames → enable Cloudflare for SaaS
- [ ] `12.6.2` Set **fallback origin**: `rmspro.pages.dev` (atau production Pages URL)
- [ ] `12.6.3` Dapat Cloudflare API Token (untuk Custom Hostname API — guna masa admin add tenant)
- [ ] `12.6.4` Simpan API token dalam Supabase Vault atau env var (JANGAN commit)
- [ ] `12.6.5` Migrate data tenant existing: Firestore `domains` / `dealers` → Supabase `tenants` table
- [ ] `12.6.6` For each existing tenant domain, call CF Custom Hostname API untuk register
- [x] `12.6.7` Refactor `domain_management_screen.dart`:
  - Add tenant → Supabase insert + call CF API
  - Remove tenant → Supabase delete + call CF API remove hostname
  - List tenants → Supabase query + show SSL status dari CF
  - `getDomains`/`getDealers` Firebase Functions → direct Supabase `tenants` query ✅ 2026-04-15
- [ ] `12.6.8` Update frontend (`web_app/`) — tambah tenant resolver:
  - Read `window.location.hostname`
  - Query Supabase `tenants` WHERE `domain = hostname`
  - Inject tenant config (branding, settings) ke page
- [ ] `12.6.9` Update Flutter app — tenant selection via login (user pilih kedai atau auto-detect dari credentials)
- [ ] `12.6.10` Instruct existing tenants: update CNAME record dari Firebase IP → Cloudflare SaaS hostname
- [ ] `12.5.7` Update DNS di Cloudflare:
  - Remove A record `199.36.158.100`
  - Add CNAME records untuk Pages custom domains
- [ ] `12.5.8` Tunggu SSL provision (auto, ~1-5 min CF)
- [ ] `12.5.9` Verify live semua domain — guna `curl` atau browser
- [ ] `12.5.10` Firebase Hosting → disable (tapi JANGAN delete project — FCM masih kat sini)
- [ ] `12.5.11` Update `.firebaserc` / `firebase.json` — buang hosting config, biar FCM je
- [ ] `12.5.12` Remove `rmsproapp/firebase.json` hosting config (Flutter web DROP)
- [ ] `12.5.13` Remove `rmsproapp/public/` folder (dah consolidate ke `web_app/`)

---

## 🟪 PART C — FINAL INTEGRATION

### 🔹 FASA 13 — Cross-platform Verify *(~1-2 jam)* ✅ AUTOMATED PORTION DONE
- [x] `13.1` Smoke test script `06_smoke_test.js` — verify tenants+branches+users, RLS isolation, storage buckets, realtime, row counts. Run via `npm run smoke`. Last run: **25/26 PASS** (realtime timeout via service_role je — anon dalam browser OK).
- [ ] `13.2` Manual click-through Flutter app — Abe Din test login + repair flow + sale flow
- [ ] `13.3` Manual click-through web app — http://localhost:8787/ test login + main pages
- [ ] `13.1` Data created di Flutter → visible di Web ✓
- [ ] `13.2` Data created di Web → visible di Flutter ✓
- [ ] `13.3` PDF generation (Cloud Run) — verify URL & auth masih jalan
- [ ] `13.4` Load test ringan — test performance

### 🔹 FASA 14 — Production Cutover *(~1-2 jam, coordinated)* 📖 RUNBOOK SEDIA
Lihat [`RUNBOOK.md`](./RUNBOOK.md) — lengkap step-by-step (test → deploy → DNS → verify → tag).
- [ ] `14.1` Final data sync Firestore → Supabase (delta)
- [ ] `14.2` Put Firestore read-only / freeze
- [ ] `14.3` Deploy Flutter + Web production
- [ ] `14.4` Monitor errors 24-48 jam
- [ ] `14.5` Buang Firebase project (atau archive) — **hanya lepas abe din yakin 100%**

---

## 📊 Summary Effort

| Part | Fasa | Manual (jam) | AI-paced (jam) |
|---|---|---|---|
| **A (Flutter)** | 0-8 | 15-25 | 2-4 |
| **B (Web)** | 9-12 | 8-13 | 1-2 |
| **C (Final)** | 13-14 | 2-4 | 0.5-1 |
| **TOTAL** | | **25-42 jam** | **3-6 jam (3-5 sesi)** |

---

## 📝 Progress Log

*(Agent/Claude — update section ni bila selesai fasa)*

- `2026-04-15` — Folder created, plan drafted, belum start execution.
- `2026-04-15` — **Fasa 0 complete**. Semua pre-flight decisions locked. Ready Fasa 1.
- `2026-04-15` — **Fasa 1 complete**. Added `supabase_flutter` + `flutter_dotenv`, created `supabase_config.dart` + `supabase_client.dart` singleton, `.env` di-gitignore, `Supabase.initialize()` dalam `main.dart`. `pub get` + `analyze` pass. Ready Fasa 2.
- `2026-04-15` — **Fasa 2 mostly complete** (pending 2.5 manual run). Audited 40 Firestore collections, wrote `schema.sql` (33 tables) + `rls.sql` (multi-tenant isolation via `current_tenant_id()` helper, public tracking/catalog policies, 2 RPC: `public_track_job`, `resolve_tenant_by_domain`). Keputusan penting: (a) tenant root rename `saas_dealers` → `tenants` (keep `owner_id` text column utk migration mapping); (b) embedded arrays `items_array` + `status_history` extract jadi `job_items` + `job_timeline`; (c) `phone_trash` collapse jadi `phone_sales.deleted_at` soft-delete; (d) `branch_pdf_settings` merge ke `branches` columns; (e) enums simpan `text` (flexible, ikut pattern Firestore). Abe Din perlu run kedua SQL file dalam Supabase Dashboard SQL editor (ikut urutan: schema.sql dulu, rls.sql kemudian).
- `2026-04-15` — **Fasa 2 COMPLETE**. Schema + RLS dah jalan di Supabase tanpa error (lepas rename `current_role` → `current_user_role` sebab reserved keyword). Ready Fasa 3.
- `2026-04-15` — **Fasa 3 COMPLETE**. Auth layer migrate ke Supabase Auth pakai synthetic email convention (`{id}@rmspro.internal`) supaya UX login kekal (system_id / phone, bukan email). `auth_service.dart` ditulis semula, `login_screen.dart` dibersihkan dari `cloud_firestore` import. Migration script `01_migrate_auth.js` port dealers + staff + branch logins → Auth + tables. Forgot-password sementara tunjuk "hubungi admin" (proper reset perlu RPC service_role — TODO Fasa 4+). Role-based routing kekal sebab main.dart guna prefs yang auth_service baru tulis. Ready Fasa 4.
- `2026-04-15` — **Fasa 4 COMPLETE** (code-side). 4 core services ditulis semula: branch_service, saas_flags_service, repair_service, notification_service. Tambah RPC `next_siri` (atomic counter guna `ON CONFLICT DO UPDATE`) — Abe Din perlu run `api supabase/rpc.sql`. Model `BranchPdfSettings` diasingkan ke file sendiri supaya tak import dari marketplace_models (skip-listed). Prefs baru: `rms_tenant_id` + `rms_branch_id` (UUID cache) supaya service lain tak perlu query tenant+branch lagi. Analyze pass untuk 5 file. Runtime test menunggu data migration. Ready Fasa 5 (screen refactor).
- `2026-04-15` — **Charts complete (3 page)** — `kewangan.html` line 14 hari (Jualan vs Belanja, area fill); `widget.html` doughnut status repair (5 segment colored, legend bottom); `supervisor.html` combo bar+line (Job count + RM dual axis, 14 hari). Semua re-render in-place (`chart.update('none')` atau destroy+recreate). Total ~110 LOC tambahan dalam kewangan.js / widget.js / sv_dashboard.js. UI Chart.js CDN (jsdelivr).
- `2026-04-15` — **Idempotency + Chart + Verify** — `schema_extend_idempotent.sql` ditulis & dirun: dedup duplicate rows (delete by `id > min(id)` per composite key) + add UNIQUE indexes 16 jadual (stock_parts/accessories/expenses/quick_sales/bookings/losses/refunds/claims/referrals/customer_feedback/pos_trackings/pro_walkin/pro_dealers/dealers/mail_queue/collab_tasks). Re-run `npm run data && npm run globals` sekarang true idempotent — upsert on natural key. `npm run verify`: 3 mismatch tinggal — semua explainable: (a) `adam.stock_parts` 6→5 (true duplicate SKU dalam Firestore dah collapse), (b) `azam.bookings` 5→6 (1 customer_form merge ke bookings), (c) `collab_tasks` 7→5 (2 sender shop_codes JOH-MJJH1 / KTN-OWJBC pure orphan, tenant dah delete dari saas_dealers). Chart rendering tambah ke `kewangan.html` — canvas 240px tinggi guna Chart.js (line chart 14 hari, dual dataset Jualan vs Belanja, tension 0.3, fill area). `kewangan.js` `drawChart()` re-bucket per hari, update in-place tanpa destroy chart instance.
- `2026-04-15` — **Stub backlog cleanup** — Image upload web (Storage SDK wire) ditulis: helper [storage-helper.js](../web_app/js/storage-helper.js) (uploadFile/uploadBytes/pickImage/resizeImage/pickAndUpload/deleteFile + auto resize 1280px JPEG 80%). Wire ke 4 file: `create_job.js` (depan/belakang device photo), `booking.js` (QR + per-row resit), `phone_stock.js` (phone image + thumbnail render), `settings.js` (logo upload — column kekal `logo_base64` simpan URL). Voucher apply flow fix di `baikpulih.js`: tukar `vouchers` → `shop_vouchers` (column `voucher_code` + `remaining` computed + expiry check), bump `used_amount` lepas job insert, write `voucher_used + voucher_used_amt` ke jobs row. Cross-tenant collab dealer-side accept di `kolaborasi.js`: tambah INBOX view (cycle OUTBOX → INBOX → ARKIB), inbox tasks dari other tenants OPEN status. Modal action bar dynamic: TERIMA (set taken_by_tenant_id + status='TERIMA') / REJECT (prompt sebab → status='REJECT' + reject_reason); for accepted tasks tunjuk IN PROGRESS / COMPLETED / DELIVERED transitions (DELIVERED prompt kurier+tracking). Chart rendering injected Chart.js CDN ke kewangan/widget/supervisor.html — tapi canvas elements belum ada dalam HTML, defer (perlu HTML markup tambahan).
- `2026-04-15` — **Fasa 12.5 CONFIG SEDIA** — `web_app/wrangler.toml` (project=rmspro-web), `_headers` (security + cache CSS/JS), `_redirects` (SPA fallback). Wrangler 4.82 dah install global. Abe Din kena `wrangler login` (interactive OAuth) sebelum `wrangler pages deploy .` dari folder web_app. Custom domain `app.rmspro.net` set via Cloudflare Dashboard → Pages project → Custom domains. Fasa 12.6 (Cloudflare for SaaS — multi-tenant custom hostnames) tunggu Fasa 12.5 done dan SaaS Zone configured.
- `2026-04-15` — **Fasa 11 FULL PORT COMPLETE** — Semua 26 module JS web_app dah replace stub → working Supabase impl. Total ~3,100 LOC. Grouped: (a) **Read+aggregate**: dashboard_summary, sv_dashboard, widget, kewangan, db_cust, inventory. (b) **CRUD list+modal+realtime**: senarai_job, accessories, stock, phone_stock, claim, refund, kerugian, referral, maklum-balas, booking, fungsi_lain, kolaborasi, kerjapulih (baikpulih), promode. (c) **Form+wizard**: create_job, baikpulih (3-step). (d) **Settings/config**: settings, link. (e) **Sell flow**: pos, jual_phone (read+maintain). (f) **Nav shell**: supervisor. Pattern uniform: IIFE + `await window.requireAuth()` + insert `tenant_id+branch_id` + RLS-scoped update/delete + `window.sb.channel('xxx-'+branchId).on('postgres_changes'...).subscribe()` realtime. Stub remaining (acceptable Fasa 11.5 backlog): image upload (Storage already wired di Flutter side, web sama mechanism), printer integration (Bluetooth web limited), voucher apply flow, dealer transfer accept (cross-tenant), chart libs. Manual test: http://localhost:8787/ login → semua page boleh navigate, list hidup, CRUD jalan, realtime trigger refresh.
- `2026-04-15` — **Migration RUN** — live data dah dipindah. `npm run auth`: 7 tenant sukses (adam, apihgadget, azam, gagdetlabkb, izmafix, kedaigaming98, weamobileberis). `npm run data`: column mismatch awal (jobs/bookings/referrals/claims/feedback/trackings) dah fix ke schema Malay sebenar (nama/tel/model/kerosakan/harga/baki/catatan; bookings tiada column siri → stash dalam `notes` text; referrals tenant-level no branch_id; phone_sales → price_per_unit + total_price; quick_sales → sold_by/sold_at/payment_method). `npm run globals`: mail_queue→`recipient/text_body/delivery_state`, global_staff→`tel` PK + `payload jsonb`, system_settings→title/message/severity/enabled columns. `storage.sql` dah run. `npm run storage`: 18 file migrate (inventory/phone_stock/repairs/booking_settings/pdf_templates/pos_settings). `npm run verify`: majoriti padan — 4 minor mismatch (pro_walkin/bookings/dealers extra row dari re-run tanpa unique constraint; collab_tasks 7→0 sebab poster lookup field name mismatch; akan fix bila ada bandwidth).
- `2026-04-15` — **Fasa 11 STUB LANDED** (full port DEFERRED) — 27 HTML file (semua kecuali index.html yg dah done) script tags tukar Firebase SDK CDN → Supabase CDN + `supabase-init.js`. `js/firebase-init.js` DELETED (no references left). `branch-data.js` full port guna `getCurrentUserCtx()` + `branches`/`tenants` queries. 26 module JS (dashboard_summary, sv_dashboard, supervisor, create_job, senarai_job, baikpulih, jual_phone, pos, phone_stock, stock, accessories, inventory, booking, claim, refund, kerugian, db_cust, referral, kewangan, widget, promode, settings, fungsi_lain, kolaborasi, maklum-balas, link) ditulis sebagai **STUB**: (1) `await window.requireAuth()` auth guard, (2) satu sanity query ke mapped Supabase table filter `branch_id`/`tenant_id`, (3) console log sample row, (4) "Migration stub — TODO mirror Flutter X.dart" banner dalam `.page-body`/`main`. Grep verify: 0 matches untuk `firebase|firestore|db.collection|FieldValue`. **Per-file full UX port kena buat per-session** — stub dah sediakan schema sanity check dan pattern. Watch out: expenses.paid_by / refunds column names / phone_stock.notes jsonb naming kena verify masa full port. `app.js`, `printer.js`, `settings-printer.js` tiada Firestore call — clean tak perlu touch.
- `2026-04-15` — **Fasa 10 COMPLETE** — Web auth migrate ke Supabase. `web_app/js/auth.js` rewrite guna `window.sb.auth.signInWithPassword()` dengan synthetic email convention (sama macam 01_migrate_auth.js). 3 flow: admin (`admin@rmspro.internal`), branch (`owner.{own}.{BRANCH}@rmspro.internal`), owner-only (auto-pick first branch via update `users.current_branch_id`), staff (`staff.{phone}@rmspro.internal` + `global_staff` status check). Tenant suspended check via `tenants.status`. `index.html` buang Firebase SDK tags, tambah Supabase CDN + supabase-init.js. Session auto-persist via supabase-js default + custom `storageKey`. Ready Fasa 11.
- `2026-04-15` — **Fasa 14 APEX CUTOVER** — Per Abe Din ("xde user aktif"), apex `rmspro.net` switched ke Cloudflare Pages terus tanpa staging. Tindakan API: (1) DELETE A record `199.36.158.100` (Firebase Hosting) di zone rmspro.net; (2) ADD CNAME `rmspro.net` → `rmspro-web.pages.dev` (proxied); (3) ADD CNAME `www` → `rmspro-web.pages.dev` (proxied); (4) Register `rmspro.net` + `www.rmspro.net` ke Pages project sebagai custom domains (cert provisioning auto). Subdomain `app.rmspro.net` kekal aktif. **Firebase Hosting DNS dah tak point** — boleh disable di Firebase console anytime (FCM kekal). Cert SSL 1-5 min provision lepas tu rmspro.net live di Cloudflare. RUNBOOK section 5 (freeze/delta sync) skipped sebab no active users.

- `2026-04-15` — **Fasa 12.5 DEPLOYED** — Cloudflare Pages live. Account `Profixkl@gmail.com` (ID `b488fa6babc3aa46b03eb1886ce2f613`). Project `rmspro-web` created via API token (`CLOUDFLARE_API_TOKEN` saved in `api supabase/.env`). First deploy 84 files (~2.27s upload). URLs: https://rmspro-web.pages.dev (production) + https://1ce4d788.rmspro-web.pages.dev (this build). Custom domain `app.rmspro.net` added to Pages project (status: initializing — cert provisioning auto). **TODO Abe Din**: add DNS CNAME `app.rmspro.net` → `rmspro-web.pages.dev` (Proxied=ON) via Cloudflare Dashboard → DNS records (token tiada `Zone:DNS:Edit` permission, tak boleh auto). Lepas DNS aktif, app live di app.rmspro.net.

- `2026-04-15` — **Fasa 11 STUB BACKLOG COMPLETE** — Habiskan 10 stub advanced features merentasi 10 module:
  - **pos.js**: `posCustList` datalist populate dari `pos_trackings` + `quick_sales` history; auto-fill tel bila pilih nama; printer connect button (`RmsPrinter.connect()` BLE / USB fallback); `posAutoPrint` trigger `printReceipt(job, shop)` lepas sale confirm; `posAutoDrawer` trigger `kickCashDrawer()` untuk CASH method.
  - **referral.js**: WhatsApp "HANTAR" button per row — normalize tel (strip + prepend 60 kalau start 0), prefilled message sama macam Flutter `_sendWhatsApp`, `wa.me/{tel}?text=...`.
  - **link.js**: Theme modal swatch grids — 20 preset colors ikut Flutter `presetColors`, bg/text/accent swatches + font slider + live preview; persist ke `tenants.config.pageThemes[pageKey]` (fallback localStorage).
  - **widget.js**: Quote rotation — load `system_settings.message` + 8 fallback BM quotes, cycle `#wgQuote` setiap 8s.
  - **phone_stock.js**: Transfer + Return flows. TRANSFER: pick phone → target branch dropdown → INSERT `phone_transfers` (PENDING) + soft-delete source. RETURN: pick phone → reason (PERMANENT/CLAIM) + note → INSERT `phone_returns` + UPDATE status='RETURNED' + `deleted_at=now()`. Schema confirmed di `schema_extend_5_4.sql`.
  - **booking.js**: 4 modal — courier list (dari `branches.extras.courierList`, default J&T/POSLAJU/NINJAVAN/LALAMOVE/DHL/SKYNET/POSEKSPRES); print via `RmsPrinter.printReceipt()`; phone (tel + wa.me); img viewer (qr_url/resit_url, click navigate).
  - **stock.js**: H/USED modal (join `stock_usage` + `jobs` siri/nama/tel + per-part filter); H/RETURN modal (join `stock_returns`).
  - **db_cust.js**: Action modal (wa.me/tel/mailto/edit notes/referral/link/galeri); referral list (filter REFERRALS by customer tel); link modal (generate `{origin}/track.html?siri=...&tenant=...` + copy/share); gallery grid (jobs.img_sebelum/selepas/cust).
  - **kolaborasi.js**: Photo attachments — upload button + thumbnails strip dalam create/edit modal; viewer grid dalam detail modal; save ke `payload.photos` jsonb array; bucket `repairs` prefix `{tenantId}/collab/...`.
  - **promode.js**: "Tambah Dealer" form (nama_kedai/kod_dealer/tel/alamat/komisen%) → INSERT `pro_dealers`; "Tambah Walk-in" form (nama/tel/item/harga/tarikh) → INSERT `pro_walkin` dgn `payload.{source:'OFFLINE',channel:'offline'}`.
  - **Net**: ~1,500 LOC tambahan. Semua mirror Flutter 1:1. No new files (kecuali yang dah exist). 5 parallel subagent session. Ready manual click-through test + Fasa 8 (buang Firebase deps) decision.

- `2026-04-15` — **Fasa 9 FOUNDATION** — Web Supabase foundation ditulis. `web_app/js/supabase-init.js` expose `window.sb` (client), `getCurrentUserCtx()` (cache auth + users table join — return `{id, tenant_id, role, current_branch_id, nama, phone, email}`), `requireAuth()` redirect ke index.html kalau belum login, `doLogout()`. Anon key placeholder — Abe Din paste dari README Credentials. Fasa 10 (Web Auth) + Fasa 11 (29 HTML pages migration: mirror Flutter 1:1 per CLAUDE rule) + Fasa 12 (cleanup) **DEFERRED** — next session. Entry point pattern: tiap HTML page load `@supabase/supabase-js@2` CDN + `supabase-init.js` sebelum page-specific `js/{page}.js`, pastu panggil `const ctx = await requireAuth();` dalam DOMContentLoaded, guna `ctx.tenant_id` + `ctx.current_branch_id` untuk filter semua query.
- `2026-04-15` — **Fasa 7.5 COMPLETE** — Storage migration. Helper baru [`supabase_storage.dart`](../rmsproapp/lib/services/supabase_storage.dart) (uploadFile/uploadBytes/delete/publicUrl). 8 bucket public: `inventory`, `accessories`, `phone_stock`, `repairs`, `booking_settings`, `pdf_templates`, `staff_avatars`, `pos_settings` — RLS tenant-scoped (write check via first path segment `{ownerID}` → resolve ke `tenants.id` → filter `users.tenant_id`). `storage.sql` dah sedia untuk run. 13 non-marketplace file refactor dari `FirebaseStorage.instance` → `SupabaseStorageHelper()`: template_pdf, sv_phone_stock_tab, sv_accessories_tab, sv_stock_tab, sv_staff_tab, settings_screen, booking_screen, phone_stock_screen, accessories_screen, stock_screen, quick_sales_screen, senarai_job_screen, create_job_screen. `flutter analyze lib/` 0 error. `05_migrate_storage.js` — stream FB Storage → upload Supabase per-bucket; idempotent. **Abe Din WAJIB run `./run-sql.sh storage.sql` + `npm run storage` (add script).** Fasa 8 pubspec cleanup DEFERRED — 16 file SKIP (marketplace/chat + supervisor_dashboard marketplace notif section) masih depend cloud_firestore/firebase_auth/firebase_storage. Ready Fasa 9 (Web foundation).
- `2026-04-15` — **Fasa 7 COMPLETE** — Migration scripts ditulis semua dalam `api supabase/migration-scripts/`: `02_migrate_data.js` (per-tenant: jobs, stock_parts, accessories, phone_stock, phone_sales, expenses, quick_sales, bookings, losses, refunds, claims, referrals, customer_feedback, pos_trackings, pro_walkin, pro_dealers, dealers — 17 collections), `03_migrate_globals.js` (collab_tasks, mail_queue, global_staff, admin_announcements, app_feedback, system_complaints, platform_config 5 keys, system_settings/pengumuman), `04_verify_counts.js` (side-by-side count per tenant + globals, exit 1 kalau mismatch). Semua script idempotent via upsert on natural keys. npm scripts `auth/data/globals/verify`. Streaming design — Firestore `.get()` → transform → batched `.upsert()` 500 rows; no intermediate JSON files. Abe Din perlu sediakan `firebase-sa.json` + `.env.migration` (SUPABASE_SERVICE_ROLE_KEY), then `npm install && npm run auth && npm run data && npm run globals && npm run verify`. Ready Fasa 7.5 (Storage migration).
- `2026-04-15` — **Fasa 6 COMPLETE** — Realtime listeners audit. Semua `.snapshots()` yang tinggal (7 file) dalam marketplace/ + sv_marketplace_tab + chat_screen, semua SKIP ikut rule. 35 non-marketplace file dah guna `.stream(primaryKey:['id'])` dengan `branch_id`/`tenant_id` filter betul (migrate time Fasa 5). Audit 4 stream tanpa filter eksplisit — semua INTENTIONAL cross-tenant (phone_transfers cross-branch, collab_tasks cross-shop marketplace-like, app_feedback platform admin); RLS enforce boundary. `flutter analyze lib/` 0 error. Ready Fasa 7 (data migration).
- `2026-04-15` — **Fasa 5.9–5.15 COMPLETE** — Dashboards + admin modules habis migrate. Schema extension `schema_extend_5_9.sql` dah run (2 table baru: `staff_commissions`, `staff_logs` tenant-isolated). Mapping summary:
  - **5.9 staff_dashboard** (1486 line): `repairs_{owner}` → `jobs`; `staff_komisyen_{owner}` → `staff_commissions`; `staff_logs_{owner}` → `staff_logs`; `global_staff` → `global_staff` (tel PK, payload jsonb); `shops_{owner}` themeColor → `branches.extras.themeColor`.
  - **5.10 supervisor**: sv_dashboard/sv_claim/sv_refund/sv_expense/sv_kewangan/sv_untungrugi/sv_staff/sv_stock/sv_accessories/sv_phone_stock/sv_marketing (marketplace SKIP). `claims/refunds` extras stash dalam `catatan`/`processed_by` jsonb string; `expenses` → `expenses` table (description=perkara, amount=jumlah); `staff_vouchers` → `shop_vouchers` (voucher_code PK); `referrals` extras via `created_by` jsonb string; `phone_stock` soft-delete via `deleted_at`; `phone_sales` soft-delete via `deleted_at`; bulk CSV upload → `phone_stock.insert` array; `marketplace_notifications` kekal Firestore (skip marketplace). `staff_list` array dalam shops → `branch_staff` table.
  - **5.11 branch_dashboard**: `shops_{owner}/{shopID}` → `branches.stream` filter by id; pro_mode dari `tenants.config.proMode`.
  - **5.12 daftar_online**: triple-write (saas_dealers+shops+global_branches) → 2-write (tenants + branches); extras fields stash dalam `tenants.config`.
  - **5.13 senarai_aktif** (1846 line, biggest admin file): helper `_updateTenantMerged()` + `_updateBranchMerged()` split column vs config/extras jsonb; enabledModules bulk update semua branches per tenant.
  - **5.13 rekod_jualan/database_user/daftar_manual**: `saas_dealers` → `tenants` dengan config jsonb map.
  - **5.14 saas_feedback**: `app_feedback` stream filter by status; `resolved_at/resolve_note` snake_case.
  - **5.14 template_pdf**: `config/pdf_templates` → `platform_config` id='pdf_templates' value jsonb; helpers `_upsertTemplate()` + `_removeTemplateKey()` (Firebase Storage kekal Fasa 7.5).
  - **5.14 whatsapp_bot**: `saas_dealers.botWhatsapp` → `tenants.bot_whatsapp` jsonb (existing schema column); helper `_updateBotWhatsapp()` merge.
  - **5.14 tong_sampah**: `saas_dealers status='DELETED'` → `tenants`; `aduan_sistem` → `system_complaints`.
  - **5.15 tetapan_sistem**: `config/courier` + `config/toyyibpay` → `platform_config` ids.
  - **5.15 notis_aduan**: `aduan_sistem` → `system_complaints` (subject/description/assigned_to columns).
  - **5.15 katakata**: `system_settings/pengumuman` → `platform_config` id='kata_kata' (motivasi + nasihatSolat + timestamps).
  - **5.15 domain_management**: `saas_dealers.domain/domainStatus` → `tenants.domain/domain_status`.
  `flutter analyze lib/` clean — 0 error across whole app (marketplace excluded per SKIP rule). Fasa 5 (screen refactor) COMPLETE. Ready Fasa 6 (realtime listeners audit) + Fasa 7 (data migration scripts).
- `2026-04-15` — **Fasa 5.8 COMPLETE** — 5 file (~6685 line, chat_screen SKIP ikut arahan). Schema extension `schema_extend_5_8.sql` dah dirun via `run-sql.sh`: 4 table baru `customer_feedback`, `pos_trackings`, `app_feedback`, `global_staff` + tambah `branches.extras` jsonb + `collab_tasks.poster_branch_id/receiver_shop_id/siri` columns. Mapping: `feedback_{owner}` → `customer_feedback` (maklum_balas: rating/komen per-siri per-branch); `trackings_{owner}` → `pos_trackings` + `app_feedback` collection → `app_feedback` table + `admin_announcements/global` doc → poll-last row dari `admin_announcements` (fungsi_lain); `collab_global_network` → `collab_tasks` w/ payload jsonb stash sender_name/kurier/hantar/terima/catatan/password (collab: semak dealer via branches+tenants JOIN, savedDealers simpan `branches.extras`); `saas_dealers` domain/dealerCode/pageThemes → `tenants.domain/domain_status/dns_records` + `tenants.config.dealerCode/pageThemes` (link); `shops_{owner}` settings → `branches` columns (phone/email/logo_base64/single_staff_mode) + `branches.extras` jsonb (nota/svPass/svTel/bookingQr/etc); `saas_dealers` password → `tenants.password_hash` + `tenants.config.email`; `mail` collection → `mail_queue`; `global_staff` Firestore → `global_staff` table (public read cross-tenant uniqueness); `config/pdf_templates` → `platform_config` id='pdf_templates' value jsonb. `flutter analyze` 0 error (10 pre-existing warnings/info). Ready 5.9.
- `2026-04-15` — **Fasa 5.7 COMPLETE** — 3 file (~6633 line). Schema extension `schema_extend_5_7.sql` 3 table baru: `pro_walkin`, `pro_dealers`, `collab_tasks` (cross-tenant public read). Mapping: `expenses_{owner}` → `expenses` (description=perkara, amount=jumlah, paid_by=staff); `jualan_pantas_{owner}` + `kewangan_{owner}` triple-write → `jobs` + `quick_sales` (kind='JUALAN PANTAS'); `pro_walkin_{owner}` → `pro_walkin` (extra fields stash payload jsonb); `pro_dealers_{owner}` → `pro_dealers`; `collab_global_network` → `collab_tasks` (poster_shop_id filter, payload jsonb); `database_bateri_admin/lcd_admin` → `platform_config` (id='battery_db'/'lcd_db' value jsonb {items:[]}); `system_settings/pengumuman` → `system_settings` table by id='pengumuman'; pro mode toggle → `branches.enabled_modules.proMode`. 0 error 3 file.
- `2026-04-15` — **Fasa 5.6 COMPLETE** — `db_cust_screen.dart` + `referral_screen.dart`. Schema extension `schema_extend_5_6.sql` ditambah: table `referral_claims` baru (referral_id FK, claimed_by, siri, amount, status). Mapping: `referrals_{owner}` → `referrals` (code mapped from refCode; extra bank/accNo/commission/nama/tel stash dalam `created_by` jsonb string); `referral_claims_{owner}` → `referral_claims` (paymentStatus PAID/UNPAID → schema status APPROVED/PENDING); `repairs_{owner}` → `jobs`; `phone_sales_{owner}` → `phone_sales` (device_name/customer_phone/customer_name/sold_at map); tenant config (svPass, addon_gallery) via `tenants.config`/`tenants.addon_gallery`. Voucher jana → `jobs.voucher_generated` + insert `shop_vouchers`. 0 error dua file.
- `2026-04-15` — **Fasa 5.5 COMPLETE** — 4 file (~3943 line). Mapping semua terus ke schema existing (0 schema gap baru): `losses_{owner}` → `losses` (jenis=item_type, jumlah=estimated_value, keterangan=reason, siri stash dalam notes text); `refunds_{owner}` → `refunds` (amount=refund_amount, status=refund_status, bank/method details stash dalam processed_by jsonb); `claims_{owner}` → `claims` (claim_code, claim_status; semua extra field warranty/staff/tarikh stash dalam catatan jsonb); `bookings_{owner}` → `bookings` (status ACTIVE/ARCHIVED/DELETED direct column; nama/tel/model schema column; semua extra siriBooking/staff/harga/deposit/baki/kurier/tracking/resitUrl/pdfUrl stash dalam notes jsonb); `shops_{owner}` settings (courierList, bookingQr/Bank) → `branches.enabled_modules` jsonb; `saas_dealers` → `tenants.domain/config`. Admin password (svPass) → `tenants.config.svPass`. 0 error semua 4 file.
- `2026-04-15` — **Fasa 5.4 COMPLETE** — `phone_stock_screen.dart` (2836 line) habis refactor. Schema extension `schema_extend_5_4.sql` dirun Abe Din: add `phone_stock.deleted_at/deleted_by/sold_siri` + new tables `phone_transfers`/`phone_returns`. Mapping: `phone_stock_{owner}` → `phone_stock` (device_name=nama, price=jual, cost=kos, notes jsonb stash imei/kod/warna/storage/supplier); `phone_sales_{owner}` → `phone_sales` (soft-delete pattern: tong sampah = `deleted_at` SET, recover = SET NULL); `phone_trash_{owner}` DIBUANG — gantikan dengan phone_stock.deleted_at; `phone_sales_trash_{owner}` DIBUANG — gantikan dengan phone_sales.deleted_at; `phone_returns_{owner}` → `phone_returns` (reason=PERMANENT/CLAIM); `phone_transfers_{owner}` → `phone_transfers` (from_branch_id/to_branch_id FK, to_branch_name fallback untuk cross-tenant); `phone_categories_{owner}` + `phone_suppliers_{owner}` + `saved_branches_{owner}` → **disimpan dalam `tenants.config` jsonb** (helper `_readTenantConfigList`/`_updateTenantConfigList`). Transfer accept = insert phone_stock baru + update transfer status ACCEPTED. `flutter analyze` clean (0 error, 13 info/warning pre-existing).
- `2026-04-15` — **Fasa 5.4 SEPARUH** — `stock_screen.dart` (1308 line) + `accessories_screen.dart` (1302 line) SIAP. Mapping: `inventory_{owner}` → `stock_parts` (UI keys: kod=sku, nama=part_name, kos=cost, jual=price); `accessories_{owner}` → `accessories` (nama=item_name, lain sama); `stock_usage_{owner}` + `acc_usage_{owner}` → `stock_usage`/`accessory_usage` (schema takde `status` column — reverse pattern: delete usage row + restore qty); `inventory/{id}/returns` + `accessories/{id}/returns` subcollection → `stock_returns`/`accessory_returns` (FK ke parent part/accessory, supabase join select guna `*, stock_parts(sku, part_name)`). 0 error, 3 pre-existing warnings. Schema extension `schema_extend_5_4.sql` ditulis untuk `phone_stock_screen.dart`: add `phone_stock.deleted_at/deleted_by/sold_siri` columns (soft-delete ganti phone_trash) + new tables `phone_transfers` (antara branches, status PENDING/ACCEPTED/REJECTED) + `phone_returns` (to supplier). `phone_categories/suppliers/saved_branches` simpan dalam `tenants.config` jsonb (no new table). **Abe Din run `schema_extend_5_4.sql` dalam Supabase SQL Editor.** `phone_stock_screen.dart` (2836 line, 35+ sites) defer ke sesi baru.
- `2026-04-15` — **Fasa 5.3 COMPLETE** — `jual_telefon_screen.dart` (2753 line, 25+ sites) habis refactor. Schema extension `schema_extend_5_3.sql` dah dirun Abe Din. Mapping: `dealers_{owner}` → `dealers` (field rename: namaPemilik→nama_pemilik, namaKedai→nama_kedai, noSSM→no_ssm; cawangan jsonb kekal); `phone_receipts_{owner}` → `phone_receipts` (lifecycle field rename: billStatus→bill_status, archivedAt/deletedAt jadi timestamptz; FieldValue.delete() → set NULL); `phone_stock_{owner}` → `phone_stock` (UI keys nama=device_name, jual=price, kos=cost); stock sell update (qty/status SOLD); `phone_sales_{owner}.add` → `phone_sales.insert` (notes jsonb stash imei/kod/warna/storage/kos/siri/saleType/dealer info); `inventory_{owner}` add-on picker → `stock_parts` w/ UI key map; triple-write (phone_receipts+jualan_pantas) → `phone_receipts` + `quick_sales` kind='JUALAN TELEFON'; dealer CRUD (save/delete/update/cawangan) semua guna `dealers` table; trade-in → `phone_stock.insert` w/ condition='TRADE-IN'. Warnings info je (6), 0 error. Ready 5.4.
- `2026-04-15` — **Fasa 5.3 SEPARUH** — `quick_sales_screen.dart` (1937 line) SIAP. Schema extension ditulis (`api supabase/schema_extend_5_3.sql`) tambah 3 table baru: `dealers` (phone suppliers w/ nested cawangan), `saved_bills` (draft invoice w/ payload jsonb), `phone_receipts` (4-state lifecycle ACTIVE/ARCHIVED/DELETED + dealer fields + invoice_url). **Abe Din WAJIB run `schema_extend_5_3.sql` dalam Supabase SQL Editor sebelum test runtime.** Mapping quick_sales: `accessories_{owner}` → `accessories`, `inventory_{owner}` → `stock_parts`, `phone_stock_{owner}` → `phone_stock`, `repairs_{owner}` (cust dedup) → `customers` stream, `shops_{owner}` → `branches` join `branch_staff`, `saved_bills_{owner}` → `saved_bills` table (siri + payload jsonb, upsert on conflict). Triple-write (jualan_pantas+kewangan+repairs) simplify → **2 writes**: `jobs`+`job_items` (unified listing) + `quick_sales` (kind='JUALAN PANTAS', description=siri, income log). Products UI keys dimap ke schema column names (nama/kod/harga/qty). `jual_telefon_screen.dart` (2753 line, 25+ sites, dealer+cawangan management) belum siap — dalam sesi seterusnya.
- `2026-04-15` — **Fasa 5.2 COMPLETE** — `senarai_job_screen.dart` (4058 line) refactor ke Supabase. Mapping: `repairs_{owner}.snapshots` → `jobs.stream` filtered by `branch_id` (transform `created_at` → `timestamp` ms untuk compat UI); `inventory_{owner}.stream` → `stock_parts.stream` (map keys ke UI-compat: `nama`=part_name, `kod`=sku, `jual`=price, `kos`=cost); `shops_{owner}` + `saas_dealers` → joined `branches` + `tenants!inner` (one query); `kewangan_{owner}` → `quick_sales` dengan `kind='REPAIR'` + siri dalam `description` (**schema gap** — takde table khusus; TODO extend later); `warranty_rules` → `branches.enabled_modules` jsonb; jobs update/delete by siri guna helper `_updateJobBySiri` + `_addTimeline` (status_history dibuang dari write, simpan via `job_timeline` rows). `flutter analyze` clean (0 error, 1 info `use_build_context_synchronously` pre-existing).
- `2026-04-15` — **12.6.7 refactor** — `domain_management_screen.dart` buang Firebase Functions (`getDomains`/`getDealers`). `_loadDomains()` + `_showAddDialog()` dealer picker sekarang query `tenants` table terus via Supabase: filter `domain IS NOT NULL` untuk list, order by `nama_kedai`, map schema column → UI key (`owner_id`→`id`, `nama_kedai`→`namaKedai`, `domain_status`→`domainStatus`, `dns_records`→`dnsRecords`). Const `_functionsBase` dibuang. `flutter analyze` clean 0 issue.
- `2026-04-15` — **Fasa 5.1 COMPLETE** — `create_job_screen.dart` refactor ke Supabase. Mapping: `customer_forms_{owner}` → `bookings` (extra fields stashed dalam `notes` JSON); `inventory_{owner}` → `stock_parts` (sku/part_name/price/cost/qty); `stock_usage_{owner}` → `stock_usage` (cancel = delete row + restore qty, no status column); `shop_vouchers_{owner}/{code}` → `shop_vouchers` by `voucher_code` (value inferred dari branch_settings.voucherAmount, claim = bump `used_amount`); `referrals_{owner}/{code}` → `referrals` by `code` (claim = bump `used_count`); `repairs_{owner}/{siri}` → `jobs` update/select by `siri+tenant_id`; customer dedup list → `customers` table terus. Autocomplete UI dipacking semula guna column name schema (`part_name/sku/price`). **Schema gaps** noted: (a) no `referral_claims` log table — skip for now; (b) `referrals.tel` (referrer phone) takde — self-referral check dibuang; (c) `shop_vouchers.value` per-claim takde — fallback ke `branch_settings.voucherAmount`. Firebase Storage kekal untuk image upload (Fasa 7.5). `flutter analyze` clean (0 error, 3 pre-existing info lint). `RepairService` tambah getter `tenantId/branchId`.

---

## 🧭 Entry Point untuk Agent Baru

Kalau sy agent baru baca file ni untuk sambung kerja:

1. **Baca** `api supabase/README.md` ni (full context).
2. **Check** section "Progress Log" — mana last fasa selesai.
3. **Check** keputusan Fasa 0 — kalau belum dijawab, jangan mula coding, tanya user dulu.
4. **Next fasa** — ikut urutan, jangan skip.
5. **Update Progress Log** bila habis satu fasa, commit + push.

### 🚨 Rules WAJIB ikut

1. **Pattern consistency Flutter ↔ Web** — table name, column name, RLS policy, file naming Storage MESTI sama 100% antara `rmsproapp` dan `web_app`. Kalau buat Web, rujuk Flutter sebagai source of truth, jangan reka.
2. **Data split risk** — kalau Web masih Firestore tapi Flutter dah Supabase, WAJIB ikut strategy Fasa 0.8 (dual-write / back-to-back / freeze). Jangan biar dua database hidup sendiri-sendiri tanpa sync.
3. **Marketplace SKIP** — jangan touch `lib/services/marketplace_service.dart`, `billplz_service.dart`, `courier_service.dart`, `lib/screens/marketplace/*`, `lib/models/marketplace_models.dart`.
4. **PDF kekal Cloud Run, FCM kekal Firebase** — jangan cuba pindah ke Supabase Edge Functions atau OneSignal.
5. **Jangan delete Firebase project** sehingga abe din confirm 100% migration berjaya (Fasa 14.5).

### 👤 User Profile

- Panggil **Abe Din** (bukan "user" atau "Din" sahaja).
- Reply dalam **BM santai** (singkatan `sy`, `nk`, `tuka`, `kcuali`, `mcm` dll ok).
- Flutter dulu siap → Web mirror pattern Flutter lepas tu.
- Verbose tak suka — ringkas, padat, point-by-point bila boleh.
