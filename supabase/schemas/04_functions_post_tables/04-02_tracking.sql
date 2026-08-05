-- Creates a generic opaque redirect link. The caller receives the raw token
-- separately; only its SHA-256 hash reaches Postgres.
create function public.create_tracking_link(
  p_organization_id uuid,
  p_project_id uuid,
  p_token_hash bytea,
  p_destination_url text,
  p_expires_at timestamp with time zone,
  p_idempotency_key text,
  p_message_id uuid default null,
  p_source text default 'api',
  p_attribution jsonb default '{}'::jsonb
)
returns table (
  tracking_link_id uuid,
  created boolean,
  token_matches boolean,
  link_expires_at timestamp with time zone
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  _project public.tracking_projects%rowtype;
  _tracking_link_id uuid;
  _existing_token_hash bytea;
  _link_expires_at timestamp with time zone;
  _destination_origin text;
begin
  if p_token_hash is null or octet_length(p_token_hash) <> 32 then
    raise exception 'Invalid tracking token hash';
  end if;
  if p_idempotency_key is null
    or length(trim(p_idempotency_key)) not between 8 and 200
  then
    raise exception 'Invalid tracking idempotency key';
  end if;
  if p_expires_at is null or p_expires_at <= now()
    or p_expires_at > now() + interval '365 days'
  then
    raise exception 'Invalid tracking link expiration';
  end if;
  if p_attribution is null or jsonb_typeof(p_attribution) <> 'object'
    or pg_column_size(p_attribution) > 8192
  then
    raise exception 'Invalid tracking attribution';
  end if;

  select * into _project
  from public.tracking_projects
  where id = p_project_id
    and organization_id = p_organization_id
    and status = 'active';
  if not found then raise exception 'Tracking project is unavailable'; end if;

  _destination_origin := substring(p_destination_url from '^(https://[^/?#]+)');
  if _destination_origin is null
    or not (_destination_origin = any(_project.allowed_origins))
  then
    raise exception 'Tracking destination origin is not allowed';
  end if;

  if p_message_id is not null and not exists (
    select 1 from public.messages
    where id = p_message_id and organization_id = p_organization_id
  ) then
    raise exception 'Message does not belong to the organization';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(p_organization_id::text || ':' || p_idempotency_key, 0)
  );

  select id, token_hash, expires_at
  into _tracking_link_id, _existing_token_hash, _link_expires_at
  from public.tracking_links
  where organization_id = p_organization_id
    and idempotency_key = p_idempotency_key;

  if _tracking_link_id is not null then
    return query select _tracking_link_id, false,
      _existing_token_hash = p_token_hash, _link_expires_at;
    return;
  end if;

  insert into public.tracking_links (
    organization_id, project_id, message_id, token_hash, destination_url,
    source, attribution, expires_at, idempotency_key
  ) values (
    p_organization_id, p_project_id, p_message_id, p_token_hash,
    p_destination_url, p_source, p_attribution, p_expires_at,
    p_idempotency_key
  ) returning id into _tracking_link_id;

  return query select _tracking_link_id, true, true, p_expires_at;
end;
$$;

revoke all on function public.create_tracking_link(
  uuid, uuid, bytea, text, timestamp with time zone, text, uuid, text, jsonb
) from public, anon, authenticated;
grant execute on function public.create_tracking_link(
  uuid, uuid, bytea, text, timestamp with time zone, text, uuid, text, jsonb
) to service_role;

