-- =====================================================================
-- RMS PRO — Schema extension untuk Fasa 5.6 (db_cust + referral screens)
-- Run dalam Supabase SQL Editor SELEPAS schema_extend_5_4.sql
-- Menambah: referral_claims (log bila referral code diguna)
-- =====================================================================

CREATE TABLE IF NOT EXISTS referral_claims (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  branch_id uuid REFERENCES branches(id) ON DELETE SET NULL,
  referral_id uuid REFERENCES referrals(id) ON DELETE SET NULL,
  referral_code text,
  claimed_by text,                           -- customer tel/name who used it
  claimed_by_name text,
  siri text,                                 -- job siri (kalau ada)
  amount numeric DEFAULT 0,
  status text DEFAULT 'PENDING',             -- PENDING / APPROVED / REJECTED
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS referral_claims_tenant_idx ON referral_claims(tenant_id);
CREATE INDEX IF NOT EXISTS referral_claims_ref_idx ON referral_claims(referral_id);
CREATE INDEX IF NOT EXISTS referral_claims_code_idx ON referral_claims(referral_code);
CREATE INDEX IF NOT EXISTS referral_claims_status_idx ON referral_claims(status);

-- Trigger + RLS
DO $$
BEGIN
  EXECUTE 'DROP TRIGGER IF EXISTS trg_referral_claims_updated ON referral_claims;
   CREATE TRIGGER trg_referral_claims_updated BEFORE UPDATE ON referral_claims
   FOR EACH ROW EXECUTE FUNCTION set_updated_at();';
  EXECUTE 'ALTER TABLE referral_claims ENABLE ROW LEVEL SECURITY;';
  EXECUTE 'DROP POLICY IF EXISTS tenant_isolation ON referral_claims;
   CREATE POLICY tenant_isolation ON referral_claims
   FOR ALL TO authenticated
   USING (tenant_id = current_tenant_id() OR is_platform_admin())
   WITH CHECK (tenant_id = current_tenant_id() OR is_platform_admin());';
END $$;
