-- =====================================================================
-- RMS PRO — Schema extension untuk Fasa 5.7 (kewangan, dashboard, profesional)
-- Run dalam Supabase SQL Editor SELEPAS schema_extend_5_6.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- PRO_WALKIN — Firestore pro_walkin_{ownerID} (professional walk-in jobs)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pro_walkin (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  branch_id uuid REFERENCES branches(id) ON DELETE SET NULL,
  siri text,
  nama text,
  tel text,
  model text,
  kerosakan text,
  harga numeric DEFAULT 0,
  kos numeric DEFAULT 0,
  status text DEFAULT 'ACTIVE',
  archived boolean DEFAULT false,
  payload jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS pro_walkin_tenant_idx ON pro_walkin(tenant_id);
CREATE INDEX IF NOT EXISTS pro_walkin_branch_idx ON pro_walkin(branch_id);
CREATE INDEX IF NOT EXISTS pro_walkin_archived_idx ON pro_walkin(archived);

-- ---------------------------------------------------------------------
-- PRO_DEALERS — Firestore pro_dealers_{ownerID}
-- (Asing dari 'dealers' yang untuk phone supplier. Pro dealers = partner shop)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pro_dealers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  branch_id uuid REFERENCES branches(id) ON DELETE SET NULL,
  nama_pemilik text,
  nama_kedai text,
  no_ssm text,
  phone text,
  alamat text,
  cawangan jsonb DEFAULT '[]'::jsonb,
  payload jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS pro_dealers_tenant_idx ON pro_dealers(tenant_id);
CREATE INDEX IF NOT EXISTS pro_dealers_branch_idx ON pro_dealers(branch_id);

-- ---------------------------------------------------------------------
-- COLLAB_TASKS — Firestore collab_global_network (cross-tenant task board)
-- Public read (semua tenants boleh nampak), post-owner boleh edit
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS collab_tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  poster_shop_id text,                          -- shop code yang post
  poster_name text,
  nama text,
  tel text,
  model text,
  kerosakan text,
  harga numeric DEFAULT 0,
  status text DEFAULT 'OPEN',                   -- OPEN / TAKEN / DONE / ARCHIVED
  taken_by_tenant_id uuid REFERENCES tenants(id) ON DELETE SET NULL,
  archived boolean DEFAULT false,
  payload jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS collab_tasks_owner_idx ON collab_tasks(owner_tenant_id);
CREATE INDEX IF NOT EXISTS collab_tasks_status_idx ON collab_tasks(status);
CREATE INDEX IF NOT EXISTS collab_tasks_archived_idx ON collab_tasks(archived);

-- Trigger + RLS (collab_tasks ada public read + owner-only write via custom policy)
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT table_name FROM information_schema.columns
    WHERE table_schema = 'public'
      AND column_name = 'updated_at'
      AND table_name IN ('pro_walkin', 'pro_dealers', 'collab_tasks')
  LOOP
    EXECUTE format(
      'DROP TRIGGER IF EXISTS trg_%1$s_updated ON %1$I;
       CREATE TRIGGER trg_%1$s_updated BEFORE UPDATE ON %1$I
       FOR EACH ROW EXECUTE FUNCTION set_updated_at();',
      r.table_name
    );
  END LOOP;
END $$;

-- Tenant isolation untuk pro_walkin + pro_dealers
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT table_name FROM information_schema.columns
    WHERE table_schema = 'public'
      AND column_name = 'tenant_id'
      AND table_name IN ('pro_walkin', 'pro_dealers')
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

-- collab_tasks: public read (all authenticated), write only owner tenant
ALTER TABLE collab_tasks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS collab_read ON collab_tasks;
CREATE POLICY collab_read ON collab_tasks
  FOR SELECT TO authenticated
  USING (true);
DROP POLICY IF EXISTS collab_write_owner ON collab_tasks;
CREATE POLICY collab_write_owner ON collab_tasks
  FOR ALL TO authenticated
  USING (owner_tenant_id = current_tenant_id() OR is_platform_admin())
  WITH CHECK (owner_tenant_id = current_tenant_id() OR is_platform_admin());

-- ---------------------------------------------------------------------
-- database_bateri_admin + database_lcd_admin → simpan dalam platform_config
-- (no new table — guna existing platform_config jsonb)
-- Akses guna: SELECT value FROM platform_config WHERE id IN ('battery_db', 'lcd_db')
-- ---------------------------------------------------------------------
INSERT INTO platform_config (id, value) VALUES
  ('battery_db', '{"items":[]}'::jsonb),
  ('lcd_db', '{"items":[]}'::jsonb)
ON CONFLICT (id) DO NOTHING;
