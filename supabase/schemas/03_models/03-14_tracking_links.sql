-- Opaque redirect links may be associated with a WhatsApp message, but the
-- tracking core also supports links created by an API or another channel.
create table public.tracking_links (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  project_id uuid not null,
  message_id uuid,
  token_hash bytea not null,
  destination_url text not null,
  source text default 'api' not null,
  attribution jsonb default '{}'::jsonb not null,
  expires_at timestamp with time zone not null,
  disabled_at timestamp with time zone,
  first_opened_at timestamp with time zone,
  last_opened_at timestamp with time zone,
  idempotency_key text not null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint tracking_links_pkey primary key (id),
  constraint tracking_links_token_hash_key unique (token_hash),
  constraint tracking_links_idempotency_key unique (organization_id, idempotency_key),
  constraint tracking_links_token_hash_length check (octet_length(token_hash) = 32),
  constraint tracking_links_expiration check (expires_at > created_at),
  constraint tracking_links_destination check (destination_url ~ '^https://'),
  constraint tracking_links_source check (source in ('whatsapp', 'api', 'manual', 'other')),
  constraint tracking_links_attribution_shape check (jsonb_typeof(attribution) = 'object')
);

alter table only public.tracking_links
add constraint tracking_links_organization_id_fkey
foreign key (organization_id) references public.organizations(id) on delete cascade;

alter table only public.tracking_links
add constraint tracking_links_project_id_fkey
foreign key (project_id) references public.tracking_projects(id) on delete cascade;

alter table only public.tracking_links
add constraint tracking_links_message_id_fkey
foreign key (message_id) references public.messages(id) on delete set null;

create index tracking_links_project_created_at_idx
on public.tracking_links (project_id, created_at desc);

create index tracking_links_message_id_idx
on public.tracking_links (message_id) where message_id is not null;

create trigger set_updated_at
before update on public.tracking_links
for each row execute function public.moddatetime('updated_at');
