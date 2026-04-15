-- =====================================================================
-- RMS PRO — Schema extension untuk Fasa 5.4 (phone_stock_screen)
-- Run dalam Supabase SQL Editor SELEPAS schema_extend_5_3.sql
-- Menambah: phone_transfers, phone_returns
-- Strategi: phone_categories/suppliers/saved_branches disimpan dalam
-- tenants.config jsonb (no new table). phone_trash digantikan dengan
-- phone_stock.deleted_at soft-delete (mirror phone_sales pattern).
-- =====================================================================

-- ---------------------------------------------------------------------
-- phone_stock — tambah deleted_at untuk soft-delete (ganti phone_trash)
-- ---------------------------------------------------------------------
ALTER TABLE phone_stock
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz,
  ADD COLUMN IF NOT EXISTS deleted_by text,
  ADD COLUMN IF NOT EXISTS sold_siri text;      -- link balik ke job siri bila SOLD

CREATE INDEX IF NOT EXISTS phone_stock_active_idx
  ON phone_stock(tenant_id, deleted_at) WHERE deleted_at IS NULL;

-- ---------------------------------------------------------------------
-- PHONE_TRANSFERS — Firestore phone_transfers_{ownerID}
-- Transfer stock antara branches (sending/accepted/rejected)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS phone_transfers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  from_branch_id uuid REFERENCES branches(id) ON DELETE SET NULL,
  to_branch_id uuid REFERENCES branches(id) ON DELETE SET NULL,
  to_branch_name text,                          -- fallback nama text jika dealer/external
  phone_stock_id uuid REFERENCES phone_stock(id) ON DELETE SET NULL,
  device_name text,
  imei text,
  kos numeric DEFAULT 0,
  jual numeric DEFAULT 0,
  status text DEFAULT 'PENDING',                -- PENDING / ACCEPTED / REJECTED
  notes text,
  transferred_at timestamptz DEFAULT now(),
  accepted_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS phone_transfers_tenant_idx ON phone_transfers(tenant_id);
CREATE INDEX IF NOT EXISTS phone_transfers_from_idx ON phone_transfers(from_branch_id);
CREATE INDEX IF NOT EXISTS phone_transfers_to_idx ON phone_transfers(to_branch_id);
CREATE INDEX IF NOT EXISTS phone_transfers_status_idx ON phone_transfers(status);

-- ---------------------------------------------------------------------
-- PHONE_RETURNS — Firestore phone_returns_{ownerID}
-- Phone returned to supplier/warehouse (pending disposition)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS phone_returns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  branch_id uuid REFERENCES branches(id) ON DELETE SET NULL,
  phone_stock_id uuid REFERENCES phone_stock(id) ON DELETE SET NULL,
  device_name text,
  imei text,
  kos numeric DEFAULT 0,
  jual numeric DEFAULT 0,
  reason text,
  returned_by text,
  returned_at timestamptz DEFAULT now(),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS phone_returns_tenant_idx ON phone_returns(tenant_id);
CREATE INDEX IF NOT EXISTS phone_returns_branch_idx ON phone_returns(branch_id);

-- ---------------------------------------------------------------------
-- updated_at trigger + RLS auto-apply
-- ---------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT table_name FROM information_schema.columns
    WHERE table_schema = 'public'
      AND column_name = 'updated_at'
      AND table_name IN ('phone_transfers', 'phone_returns')
  LOOP
    EXECUTE format(
      'DROP TRIGGER IF EXISTS trg_%1$s_updated ON %1$I;
       CREATE TRIGGER trg_%1$s_updated BEFORE UPDATE ON %1$I
       FOR EACH ROW EXECUTE FUNCTION set_updated_at();',
      r.table_name
    );
  END LOOP;
END $$;

DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT c.table_name
    FROM information_schema.columns c
    WHERE c.table_schema = 'public'
      AND c.column_name = 'tenant_id'
      AND c.table_name IN ('phone_transfers', 'phone_returns')
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
