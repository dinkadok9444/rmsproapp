-- Backfill jobs.tel dari customers.tel (match by tenant + nama)
-- Safe to re-run: hanya update baris yang tel kosong/null/'-'

UPDATE jobs j
SET tel = c.tel
FROM customers c
WHERE j.tenant_id = c.tenant_id
  AND LOWER(TRIM(j.nama)) = LOWER(TRIM(c.nama))
  AND j.nama IS NOT NULL
  AND TRIM(j.nama) <> ''
  AND c.tel IS NOT NULL
  AND TRIM(c.tel) <> ''
  AND (j.tel IS NULL OR TRIM(j.tel) = '' OR TRIM(j.tel) = '-');

-- Report berapa baris ada tel selepas backfill
SELECT
  COUNT(*) FILTER (WHERE tel IS NOT NULL AND TRIM(tel) NOT IN ('', '-')) AS jobs_with_tel,
  COUNT(*) FILTER (WHERE tel IS NULL OR TRIM(tel) IN ('', '-')) AS jobs_missing_tel,
  COUNT(*) AS total_jobs
FROM jobs;
