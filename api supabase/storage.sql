-- Supabase Storage buckets + RLS
-- Run via: ./run-sql.sh storage.sql
-- Note: Buckets kena create dulu via dashboard/SQL; policies attached selepas.

-- Buckets (idempotent)
insert into storage.buckets (id, name, public) values
  ('inventory',        'inventory',        true),
  ('accessories',      'accessories',      true),
  ('phone_stock',      'phone_stock',      true),
  ('repairs',          'repairs',          true),
  ('booking_settings', 'booking_settings', true),
  ('pdf_templates',    'pdf_templates',    true),
  ('staff_avatars',    'staff_avatars',    true),
  ('pos_settings',     'pos_settings',     true)
on conflict (id) do nothing;

-- Helper: extract tenant owner_id from path first segment
-- Path convention: {bucket}/{owner_id}/...  → owner_id = (storage.foldername(name))[1]

-- Read: public buckets → authenticated dapat semua; anon dapat juga sebab public=true
-- Write: only authenticated users in same tenant
do $$
declare
  b text;
begin
  foreach b in array array['inventory','accessories','phone_stock','repairs','booking_settings','staff_avatars','pos_settings']
  loop
    execute format($p$
      drop policy if exists "%1$s_read_all" on storage.objects;
    $p$, b);
    execute format($p$
      create policy "%1$s_read_all" on storage.objects
        for select using (bucket_id = %1$L);
    $p$, b);

    execute format($p$
      drop policy if exists "%1$s_write_own_tenant" on storage.objects;
    $p$, b);
    execute format($p$
      create policy "%1$s_write_own_tenant" on storage.objects
        for insert to authenticated with check (
          bucket_id = %1$L
          and exists (
            select 1 from public.users u
            where u.id = auth.uid()
              and u.tenant_id = (
                select t.id from public.tenants t
                where t.owner_id = (storage.foldername(name))[1]
              )
          )
        );
    $p$, b);

    execute format($p$
      drop policy if exists "%1$s_update_own_tenant" on storage.objects;
    $p$, b);
    execute format($p$
      create policy "%1$s_update_own_tenant" on storage.objects
        for update to authenticated using (
          bucket_id = %1$L
          and exists (
            select 1 from public.users u
            where u.id = auth.uid()
              and u.tenant_id = (
                select t.id from public.tenants t
                where t.owner_id = (storage.foldername(name))[1]
              )
          )
        );
    $p$, b);

    execute format($p$
      drop policy if exists "%1$s_delete_own_tenant" on storage.objects;
    $p$, b);
    execute format($p$
      create policy "%1$s_delete_own_tenant" on storage.objects
        for delete to authenticated using (
          bucket_id = %1$L
          and exists (
            select 1 from public.users u
            where u.id = auth.uid()
              and u.tenant_id = (
                select t.id from public.tenants t
                where t.owner_id = (storage.foldername(name))[1]
              )
          )
        );
    $p$, b);
  end loop;
end $$;

-- pdf_templates: admin only write, public read
drop policy if exists "pdf_templates_read_all" on storage.objects;
create policy "pdf_templates_read_all" on storage.objects
  for select using (bucket_id = 'pdf_templates');

drop policy if exists "pdf_templates_admin_write" on storage.objects;
create policy "pdf_templates_admin_write" on storage.objects
  for all to authenticated using (
    bucket_id = 'pdf_templates'
    and exists (select 1 from public.users where id = auth.uid() and role = 'admin')
  );
