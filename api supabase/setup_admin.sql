DO $$
DECLARE
  _admin_email     text := 'admin@rmspro.internal';
  _admin_password  text := 'master123';
  _admin_user_id   uuid;
  _platform_tenant uuid;
BEGIN
  DELETE FROM auth.users WHERE email = _admin_email;

  SELECT id INTO _platform_tenant FROM public.tenants WHERE owner_id = '__platform__';
  IF _platform_tenant IS NULL THEN
    INSERT INTO public.tenants (owner_id, nama_kedai, status, active)
    VALUES ('__platform__', 'RMS Platform Admin', 'Aktif', true)
    RETURNING id INTO _platform_tenant;
  END IF;

  _admin_user_id := gen_random_uuid();
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data, is_sso_user,
    confirmation_token, recovery_token, email_change_token_new, email_change
  )
  VALUES (
    _admin_user_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated',
    _admin_email,
    crypt(_admin_password, gen_salt('bf')),
    now(), now(), now(),
    jsonb_build_object('provider', 'email', 'providers', ARRAY['email']),
    '{}'::jsonb,
    false,
    '', '', '', ''
  );

  INSERT INTO auth.identities (
    provider_id, user_id, identity_data, provider,
    last_sign_in_at, created_at, updated_at
  )
  VALUES (
    _admin_email,
    _admin_user_id,
    jsonb_build_object(
      'sub', _admin_user_id::text,
      'email', _admin_email,
      'email_verified', true,
      'phone_verified', false
    ),
    'email',
    now(), now(), now()
  );

  INSERT INTO public.users (id, tenant_id, email, nama, role, status)
  VALUES (_admin_user_id, _platform_tenant, _admin_email, 'Platform Admin', 'admin', 'active');
END $$;

SELECT u.id, u.email, u.email_confirmed_at IS NOT NULL AS confirmed,
       pu.role, pu.status,
       (SELECT count(*) FROM auth.identities WHERE user_id = u.id) AS identity_count
  FROM auth.users u
  JOIN public.users pu ON pu.id = u.id
 WHERE u.email = 'admin@rmspro.internal';
