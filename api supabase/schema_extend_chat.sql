-- =============================================================
-- Dealer Support chat — user (branch) ↔ Dealer Support (platform admin)
-- One thread per branch, keyed by branch_id. Platform admin can see all.
-- Replaces Firebase RTDB rms_chat_v4/tickets (support model).
-- =============================================================

CREATE TABLE IF NOT EXISTS public.sv_tickets (
  id           uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid         NOT NULL,
  branch_id    uuid         NOT NULL,
  sender_id    text         NOT NULL,
  sender_name  text         NOT NULL,
  role         text         NOT NULL CHECK (role IN ('user', 'admin')),
  text         text         NOT NULL,
  created_at   timestamptz  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS sv_tickets_branch_created_idx
  ON public.sv_tickets (branch_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.sv_ticket_meta (
  branch_id    uuid         PRIMARY KEY,
  tenant_id    uuid         NOT NULL,
  name         text,
  shop_code    text,
  last_msg     text,
  last_ts      timestamptz,
  last_from    text,       -- 'user' | 'admin'
  updated_at   timestamptz  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS sv_ticket_meta_last_ts_idx
  ON public.sv_ticket_meta (last_ts DESC);

-- RLS
ALTER TABLE public.sv_tickets     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sv_ticket_meta ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS sv_tickets_select ON public.sv_tickets;
CREATE POLICY sv_tickets_select ON public.sv_tickets
  FOR SELECT USING (tenant_id = current_tenant_id() OR is_platform_admin());

DROP POLICY IF EXISTS sv_tickets_insert ON public.sv_tickets;
CREATE POLICY sv_tickets_insert ON public.sv_tickets
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id() OR is_platform_admin());

DROP POLICY IF EXISTS sv_ticket_meta_select ON public.sv_ticket_meta;
CREATE POLICY sv_ticket_meta_select ON public.sv_ticket_meta
  FOR SELECT USING (tenant_id = current_tenant_id() OR is_platform_admin());

DROP POLICY IF EXISTS sv_ticket_meta_upsert ON public.sv_ticket_meta;
CREATE POLICY sv_ticket_meta_upsert ON public.sv_ticket_meta
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id() OR is_platform_admin());

DROP POLICY IF EXISTS sv_ticket_meta_update ON public.sv_ticket_meta;
CREATE POLICY sv_ticket_meta_update ON public.sv_ticket_meta
  FOR UPDATE USING (tenant_id = current_tenant_id() OR is_platform_admin())
              WITH CHECK (tenant_id = current_tenant_id() OR is_platform_admin());

-- Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.sv_tickets;
ALTER PUBLICATION supabase_realtime ADD TABLE public.sv_ticket_meta;
