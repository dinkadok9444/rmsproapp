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

### ✅ Include
- **Flutter (`rmsproapp`) DULU** → Web (`web_app`) mirror pattern Flutter kemudian.
- Data layer: Firestore reads/writes → Supabase client.
- Auth: (belum putus — lihat Fasa 0).
- Storage: (audit dulu — lihat Fasa 0).

### ❌ Exclude
- **PDF generation KEKAL di Cloud Run** (`rmsproapp/functions/index.js` + `lib/utils/pdf_url_helper.dart`) — jangan pindah.
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

### 🔹 FASA 0 — Pre-flight Decisions *(tiada coding)*
- [ ] `0.1` **Auth strategy**: Supabase Auth full, atau kekal Firebase Auth (sync je)?
- [ ] `0.2` **Firebase Storage**: audit ada upload gambar ke tak → pindah atau kekal?
- [ ] `0.3` **Credentials**: `.env + flutter_dotenv` / `--dart-define` / hardcode config file?
- [ ] `0.4` **Realtime audit**: screen mana guna `.snapshots()` (live listener) → perlu Supabase Realtime?

> ⚠️ Tanpa jawapan ni, Fasa 1 tak boleh mula.

---

### 🔹 FASA 1 — Foundation Setup *(~30-45 min)*
- [ ] `1.1` Tambah `supabase_flutter` (+ optional `flutter_dotenv`) dalam `rmsproapp/pubspec.yaml`
- [ ] `1.2` Create `rmsproapp/lib/config/supabase_config.dart`
- [ ] `1.3` Create `.env` + tambah dalam `.gitignore` (kalau pilih dotenv)
- [ ] `1.4` Init `Supabase.initialize()` dalam `rmsproapp/lib/main.dart`
- [ ] `1.5` Create helper: `rmsproapp/lib/services/supabase_client.dart` (singleton wrapper)
- [ ] `1.6` Smoke test — app boot, tiada crash

---

### 🔹 FASA 2 — Schema Design & RLS *(~2-3 jam, paling kritikal)*
- [ ] `2.1` Reverse-engineer Firestore structure dari code Flutter
- [ ] `2.2` Tulis SQL schema tables core:
  - `users`, `branches`, `roles`
  - `jobs` (repair), `job_items`, `job_timeline`
  - `bookings`
  - `stock`, `phone_stock`, `accessories`
  - `claims`, `refunds`, `losses` (kerugian)
  - `customers` (db_cust), `referrals`
  - `expenses`, `finance` (kewangan), `promotions`
  - `notifications`, `feedback`, `settings`
- [ ] `2.3` Tambah indexes + foreign keys
- [ ] `2.4` Tulis RLS policies (ganti `rmsproapp/firestore.rules`)
- [ ] `2.5` Run migration SQL di Supabase dashboard
- [ ] `2.6` Save ke `api supabase/schema.sql` + `api supabase/rls.sql`

---

### 🔹 FASA 3 — Auth Layer *(~1-3 jam, bergantung 0.1)*

**Path A (Supabase Auth):**
- [ ] Refactor `rmsproapp/lib/services/auth_service.dart`
- [ ] Update `rmsproapp/lib/screens/login_screen.dart`
- [ ] Migration script: Firebase Auth users → Supabase (email, metadata, roles)
- [ ] Handle role-based routing (admin/supervisor/staff)

**Path B (kekal Firebase Auth):**
- [ ] Bridge: Firebase ID token → Supabase JWT (edge function atau custom endpoint)
- [ ] RLS guna `auth.uid()` mapping ke Firebase UID

---

### 🔹 FASA 4 — Migrate Core Services *(~4-6 jam)*
Order ikut dependency (paling independent dulu):
- [ ] `4.1` `rmsproapp/lib/services/branch_service.dart` *(foundation semua)*
- [ ] `4.2` `rmsproapp/lib/services/saas_flags_service.dart` *(feature flags)*
- [ ] `4.3` `rmsproapp/lib/services/repair_service.dart` *(core business)*
- [ ] `4.4` `rmsproapp/lib/services/notification_service.dart`
- [ ] `4.5` Test tiap service lepas migrate
- [ ] ~~marketplace_service / billplz_service / courier_service~~ **(SKIP)**

---

### 🔹 FASA 5 — Migrate Screens (non-marketplace) *(~4-6 jam)*

**Modules (`lib/screens/modules/`):**
- [ ] `5.1` `create_job_screen.dart`
- [ ] `5.2` `senarai_job_screen.dart`
- [ ] `5.3` `jual_telefon_screen.dart` + `quick_sales_screen.dart`
- [ ] `5.4` `phone_stock_screen.dart`, `stock_screen.dart`, `accessories_screen.dart`
- [ ] `5.5` `booking_screen.dart`, `claim_warranty_screen.dart`, `refund_screen.dart`, `lost_screen.dart`
- [ ] `5.6` `db_cust_screen.dart`, `referral_screen.dart`
- [ ] `5.7` `kewangan_screen.dart`, `dashboard_widget_screen.dart`, `profesional_screen.dart`
- [ ] `5.8` `settings_screen.dart`, `fungsi_lain_screen.dart`, `collab_screen.dart`, `maklum_balas_screen.dart`, `link_screen.dart`, `chat_screen.dart`

**Dashboards:**
- [ ] `5.9` `staff_dashboard_screen.dart`
- [ ] `5.10` `supervisor_dashboard_screen.dart` + semua `sv_*_tab.dart`
- [ ] `5.11` `branch_dashboard_screen.dart`
- [ ] `5.12` `daftar_online_screen.dart`

