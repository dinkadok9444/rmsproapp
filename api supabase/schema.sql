-- =====================================================================
-- RMS PRO — Supabase schema (Fasa 2)
-- Generated: 2026-04-15
-- Source: reverse-engineered dari Firestore collections rmsproapp/lib
-- Multi-tenant: semua tenant-scoped table ada tenant_id FK ke tenants(id)
-- Excludes: marketplace_* (postponed)
-- =====================================================================

-- Extensions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ---------------------------------------------------------------------
-- TENANTS (root — Firestore saas_dealers)
-- ---------------------------------------------------------------------
CREATE TABLE tenants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id text UNIQUE NOT NULL,               -- original Firestore ownerID (keep for migration mapping)
  domain text UNIQUE,                           -- custom domain e.g. profixmobile.my
  subdomain text UNIQUE,                        -- rmspro.net/<subdomain> fallback
  nama_kedai text NOT NULL,
  password_hash text,                           -- legacy login (akan dibuang lepas Supabase Auth)
  status text DEFAULT 'Aktif',
  session_token text,
  domain_status text DEFAULT 'PENDING_DNS',     -- PENDING_DNS / VERIFIED / ACTIVE
  dns_records jsonb DEFAULT '[]'::jsonb,
  cloudflare_hostname_id text,
  ssl_status text DEFAULT 'pending',
  single_staff_mode boolean DEFAULT false,
  expire_date timestamptz,
  addon_gallery boolean DEFAULT false,
  gallery_expire timestamptz,
  bot_whatsapp jsonb DEFAULT '{}'::jsonb,       -- {verifyToken, phoneNumberId, accessToken, ...}
  total_sales numeric DEFAULT 0,
  ticket_count integer DEFAULT 0,
  last_sale_at timestamptz,
  config jsonb DEFAULT '{}'::jsonb,             -- branding + misc settings
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX tenants_domain_idx ON tenants(domain);
CREATE INDEX tenants_subdomain_idx ON tenants(subdomain);
CREATE INDEX tenants_owner_id_idx ON tenants(owner_id);

-- ---------------------------------------------------------------------
-- USERS (Supabase Auth link + profile)
-- ---------------------------------------------------------------------
CREATE TABLE users (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  email text,
  phone text,
  nama text,
  role text NOT NULL DEFAULT 'staff',           -- admin / owner / supervisor / staff
  pin text,                                     -- legacy 4-6 digit login PIN
  status text DEFAULT 'active',
  current_branch_id uuid,                       -- FK added after branches table
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX users_tenant_id_idx ON users(tenant_id);
CREATE INDEX users_phone_idx ON users(phone);
CREATE INDEX users_role_idx ON users(role);

-- ---------------------------------------------------------------------
-- BRANCHES (Firestore shops_{ownerID})
-- ---------------------------------------------------------------------
CREATE TABLE branches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  shop_code text NOT NULL,                      -- original shopID (MAIN, BRANCH1, etc.)
  nama_kedai text NOT NULL,
  alamat text,
  phone text,
  email text,
  logo_base64 text,
  enabled_modules jsonb DEFAULT '{}'::jsonb,
  single_staff_mode boolean DEFAULT false,
  expire_date timestamptz,
  pdf_cloud_run_url text,                       -- merged from branch_pdf_settings
  use_custom_pdf_url boolean DEFAULT false,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE (tenant_id, shop_code)
);
CREATE INDEX branches_tenant_id_idx ON branches(tenant_id);

-- Add the deferred FK on users.current_branch_id
ALTER TABLE users ADD CONSTRAINT users_current_branch_fk
  FOREIGN KEY (current_branch_id) REFERENCES branches(id) ON DELETE SET NULL;

