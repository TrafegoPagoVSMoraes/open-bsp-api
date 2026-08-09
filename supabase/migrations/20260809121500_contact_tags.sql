-- Organization-scoped contact tags, contact metadata normalization and durable
-- synchronization of the reserved opt-out tag.

alter table public.contacts
add column email text;

alter table public.contacts
add constraint contacts_organization_id_id_key
unique (organization_id, id);

create function public.normalize_contact_name(value text) returns text
language sql
immutable
set search_path to ''
as $$
  select case
    when value is null then null
    else (
      select nullif(
        pg_catalog.string_agg(
          case
            when word_number > 1
              and pg_catalog.lower(word) in (
                'a', 'as', 'e', 'o', 'os',
                'da', 'das', 'de', 'do', 'dos'
              )
            then pg_catalog.lower(word)
            else pg_catalog.upper(pg_catalog.left(word, 1)) ||
              pg_catalog.lower(pg_catalog.substr(word, 2))
          end,
          ' ' order by word_number
        ),
        ''
      )
      from pg_catalog.regexp_split_to_table(
        pg_catalog.btrim(
          pg_catalog.regexp_replace(value, '\\s+', ' ', 'g')
        ),
        ' '
      ) with ordinality as parts(word, word_number)
    )
  end;
$$;

create function public.normalize_contact_fields() returns trigger
language plpgsql
set search_path to ''
as $$
begin
  if tg_op = 'INSERT' or new.name is distinct from old.name then
    new.name := public.normalize_contact_name(new.name);
  end if;

  if tg_op = 'INSERT' or new.email is distinct from old.email then
    new.email := nullif(
      pg_catalog.lower(pg_catalog.btrim(new.email)),
      ''
    );
  end if;

  return new;
end;
$$;

create trigger normalize_contact_fields
before insert or update of name, email
on public.contacts
for each row
execute function public.normalize_contact_fields();

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
  constraint tags_name_length check (
    pg_catalog.length(pg_catalog.btrim(name)) between 1 and 80
  ),
  constraint tags_slug_format check (
    slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'
  ),
  constraint tags_color_format check (
    color ~ '^#[0-9A-Fa-f]{6}$'
  ),
  constraint tags_system_shape check (
    (is_system and system_key is not null)
    or (not is_system and system_key is null)
  ),
  constraint tags_system_key_format check (
    system_key is null or system_key ~ '^[a-z0-9]+(?:_[a-z0-9]+)*$'
  )
);

create index tags_organization_id_name_idx
on public.tags (organization_id, pg_catalog.lower(name));

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
  constraint contact_tags_source_length check (
    pg_catalog.length(pg_catalog.btrim(source)) between 1 and 40
  )
);

create index contact_tags_tag_id_contact_id_idx
on public.contact_tags (organization_id, tag_id, contact_id);

alter table public.tags enable row level security;
alter table public.contact_tags enable row level security;

create policy "members can read their orgs tags"
on public.tags
for select
to authenticated, anon
using (
  organization_id in (
    select public.get_authorized_orgs('member')
  )
);

create policy "members can create non-system tags"
on public.tags
for insert
to authenticated, anon
with check (
  not is_system
  and system_key is null
  and organization_id in (
    select public.get_authorized_orgs('member')
  )
);

create policy "members can update non-system tags"
on public.tags
for update
to authenticated, anon
using (
  not is_system
  and organization_id in (
    select public.get_authorized_orgs('member')
  )
)
with check (
  not is_system
  and system_key is null
  and organization_id in (
    select public.get_authorized_orgs('member')
  )
);

create policy "members can delete non-system tags"
on public.tags
for delete
to authenticated, anon
using (
  not is_system
  and organization_id in (
    select public.get_authorized_orgs('member')
  )
);

create policy "members can read their orgs contact tags"
on public.contact_tags
for select
to authenticated, anon
using (
  organization_id in (
    select public.get_authorized_orgs('member')
  )
);

create policy "members can create non-system contact tags"
on public.contact_tags
for insert
to authenticated, anon
with check (
  organization_id in (
    select public.get_authorized_orgs('member')
  )
  and exists (
    select 1
    from public.tags t
    where t.organization_id = contact_tags.organization_id
      and t.id = contact_tags.tag_id
      and not t.is_system
  )
);

create policy "members can delete non-system contact tags"
on public.contact_tags
for delete
to authenticated, anon
using (
  organization_id in (
    select public.get_authorized_orgs('member')
  )
  and exists (
    select 1
    from public.tags t
    where t.organization_id = contact_tags.organization_id
      and t.id = contact_tags.tag_id
      and not t.is_system
  )
);

grant select, insert, update, delete on table public.tags
to authenticated, anon;
grant select, insert, delete on table public.contact_tags
to authenticated, anon;
grant all on table public.tags, public.contact_tags to service_role;

create function public.ensure_system_tag(
  target_organization_id uuid,
  target_system_key text,
  target_name text,
  target_color text
) returns uuid
language plpgsql
security definer
set search_path to ''
as $$
declare
  result_id uuid;
begin
  insert into public.tags (
    organization_id,
    name,
    slug,
    color,
    is_system,
    system_key
  ) values (
    target_organization_id,
    target_name,
    pg_catalog.replace(target_system_key, '_', '-'),
    target_color,
    true,
    target_system_key
  )
  on conflict (organization_id, system_key) where system_key is not null
  do update set
    name = excluded.name,
    color = excluded.color
  returning id into result_id;

  return result_id;
end;
$$;

create function public.sync_contact_opt_out_tag(
  target_organization_id uuid,
  target_contact_id uuid
) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  opt_out_tag_id uuid;
  is_opted_out boolean;
