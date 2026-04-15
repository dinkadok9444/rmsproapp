# Handoff Brief — RMS Pro Supabase Migration

**Status: 2026-04-15 | Branch: `web-css-unify` | Tag: `v1.0-cutover`**

Copy-paste prompt ni untuk conversation baru:

---

Project: RMS PRO — Migration Firestore → Supabase (multi-tenant SaaS repair shop).
Path: `/Users/mohamadhafizuddin/Desktop/rmspro-web-css-unify/`

Baca DULU: `api supabase/README.md` Progress Log + `api supabase/RUNBOOK.md`.

## LIVE sekarang
- https://rmspro.net (apex, CF Pages, 200 OK SSL)
- https://www.rmspro.net
- https://app.rmspro.net
- Supabase project `lpurtgmqecabgwwenikb`
- Migration 26/26 smoke PASS

## Tugas tinggal (ikut priority)

### 🔴 Manual (Abe Din only — tak boleh agent)
- [ ] Click-through test Flutter app (`cd rmsproapp && flutter run`)
- [ ] Click-through test web (https://rmspro.net login + 26 page)

### 🟡 Infra (interactive, Abe Din)
- [ ] **Token expand**: https://dash.cloudflare.com/profile/api-tokens → edit token → tambah permission:
  - `Zone → SSL and Certificates → Edit`
  - `Zone → Custom Hostnames → Edit`
  - Scope: rmspro.net zone
- [ ] **Deploy Edge Function** untuk domain management:
  ```bash
  cd "api supabase"
  supabase functions deploy cf-custom-hostname --no-verify-jwt
  supabase secrets set CLOUDFLARE_API_TOKEN=<token> CLOUDFLARE_ZONE_ID=2dbf35fb5bd6b3330abe31754f6fd5e8 CF_FALLBACK_ORIGIN=rmspro-web.pages.dev
  ```
- [ ] **Sync tenant domains** (lepas token expand):
  ```bash
  cd "api supabase/migration-scripts" && npm run cf:sync
  ```
- [ ] Firebase Hosting disable via console (cosmetic, FCM kekal)

### 🟠 Agent-completable (low priority)
- [x] Refactor `getDomains` + `getDealers` dari Firebase Functions → Supabase query langsung dalam `domain_management_screen.dart`. ✅ 2026-04-15
- [ ] Fasa 12.6 end-to-end test bila Edge Function deployed: add test tenant domain → verify SSL active → tenant dashboard load via custom hostname.

### 🚫 Decided — JANGAN sentuh
- Marketplace: hidden via `saas_flags`, files kekal (`lib/screens/marketplace/**`). Decision 2026-04-15 per Abe Din.
- Chat: Firebase Realtime Database kekal per arahan.
- FCM firebase_messaging: kekal.
- PDF Cloud Run: kekal.
- Fasa 8 (buang Firebase deps): BLOCKED sebab marketplace + chat masih guna.

## Credentials
- `api supabase/.env` — SUPABASE_*, CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID=`b488fa6babc3aa46b03eb1886ce2f613`
- Zone ID rmspro.net: `2dbf35fb5bd6b3330abe31754f6fd5e8`
- CF Pages project: `rmspro-web`
- Firebase project (FCM only): `rmspro-2f454`

## Rules (dari memory)
- Panggil Abe Din, reply BM santai ringkas
- Audit dulu, terus proceed tanpa tanya A/B
- Tick checkbox dalam README + update Progress Log lepas task
- `flutter analyze lib/` target 0 error
- Schema baru: `schema_extend_X.sql` + `./run-sql.sh`
- Web mirror Flutter 1:1

## Recent commits (this session)
```
451ec98 Fasa 12.6 prep — tenant resolver + CF custom hostname tooling
62728e6 Cutover apex rmspro.net → Cloudflare Pages
2c0e0ab Hide marketplace from UI (default off)
d6c606a Deploy web_app to Cloudflare Pages (rmspro-web)
faa1102 Wire printer integration to senarai_job + baikpulih
05bbf69 Complete Fasa 11 stub backlog — 10 advanced features across 10 modules
```
