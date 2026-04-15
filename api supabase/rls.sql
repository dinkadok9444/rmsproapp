-- =====================================================================
-- RMS PRO — Row-Level Security policies (Fasa 2)
-- Run selepas schema.sql
-- Model:
--   * auth.uid() = users.id (Supabase Auth)
--   * users.tenant_id = tenant yang user tu milik
--   * Helper current_tenant_id() dipakai semua policy tenant-scoped
--   * Role admin = cross-tenant access (Abe Din super-admin)
--   * Public pages (tracking, booking, catalog) guna anon policies terhad
-- =====================================================================

-- ---------------------------------------------------------------------
-- Helper functions
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION current_tenant_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT tenant_id FROM public.users WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION current_user_role()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT role FROM public.users WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION is_platform_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT COALESCE((SELECT role = 'admin' FROM public.users WHERE id = auth.uid()), false);
$$;

-- Enable RLS on every table in public
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', r.tablename);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- Generic tenant-scoped policy helper
-- Generate select/insert/update/delete policies for tables with tenant_id
-- ---------------------------------------------------------------------
DO $$
DECLARE
  r record;
  tbl text;
BEGIN
  FOR r IN
    SELECT DISTINCT table_name
    FROM information_schema.columns
    WHERE table_schema = 'public' AND column_name = 'tenant_id'
  LOOP
    tbl := r.table_name;
    EXECUTE format($f$
      CREATE POLICY tenant_select ON public.%1$I FOR SELECT
        USING (tenant_id = current_tenant_id() OR is_platform_admin());
      CREATE POLICY tenant_insert ON public.%1$I FOR INSERT
        WITH CHECK (tenant_id = current_tenant_id() OR is_platform_admin());
      CREATE POLICY tenant_update ON public.%1$I FOR UPDATE
        USING (tenant_id = current_tenant_id() OR is_platform_admin())
        WITH CHECK (tenant_id = current_tenant_id() OR is_platform_admin());
      CREATE POLICY tenant_delete ON public.%1$I FOR DELETE
        USING (tenant_id = current_tenant_id() OR is_platform_admin());
    $f$, tbl);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- TENANTS table — override generic (no tenant_id column, special rules)
-- User boleh select own tenant row sahaja; admin select all
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS tenant_select ON tenants;
DROP POLICY IF EXISTS tenant_insert ON tenants;
DROP POLICY IF EXISTS tenant_update ON tenants;
DROP POLICY IF EXISTS tenant_delete ON tenants;

CREATE POLICY tenants_select_own ON tenants FOR SELECT
  USING (id = current_tenant_id() OR is_platform_admin());
CREATE POLICY tenants_update_own ON tenants FOR UPDATE
  USING (id = current_tenant_id() OR is_platform_admin());
CREATE POLICY tenants_admin_insert ON tenants FOR INSERT
  WITH CHECK (is_platform_admin());
CREATE POLICY tenants_admin_delete ON tenants FOR DELETE
  USING (is_platform_admin());

-- ---------------------------------------------------------------------
-- USERS — self row + tenant-mates readable; self-update only
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS tenant_select ON users;
DROP POLICY IF EXISTS tenant_insert ON users;
DROP POLICY IF EXISTS tenant_update ON users;
DROP POLICY IF EXISTS tenant_delete ON users;

CREATE POLICY users_select ON users FOR SELECT
  USING (id = auth.uid() OR tenant_id = current_tenant_id() OR is_platform_admin());
CREATE POLICY users_insert_self ON users FOR INSERT
  WITH CHECK (id = auth.uid() OR is_platform_admin());
CREATE POLICY users_update_self ON users FOR UPDATE
  USING (id = auth.uid() OR is_platform_admin())
  WITH CHECK (id = auth.uid() OR is_platform_admin());
CREATE POLICY users_delete_admin ON users FOR DELETE
  USING (is_platform_admin());

-- ---------------------------------------------------------------------
-- BOOKINGS — public can INSERT (customer borang booking)
-- ---------------------------------------------------------------------
CREATE POLICY bookings_public_insert ON bookings FOR INSERT TO anon
  WITH CHECK (tenant_id IS NOT NULL);
