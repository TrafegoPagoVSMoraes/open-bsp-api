-- Short-lived browser capability. Only the SHA-256 hash is persisted.
create table public.tracking_sessions (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  project_id uuid not null,
  tracking_link_id uuid,
  message_id uuid,
  session_token_hash bytea not null,
  origin text not null,
  event_count integer default 0 not null,
  expires_at timestamp with time zone not null,
  revoked_at timestamp with time zone,
  created_at timestamp with time zone default now() not null,
  last_seen_at timestamp with time zone default now() not null,
  constraint tracking_sessions_pkey primary key (id),
  constraint tracking_sessions_token_hash_key unique (session_token_hash),
  constraint tracking_sessions_token_hash_length check (octet_length(session_token_hash) = 32),
  constraint tracking_sessions_expiration check (expires_at > created_at),
  constraint tracking_sessions_origin check (origin ~ '^https://'),
  constraint tracking_sessions_event_count check (event_count between 0 and 2000)
);

alter table only public.tracking_sessions
add constraint tracking_sessions_organization_id_fkey
foreign key (organization_id) references public.organizations(id) on delete cascade;

alter table only public.tracking_sessions
add constraint tracking_sessions_project_id_fkey
foreign key (project_id) references public.tracking_projects(id) on delete cascade;

alter table only public.tracking_sessions
add constraint tracking_sessions_tracking_link_id_fkey
foreign key (tracking_link_id) references public.tracking_links(id) on delete cascade;

alter table only public.tracking_sessions
add constraint tracking_sessions_message_id_fkey
foreign key (message_id) references public.messages(id) on delete set null;

create index tracking_sessions_project_last_seen_idx
on public.tracking_sessions (project_id, last_seen_at desc);

create index tracking_sessions_project_direct_created_idx
on public.tracking_sessions (project_id, created_at desc)
where tracking_link_id is null;

create index tracking_sessions_link_id_idx
on public.tracking_sessions (tracking_link_id) where tracking_link_id is not null;
