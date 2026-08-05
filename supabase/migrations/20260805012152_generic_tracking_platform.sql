create type "public"."tracking_classification" as enum ('human_candidate', 'bot', 'preview', 'prefetch', 'unknown');

create type "public"."tracking_event_type" as enum ('link_open', 'page_view', 'click', 'form_start', 'form_submit', 'conversion', 'custom');
  create table "public"."tracking_events" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "project_id" uuid not null,
    "message_id" uuid,
    "tracking_link_id" uuid,
    "tracking_session_id" uuid,
    "event_id" uuid not null,
    "event_name" text not null,
    "event_type" public.tracking_event_type not null,
    "element_id" text,
    "classification" public.tracking_classification not null default 'unknown'::public.tracking_classification,
    "occurred_at" timestamp with time zone not null,
    "received_at" timestamp with time zone not null default now(),
    "page_path" text,
    "metadata" jsonb not null default '{}'::jsonb,
    "browser_family" text,
    "os_family" text,
    "device_type" text,
    "country" text,
    "region" text,
    "referer" text,
    "accept_language" text,
    "request_id" text
      );


alter table "public"."tracking_events" enable row level security;


  create table "public"."tracking_links" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "project_id" uuid not null,
    "message_id" uuid,
    "token_hash" bytea not null,
    "destination_url" text not null,
    "source" text not null default 'api'::text,
    "attribution" jsonb not null default '{}'::jsonb,
    "expires_at" timestamp with time zone not null,
    "disabled_at" timestamp with time zone,
    "first_opened_at" timestamp with time zone,
    "last_opened_at" timestamp with time zone,
    "idempotency_key" text not null,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "public"."tracking_links" enable row level security;


  create table "public"."tracking_projects" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "public_key" uuid not null default gen_random_uuid(),
    "name" text not null,
    "slug" text not null,
    "status" text not null default 'active'::text,
    "allowed_origins" text[] not null,
    "default_destination_url" text,
    "session_ttl_minutes" integer not null default 30,
    "direct_session_rate_limit_per_minute" integer not null default 600,
    "retention_days" integer not null default 90,
    "metadata" jsonb not null default '{}'::jsonb,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "public"."tracking_projects" enable row level security;


  create table "public"."tracking_sessions" (
    "id" uuid not null default gen_random_uuid(),
    "organization_id" uuid not null,
    "project_id" uuid not null,
    "tracking_link_id" uuid,
    "message_id" uuid,
    "session_token_hash" bytea not null,
    "origin" text not null,
    "event_count" integer not null default 0,
    "expires_at" timestamp with time zone not null,
    "revoked_at" timestamp with time zone,
    "created_at" timestamp with time zone not null default now(),
    "last_seen_at" timestamp with time zone not null default now()
      );


alter table "public"."tracking_sessions" enable row level security;

CREATE UNIQUE INDEX tracking_events_dedup_key ON public.tracking_events USING btree (project_id, event_id);

CREATE INDEX tracking_events_link_occurred_at_idx ON public.tracking_events USING btree (tracking_link_id, occurred_at DESC) WHERE (tracking_link_id IS NOT NULL);

CREATE INDEX tracking_events_message_occurred_at_idx ON public.tracking_events USING btree (message_id, occurred_at DESC) WHERE (message_id IS NOT NULL);

CREATE UNIQUE INDEX tracking_events_pkey ON public.tracking_events USING btree (id);

CREATE INDEX tracking_events_project_occurred_at_idx ON public.tracking_events USING btree (project_id, occurred_at DESC);

CREATE INDEX tracking_events_project_type_occurred_at_idx ON public.tracking_events USING btree (project_id, event_type, occurred_at DESC);

CREATE UNIQUE INDEX tracking_links_idempotency_key ON public.tracking_links USING btree (organization_id, idempotency_key);

CREATE INDEX tracking_links_message_id_idx ON public.tracking_links USING btree (message_id) WHERE (message_id IS NOT NULL);

CREATE UNIQUE INDEX tracking_links_pkey ON public.tracking_links USING btree (id);

CREATE INDEX tracking_links_project_created_at_idx ON public.tracking_links USING btree (project_id, created_at DESC);

