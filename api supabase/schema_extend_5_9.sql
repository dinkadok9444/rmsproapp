-- =====================================================================
-- RMS PRO — Schema extension untuk Fasa 5.9 (staff dashboard)
-- Run SELEPAS schema_extend_5_8.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- STAFF_COMMISSIONS — Firestore staff_komisyen_{ownerID}
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS staff_commissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  branch_id uuid REFERENCES branches(id) ON DELETE SET NULL,
  staff_name text,
  staff_phone text,
  siri text,
  kind text,                                  -- REPAIR / SALES / etc
  amount numeric DEFAULT 0,
  status text DEFAULT 'PENDING',              -- PENDING / PAID
  paid_at timestamptz,
  payload jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS staff_commissions_tenant_idx ON staff_commissions(tenant_id);
CREATE INDEX IF NOT EXISTS staff_commissions_branch_idx ON staff_commissions(branch_id);
CREATE INDEX IF NOT EXISTS staff_commissions_phone_idx ON staff_commissions(staff_phone);
CREATE INDEX IF NOT EXISTS staff_commissions_status_idx ON staff_commissions(status);

-- ---------------------------------------------------------------------
-- STAFF_LOGS — Firestore staff_logs_{ownerID}
-- (Aktiviti staff: ambil job, tukar status, etc.)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS staff_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  branch_id uuid REFERENCES branches(id) ON DELETE SET NULL,
  staff_name text,
  staff_phone text,
  action text,                                -- AMBIL JOB / UBAH STATUS / etc
  aktiviti text,
  siri text,
  payload jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS staff_logs_tenant_idx ON staff_logs(tenant_id);
CREATE INDEX IF NOT EXISTS staff_logs_branch_idx ON staff_logs(branch_id);
CREATE INDEX IF NOT EXISTS staff_logs_staff_idx ON staff_logs(staff_phone);

-- Trigger updated_at
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT table_name FROM information_schema.columns
    WHERE table_schema = 'public'
      AND column_name = 'updated_at'
      AND table_name IN ('staff_commissions')
  LOOP
    EXECUTE format(
      'DROP TRIGGER IF EXISTS trg_%1$s_updated ON %1$I;
       CREATE TRIGGER trg_%1$s_updated BEFORE UPDATE ON %1$I
       FOR EACH ROW EXECUTE FUNCTION set_updated_at();',
      r.table_name
    );
  END LOOP;
END $$;

-- RLS tenant isolation
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT table_name FROM information_schema.columns
    WHERE table_schema = 'public'
      AND column_name = 'tenant_id'
      AND table_name IN ('staff_commissions', 'staff_logs')
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
