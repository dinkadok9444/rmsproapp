-- =====================================================================
-- RMS PRO — Schema extension untuk Fasa 5.8
-- (settings, fungsi_lain, collab, maklum_balas, link, chat)
-- Run dalam Supabase SQL Editor SELEPAS schema_extend_5_7.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- CUSTOMER_FEEDBACK — Firestore feedback_{ownerID}
-- (Customer rating + comment lepas repair siap. Per-branch, per-siri)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS customer_feedback (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  branch_id uuid REFERENCES branches(id) ON DELETE SET NULL,
  siri text,
  nama text,
  tel text,
  rating integer,
  komen text,
  payload jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS customer_feedback_tenant_idx ON customer_feedback(tenant_id);
CREATE INDEX IF NOT EXISTS customer_feedback_branch_idx ON customer_feedback(branch_id);
CREATE INDEX IF NOT EXISTS customer_feedback_siri_idx ON customer_feedback(siri);

-- ---------------------------------------------------------------------
-- POS_TRACKINGS — Firestore trackings_{ownerID}
-- (Pos / courier tracking per-branch)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pos_trackings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  branch_id uuid REFERENCES branches(id) ON DELETE SET NULL,
  tarikh text,
  item text,
  kurier text,
  track_no text,
  status_track text DEFAULT 'DIPOS',
  payload jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS pos_trackings_tenant_idx ON pos_trackings(tenant_id);
CREATE INDEX IF NOT EXISTS pos_trackings_branch_idx ON pos_trackings(branch_id);

-- ---------------------------------------------------------------------
-- APP_FEEDBACK — Firestore app_feedback
-- (Dealer hantar cadangan/aduan/bug ke developer)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS app_feedback (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  branch_id uuid REFERENCES branches(id) ON DELETE SET NULL,
  sender_role text,
  sender_name text,
  message text NOT NULL,
  status text DEFAULT 'open',                  -- open / resolved
  resolve_note text,
  resolved_at timestamptz,
  payload jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS app_feedback_tenant_idx ON app_feedback(tenant_id);
CREATE INDEX IF NOT EXISTS app_feedback_status_idx ON app_feedback(status);

-- ---------------------------------------------------------------------
-- GLOBAL_STAFF — Firestore global_staff
-- (Cross-tenant staff phone uniqueness check — prevent double-register)
-- Public read (all authenticated), write only via app
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS global_staff (
  tel text PRIMARY KEY,
  tenant_id uuid REFERENCES tenants(id) ON DELETE CASCADE,
  branch_id uuid REFERENCES branches(id) ON DELETE SET NULL,
  owner_id text,
  shop_id text,
  nama text,
  role text,
  payload jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS global_staff_tenant_idx ON global_staff(tenant_id);

-- ---------------------------------------------------------------------
-- Trigger updated_at
-- ---------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT table_name FROM information_schema.columns
    WHERE table_schema = 'public'
      AND column_name = 'updated_at'
      AND table_name IN ('pos_trackings', 'global_staff')
  LOOP
    EXECUTE format(
      'DROP TRIGGER IF EXISTS trg_%1$s_updated ON %1$I;
       CREATE TRIGGER trg_%1$s_updated BEFORE UPDATE ON %1$I
       FOR EACH ROW EXECUTE FUNCTION set_updated_at();',
      r.table_name
    );
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- RLS: customer_feedback, pos_trackings, app_feedback — tenant isolated
-- ---------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT table_name FROM information_schema.columns
    WHERE table_schema = 'public'
      AND column_name = 'tenant_id'
      AND table_name IN ('customer_feedback', 'pos_trackings', 'app_feedback')
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

-- global_staff: public read (for cross-tenant uniqueness check), write any auth
ALTER TABLE global_staff ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS global_staff_read ON global_staff;
CREATE POLICY global_staff_read ON global_staff
  FOR SELECT TO authenticated
  USING (true);
DROP POLICY IF EXISTS global_staff_write ON global_staff;
CREATE POLICY global_staff_write ON global_staff
  FOR ALL TO authenticated
  USING (tenant_id = current_tenant_id() OR is_platform_admin())
  WITH CHECK (tenant_id = current_tenant_id() OR is_platform_admin());

-- ---------------------------------------------------------------------
-- Seed: admin_announcements global row (replaces Firestore admin_announcements/global)
-- Access pattern: SELECT * FROM admin_announcements ORDER BY created_at DESC LIMIT 1
-- ---------------------------------------------------------------------
-- (no seed needed — table exists; fungsi_lain akan fetch latest)

-- ---------------------------------------------------------------------
-- Branches.extras jsonb — simpan savedDealers + misc branch-level config
-- ---------------------------------------------------------------------
ALTER TABLE branches ADD COLUMN IF NOT EXISTS extras jsonb DEFAULT '{}'::jsonb;

-- ---------------------------------------------------------------------
-- collab_tasks extend: tambah poster_branch_id + receiver_shop_id untuk
-- support filter per-branch (bukan sekadar per-tenant)
-- ---------------------------------------------------------------------
ALTER TABLE collab_tasks ADD COLUMN IF NOT EXISTS poster_branch_id uuid REFERENCES branches(id) ON DELETE SET NULL;
ALTER TABLE collab_tasks ADD COLUMN IF NOT EXISTS receiver_shop_id text;
ALTER TABLE collab_tasks ADD COLUMN IF NOT EXISTS siri text;
CREATE INDEX IF NOT EXISTS collab_tasks_poster_branch_idx ON collab_tasks(poster_branch_id);
CREATE INDEX IF NOT EXISTS collab_tasks_receiver_idx ON collab_tasks(receiver_shop_id);