-- Starts a direct browser session for a configured project. The public key is
-- non-secret; origin matching is the browser-installation boundary.
create function public.create_tracking_session(
  p_public_key uuid,
  p_session_token_hash bytea,
  p_origin text,
  p_event_count integer
)
returns table (
  tracking_session_id uuid,
  organization_id uuid,
  project_id uuid,
  expires_at timestamp with time zone
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  _project public.tracking_projects%rowtype;
  _session_id uuid;
  _expires_at timestamp with time zone;
begin
  if p_session_token_hash is null or octet_length(p_session_token_hash) <> 32 then
    return;
  end if;
  if p_event_count is null or p_event_count not between 1 and 20 then return; end if;

  select * into _project
  from public.tracking_projects
  where public_key = p_public_key and status = 'active';
  if not found or not (p_origin = any(_project.allowed_origins)) then return; end if;

  -- Origin is an installation boundary, not authentication. This atomic,
  -- configurable ceiling limits non-browser clients that spoof an allowed
  -- Origin while keeping normal campaign bursts available.
  perform pg_advisory_xact_lock(
    hashtextextended('tracking-direct-session:' || _project.id::text, 0)
  );
  if (
    select count(*)
    from public.tracking_sessions as rate_session
    where rate_session.project_id = _project.id
      and rate_session.tracking_link_id is null
      and rate_session.created_at >= now() - interval '1 minute'
  ) >= _project.direct_session_rate_limit_per_minute then
    return;
  end if;

  _expires_at := now() + make_interval(mins => _project.session_ttl_minutes);
  insert into public.tracking_sessions (
    organization_id, project_id, session_token_hash, origin, event_count,
    expires_at
  ) values (
    _project.organization_id, _project.id, p_session_token_hash, p_origin,
    p_event_count, _expires_at
  ) returning id into _session_id;

  return query select _session_id, _project.organization_id, _project.id, _expires_at;
end;
$$;

revoke all on function public.create_tracking_session(uuid, bytea, text, integer)
from public, anon, authenticated;
grant execute on function public.create_tracking_session(uuid, bytea, text, integer)
to service_role;

-- Atomically reserves event slots and resolves the organization/project from
-- the session capability. This prevents concurrent batches from bypassing the
-- per-session ceiling.
create function public.reserve_tracking_session(
  p_session_token_hash bytea,
  p_origin text,
  p_event_count integer
)
returns table (
  tracking_session_id uuid,
  organization_id uuid,
  project_id uuid,
  tracking_link_id uuid,
  message_id uuid,
  session_origin text,
  event_count integer,
  expires_at timestamp with time zone
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  _session record;
begin
  if p_session_token_hash is null or octet_length(p_session_token_hash) <> 32
    or p_event_count is null or p_event_count not between 1 and 20
  then return; end if;

  select session.*, project.allowed_origins, project.status as project_status
  into _session
  from public.tracking_sessions as session
  join public.tracking_projects as project on project.id = session.project_id
  where session.session_token_hash = p_session_token_hash
    and session.revoked_at is null
    and session.expires_at > now()
    and project.status = 'active'
  for update of session;

  if not found or not (p_origin = any(_session.allowed_origins))
    or _session.event_count + p_event_count > 2000
  then return; end if;

  update public.tracking_sessions
  set event_count = public.tracking_sessions.event_count + p_event_count,
    last_seen_at = now()
  where id = _session.id;

  return query select _session.id, _session.organization_id,
    _session.project_id, _session.tracking_link_id, _session.message_id,
    _session.origin, _session.event_count + p_event_count, _session.expires_at;
end;
$$;

revoke all on function public.reserve_tracking_session(bytea, text, integer)
from public, anon, authenticated;
grant execute on function public.reserve_tracking_session(bytea, text, integer)
to service_role;

-- Validates a link and records its technical open atomically. Browser sessions
-- are issued only to human-candidate requests.
create function public.record_tracking_open(
  p_token_hash bytea,
  p_session_token_hash bytea,
  p_event_id uuid,
  p_classification public.tracking_classification,
  p_occurred_at timestamp with time zone,
  p_browser_family text default null,
  p_os_family text default null,
  p_device_type text default null,
  p_country text default null,
  p_region text default null,
  p_referer text default null,
  p_accept_language text default null,
  p_request_id text default null
)
returns table (
  organization_id uuid,
  project_id uuid,
  message_id uuid,
  tracking_link_id uuid,
  tracking_session_id uuid,
  destination_url text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  _link record;
  _session_id uuid;
  _origin text;
begin
  if p_token_hash is null or octet_length(p_token_hash) <> 32 then return; end if;
  if p_session_token_hash is not null
    and octet_length(p_session_token_hash) <> 32
  then return; end if;

  select link.*, project.session_ttl_minutes, project.status as project_status
  into _link
  from public.tracking_links as link
  join public.tracking_projects as project on project.id = link.project_id
  where link.token_hash = p_token_hash
    and link.disabled_at is null
    and link.expires_at > now()
    and project.status = 'active'
  for update of link;
  if not found then return; end if;

  _origin := substring(_link.destination_url from '^(https://[^/?#]+)');
  if p_session_token_hash is not null then
    insert into public.tracking_sessions (
      organization_id, project_id, tracking_link_id, message_id,
      session_token_hash, origin, expires_at
    ) values (
      _link.organization_id, _link.project_id, _link.id, _link.message_id,
      p_session_token_hash, _origin,
      now() + make_interval(mins => _link.session_ttl_minutes)
    ) returning id into _session_id;
  end if;

  insert into public.tracking_events (
    organization_id, project_id, message_id, tracking_link_id,
    tracking_session_id, event_id, event_name, event_type, classification,
    occurred_at, page_path, browser_family, os_family, device_type, country,
    region, referer, accept_language, request_id
  ) values (
    _link.organization_id, _link.project_id, _link.message_id, _link.id,
    _session_id, p_event_id, 'link_open', 'link_open', p_classification,
    p_occurred_at, '/r/:token', left(p_browser_family, 64),
    left(p_os_family, 64), left(p_device_type, 32), left(p_country, 8),
    left(p_region, 128), left(p_referer, 512), left(p_accept_language, 128),
    left(p_request_id, 128)
  ) on conflict on constraint tracking_events_dedup_key do nothing;

  update public.tracking_links set
    first_opened_at = coalesce(first_opened_at, now()),
    last_opened_at = now()
  where id = _link.id;

  return query select _link.organization_id, _link.project_id,
    _link.message_id, _link.id, _session_id, _link.destination_url;
end;
$$;

revoke all on function public.record_tracking_open(
  bytea, bytea, uuid, public.tracking_classification,
  timestamp with time zone, text, text, text, text, text, text, text, text
) from public, anon, authenticated;
grant execute on function public.record_tracking_open(
  bytea, bytea, uuid, public.tracking_classification,
  timestamp with time zone, text, text, text, text, text, text, text, text
) to service_role;

-- Dashboard-safe aggregates. The function checks the JWT-derived organization
-- membership before reading tables that contain capability hashes.
create function public.get_tracking_dashboard(
  p_organization_id uuid,
  p_project_id uuid default null,
  p_from timestamp with time zone default now() - interval '30 days',
  p_to timestamp with time zone default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  _summary jsonb;
  _series jsonb;
  _top_events jsonb;
  _recent jsonb;
begin
  if p_from is null or p_to is null or p_from >= p_to
    or p_to - p_from > interval '366 days'
  then raise exception 'Invalid tracking dashboard range'; end if;

  if not exists (
    select 1
    from public.get_authorized_orgs('member') as authorized(organization_id)
    where organization_id = p_organization_id
  ) then raise exception 'Tracking dashboard access denied'; end if;

  if p_project_id is not null and not exists (
    select 1 from public.tracking_projects
    where id = p_project_id and organization_id = p_organization_id
  ) then raise exception 'Tracking project not found'; end if;

  select jsonb_build_object(
    'tracked_links', count(*) filter (where link.created_at >= p_from and link.created_at < p_to),
    'opened_links', count(*) filter (where link.first_opened_at >= p_from and link.first_opened_at < p_to),
    'open_rate', case when count(*) filter (where link.created_at >= p_from and link.created_at < p_to) = 0
      then 0 else round(
        100.0 * count(*) filter (where link.first_opened_at >= p_from and link.first_opened_at < p_to)
        / count(*) filter (where link.created_at >= p_from and link.created_at < p_to), 2
      ) end
  ) into _summary
  from public.tracking_links as link
  where link.organization_id = p_organization_id
    and (p_project_id is null or link.project_id = p_project_id);

  select _summary || jsonb_build_object(
    'unique_visitors', count(distinct event.tracking_session_id) filter (where event.tracking_session_id is not null),
    'page_views', count(*) filter (where event.event_type = 'page_view'),
    'clicks', count(*) filter (where event.event_type = 'click'),
    'conversions', count(*) filter (where event.event_type in ('form_submit', 'conversion')),
    'events', count(*)
  ) into _summary
  from public.tracking_events as event
  where event.organization_id = p_organization_id
    and (p_project_id is null or event.project_id = p_project_id)
    and event.occurred_at >= p_from and event.occurred_at < p_to;

  select coalesce(jsonb_agg(to_jsonb(day_row) order by day_row.day), '[]'::jsonb)
  into _series from (
    select date_trunc('day', event.occurred_at)::date as day,
      count(*) filter (where event.event_type = 'link_open') as opens,
      count(*) filter (where event.event_type = 'page_view') as page_views,
      count(*) filter (where event.event_type = 'click') as clicks,
      count(*) filter (where event.event_type in ('form_submit', 'conversion')) as conversions
    from public.tracking_events as event
    where event.organization_id = p_organization_id
      and (p_project_id is null or event.project_id = p_project_id)
      and event.occurred_at >= p_from and event.occurred_at < p_to
    group by 1
  ) as day_row;

  select coalesce(jsonb_agg(to_jsonb(event_row) order by event_row.total desc), '[]'::jsonb)
  into _top_events from (
    select event.event_name, event.event_type, count(*) as total
    from public.tracking_events as event
    where event.organization_id = p_organization_id
      and (p_project_id is null or event.project_id = p_project_id)
      and event.occurred_at >= p_from and event.occurred_at < p_to
    group by event.event_name, event.event_type
    order by total desc limit 20
  ) as event_row;

  select coalesce(jsonb_agg(to_jsonb(recent_row) order by recent_row.occurred_at desc), '[]'::jsonb)
  into _recent from (
    select event.event_id, event.project_id, event.message_id, event.event_name,
      event.event_type, event.element_id, event.page_path, event.occurred_at,
      case when message.contact_address is null then null
        when length(message.contact_address) <= 4 then repeat('*', length(message.contact_address))
        else repeat('*', greatest(length(message.contact_address) - 4, 0))
          || right(message.contact_address, 4)
      end as contact_address_masked
    from public.tracking_events as event
    left join public.messages as message on message.id = event.message_id
    where event.organization_id = p_organization_id
      and (p_project_id is null or event.project_id = p_project_id)
      and event.occurred_at >= p_from and event.occurred_at < p_to
    order by event.occurred_at desc limit 50
  ) as recent_row;

  return jsonb_build_object(
    'summary', _summary,
    'series', _series,
    'top_events', _top_events,
    'recent_activity', _recent,
    'from', p_from,
    'to', p_to
  );
end;
$$;

revoke all on function public.get_tracking_dashboard(
  uuid, uuid, timestamp with time zone, timestamp with time zone
) from public, anon;
grant execute on function public.get_tracking_dashboard(
  uuid, uuid, timestamp with time zone, timestamp with time zone
) to authenticated, service_role;

-- Daily retention worker. Detailed data follows each project's configured
-- window; projects and aggregate-ready configuration remain intact.
create function public.cleanup_tracking_data()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  _events integer;
  _sessions integer;
  _links integer;
begin
  delete from public.tracking_events as event
  using public.tracking_projects as project
  where event.project_id = project.id
    and event.received_at < now() - make_interval(days => project.retention_days);
  get diagnostics _events = row_count;

  delete from public.tracking_sessions as session
  using public.tracking_projects as project
  where session.project_id = project.id
    and session.created_at < now() - make_interval(days => project.retention_days);
  get diagnostics _sessions = row_count;

  delete from public.tracking_links as link
  using public.tracking_projects as project
  where link.project_id = project.id
    and link.created_at < now() - make_interval(days => project.retention_days)
    and (link.expires_at < now() or link.disabled_at is not null);
  get diagnostics _links = row_count;

  return jsonb_build_object(
    'events_deleted', _events,
    'sessions_deleted', _sessions,
    'links_deleted', _links
  );
end;
$$;

revoke all on function public.cleanup_tracking_data()
from public, anon, authenticated;
grant execute on function public.cleanup_tracking_data() to service_role;
