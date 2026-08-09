create table public.tags (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  name text not null,
  slug text not null,
  color text default '#64748b'::text not null,
  description text,
  is_system boolean default false not null,
  system_key text,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint tags_pkey primary key (id),
  constraint tags_organization_id_fkey
    foreign key (organization_id)
    references public.organizations(id)
    on delete cascade,
  constraint tags_organization_id_id_key unique (organization_id, id),
  constraint tags_organization_id_slug_key unique (organization_id, slug),
  constraint tags_name_length check (length(trim(name)) between 1 and 80),
  constraint tags_slug_format check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  constraint tags_color_format check (color ~ '^#[0-9A-Fa-f]{6}$'),
  constraint tags_system_shape check (
    (is_system and system_key is not null)
    or (not is_system and system_key is null)
  ),
  constraint tags_system_key_format check (
    system_key is null or system_key ~ '^[a-z0-9]+(?:_[a-z0-9]+)*$'
  )
);

create index tags_organization_id_name_idx
on public.tags (organization_id, lower(name));

create unique index tags_organization_id_system_key_key
on public.tags (organization_id, system_key)
where system_key is not null;

create trigger set_updated_at
before update on public.tags
for each row execute function public.moddatetime('updated_at');

create table public.contact_tags (
  organization_id uuid not null,
  contact_id uuid not null,
  tag_id uuid not null,
  source text default 'manual'::text not null,
  created_at timestamp with time zone default now() not null,
  constraint contact_tags_pkey primary key (
    organization_id,
    contact_id,
    tag_id
  ),
  constraint contact_tags_contact_fkey
    foreign key (organization_id, contact_id)
    references public.contacts(organization_id, id)
    on delete cascade,
  constraint contact_tags_tag_fkey
    foreign key (organization_id, tag_id)
    references public.tags(organization_id, id)
    on delete cascade,
  constraint contact_tags_source_length check (length(trim(source)) between 1 and 40)
);

create index contact_tags_tag_id_contact_id_idx
on public.contact_tags (organization_id, tag_id, contact_id);