**Admin modules (`lib/screens/admin_modules/`):**
- [ ] `5.13` `senarai_aktif`, `rekod_jualan`, `database_user`, `daftar_manual`
- [ ] `5.14` `saas_feedback`, `template_pdf`, `whatsapp_bot`, `tong_sampah`
- [ ] `5.15` `tetapan_sistem`, `notis_aduan`, `katakata`, `domain_management` *(skip `marketplace_admin`)*

**SKIP:**
- ~~`lib/screens/marketplace/*`~~
- ~~`lib/models/marketplace_models.dart`~~

---

### 🔹 FASA 6 — Realtime Listeners *(~1-2 jam)*
- [ ] `6.1` Convert `.snapshots()` → Supabase `.stream()` untuk screen perlu realtime
- [ ] `6.2` Test — update dari browser, screen auto refresh

---

### 🔹 FASA 7 — Data Migration *(~2-3 jam)*
- [ ] `7.1` Script Node.js: export Firestore collections → JSON
- [ ] `7.2` Script: transform + import JSON → Supabase (service_role)
- [ ] `7.3` Verify row counts padan
- [ ] `7.4` Save scripts ke `api supabase/migration-scripts/`

---

### 🔹 FASA 8 — Flutter Cleanup *(~30-45 min)*
- [ ] `8.1` Buang `cloud_firestore` dari `rmsproapp/pubspec.yaml`
- [ ] `8.2` Buang `firebase_core` **HANYA kalau** PDF Cloud Run tak perlu client-side Firebase (verify dulu)
- [ ] `8.3` Kekal `firebase_auth` kalau Path B dipilih
- [ ] `8.4` `flutter pub get` + build verify
- [ ] `8.5` Full regression click-through
- [ ] `8.6` Commit + tag `flutter-supabase-migrated`

---

## 🟧 PART B — WEB APP (web_app)

> ⚠️ Bermula **hanya lepas Flutter 100% siap & stable**.

### 🔹 FASA 9 — Web Foundation *(~30 min)*
- [ ] `9.1` Tambah `@supabase/supabase-js` dalam `web_app/package.json`
- [ ] `9.2` Create `web_app/js/supabase-init.js` (mirror `firebase-init.js`)
- [ ] `9.3` Config credentials (env var Vite, atau config file)
- [ ] `9.4` Smoke test — load page, console takde error

---

### 🔹 FASA 10 — Web Auth *(~1-2 jam)*
- [ ] `10.1` Refactor `web_app/js/auth.js` → Supabase auth
- [ ] `10.2` Update `web_app/index.html` login flow
- [ ] `10.3` Session handling — persist antara page reload

---

### 🔹 FASA 11 — Web Screens (mirror Flutter pattern) *(~6-10 jam)*
Order ikut Flutter untuk pattern consistency:

**Core pages:**
- [ ] `11.1` `dashboard.html` + `dashboard_summary.js`
- [ ] `11.2` `create_job.html` + `create_job.js`
- [ ] `11.3` `senarai_job.html` + `baikpulih.html`
- [ ] `11.4` `jual_phone.html`, `pos.html`
- [ ] `11.5` `phone_stock.html`, `stock.html`, `accessories.html`, `inventory.html`
- [ ] `11.6` `booking.html`, `claim.html`, `refund.html`, `kerugian.html`
- [ ] `11.7` `db_cust.html`, `referral.html`
- [ ] `11.8` `kewangan.html`, `widget.html`, `promode.html`
- [ ] `11.9` `settings.html`, `branch.html`, `fungsi_lain.html`
- [ ] `11.10` `kolaborasi.html`, `maklum_balas.html`, `link.html`

**Supervisor:**
- [ ] `11.11` `supervisor.html` + `sv_dashboard.js`

**Helpers:**
- [ ] `11.12` `branch-data.js` (mirror `branch_service.dart`)

---

### 🔹 FASA 12 — Web Cleanup *(~30 min)*
- [ ] `12.1` Buang Firebase SDK dari HTML `<script>` tags
- [ ] `12.2` Buang `firebase-init.js` *(kekal kalau Firebase Auth Path B)*
- [ ] `12.3` Verify build Vite
- [ ] `12.4` Full click-through test

---

## 🟪 PART C — FINAL INTEGRATION

### 🔹 FASA 13 — Cross-platform Verify *(~1-2 jam)*
- [ ] `13.1` Data created di Flutter → visible di Web ✓
- [ ] `13.2` Data created di Web → visible di Flutter ✓
- [ ] `13.3` PDF generation (Cloud Run) — verify URL & auth masih jalan
- [ ] `13.4` Load test ringan — test performance

### 🔹 FASA 14 — Production Cutover *(~1-2 jam, coordinated)*
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

---

## 🧭 Entry Point untuk Agent Baru

Kalau sy agent baru baca file ni untuk sambung kerja:

1. **Baca** `api supabase/README.md` ni (full context).
2. **Check** section "Progress Log" — mana last fasa selesai.
3. **Check** keputusan Fasa 0 — kalau belum dijawab, jangan mula coding, tanya user dulu.
4. **Next fasa** — ikut urutan, jangan skip.
5. **Update Progress Log** bila habis satu fasa, commit + push.

User prefer:
- Panggil **Abe Din**
- Reply dalam **BM santai** (singkatan `sy`, `nk`, `tuka` dll ok)
- Flutter dulu, web ikut pattern Flutter lepas tu
