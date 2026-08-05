-- Organization-scoped tracking installations. The public key identifies a
-- project in browser code; it is intentionally not a secret. Origin checks,
-- short-lived session capabilities and rate limits protect event ingestion.
create table public.tracking_projects (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  public_key uuid default gen_random_uuid() not null,
  name text not null,
  slug text not null,
  status text default 'active' not null,
  allowed_origins text[] not null,
  default_destination_url text,
  session_ttl_minutes integer default 30 not null,
  direct_session_rate_limit_per_minute integer default 600 not null,
  retention_days integer default 90 not null,
  metadata jsonb default '{}'::jsonb not null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint tracking_projects_pkey primary key (id),
  constraint tracking_projects_public_key_key unique (public_key),
  constraint tracking_projects_slug_key unique (organization_id, slug),
  constraint tracking_projects_name_length check (length(trim(name)) between 1 and 120),
  constraint tracking_projects_slug_format check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  constraint tracking_projects_status check (status in ('active', 'paused', 'archived')),
  constraint tracking_projects_origins_count check (cardinality(allowed_origins) between 1 and 20),
  constraint tracking_projects_default_destination check (
    default_destination_url is null or default_destination_url ~ '^https://'
  ),
  constraint tracking_projects_session_ttl check (session_ttl_minutes between 5 and 1440),
  constraint tracking_projects_direct_session_rate_limit check (
    direct_session_rate_limit_per_minute between 10 and 10000
  ),
  constraint tracking_projects_retention check (retention_days between 1 and 365),
  constraint tracking_projects_metadata_shape check (jsonb_typeof(metadata) = 'object')
);

alter table only public.tracking_projects
add constraint tracking_projects_organization_id_fkey
foreign key (organization_id)
references public.organizations(id)
on delete cascade;

create index tracking_projects_organization_id_idx
on public.tracking_projects (organization_id, status);

create trigger set_updated_at
before update on public.tracking_projects
for each row execute function public.moddatetime('updated_at');
