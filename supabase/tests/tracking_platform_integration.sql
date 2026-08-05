begin;

do $$
declare
  _organization_id uuid := '3a182d8d-d6d8-44bd-b021-029915476b8c';
  _user_id uuid := '185f2f83-d63a-4c9b-b4a0-7e4a885799e2';
  _project_id uuid;
  _project_key uuid;
  _link_id uuid;
  _link_retry_id uuid;
  _created boolean;
  _token_matches boolean;
  _link_expires_at timestamp with time zone;
  _session_id uuid;
  _rate_session_id uuid;
  _link_session_id uuid;
  _dashboard jsonb;
  _rows integer;
  _i integer;
begin
  insert into public.tracking_projects (
    organization_id, name, slug, allowed_origins, default_destination_url,
    direct_session_rate_limit_per_minute
  ) values (
    _organization_id,
    'Integration tracking project',
    'integration-tracking-project',
    array['https://landing.example'],
    'https://landing.example/campaign',
    10
  ) returning id, public_key into _project_id, _project_key;

  select tracking_link_id, created, token_matches, link_expires_at
  into _link_id, _created, _token_matches, _link_expires_at
  from public.create_tracking_link(
    _organization_id,
    _project_id,
    digest('integration-link-token', 'sha256'),
    'https://landing.example/campaign',
    now() + interval '30 days',
    'integration-link-key',
    null,
    'whatsapp',
    '{"campaign":"integration"}'::jsonb
  );
  if _link_id is null or not _created or not _token_matches then
    raise exception 'tracking link was not created';
  end if;

  select tracking_link_id, created, token_matches, link_expires_at
  into _link_retry_id, _created, _token_matches, _link_expires_at
  from public.create_tracking_link(
    _organization_id,
    _project_id,
    digest('integration-link-token', 'sha256'),
    'https://landing.example/campaign',
    now() + interval '30 days',
    'integration-link-key',
    null,
    'whatsapp',
    '{}'::jsonb
  );
  if _link_retry_id is distinct from _link_id or _created or not _token_matches then
    raise exception 'safe tracking link retry failed';
  end if;

  select tracking_link_id, created, token_matches, link_expires_at
  into _link_retry_id, _created, _token_matches, _link_expires_at
  from public.create_tracking_link(
    _organization_id,
    _project_id,
    digest('another-token-that-must-not-win', 'sha256'),
    'https://landing.example/campaign',
    now() + interval '30 days',
    'integration-link-key',
    null,
    'whatsapp',
    '{}'::jsonb
  );
  if _link_retry_id is distinct from _link_id or _created or _token_matches then
    raise exception 'tracking link idempotency conflict was not detected';
  end if;

  select count(*) into _rows
  from public.create_tracking_session(
    _project_key,
    digest('blocked-origin-session', 'sha256'),
    'https://other.example',
    1
  );
  if _rows <> 0 then raise exception 'unapproved origin created a session'; end if;

  select tracking_session_id into _session_id
  from public.create_tracking_session(
    _project_key,
    digest('direct-session', 'sha256'),
    'https://landing.example',
    1
  );
  if _session_id is null then raise exception 'direct session was not created'; end if;

  for _i in 1..9 loop
    select tracking_session_id into _rate_session_id
    from public.create_tracking_session(
      _project_key,
      digest('rate-session-' || _i::text, 'sha256'),
      'https://landing.example',
      1
    );
    if _rate_session_id is null then
      raise exception 'direct session rate limit activated too early';
    end if;
  end loop;

  select count(*) into _rows
  from public.create_tracking_session(
    _project_key,
    digest('rate-session-overflow', 'sha256'),
    'https://landing.example',
    1
  );
  if _rows <> 0 then raise exception 'direct session rate limit was bypassed'; end if;

  select tracking_session_id into _link_session_id
  from public.record_tracking_open(
    digest('integration-link-token', 'sha256'),
    digest('linked-session', 'sha256'),
    gen_random_uuid(),
    'human_candidate',
    now(),
    'Chrome',
    'Windows',
    'desktop',
    'BR',
    'SP',
    'https://referrer.example/path',
    'pt-BR',
    'integration-request'
  );
  if _link_session_id is null then raise exception 'link session was not created'; end if;

  select count(*) into _rows
  from public.reserve_tracking_session(
    digest('direct-session', 'sha256'),
    'https://landing.example',
    1
  );
  if _rows <> 1 then raise exception 'session reservation failed'; end if;

  insert into public.tracking_events (
    organization_id, project_id, tracking_session_id, event_id, event_name,
    event_type, occurred_at, page_path, metadata
  ) values (
    _organization_id, _project_id, _session_id, gen_random_uuid(),
    'hero.cta_clicked', 'click', now(), '/campaign', '{"section":"hero"}'
  );

  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', _user_id::text, 'role', 'authenticated')::text,
    true
  );
  _dashboard := public.get_tracking_dashboard(
    _organization_id, _project_id, now() - interval '1 day', now() + interval '1 day'
  );
  if (_dashboard #>> '{summary,tracked_links}')::integer <> 1
    or (_dashboard #>> '{summary,clicks}')::integer <> 1
    or jsonb_array_length(_dashboard->'recent_activity') < 2
  then raise exception 'dashboard aggregation failed: %', _dashboard; end if;

  if has_table_privilege('anon', 'public.tracking_projects', 'SELECT')
    or has_table_privilege('authenticated', 'public.tracking_events', 'SELECT')
    or not has_table_privilege('authenticated', 'public.tracking_projects', 'SELECT')
  then raise exception 'tracking table privileges are unsafe'; end if;

  if has_function_privilege(
    'anon',
    'public.create_tracking_link(uuid,uuid,bytea,text,timestamp with time zone,text,uuid,text,jsonb)',
    'EXECUTE'
  ) or has_function_privilege(
    'authenticated',
    'public.reserve_tracking_session(bytea,text,integer)',
    'EXECUTE'
  ) then raise exception 'public tracking RPC privileges are unsafe'; end if;
end;
$$;

rollback;