begin
  if target_contact_id is null then
    return;
  end if;

  select exists (
    select 1
    from public.contacts_addresses ca
    join public.contact_opt_outs o
      on o.organization_id = ca.organization_id
      and o.service = ca.service
      and o.contact_address = ca.address
    where ca.organization_id = target_organization_id
      and ca.contact_id = target_contact_id
  ) into is_opted_out;

  select t.id into opt_out_tag_id
  from public.tags t
  where t.organization_id = target_organization_id
    and t.system_key = 'opt_out';

  if is_opted_out then
    if opt_out_tag_id is null then
      opt_out_tag_id := public.ensure_system_tag(
        target_organization_id,
        'opt_out',
        'Opt-out',
        '#dc2626'
      );
    end if;

    insert into public.contact_tags (
      organization_id,
      contact_id,
      tag_id,
      source
    ) values (
      target_organization_id,
      target_contact_id,
      opt_out_tag_id,
      'system'
    )
    on conflict do nothing;
  elsif opt_out_tag_id is not null then
    delete from public.contact_tags ct
    where ct.organization_id = target_organization_id
      and ct.contact_id = target_contact_id
      and ct.tag_id = opt_out_tag_id;
  end if;
end;
$$;

create function public.sync_opt_out_tag_from_consent() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  linked_contact_id uuid;
  target_organization_id uuid;
  target_service public.service;
  target_contact_address text;
begin
  if tg_op = 'INSERT' then
    target_organization_id := new.organization_id;
    target_service := new.service;
    target_contact_address := new.contact_address;
  else
    target_organization_id := old.organization_id;
    target_service := old.service;
    target_contact_address := old.contact_address;
  end if;

  select ca.contact_id into linked_contact_id
  from public.contacts_addresses ca
  where ca.organization_id = target_organization_id
    and ca.service = target_service
    and ca.address = target_contact_address;

  perform public.sync_contact_opt_out_tag(
    target_organization_id,
    linked_contact_id
  );

  return null;
end;
$$;

create trigger sync_opt_out_tag_from_consent
after insert or delete
on public.contact_opt_outs
for each row
execute function public.sync_opt_out_tag_from_consent();

create function public.sync_opt_out_tag_from_contact_address() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if tg_op = 'UPDATE' and old.contact_id is not null then
    perform public.sync_contact_opt_out_tag(old.organization_id, old.contact_id);
  end if;

  if new.contact_id is not null then
    perform public.sync_contact_opt_out_tag(new.organization_id, new.contact_id);
  end if;

  return null;
end;
$$;

create trigger sync_opt_out_tag_from_contact_address
after update of contact_id
on public.contacts_addresses
for each row
when (old.contact_id is distinct from new.contact_id)
execute function public.sync_opt_out_tag_from_contact_address();

create trigger sync_opt_out_tag_from_contact_address_insert
after insert
on public.contacts_addresses
for each row
when (new.contact_id is not null)
execute function public.sync_opt_out_tag_from_contact_address();

revoke all on function public.ensure_system_tag(uuid, text, text, text)
from public, authenticated, anon;
revoke all on function public.sync_contact_opt_out_tag(uuid, uuid)
from public, authenticated, anon;
revoke all on function public.sync_opt_out_tag_from_consent()
from public, authenticated, anon;
revoke all on function public.sync_opt_out_tag_from_contact_address()
from public, authenticated, anon;

-- Ensure every organization with historical suppression state has its reserved
-- tag, then attach it to every currently linked contact. Unlinked addresses are
-- handled automatically when contact_id is assigned later.
insert into public.tags (
  organization_id,
  name,
  slug,
  color,
  is_system,
  system_key
)
select distinct
  o.organization_id,
  'Opt-out',
  'opt-out',
  '#dc2626',
  true,
  'opt_out'
from public.contact_opt_outs o
on conflict (organization_id, system_key) where system_key is not null
do nothing;

insert into public.contact_tags (
  organization_id,
  contact_id,
  tag_id,
  source
)
select distinct
  ca.organization_id,
  ca.contact_id,
  t.id,
  'system'
from public.contact_opt_outs o
join public.contacts_addresses ca
  on ca.organization_id = o.organization_id
  and ca.service = o.service
  and ca.address = o.contact_address
join public.tags t
  on t.organization_id = o.organization_id
  and t.system_key = 'opt_out'
where ca.contact_id is not null
on conflict do nothing;

create function public.get_tag_report(p_organization_id uuid)
returns table (
  tag_id uuid,
  tag_name text,
  tag_color text,
  contact_count bigint,
  opt_out_count bigint
)
language plpgsql
security invoker
set search_path to ''
as $$
begin
  if not exists (
    select 1
    from public.get_authorized_orgs('member') as authorized(organization_id)
    where authorized.organization_id = p_organization_id
  ) then
    raise exception using
      errcode = '42501',
      message = 'Not authorized to read tag report for this organization';
  end if;

  return query
  select
    t.id,
    t.name,
    t.color,
    pg_catalog.count(distinct ct.contact_id),
    pg_catalog.count(distinct ct.contact_id) filter (
      where exists (
        select 1
        from public.contacts_addresses ca
        join public.contact_opt_outs o
          on o.organization_id = ca.organization_id
          and o.service = ca.service
          and o.contact_address = ca.address
        where ca.organization_id = ct.organization_id
          and ca.contact_id = ct.contact_id
      )
    )
  from public.tags t
  left join public.contact_tags ct
    on ct.organization_id = t.organization_id
    and ct.tag_id = t.id
  where t.organization_id = p_organization_id
  group by t.id, t.name, t.color
  order by pg_catalog.count(distinct ct.contact_id) desc, t.name;
end;
$$;

revoke all on function public.get_tag_report(uuid) from public;
grant execute on function public.get_tag_report(uuid) to authenticated, anon;