CREATE UNIQUE INDEX tracking_links_token_hash_key ON public.tracking_links USING btree (token_hash);

CREATE INDEX tracking_projects_organization_id_idx ON public.tracking_projects USING btree (organization_id, status);

CREATE UNIQUE INDEX tracking_projects_pkey ON public.tracking_projects USING btree (id);

CREATE UNIQUE INDEX tracking_projects_public_key_key ON public.tracking_projects USING btree (public_key);

CREATE UNIQUE INDEX tracking_projects_slug_key ON public.tracking_projects USING btree (organization_id, slug);

CREATE INDEX tracking_sessions_link_id_idx ON public.tracking_sessions USING btree (tracking_link_id) WHERE (tracking_link_id IS NOT NULL);

CREATE UNIQUE INDEX tracking_sessions_pkey ON public.tracking_sessions USING btree (id);

CREATE INDEX tracking_sessions_project_last_seen_idx ON public.tracking_sessions USING btree (project_id, last_seen_at DESC);

CREATE INDEX tracking_sessions_project_direct_created_idx ON public.tracking_sessions USING btree (project_id, created_at DESC) WHERE (tracking_link_id IS NULL);

CREATE UNIQUE INDEX tracking_sessions_token_hash_key ON public.tracking_sessions USING btree (session_token_hash);

alter table "public"."tracking_events" add constraint "tracking_events_pkey" PRIMARY KEY using index "tracking_events_pkey";

alter table "public"."tracking_links" add constraint "tracking_links_pkey" PRIMARY KEY using index "tracking_links_pkey";

alter table "public"."tracking_projects" add constraint "tracking_projects_pkey" PRIMARY KEY using index "tracking_projects_pkey";

alter table "public"."tracking_sessions" add constraint "tracking_sessions_pkey" PRIMARY KEY using index "tracking_sessions_pkey";

alter table "public"."tracking_events" add constraint "tracking_events_dedup_key" UNIQUE using index "tracking_events_dedup_key";

alter table "public"."tracking_events" add constraint "tracking_events_element_id_length" CHECK (((element_id IS NULL) OR (length(element_id) <= 128))) not valid;

alter table "public"."tracking_events" validate constraint "tracking_events_element_id_length";

alter table "public"."tracking_events" add constraint "tracking_events_message_id_fkey" FOREIGN KEY (message_id) REFERENCES public.messages(id) ON DELETE SET NULL not valid;

alter table "public"."tracking_events" validate constraint "tracking_events_message_id_fkey";

alter table "public"."tracking_events" add constraint "tracking_events_metadata_shape" CHECK ((jsonb_typeof(metadata) = 'object'::text)) not valid;

alter table "public"."tracking_events" validate constraint "tracking_events_metadata_shape";

alter table "public"."tracking_events" add constraint "tracking_events_name" CHECK ((event_name ~ '^[a-z][a-z0-9_.:-]{0,63}$'::text)) not valid;

alter table "public"."tracking_events" validate constraint "tracking_events_name";

alter table "public"."tracking_events" add constraint "tracking_events_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "public"."tracking_events" validate constraint "tracking_events_organization_id_fkey";

alter table "public"."tracking_events" add constraint "tracking_events_page_path_length" CHECK (((page_path IS NULL) OR (length(page_path) <= 512))) not valid;

alter table "public"."tracking_events" validate constraint "tracking_events_page_path_length";

alter table "public"."tracking_events" add constraint "tracking_events_project_id_fkey" FOREIGN KEY (project_id) REFERENCES public.tracking_projects(id) ON DELETE CASCADE not valid;

alter table "public"."tracking_events" validate constraint "tracking_events_project_id_fkey";

alter table "public"."tracking_events" add constraint "tracking_events_shape" CHECK ((((event_type = 'link_open'::public.tracking_event_type) AND (tracking_link_id IS NOT NULL)) OR ((event_type <> 'link_open'::public.tracking_event_type) AND (tracking_session_id IS NOT NULL)))) not valid;

alter table "public"."tracking_events" validate constraint "tracking_events_shape";

alter table "public"."tracking_events" add constraint "tracking_events_tracking_link_id_fkey" FOREIGN KEY (tracking_link_id) REFERENCES public.tracking_links(id) ON DELETE CASCADE not valid;

