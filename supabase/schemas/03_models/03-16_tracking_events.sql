-- Immutable, generic engagement events. Raw IP addresses and precise
-- geolocation are deliberately excluded from the default data model.
create table public.tracking_events (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  project_id uuid not null,
  message_id uuid,
  tracking_link_id uuid,
  tracking_session_id uuid,
  event_id uuid not null,
  event_name text not null,
  event_type public.tracking_event_type not null,
  element_id text,
  classification public.tracking_classification default 'unknown' not null,
  occurred_at timestamp with time zone not null,
  received_at timestamp with time zone default now() not null,
  page_path text,
  metadata jsonb default '{}'::jsonb not null,
  browser_family text,
  os_family text,
  device_type text,
  country text,
  region text,
  referer text,
  accept_language text,
  request_id text,
  constraint tracking_events_pkey primary key (id),
  constraint tracking_events_dedup_key unique (project_id, event_id),
  constraint tracking_events_name check (event_name ~ '^[a-z][a-z0-9_.:-]{0,63}$'),
  constraint tracking_events_element_id_length check (element_id is null or length(element_id) <= 128),
  constraint tracking_events_page_path_length check (page_path is null or length(page_path) <= 512),
  constraint tracking_events_metadata_shape check (jsonb_typeof(metadata) = 'object'),
  constraint tracking_events_shape check (
    (event_type = 'link_open' and tracking_link_id is not null)
    or (event_type <> 'link_open' and tracking_session_id is not null)
  )
);

alter table only public.tracking_events
add constraint tracking_events_organization_id_fkey
foreign key (organization_id) references public.organizations(id) on delete cascade;

alter table only public.tracking_events
add constraint tracking_events_project_id_fkey
foreign key (project_id) references public.tracking_projects(id) on delete cascade;

alter table only public.tracking_events
add constraint tracking_events_message_id_fkey
foreign key (message_id) references public.messages(id) on delete set null;

alter table only public.tracking_events
add constraint tracking_events_tracking_link_id_fkey
foreign key (tracking_link_id) references public.tracking_links(id) on delete cascade;

alter table only public.tracking_events
add constraint tracking_events_tracking_session_id_fkey
foreign key (tracking_session_id) references public.tracking_sessions(id) on delete cascade;

create index tracking_events_project_occurred_at_idx
on public.tracking_events (project_id, occurred_at desc);

create index tracking_events_project_type_occurred_at_idx
on public.tracking_events (project_id, event_type, occurred_at desc);

create index tracking_events_link_occurred_at_idx
on public.tracking_events (tracking_link_id, occurred_at desc)
where tracking_link_id is not null;

create index tracking_events_message_occurred_at_idx
on public.tracking_events (message_id, occurred_at desc)
where message_id is not null;