-- Staff assignment (was embedded array shops.staffList)
CREATE TABLE branch_staff (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  branch_id uuid NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  user_id uuid REFERENCES users(id) ON DELETE SET NULL,
  nama text NOT NULL,
  phone text,
  pin text,
  role text DEFAULT 'staff',                    -- staff / supervisor
  status text DEFAULT 'active',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX branch_staff_branch_idx ON branch_staff(branch_id);
CREATE INDEX branch_staff_tenant_idx ON branch_staff(tenant_id);
CREATE INDEX branch_staff_phone_idx ON branch_staff(phone);

-- ---------------------------------------------------------------------
-- JOBS (Firestore repairs_{ownerID}) + DRAFTS + COUNTERS
-- ---------------------------------------------------------------------
CREATE TABLE jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  branch_id uuid NOT NULL REFERENCES branches(id) ON DELETE RESTRICT,
  siri text NOT NULL,                           -- ticket number (unique per tenant)
  receipt_no text,
  nama text,
  tel text,
  tel_wasap text,
  model text,
  kerosakan text,
  jenis_servis text,
  status text DEFAULT 'IN PROGRESS',
  tarikh date,
  harga numeric DEFAULT 0,
  deposit numeric DEFAULT 0,
  diskaun numeric DEFAULT 0,
  tambahan numeric DEFAULT 0,
  total numeric DEFAULT 0,
  baki numeric DEFAULT 0,
  payment_status text DEFAULT 'PENDING',        -- PAID / PENDING / PARTIAL
  cara_bayaran text,
  voucher_generated text,
  voucher_used text,
  voucher_used_amt numeric DEFAULT 0,
  device_password text,
  cust_type text,
  staff_terima text,
  staff_repair text,
  staff_serah text,
  catatan text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE (tenant_id, siri)
);
CREATE INDEX jobs_tenant_idx ON jobs(tenant_id);
CREATE INDEX jobs_branch_idx ON jobs(branch_id);
CREATE INDEX jobs_status_idx ON jobs(status);
CREATE INDEX jobs_tel_idx ON jobs(tel);
CREATE INDEX jobs_created_at_idx ON jobs(created_at DESC);

-- Extracted from embedded items_array
CREATE TABLE job_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  job_id uuid NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  nama text NOT NULL,
  qty integer DEFAULT 1,
  harga numeric DEFAULT 0,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX job_items_job_idx ON job_items(job_id);
CREATE INDEX job_items_tenant_idx ON job_items(tenant_id);

