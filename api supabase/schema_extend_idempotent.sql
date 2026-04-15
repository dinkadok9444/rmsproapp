-- Dedup existing rows + add UNIQUE constraints supaya migration script idempotent.
-- Strategy: untuk setiap composite key, retain row dengan id terkecil (created earliest), buang lain.

-- Helper: dedup function for any table by composite key
DO $$
DECLARE r record;
BEGIN
  -- stock_parts
  DELETE FROM stock_parts a USING stock_parts b
  WHERE a.id > b.id AND a.tenant_id = b.tenant_id AND a.branch_id = b.branch_id AND a.sku = b.sku;

  -- accessories
  DELETE FROM accessories a USING accessories b
  WHERE a.id > b.id AND a.tenant_id = b.tenant_id AND a.branch_id = b.branch_id AND a.sku = b.sku;

  -- expenses
  DELETE FROM expenses a USING expenses b
  WHERE a.id > b.id AND a.tenant_id = b.tenant_id AND a.branch_id = b.branch_id
    AND a.description = b.description AND a.amount = b.amount AND a.created_at = b.created_at;

  -- quick_sales
  DELETE FROM quick_sales a USING quick_sales b
  WHERE a.id > b.id AND a.tenant_id = b.tenant_id AND a.branch_id = b.branch_id
    AND coalesce(a.description,'') = coalesce(b.description,'') AND a.amount = b.amount AND coalesce(a.sold_at, '1970-01-01'::timestamptz) = coalesce(b.sold_at, '1970-01-01'::timestamptz);

  -- bookings
  DELETE FROM bookings a USING bookings b
  WHERE a.id > b.id AND a.tenant_id = b.tenant_id AND a.branch_id = b.branch_id
    AND coalesce(a.nama,'') = coalesce(b.nama,'') AND coalesce(a.tel,'') = coalesce(b.tel,'') AND a.created_at = b.created_at;

  -- losses
  DELETE FROM losses a USING losses b
  WHERE a.id > b.id AND a.tenant_id = b.tenant_id AND a.branch_id = b.branch_id
    AND coalesce(a.item_name,'') = coalesce(b.item_name,'') AND a.created_at = b.created_at;

  -- refunds
  DELETE FROM refunds a USING refunds b
  WHERE a.id > b.id AND a.tenant_id = b.tenant_id AND a.branch_id = b.branch_id
    AND coalesce(a.siri,'') = coalesce(b.siri,'') AND a.created_at = b.created_at;

  -- claims
  DELETE FROM claims a USING claims b
  WHERE a.id > b.id AND a.tenant_id = b.tenant_id AND coalesce(a.claim_code,'') = coalesce(b.claim_code,'');

  -- referrals
  DELETE FROM referrals a USING referrals b
  WHERE a.id > b.id AND a.tenant_id = b.tenant_id AND a.code = b.code;

  -- customer_feedback
  DELETE FROM customer_feedback a USING customer_feedback b
  WHERE a.id > b.id AND a.tenant_id = b.tenant_id AND a.branch_id = b.branch_id
    AND coalesce(a.siri,'') = coalesce(b.siri,'') AND a.created_at = b.created_at;

  -- pos_trackings
  DELETE FROM pos_trackings a USING pos_trackings b
  WHERE a.id > b.id AND a.tenant_id = b.tenant_id AND a.branch_id = b.branch_id AND a.track_no = b.track_no;

  -- pro_walkin
  DELETE FROM pro_walkin a USING pro_walkin b
  WHERE a.id > b.id AND a.tenant_id = b.tenant_id AND a.branch_id = b.branch_id AND a.created_at = b.created_at;

  -- pro_dealers
  DELETE FROM pro_dealers a USING pro_dealers b
  WHERE a.id > b.id AND a.tenant_id = b.tenant_id AND a.branch_id = b.branch_id
    AND coalesce(a.nama_kedai,'') = coalesce(b.nama_kedai,'') AND coalesce(a.phone,'') = coalesce(b.phone,'');

  -- dealers
  DELETE FROM dealers a USING dealers b
  WHERE a.id > b.id AND a.tenant_id = b.tenant_id AND a.branch_id = b.branch_id
    AND coalesce(a.nama_kedai,'') = coalesce(b.nama_kedai,'');

  -- mail_queue
  DELETE FROM mail_queue a USING mail_queue b
  WHERE a.id > b.id AND a.recipient = b.recipient AND coalesce(a.subject,'') = coalesce(b.subject,'') AND a.created_at = b.created_at;

  -- collab_tasks
  DELETE FROM collab_tasks a USING collab_tasks b
  WHERE a.id > b.id AND a.owner_tenant_id = b.owner_tenant_id
    AND coalesce(a.poster_shop_id,'') = coalesce(b.poster_shop_id,'') AND a.created_at = b.created_at;
END $$;

-- Now create UNIQUE indexes
CREATE UNIQUE INDEX IF NOT EXISTS stock_parts_uniq ON stock_parts (tenant_id, branch_id, sku);
CREATE UNIQUE INDEX IF NOT EXISTS accessories_uniq ON accessories (tenant_id, branch_id, sku);
CREATE UNIQUE INDEX IF NOT EXISTS expenses_uniq ON expenses (tenant_id, branch_id, description, amount, created_at);
CREATE UNIQUE INDEX IF NOT EXISTS quick_sales_uniq ON quick_sales (tenant_id, branch_id, description, amount, sold_at);
CREATE UNIQUE INDEX IF NOT EXISTS bookings_uniq ON bookings (tenant_id, branch_id, nama, tel, created_at);
CREATE UNIQUE INDEX IF NOT EXISTS losses_uniq ON losses (tenant_id, branch_id, item_name, created_at);
CREATE UNIQUE INDEX IF NOT EXISTS refunds_uniq ON refunds (tenant_id, branch_id, siri, created_at);
CREATE UNIQUE INDEX IF NOT EXISTS claims_uniq ON claims (tenant_id, claim_code);
CREATE UNIQUE INDEX IF NOT EXISTS referrals_uniq ON referrals (tenant_id, code);
CREATE UNIQUE INDEX IF NOT EXISTS customer_feedback_uniq ON customer_feedback (tenant_id, branch_id, siri, created_at);
CREATE UNIQUE INDEX IF NOT EXISTS pos_trackings_uniq ON pos_trackings (tenant_id, branch_id, track_no);
CREATE UNIQUE INDEX IF NOT EXISTS pro_walkin_uniq ON pro_walkin (tenant_id, branch_id, created_at);
CREATE UNIQUE INDEX IF NOT EXISTS pro_dealers_uniq ON pro_dealers (tenant_id, branch_id, nama_kedai, phone);
CREATE UNIQUE INDEX IF NOT EXISTS dealers_uniq ON dealers (tenant_id, branch_id, nama_kedai);
CREATE UNIQUE INDEX IF NOT EXISTS mail_queue_uniq ON mail_queue (recipient, subject, created_at);
CREATE UNIQUE INDEX IF NOT EXISTS collab_tasks_uniq ON collab_tasks (owner_tenant_id, poster_shop_id, created_at);
