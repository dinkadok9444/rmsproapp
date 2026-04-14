# API Supabase — Rujukan

Folder ni simpan credentials & rujukan Supabase untuk projek **rms-pro-flutter**.
Tujuan: supaya Claude (assistant) boleh rujuk balik pada future conversation.

⚠️ **PENTING**: Repo ni **PRIVATE**. Jangan tukar ke public selagi file ni ada credentials.

---

## Project Info

- **Project Ref**: `lpurtgmqecabgwwenikb`
- **Project URL**: `https://lpurtgmqecabgwwenikb.supabase.co`
- **Region**: (isi bila tahu)
- **Created**: 2026-04-15

## Credentials

### Anon (public) key
Guna dalam Flutter app (rmsproapp) dan web_app. Selamat untuk client-side **kalau RLS enabled**.

```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxwdXJ0Z21xZWNhYmd3d2VuaWtiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYxODQ2MTUsImV4cCI6MjA5MTc2MDYxNX0.7FiqQwNJC6XXv0r8Emmt9KyygOnHfSrXVirsJBIsdhU
```

- Role: `anon`
- Issued: 1776184615
- Expires: 2091760615 (~10 tahun)

### Service role key
❌ **BELUM disimpan** — jangan letak dalam file yang akan di-bundle ke Flutter/web client.
Tempat simpan bila ada: Cloud Run env var, atau file berasingan yang di-`.gitignore`.

---

## Scope Migrasi

- **Flutter (rmsproapp) dibuat DULU**, web_app mirror pattern Flutter kemudian.
- PDF generation **KEKAL di Cloud Run** (`rmsproapp/functions/index.js`) — tak pindah.
- 149 fail guna Firestore (pre-migration audit): web_app ~40, rmsproapp ~60+.

## Keputusan Belum Dibuat

- [ ] Auth: pindah ke Supabase Auth, atau kekal Firebase Auth?
- [ ] Firebase Storage: pindah ke Supabase Storage juga?
- [ ] Realtime: mana screen yang guna `.snapshots()` live listener?
- [ ] Schema: design dari scratch vs reverse-engineer dari Firestore?
- [ ] Entry point: service mana nk POC dulu?

## Dashboard Links

- Supabase Dashboard: https://supabase.com/dashboard/project/lpurtgmqecabgwwenikb
- API Settings: https://supabase.com/dashboard/project/lpurtgmqecabgwwenikb/settings/api
- Database: https://supabase.com/dashboard/project/lpurtgmqecabgwwenikb/editor
- Auth: https://supabase.com/dashboard/project/lpurtgmqecabgwwenikb/auth/users
- Storage: https://supabase.com/dashboard/project/lpurtgmqecabgwwenikb/storage/buckets