-- Extracted from embedded status_history array
CREATE TABLE job_timeline (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  job_id uuid NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  status text NOT NULL,
  note text,
  by_user text,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX job_timeline_job_idx ON job_timeline(job_id);
CREATE INDEX job_timeline_tenant_idx ON job_timeline(tenant_id);

-- Drafts (Firestore drafts_{ownerID})
CREATE TABLE job_drafts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  branch_id uuid NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,   -- simpan form state penuh
  status text DEFAULT 'ACTIVE',                 -- ACTIVE / PULLED
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX job_drafts_branch_idx ON job_drafts(branch_id);
CREATE INDEX job_drafts_tenant_idx ON job_drafts(tenant_id);

-- Siri counter per branch (replaces Firestore counters_{ownerID})
CREATE TABLE job_counters (
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  branch_id uuid NOT NULL REFERENCES branches(id) ON DELETE CASCADE,
  count bigint NOT NULL DEFAULT 0,
  updated_at timestamptz DEFAULT now(),
  PRIMARY KEY (tenant_id, branch_id)
);

-- ---------------------------------------------------------------------
-- CLAIMS (warranty) + REFUNDS + LOSSES
-- ---------------------------------------------------------------------
CREATE TABLE claims (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  branch_id uuid NOT NULL REFERENCES branches(id) ON DELETE RESTRICT,
  job_id uuid REFERENCES jobs(id) ON DELETE SET NULL,
  siri text,                                    -- keep for historical search
  claim_code text,
  nama text,
  claim_status text DEFAULT 'PENDING',          -- PENDING / CLAIM APPROVE / CLAIM REJECT
  approved_by text,
  approved_at timestamptz,
  reject_reason text,
  catatan text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX claims_tenant_idx ON claims(tenant_id);
CREATE INDEX claims_branch_idx ON claims(branch_id);
CREATE INDEX claims_job_idx ON claims(job_id);

CREATE TABLE refunds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  branch_id uuid NOT NULL REFERENCES branches(id) ON DELETE RESTRICT,
  job_id uuid REFERENCES jobs(id) ON DELETE SET NULL,
  siri text,
  nama text,
  refund_amount numeric DEFAULT 0,
  refund_status text DEFAULT 'PENDING',
  reason text,
  processed_by text,
  processed_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX refunds_tenant_idx ON refunds(tenant_id);
CREATE INDEX refunds_job_idx ON refunds(job_id);

CREATE TABLE losses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  branch_id uuid REFERENCES branches(id) ON DELETE SET NULL,
  item_type text,                               -- DEVICE / PART / CASH / OTHER
  item_name text,
  quantity integer DEFAULT 1,
  estimated_value numeric DEFAULT 0,
  reason text,
  reported_by text,
  reported_at timestamptz DEFAULT now(),
  status text DEFAULT 'REPORTED',
  notes text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX losses_tenant_idx ON losses(tenant_id);

-- ---------------------------------------------------------------------
-- INVENTORY — parts, phone stock, accessories + usage logs
-- ---------------------------------------------------------------------
CREATE TABLE stock_parts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  branch_id uuid REFERENCES branches(id) ON DELETE SET NULL,
  sku text,
  part_name text NOT NULL,
  qty integer DEFAULT 0,
  price numeric DEFAULT 0,
  cost numeric DEFAULT 0,
  category text,
  reorder_level integer DEFAULT 0,
  status text DEFAULT 'AVAILABLE',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX stock_parts_tenant_idx ON stock_parts(tenant_id);
CREATE INDEX stock_parts_branch_idx ON stock_parts(branch_id);

CREATE TABLE stock_usage (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  branch_id uuid REFERENCES branches(id) ON DELETE SET NULL,
  stock_part_id uuid REFERENCES stock_parts(id) ON DELETE SET NULL,
  job_id uuid REFERENCES jobs(id) ON DELETE SET NULL,
  part_name text,
  qty integer DEFAULT 1,
  reason text,
  used_by text,
  used_at timestamptz DEFAULT now(),
  created_at timestamptz DEFAULT now()
);
CREATE INDEX stock_usage_tenant_idx ON stock_usage(tenant_id);
CREATE INDEX stock_usage_job_idx ON stock_usage(job_id);

CREATE TABLE stock_returns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  stock_part_id uuid NOT NULL REFERENCES stock_parts(id) ON DELETE CASCADE,
  qty integer DEFAULT 1,
  reason text,
  staff text,
  returned_at timestamptz DEFAULT now()
);
CREATE INDEX stock_returns_part_idx ON stock_returns(stock_part_id);

CREATE TABLE phone_stock (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  branch_id uuid REFERENCES branches(id) ON DELETE SET NULL,
  device_name text NOT NULL,
  qty integer DEFAULT 0,
  price numeric DEFAULT 0,
  cost numeric DEFAULT 0,
  condition text,                               -- NEW / EXCELLENT / GOOD / FAIR
  status text DEFAULT 'AVAILABLE',
  added_by text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX phone_stock_tenant_idx ON phone_stock(tenant_id);
CREATE INDEX phone_stock_branch_idx ON phone_stock(branch_id);

CREATE TABLE phone_sales (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  branch_id uuid REFERENCES branches(id) ON DELETE SET NULL,
  phone_stock_id uuid REFERENCES phone_stock(id) ON DELETE SET NULL,
  device_name text,
  qty integer DEFAULT 1,
  price_per_unit numeric DEFAULT 0,
  total_price numeric DEFAULT 0,
  customer_name text,
  customer_phone text,
  sold_by text,
  sold_at timestamptz DEFAULT now(),
  payment_method text,
  payment_status text DEFAULT 'PAID',
  notes text,
  deleted_at timestamptz,                       -- soft delete (replaces phone_trash)
  deleted_by text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX phone_sales_tenant_idx ON phone_sales(tenant_id);
CREATE INDEX phone_sales_branch_idx ON phone_sales(branch_id);
CREATE INDEX phone_sales_active_idx ON phone_sales(tenant_id, deleted_at) WHERE deleted_at IS NULL;

CREATE TABLE accessories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  branch_id uuid REFERENCES branches(id) ON DELETE SET NULL,
  sku text,
  item_name text NOT NULL,
  category text,
  qty integer DEFAULT 0,
  price numeric DEFAULT 0,
  cost numeric DEFAULT 0,
  supplier text,
  status text DEFAULT 'AVAILABLE',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX accessories_tenant_idx ON accessories(tenant_id);
CREATE INDEX accessories_branch_idx ON accessories(branch_id);

CREATE TABLE accessory_usage (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  branch_id uuid REFERENCES branches(id) ON DELETE SET NULL,
  accessory_id uuid REFERENCES accessories(id) ON DELETE SET NULL,
  job_id uuid REFERENCES jobs(id) ON DELETE SET NULL,
  item_name text,
  qty integer DEFAULT 1,
  used_by text,
  used_at timestamptz DEFAULT now(),
  created_at timestamptz DEFAULT now()
);
CREATE INDEX accessory_usage_tenant_idx ON accessory_usage(tenant_id);

CREATE TABLE accessory_returns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  accessory_id uuid NOT NULL REFERENCES accessories(id) ON DELETE CASCADE,
  qty integer DEFAULT 1,
  reason text,
  staff text,
  returned_at timestamptz DEFAULT now()
);
CREATE INDEX accessory_returns_acc_idx ON accessory_returns(accessory_id);

-- ---------------------------------------------------------------------
-- BOOKINGS (customer online booking) — public insert via RLS
-- ---------------------------------------------------------------------
CREATE TABLE bookings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  branch_id uuid REFERENCES branches(id) ON DELETE SET NULL,
  nama text NOT NULL,
  tel text NOT NULL,
  model text,
  kerosakan text,
  booking_date date,
  booking_time text,
  status text DEFAULT 'PENDING',                -- PENDING / CONFIRMED / CANCELLED / DONE
  notes text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX bookings_tenant_idx ON bookings(tenant_id);
CREATE INDEX bookings_branch_idx ON bookings(branch_id);
CREATE INDEX bookings_status_idx ON bookings(status);

-- ---------------------------------------------------------------------
-- CUSTOMERS (db_cust) + REFERRALS + VOUCHERS
-- ---------------------------------------------------------------------
CREATE TABLE customers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  nama text,
  tel text,
  email text,
  alamat text,
  notes text,
  total_repairs integer DEFAULT 0,
  total_spend numeric DEFAULT 0,
  last_visit_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE (tenant_id, tel)
);
CREATE INDEX customers_tenant_idx ON customers(tenant_id);
CREATE INDEX customers_tel_idx ON customers(tel);

CREATE TABLE referrals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  code text NOT NULL,
  discount_percent numeric DEFAULT 0,
  discount_amount numeric DEFAULT 0,
  max_uses integer DEFAULT 0,                   -- 0 = unlimited
  used_count integer DEFAULT 0,
  valid_from timestamptz,
  valid_until timestamptz,
  created_by text,
  status text DEFAULT 'ACTIVE',                 -- ACTIVE / EXPIRED / DISABLED
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE (tenant_id, code)
);
CREATE INDEX referrals_tenant_idx ON referrals(tenant_id);