alter table "public"."tracking_events" validate constraint "tracking_events_tracking_link_id_fkey";

alter table "public"."tracking_events" add constraint "tracking_events_tracking_session_id_fkey" FOREIGN KEY (tracking_session_id) REFERENCES public.tracking_sessions(id) ON DELETE CASCADE not valid;

alter table "public"."tracking_events" validate constraint "tracking_events_tracking_session_id_fkey";

alter table "public"."tracking_links" add constraint "tracking_links_attribution_shape" CHECK ((jsonb_typeof(attribution) = 'object'::text)) not valid;

alter table "public"."tracking_links" validate constraint "tracking_links_attribution_shape";

alter table "public"."tracking_links" add constraint "tracking_links_destination" CHECK ((destination_url ~ '^https://'::text)) not valid;

alter table "public"."tracking_links" validate constraint "tracking_links_destination";

alter table "public"."tracking_links" add constraint "tracking_links_expiration" CHECK ((expires_at > created_at)) not valid;

alter table "public"."tracking_links" validate constraint "tracking_links_expiration";

alter table "public"."tracking_links" add constraint "tracking_links_idempotency_key" UNIQUE using index "tracking_links_idempotency_key";

alter table "public"."tracking_links" add constraint "tracking_links_message_id_fkey" FOREIGN KEY (message_id) REFERENCES public.messages(id) ON DELETE SET NULL not valid;

alter table "public"."tracking_links" validate constraint "tracking_links_message_id_fkey";

alter table "public"."tracking_links" add constraint "tracking_links_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "public"."tracking_links" validate constraint "tracking_links_organization_id_fkey";

alter table "public"."tracking_links" add constraint "tracking_links_project_id_fkey" FOREIGN KEY (project_id) REFERENCES public.tracking_projects(id) ON DELETE CASCADE not valid;

alter table "public"."tracking_links" validate constraint "tracking_links_project_id_fkey";

alter table "public"."tracking_links" add constraint "tracking_links_source" CHECK ((source = ANY (ARRAY['whatsapp'::text, 'api'::text, 'manual'::text, 'other'::text]))) not valid;

alter table "public"."tracking_links" validate constraint "tracking_links_source";

alter table "public"."tracking_links" add constraint "tracking_links_token_hash_key" UNIQUE using index "tracking_links_token_hash_key";

alter table "public"."tracking_links" add constraint "tracking_links_token_hash_length" CHECK ((octet_length(token_hash) = 32)) not valid;

alter table "public"."tracking_links" validate constraint "tracking_links_token_hash_length";

alter table "public"."tracking_projects" add constraint "tracking_projects_default_destination" CHECK (((default_destination_url IS NULL) OR (default_destination_url ~ '^https://'::text))) not valid;

alter table "public"."tracking_projects" validate constraint "tracking_projects_default_destination";

alter table "public"."tracking_projects" add constraint "tracking_projects_metadata_shape" CHECK ((jsonb_typeof(metadata) = 'object'::text)) not valid;

alter table "public"."tracking_projects" validate constraint "tracking_projects_metadata_shape";

alter table "public"."tracking_projects" add constraint "tracking_projects_name_length" CHECK (((length(TRIM(BOTH FROM name)) >= 1) AND (length(TRIM(BOTH FROM name)) <= 120))) not valid;

alter table "public"."tracking_projects" validate constraint "tracking_projects_name_length";

alter table "public"."tracking_projects" add constraint "tracking_projects_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "public"."tracking_projects" validate constraint "tracking_projects_organization_id_fkey";

alter table "public"."tracking_projects" add constraint "tracking_projects_origins_count" CHECK (((cardinality(allowed_origins) >= 1) AND (cardinality(allowed_origins) <= 20))) not valid;

alter table "public"."tracking_projects" validate constraint "tracking_projects_origins_count";

alter table "public"."tracking_projects" add constraint "tracking_projects_public_key_key" UNIQUE using index "tracking_projects_public_key_key";

alter table "public"."tracking_projects" add constraint "tracking_projects_retention" CHECK (((retention_days >= 1) AND (retention_days <= 365))) not valid;

