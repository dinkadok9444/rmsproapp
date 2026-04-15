-- Master catalog for phone component codes. Owner-maintained; shared across tenants.
-- Consumed by: web_app/widget.js (Cari Komponen) + admin_database_komponen.html

-- Categories (admin-managed list)
CREATE TABLE IF NOT EXISTS master_component_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,                    -- BATERI / LCD / TOUCHSCREEN / ...
  sort_order integer DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

-- Components
CREATE TABLE IF NOT EXISTS master_components (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category text NOT NULL,                       -- free text, matches master_component_categories.name
  brand text NOT NULL,
  model text NOT NULL,
  code text NOT NULL,
  notes text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS master_components_category_idx ON master_components(category);
CREATE INDEX IF NOT EXISTS master_components_model_idx ON master_components(lower(model));
CREATE INDEX IF NOT EXISTS master_components_brand_idx ON master_components(lower(brand));

-- RLS
ALTER TABLE master_component_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE master_components ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS mcc_read ON master_component_categories;
CREATE POLICY mcc_read ON master_component_categories FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS mcc_write ON master_component_categories;
CREATE POLICY mcc_write ON master_component_categories FOR ALL TO authenticated
  USING (is_platform_admin()) WITH CHECK (is_platform_admin());

DROP POLICY IF EXISTS mc_read ON master_components;
CREATE POLICY mc_read ON master_components FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS mc_write ON master_components;
CREATE POLICY mc_write ON master_components FOR ALL TO authenticated
  USING (is_platform_admin()) WITH CHECK (is_platform_admin());

-- Migration: if earlier version had CHECK constraint, drop it
ALTER TABLE master_components DROP CONSTRAINT IF EXISTS master_components_category_check;