CREATE TABLE shop_vouchers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  branch_id uuid REFERENCES branches(id) ON DELETE CASCADE,
  voucher_code text NOT NULL,
  allocated_amount numeric DEFAULT 0,
  used_amount numeric DEFAULT 0,
  remaining numeric GENERATED ALWAYS AS (allocated_amount - used_amount) STORED,
  expiry_date timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX shop_vouchers_tenant_idx ON shop_vouchers(tenant_id);

-- ---------------------------------------------------------------------
-- FINANCE — expenses, quick sales, summary
-- ---------------------------------------------------------------------
CREATE TABLE expenses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  branch_id uuid REFERENCES branches(id) ON DELETE SET NULL,
  unique_key text,                              -- dedup key from Firestore
  category text,
  amount numeric DEFAULT 0,
  description text,
  paid_by text,
  paid_date date,
  receipt_url text,
  status text DEFAULT 'PAID',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX expenses_tenant_idx ON expenses(tenant_id);
CREATE INDEX expenses_branch_idx ON expenses(branch_id);
CREATE INDEX expenses_paid_date_idx ON expenses(paid_date);

CREATE TABLE quick_sales (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  branch_id uuid REFERENCES branches(id) ON DELETE SET NULL,
  kind text,                                    -- SALE / SERVICE_CHARGE / MISC_INCOME
  amount numeric DEFAULT 0,
  description text,
  sold_by text,
  sold_at timestamptz DEFAULT now(),
  payment_method text,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX quick_sales_tenant_idx ON quick_sales(tenant_id);
CREATE INDEX quick_sales_branch_idx ON quick_sales(branch_id);

CREATE TABLE finance_summary (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  branch_id uuid REFERENCES branches(id) ON DELETE CASCADE,
  period_date date NOT NULL,                    -- per-hari summary
  total_repair_income numeric DEFAULT 0,
  total_device_sales numeric DEFAULT 0,
  total_accessory_sales numeric DEFAULT 0,
  total_expenses numeric DEFAULT 0,
  net_profit numeric DEFAULT 0,
  sold_devices integer DEFAULT 0,
  completed_repairs integer DEFAULT 0,
  updated_at timestamptz DEFAULT now(),
  UNIQUE (tenant_id, branch_id, period_date)
);
CREATE INDEX finance_summary_tenant_idx ON finance_summary(tenant_id);
CREATE INDEX finance_summary_date_idx ON finance_summary(period_date);

-- ---------------------------------------------------------------------
-- NOTIFICATIONS / FEEDBACK / COMPLAINTS
-- ---------------------------------------------------------------------
CREATE TABLE fcm_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  branch_id uuid REFERENCES branches(id) ON DELETE CASCADE,
  user_id uuid REFERENCES users(id) ON DELETE CASCADE,
  token text NOT NULL UNIQUE,
  platform text,                                -- web / ios / android
  updated_at timestamptz DEFAULT now(),
  created_at timestamptz DEFAULT now()
);
CREATE INDEX fcm_tokens_branch_idx ON fcm_tokens(branch_id);
CREATE INDEX fcm_tokens_tenant_idx ON fcm_tokens(tenant_id);

