# RMS Pro — Scale Setup Guide (1000 Tenant)

Langkah post-launch untuk capai penjimatan 70%.

## 1. Deploy Fix Yang Dah Siap

```bash
cd rmsproapp
flutter pub get
firebase deploy --only firestore:rules,storage,functions
```

Upgrade Firebase ke **Blaze plan** (wajib untuk scheduled functions + App Check).

## 2. Firebase App Check (Console)

1. Firebase Console → App Check → Register app
2. Android: Play Integrity → dapat SHA-256, register
3. iOS: DeviceCheck / App Attest
4. Web: reCAPTCHA v3 → dapat site key → replace `YOUR_RECAPTCHA_V3_SITE_KEY` dalam `lib/main.dart`
5. Enforcement → enable untuk Firestore, Storage, Functions (lepas test)

## 3. BigQuery Export (Analytics)

Untuk reporting complex tanpa Postgres.

```bash
firebase ext:install firebase/firestore-bigquery-export
```

Config:
- Collection: `marketplace_orders`, `saas_dealers`, `repairs_*`
- Dataset: `rmspro_analytics`
- Cost: ~RM40/bulan untuk 1000 tenant

Query example:
```sql
SELECT ownerID, SUM(totalCharges) as revenue
FROM `rmspro_analytics.repairs_*`
WHERE DATE(createdAt) >= CURRENT_DATE() - 30
GROUP BY ownerID
ORDER BY revenue DESC;
```

## 4. Cloudflare R2 Storage (Egress Save)

Bila bil Firebase Storage egress > RM100/bulan:

1. Cloudflare account → R2 → create bucket `rmspro-assets`
2. Generate API token (S3-compatible)
3. Dart: tambah package `aws_s3_api` atau `minio`
4. Migrate path: `gambar_repair`, `marketplace_products`
5. Egress R2 = **PERCUMA**, storage $0.015/GB

Jimat: ~RM300/bulan pada 1000 tenant.

## 5. Budget Alerts (GCP Console)

1. GCP Console → Billing → Budgets
2. Create budget: RM500/bulan threshold
3. Alert 50%, 90%, 100%
4. Email + FCM webhook ke admin

## 6. Monitoring

- **Crashlytics**: `firebase_crashlytics` package
- **Performance**: `firebase_performance` package
- **Status page**: statuspage.io untuk komunikasi outage

## 7. Firestore Indexes

Tambah composite indexes dalam `firestore.indexes.json` ikut query pattern:
- `saas_dealers`: (totalSales DESC), (createdAt DESC, negeri)
- `marketplace_orders`: (sellerOwnerID, status, createdAt DESC)
- `repairs_*`: (payment_status, createdAt DESC)

Deploy:
```bash
firebase deploy --only firestore:indexes
```

## Ringkasan Savings

| Fix | Status | Jimat |
|-----|--------|-------|
| Storage rules security | ✅ | Prevent abuse |
| Admin pagination | ✅ | ~15% |
| Marketplace pre-agg | ✅ | ~13% |
| Cleanup scheduled | ✅ | ~5% |
| Marketplace limit 50 | ✅ | ~8% |
| Firestore rules | ✅ | Security |
| Rekod jualan pre-agg | ✅ | ~15% |
| App Check | ✅ | Prevent bot abuse |
| Cursor pagination | ✅ | ~5% |
| BigQuery (manual) | ⏳ | ~5% |
| R2 Storage (manual) | ⏳ | ~10% |
| **Total** | | **~70%** |
