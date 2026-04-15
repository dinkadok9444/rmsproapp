-- =====================================================================
-- RMS PRO — RPC functions (Fasa 4)
-- Run selepas schema.sql + rls.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- next_siri — atomic ticket-number generator per (tenant, branch)
-- Replaces Firestore transaction on counters_{ownerID}/{shopID}_global
-- Format: {shop_code}{0-padded 5-digit count}  e.g. "MAIN00042"
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION next_siri(
  p_tenant_id uuid,
  p_branch_id uuid,
  p_shop_code text
) RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_count bigint;
  v_pure_shop text;
BEGIN
  INSERT INTO job_counters (tenant_id, branch_id, count)
  VALUES (p_tenant_id, p_branch_id, 1)
  ON CONFLICT (tenant_id, branch_id)
  DO UPDATE SET count = job_counters.count + 1, updated_at = now()
  RETURNING count INTO v_count;

  -- Legacy: kalau shop_code ada "-", ambil bahagian selepas "-"
  v_pure_shop := CASE
    WHEN position('-' in p_shop_code) > 0 THEN split_part(p_shop_code, '-', 2)
    ELSE p_shop_code
  END;

  RETURN v_pure_shop || lpad(v_count::text, 5, '0');
END;
$$;

GRANT EXECUTE ON FUNCTION next_siri(uuid, uuid, text) TO authenticated;