alter table "public"."tracking_projects" validate constraint "tracking_projects_retention";

alter table "public"."tracking_projects" add constraint "tracking_projects_session_ttl" CHECK (((session_ttl_minutes >= 5) AND (session_ttl_minutes <= 1440))) not valid;

alter table "public"."tracking_projects" validate constraint "tracking_projects_session_ttl";

alter table "public"."tracking_projects" add constraint "tracking_projects_direct_session_rate_limit" CHECK (((direct_session_rate_limit_per_minute >= 10) AND (direct_session_rate_limit_per_minute <= 10000))) not valid;

alter table "public"."tracking_projects" validate constraint "tracking_projects_direct_session_rate_limit";

alter table "public"."tracking_projects" add constraint "tracking_projects_slug_format" CHECK ((slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'::text)) not valid;

alter table "public"."tracking_projects" validate constraint "tracking_projects_slug_format";

alter table "public"."tracking_projects" add constraint "tracking_projects_slug_key" UNIQUE using index "tracking_projects_slug_key";

alter table "public"."tracking_projects" add constraint "tracking_projects_status" CHECK ((status = ANY (ARRAY['active'::text, 'paused'::text, 'archived'::text]))) not valid;

alter table "public"."tracking_projects" validate constraint "tracking_projects_status";

alter table "public"."tracking_sessions" add constraint "tracking_sessions_event_count" CHECK (((event_count >= 0) AND (event_count <= 2000))) not valid;

alter table "public"."tracking_sessions" validate constraint "tracking_sessions_event_count";

alter table "public"."tracking_sessions" add constraint "tracking_sessions_expiration" CHECK ((expires_at > created_at)) not valid;

alter table "public"."tracking_sessions" validate constraint "tracking_sessions_expiration";

alter table "public"."tracking_sessions" add constraint "tracking_sessions_message_id_fkey" FOREIGN KEY (message_id) REFERENCES public.messages(id) ON DELETE SET NULL not valid;

alter table "public"."tracking_sessions" validate constraint "tracking_sessions_message_id_fkey";

alter table "public"."tracking_sessions" add constraint "tracking_sessions_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE CASCADE not valid;

alter table "public"."tracking_sessions" validate constraint "tracking_sessions_organization_id_fkey";

alter table "public"."tracking_sessions" add constraint "tracking_sessions_origin" CHECK ((origin ~ '^https://'::text)) not valid;

alter table "public"."tracking_sessions" validate constraint "tracking_sessions_origin";

alter table "public"."tracking_sessions" add constraint "tracking_sessions_project_id_fkey" FOREIGN KEY (project_id) REFERENCES public.tracking_projects(id) ON DELETE CASCADE not valid;

alter table "public"."tracking_sessions" validate constraint "tracking_sessions_project_id_fkey";

alter table "public"."tracking_sessions" add constraint "tracking_sessions_token_hash_key" UNIQUE using index "tracking_sessions_token_hash_key";

alter table "public"."tracking_sessions" add constraint "tracking_sessions_token_hash_length" CHECK ((octet_length(session_token_hash) = 32)) not valid;

alter table "public"."tracking_sessions" validate constraint "tracking_sessions_token_hash_length";

alter table "public"."tracking_sessions" add constraint "tracking_sessions_tracking_link_id_fkey" FOREIGN KEY (tracking_link_id) REFERENCES public.tracking_links(id) ON DELETE CASCADE not valid;

alter table "public"."tracking_sessions" validate constraint "tracking_sessions_tracking_link_id_fkey";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.create_tracking_link(p_organization_id uuid, p_project_id uuid, p_token_hash bytea, p_destination_url text, p_expires_at timestamp with time zone, p_idempotency_key text, p_message_id uuid DEFAULT NULL::uuid, p_source text DEFAULT 'api'::text, p_attribution jsonb DEFAULT '{}'::jsonb)
 RETURNS TABLE(tracking_link_id uuid, created boolean, token_matches boolean, link_expires_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.create_tracking_session(p_public_key uuid, p_session_token_hash bytea, p_origin text, p_event_count integer)
 RETURNS TABLE(tracking_session_id uuid, organization_id uuid, project_id uuid, expires_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.get_tracking_dashboard(p_organization_id uuid, p_project_id uuid DEFAULT NULL::uuid, p_from timestamp with time zone DEFAULT (now() - '30 days'::interval), p_to timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.record_tracking_open(p_token_hash bytea, p_session_token_hash bytea, p_event_id uuid, p_classification public.tracking_classification, p_occurred_at timestamp with time zone, p_browser_family text DEFAULT NULL::text, p_os_family text DEFAULT NULL::text, p_device_type text DEFAULT NULL::text, p_country text DEFAULT NULL::text, p_region text DEFAULT NULL::text, p_referer text DEFAULT NULL::text, p_accept_language text DEFAULT NULL::text, p_request_id text DEFAULT NULL::text)
 RETURNS TABLE(organization_id uuid, project_id uuid, message_id uuid, tracking_link_id uuid, tracking_session_id uuid, destination_url text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.reserve_tracking_session(p_session_token_hash bytea, p_origin text, p_event_count integer)
 RETURNS TABLE(tracking_session_id uuid, organization_id uuid, project_id uuid, tracking_link_id uuid, message_id uuid, session_origin text, event_count integer, expires_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

  create policy "service role can manage tracking events"
  on "public"."tracking_events"
  as permissive
  for all
  to service_role
using (true)
with check (true);



  create policy "service role can manage tracking links"
  on "public"."tracking_links"
  as permissive
  for all
  to service_role
using (true)
with check (true);



  create policy "members can read their tracking projects"
  on "public"."tracking_projects"
  as permissive
  for select
  to authenticated
using ((organization_id IN ( SELECT public.get_authorized_orgs('member'::public.role) AS get_authorized_orgs)));



  create policy "service role can manage tracking projects"
  on "public"."tracking_projects"
  as permissive
  for all
  to service_role
using (true)
with check (true);



  create policy "service role can manage tracking sessions"
  on "public"."tracking_sessions"
  as permissive
  for all
  to service_role
using (true)
with check (true);


CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.tracking_links FOR EACH ROW EXECUTE FUNCTION public.moddatetime('updated_at');

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.tracking_projects FOR EACH ROW EXECUTE FUNCTION public.moddatetime('updated_at');

revoke all on table public.tracking_projects from anon, authenticated;
grant select on table public.tracking_projects to authenticated;
grant all on table public.tracking_projects to service_role;

revoke all on table public.tracking_links from anon, authenticated;
grant all on table public.tracking_links to service_role;

revoke all on table public.tracking_sessions from anon, authenticated;
grant all on table public.tracking_sessions to service_role;

revoke all on table public.tracking_events from anon, authenticated;
grant all on table public.tracking_events to service_role;

revoke all on function public.create_tracking_link(
  uuid, uuid, bytea, text, timestamp with time zone, text, uuid, text, jsonb
) from public, anon, authenticated;
grant execute on function public.create_tracking_link(
  uuid, uuid, bytea, text, timestamp with time zone, text, uuid, text, jsonb
) to service_role;

revoke all on function public.create_tracking_session(uuid, bytea, text, integer)
from public, anon, authenticated;
grant execute on function public.create_tracking_session(uuid, bytea, text, integer)
to service_role;

revoke all on function public.reserve_tracking_session(bytea, text, integer)
from public, anon, authenticated;
grant execute on function public.reserve_tracking_session(bytea, text, integer)
to service_role;

revoke all on function public.record_tracking_open(
  bytea, bytea, uuid, public.tracking_classification,
  timestamp with time zone, text, text, text, text, text, text, text, text
) from public, anon, authenticated;
grant execute on function public.record_tracking_open(
  bytea, bytea, uuid, public.tracking_classification,
  timestamp with time zone, text, text, text, text, text, text, text, text
) to service_role;

revoke all on function public.get_tracking_dashboard(
  uuid, uuid, timestamp with time zone, timestamp with time zone
) from public, anon;
grant execute on function public.get_tracking_dashboard(
  uuid, uuid, timestamp with time zone, timestamp with time zone
) to authenticated, service_role;

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

select cron.schedule(
  'cleanup-tracking-data',
  '15 3 * * *',
  $$select public.cleanup_tracking_data();$$
);