-- (Customer tak boleh SELECT booking orang lain; hanya staff dengan JWT boleh)

-- ---------------------------------------------------------------------
-- JOBS — public tracking (read by siri + tel match)
-- Customer check status guna endpoint khas; RLS benarkan anon select
-- JIKA mereka ada siri + tel match. Guna RPC function ganti RLS langsung.
-- (Untuk simplicity, skip policy anon pada jobs; public tracking guna RPC)
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- PHONE_STOCK / ACCESSORIES — public catalog read (barang available sahaja)
-- ---------------------------------------------------------------------
CREATE POLICY phone_stock_public_read ON phone_stock FOR SELECT TO anon
  USING (status = 'AVAILABLE' AND qty > 0);

CREATE POLICY accessories_public_read ON accessories FOR SELECT TO anon
  USING (status = 'AVAILABLE' AND qty > 0);

-- ---------------------------------------------------------------------
-- TENANTS — public read by domain (untuk tenant resolver frontend)
-- Frontend query tenants WHERE domain = window.location.hostname
-- Hanya expose field safe (id, nama_kedai, domain, subdomain, config)
-- Better: buat view terhad + grant anon. Untuk sekarang allow read row.
-- ---------------------------------------------------------------------
CREATE POLICY tenants_public_by_domain ON tenants FOR SELECT TO anon
  USING (active = true);

-- ---------------------------------------------------------------------
-- GLOBAL tables — admin-only write, authenticated read
-- ---------------------------------------------------------------------
CREATE POLICY saas_settings_read_all ON saas_settings FOR SELECT TO authenticated USING (true);
CREATE POLICY saas_settings_admin_write ON saas_settings FOR ALL
  USING (is_platform_admin()) WITH CHECK (is_platform_admin());

CREATE POLICY system_settings_read_all ON system_settings FOR SELECT USING (true);
CREATE POLICY system_settings_admin_write ON system_settings FOR ALL
  USING (is_platform_admin()) WITH CHECK (is_platform_admin());

CREATE POLICY platform_config_admin_only ON platform_config FOR ALL
  USING (is_platform_admin()) WITH CHECK (is_platform_admin());

CREATE POLICY admin_announcements_read_all ON admin_announcements FOR SELECT TO authenticated USING (true);
CREATE POLICY admin_announcements_admin_write ON admin_announcements FOR ALL
  USING (is_platform_admin()) WITH CHECK (is_platform_admin());

CREATE POLICY system_logs_admin_only ON system_logs FOR ALL
  USING (is_platform_admin()) WITH CHECK (is_platform_admin());

CREATE POLICY mail_queue_admin_only ON mail_queue FOR ALL
  USING (is_platform_admin()) WITH CHECK (is_platform_admin());

-- ---------------------------------------------------------------------
-- RPC: public tracking lookup (job status by siri + tel)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public_track_job(p_siri text, p_tel text)
RETURNS TABLE (
  siri text,
  status text,
  model text,
  kerosakan text,
  total numeric,
  payment_status text,
  created_at timestamptz,
  nama_kedai text
) LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT j.siri, j.status, j.model, j.kerosakan, j.total, j.payment_status, j.created_at, t.nama_kedai
  FROM jobs j
  JOIN tenants t ON t.id = j.tenant_id
  WHERE j.siri = p_siri AND j.tel = p_tel
  LIMIT 1;
$$;
GRANT EXECUTE ON FUNCTION public_track_job(text, text) TO anon, authenticated;

-- ---------------------------------------------------------------------
-- RPC: resolve tenant by hostname (for frontend tenant resolver)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION resolve_tenant_by_domain(p_domain text)
RETURNS TABLE (
  id uuid,
  nama_kedai text,
  domain text,
  subdomain text,
  config jsonb,
  active boolean
) LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT id, nama_kedai, domain, subdomain, config, active
  FROM tenants
  WHERE (domain = p_domain OR subdomain = p_domain) AND active = true
  LIMIT 1;
$$;
GRANT EXECUTE ON FUNCTION resolve_tenant_by_domain(text) TO anon, authenticated;