CREATE TABLE notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  branch_id uuid REFERENCES branches(id) ON DELETE CASCADE,
  user_id uuid REFERENCES users(id) ON DELETE CASCADE,
  kind text,                                    -- booking_new / job_ready / payment / etc.
  title text,
  body text,
  data jsonb DEFAULT '{}'::jsonb,
  read boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX notifications_tenant_idx ON notifications(tenant_id);
CREATE INDEX notifications_user_idx ON notifications(user_id);
CREATE INDEX notifications_unread_idx ON notifications(user_id, read) WHERE read = false;

CREATE TABLE feedback (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  category text,                                -- feature_request / improvement / general
  message text NOT NULL,
  rating integer,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX feedback_tenant_idx ON feedback(tenant_id);

CREATE TABLE system_complaints (                -- Firestore aduan_sistem
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  subject text,
  description text,
  screenshot_url text,
  status text DEFAULT 'OPEN',                   -- OPEN / IN_REVIEW / RESOLVED
  priority text DEFAULT 'medium',
  assigned_to text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX system_complaints_tenant_idx ON system_complaints(tenant_id);

-- ---------------------------------------------------------------------
-- COLLABORATIONS (collab_global_network)
-- ---------------------------------------------------------------------
CREATE TABLE collaborations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  partner_tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  kind text,                                    -- referral / partnership
  status text DEFAULT 'PENDING',                -- PENDING / ACTIVE / ENDED
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE (tenant_id, partner_tenant_id, kind)
);
CREATE INDEX collaborations_tenant_idx ON collaborations(tenant_id);
CREATE INDEX collaborations_partner_idx ON collaborations(partner_tenant_id);

-- ---------------------------------------------------------------------
-- GLOBAL / ADMIN (no tenant_id)
-- ---------------------------------------------------------------------
CREATE TABLE saas_settings (
  id text PRIMARY KEY,                          -- e.g. "feature_flags"
  value jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE system_settings (
  id text PRIMARY KEY,                          -- e.g. "pengumuman"
  title text,
  message text,
  severity text,                                -- info / warning / critical
  enabled boolean DEFAULT true,
  start_date timestamptz,
  end_date timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE platform_config (                  -- Firestore "config"
  id text PRIMARY KEY,                          -- toyyibpay / courier / pdf_templates
  value jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE admin_announcements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text,
  body text,
  priority text DEFAULT 'normal',               -- normal / urgent
  created_at timestamptz DEFAULT now()
);

CREATE TABLE system_logs (
  id text PRIMARY KEY,                          -- e.g. "cleanup", "jobs"
  last_run timestamptz,
  results jsonb DEFAULT '{}'::jsonb,
  errors jsonb DEFAULT '{}'::jsonb,
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE mail_queue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient text NOT NULL,
  subject text,
  html text,
  text_body text,
  delivery_state text DEFAULT 'PENDING',        -- PENDING / SUCCESS / ERROR
  attempts integer DEFAULT 0,
  message_id text,
  delivered_at timestamptz,
  error text,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX mail_queue_state_idx ON mail_queue(delivery_state);

-- ---------------------------------------------------------------------
-- updated_at trigger helper
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Attach trigger to semua table yang ada updated_at column
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT table_name FROM information_schema.columns
    WHERE table_schema = 'public' AND column_name = 'updated_at'
  LOOP
    EXECUTE format(
      'DROP TRIGGER IF EXISTS trg_%1$s_updated ON %1$I;
       CREATE TRIGGER trg_%1$s_updated BEFORE UPDATE ON %1$I
       FOR EACH ROW EXECUTE FUNCTION set_updated_at();',
      r.table_name
    );
  END LOOP;
END $$;
