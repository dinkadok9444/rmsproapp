-- =====================================================================
-- RMS PRO — Schema extension untuk Fasa 5.3
-- Run dalam Supabase SQL Editor SELEPAS schema.sql + rls.sql
-- Menambah 3 table: dealers, saved_bills, phone_receipts
-- =====================================================================

-- ---------------------------------------------------------------------
-- DEALERS (phone suppliers) — Firestore dealers_{ownerID}
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dealers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  branch_id uuid REFERENCES branches(id) ON DELETE SET NULL,
  nama_pemilik text,
  nama_kedai text,
  no_ssm text,
  phone text,
  alamat text,
  cawangan jsonb DEFAULT '[]'::jsonb,   -- [{nama_kedai, alamat_kedai}]
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS dealers_tenant_idx ON dealers(tenant_id);
CREATE INDEX IF NOT EXISTS dealers_branch_idx ON dealers(branch_id);

-- ---------------------------------------------------------------------
-- SAVED_BILLS (draft invoices — quick_sales_screen) — Firestore saved_bills_{ownerID}
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS saved_bills (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  branch_id uuid REFERENCES branches(id) ON DELETE SET NULL,
  siri text NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,   -- full cart + customer state
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE (tenant_id, siri)
);
CREATE INDEX IF NOT EXISTS saved_bills_branch_idx ON saved_bills(branch_id);

-- ---------------------------------------------------------------------
-- PHONE_RECEIPTS (phone sale receipts w/ 4-state lifecycle + dealer mode)
-- Firestore phone_receipts_{ownerID}
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS phone_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  branch_id uuid REFERENCES branches(id) ON DELETE SET NULL,
  siri text NOT NULL,
  sale_type text DEFAULT 'CUSTOMER',          -- CUSTOMER / DEALER
  bill_status text DEFAULT 'ACTIVE',           -- ACTIVE / ARCHIVED / DELETED
  cust_name text,
  cust_phone text,
  cust_address text,
  phone_name text,
  items jsonb DEFAULT '[]'::jsonb,             -- [{nama, kos, jual, imei, stockId, isAccessory}]
  buy_price numeric DEFAULT 0,
  sell_price numeric DEFAULT 0,
  payment_method text,
  payment_term text,
  warranty text,
  staff_name text,
  dealer_id uuid REFERENCES dealers(id) ON DELETE SET NULL,
  dealer_name text,
  dealer_kedai text,
  dealer_ssm text,
  cawangan_nama text,
  cawangan_alamat text,
  invoice_url text,
  archived_at timestamptz,
  deleted_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE (tenant_id, siri)
);
CREATE INDEX IF NOT EXISTS phone_receipts_tenant_idx ON phone_receipts(tenant_id);
CREATE INDEX IF NOT EXISTS phone_receipts_branch_idx ON phone_receipts(branch_id);
CREATE INDEX IF NOT EXISTS phone_receipts_status_idx ON phone_receipts(bill_status);

-- ---------------------------------------------------------------------
-- updated_at trigger + RLS auto-apply (re-run block dari rls.sql)
-- ---------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT table_name FROM information_schema.columns
    WHERE table_schema = 'public'
      AND column_name = 'updated_at'
      AND table_name IN ('dealers', 'saved_bills', 'phone_receipts')
  LOOP
    EXECUTE format(
      'DROP TRIGGER IF EXISTS trg_%1$s_updated ON %1$I;
       CREATE TRIGGER trg_%1$s_updated BEFORE UPDATE ON %1$I
       FOR EACH ROW EXECUTE FUNCTION set_updated_at();',
      r.table_name
    );
  END LOOP;
END $$;

-- Enable RLS + tenant-scoped policy (mirror rls.sql DO block)
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT c.table_name
    FROM information_schema.columns c
    WHERE c.table_schema = 'public'
      AND c.column_name = 'tenant_id'
      AND c.table_name IN ('dealers', 'saved_bills', 'phone_receipts')
  LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY;', r.table_name);
    EXECUTE format(
      'DROP POLICY IF EXISTS tenant_isolation ON %1$I;
       CREATE POLICY tenant_isolation ON %1$I
       FOR ALL TO authenticated
       USING (tenant_id = current_tenant_id() OR is_platform_admin())
       WITH CHECK (tenant_id = current_tenant_id() OR is_platform_admin());',
      r.table_name
    );
  END LOOP;
END $$;
