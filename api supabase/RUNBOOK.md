# Runbook — Production Cutover RMS Pro

Ringkasan langkah Abe Din kena buat sendiri (ada credentials/UI step).

## Status sekarang (2026-04-15)

| Komponen | Status |
|---|---|
| Supabase schema + RLS | ✅ jalan |
| Data migrate (7 tenant, ~200 rows per-table) | ✅ verified |
| Storage (8 bucket, 18 file) | ✅ migrate |
| Flutter `flutter analyze lib/` | ✅ 0 error |
| Web app 26 module JS | ✅ port |
| Smoke test (25/26 pass) | ✅ |

---

## 1. Test Flutter app (sebelum cutover)

```bash
cd rmsproapp
flutter run
```

Login guna credential sedia ada (cth `azam` + password). Test:
- [ ] Dashboard staff/owner buka
- [ ] List repair jobs (senarai_job)
- [ ] Create job baru
- [ ] Stock part tunjuk
- [ ] Phone stock + sale
- [ ] Settings → branch info update
- [ ] Logout + login balik

Kalau ada error, screenshot + bagitahu — Claude fix.

---

## 2. Test Web app (sebelum cutover)

Server local:
```bash
cd web_app && python3 -m http.server 8787
```
Buka http://localhost:8787/

Login → test page utama. Bila confirm OK → deploy.

---

## 3. Deploy ke Cloudflare Pages

### 3.1 First-time login
```bash
wrangler login
```
Browser bukak — auth Cloudflare account.

### 3.2 Deploy
```bash
cd web_app
wrangler pages deploy . --project-name=rmspro-web --commit-dirty=true
```

Output akan bagi URL `https://rmspro-web.pages.dev`. Test URL ni dulu sebelum custom domain.

### 3.3 Custom domain
Cloudflare Dashboard → Pages → `rmspro-web` → Custom domains → Add `app.rmspro.net`. DNS auto-update kalau zone managed by Cloudflare.

---

## 4. Cloudflare for SaaS (multi-tenant custom domain)

Untuk dealer customer guna custom domain (cth `kedai-abc.com` route ke RMS Pro):

```bash
# Dashboard → Workers & Pages → Custom Hostnames → Setup
# Atau guna API:
curl -X POST "https://api.cloudflare.com/client/v4/zones/{ZONE_ID}/custom_hostnames" \
  -H "Authorization: Bearer {API_TOKEN}" \
  -H "Content-Type: application/json" \
  --data '{"hostname":"kedai-abc.com","ssl":{"method":"http","type":"dv"}}'
```

Save returned `id` ke `tenants.cloudflare_hostname_id`.

---

## 5. Production cutover (Fasa 14)

**Order penting — jangan terbalik:**

### 5.1 Data freeze
- Bagitahu user2 jangan tukar data 30 minit
- Run `npm run data && npm run globals && npm run storage` sekali lagi (incremental — pakai upsert)

### 5.2 Verify
```bash
cd "api supabase/migration-scripts"
npm run verify  # fs vs sb count
npm run smoke   # RLS + buckets + counts
```

### 5.3 DNS switch
- Cloudflare DNS: tukar `rmspro.net` A/CNAME dari Firebase Hosting → Cloudflare Pages
- Wait 5 minit propagation
- Test http://app.rmspro.net

### 5.4 Disable Firebase
Selepas 24 jam tanpa issue:
- Firebase Console → Project Settings → suspend Firestore writes
- Kekalkan FCM (push notifications) + Firebase Storage (sampai migrate marketplace/chat)

### 5.5 Tag commit
```bash
cd /Users/mohamadhafizuddin/Desktop/rmspro-web-css-unify
git add -A
git commit -m "feat: Supabase migration complete (Fasa 6-14)"
git tag flutter-supabase-migrated
git push --tags
```

---

## 6. Troubleshooting

### Login gagal "Invalid credentials"
- Check synthetic email format: `{owner_id}@rmspro.internal`
- Run `npm run auth` semula (idempotent)

### Web page kosong / data tak load
- Open browser console — check 401 (anon key salah) atau 403 (RLS block)
- Run `npm run smoke` untuk verify RLS

### Realtime tak refresh
- Check `branches.id` betul dalam channel filter
- Try refresh page — kalau realtime down, polling fallback

### Storage upload gagal
- Check bucket exists (run `storage.sql` semula)
- Check RLS policy: file path mesti start dengan `{owner_id}/`

---

## 7. Marketplace + Chat (KEKAL Firebase)

Per arahan asal — marketplace/ + chat_screen.dart KEKAL Firebase. Tak perlu touch sehingga decision baru. `cloud_firestore + firebase_auth + firebase_storage + firebase_database` kekal dalam pubspec sebab 16 file SKIP masih depend.

---

**Kalau ada issue masa cutover**, screenshot error + tag Claude (sambungan dari conversation ni).
