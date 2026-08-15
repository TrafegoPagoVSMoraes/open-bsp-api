-- Phase 1: additive project root and manually managed paid-traffic metrics.
-- Existing organization, tag, contact and WhatsApp campaign flows remain valid.

create table public.projects (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  slug text not null,
  description text,
  planned_budget numeric(14,2) not null default 0,
  currency text not null default 'BRL',
  status text not null default 'active',
  extra jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint projects_org_id_id_key unique (organization_id, id),
  constraint projects_org_slug_key unique (organization_id, slug),
  constraint projects_name_length check (char_length(btrim(name)) between 1 and 120),
  constraint projects_slug_format check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  constraint projects_budget_nonnegative check (planned_budget >= 0),
  constraint projects_currency_format check (currency ~ '^[A-Z]{3}$'),
  constraint projects_status_check check (status in ('active', 'archived'))
);

create index projects_org_status_name_idx
on public.projects (organization_id, status, name);

create trigger set_updated_at before update on public.projects
for each row execute function public.moddatetime('updated_at');

create table public.project_tags (
  organization_id uuid not null,
  project_id uuid not null,
  tag_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (organization_id, project_id, tag_id),
  foreign key (organization_id, project_id)
    references public.projects(organization_id, id) on delete cascade,
  foreign key (organization_id, tag_id)
    references public.tags(organization_id, id) on delete cascade
);

create index project_tags_tag_project_idx
on public.project_tags (organization_id, tag_id, project_id);

create table public.project_contacts (
  organization_id uuid not null,
  project_id uuid not null,
  contact_id uuid not null,
  source text not null default 'manual',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (organization_id, project_id, contact_id),
  foreign key (organization_id, project_id)
    references public.projects(organization_id, id) on delete cascade,
  foreign key (organization_id, contact_id)
    references public.contacts(organization_id, id) on delete cascade,
  constraint project_contacts_source_check
    check (source in ('manual', 'tag', 'import', 'system'))
);

create index project_contacts_contact_project_idx
on public.project_contacts (organization_id, contact_id, project_id);

create trigger set_updated_at before update on public.project_contacts
for each row execute function public.moddatetime('updated_at');

create table public.project_import_aliases (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  alias text not null,
  source text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, project_id)
    references public.projects(organization_id, id) on delete cascade,
  constraint project_import_aliases_value check (char_length(btrim(alias)) between 1 and 200)
);

create unique index project_import_aliases_org_alias_key
on public.project_import_aliases (organization_id, lower(btrim(alias)));

create index project_import_aliases_project_idx
on public.project_import_aliases (organization_id, project_id);

create trigger set_updated_at before update on public.project_import_aliases
for each row execute function public.moddatetime('updated_at');

create table public.project_performance_daily (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid not null,
  metric_date date not null,
  spend numeric(14,2) not null default 0,
  leads integer not null default 0,
  group_joins integer not null default 0,
  reach integer not null default 0,
  notes text,
  extra jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, project_id)
    references public.projects(organization_id, id) on delete cascade,
  constraint project_performance_daily_project_date_key
    unique (organization_id, project_id, metric_date),
  constraint project_performance_daily_nonnegative check (
    spend >= 0 and leads >= 0 and group_joins >= 0 and reach >= 0
  )
);

create index project_performance_project_date_idx
on public.project_performance_daily (organization_id, project_id, metric_date desc);

create trigger set_updated_at before update on public.project_performance_daily
for each row execute function public.moddatetime('updated_at');

-- Synchronize explicit project_contacts from project/tag associations. Tags
-- help classify contacts; authorization later reads project_contacts only.
create or replace function public.sync_project_contact_from_tag_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_org uuid := coalesce(new.organization_id, old.organization_id);
  v_contact uuid := coalesce(new.contact_id, old.contact_id);
begin
  if tg_op = 'INSERT' then
    insert into public.project_contacts (organization_id, project_id, contact_id, source)
    select new.organization_id, pt.project_id, new.contact_id, 'tag'
    from public.project_tags pt
    where pt.organization_id = new.organization_id and pt.tag_id = new.tag_id
    on conflict do nothing;
    return new;
  end if;

  delete from public.project_contacts pc
  where pc.organization_id = v_org and pc.contact_id = v_contact and pc.source = 'tag'
    and not exists (
      select 1 from public.project_tags pt
      join public.contact_tags ct
        on ct.organization_id = pt.organization_id and ct.tag_id = pt.tag_id
      where pt.organization_id = pc.organization_id
        and pt.project_id = pc.project_id and ct.contact_id = pc.contact_id
    );
  return old;
end;
$$;

create trigger sync_project_contact_after_contact_tag
after insert or delete on public.contact_tags
for each row execute function public.sync_project_contact_from_tag_change();

create or replace function public.sync_project_contacts_from_project_tag()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    insert into public.project_contacts (organization_id, project_id, contact_id, source)
    select new.organization_id, new.project_id, ct.contact_id, 'tag'
    from public.contact_tags ct
    where ct.organization_id = new.organization_id and ct.tag_id = new.tag_id
    on conflict do nothing;
    return new;
  end if;

  delete from public.project_contacts pc
  where pc.organization_id = old.organization_id
    and pc.project_id = old.project_id and pc.source = 'tag'
    and not exists (
      select 1 from public.project_tags pt
      join public.contact_tags ct
        on ct.organization_id = pt.organization_id and ct.tag_id = pt.tag_id
      where pt.organization_id = pc.organization_id
        and pt.project_id = pc.project_id and ct.contact_id = pc.contact_id
    );
  return old;
end;
$$;

create trigger sync_project_contacts_after_project_tag
after insert or delete on public.project_tags
for each row execute function public.sync_project_contacts_from_project_tag();

alter table public.projects enable row level security;
alter table public.project_tags enable row level security;
alter table public.project_contacts enable row level security;
alter table public.project_import_aliases enable row level security;
alter table public.project_performance_daily enable row level security;

create policy "members can read organization projects" on public.projects
for select to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('member')));
create policy "admins can create organization projects" on public.projects
for insert to authenticated, anon
with check (organization_id in (select public.get_authorized_orgs('admin')));
create policy "admins can update organization projects" on public.projects
for update to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('admin')))
with check (organization_id in (select public.get_authorized_orgs('admin')));

create policy "members can read project tags" on public.project_tags
for select to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('member')));
create policy "admins can manage project tags" on public.project_tags
for all to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('admin')))
with check (organization_id in (select public.get_authorized_orgs('admin')));

create policy "members can read project contacts" on public.project_contacts
for select to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('member')));
create policy "admins can manage project contacts" on public.project_contacts
for all to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('admin')))
with check (organization_id in (select public.get_authorized_orgs('admin')));

create policy "members can read project aliases" on public.project_import_aliases
for select to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('member')));
create policy "admins can manage project aliases" on public.project_import_aliases
for all to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('admin')))
with check (organization_id in (select public.get_authorized_orgs('admin')));

create policy "members can read project performance" on public.project_performance_daily
for select to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('member')));
create policy "admins can manage project performance" on public.project_performance_daily
for all to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('admin')))
with check (organization_id in (select public.get_authorized_orgs('admin')));

grant select, insert, update on public.projects to authenticated, anon;
grant select, insert, update, delete on public.project_tags to authenticated, anon;
grant select, insert, update, delete on public.project_contacts to authenticated, anon;
grant select, insert, update, delete on public.project_import_aliases to authenticated, anon;
grant select, insert, update, delete on public.project_performance_daily to authenticated, anon;
grant all on public.projects, public.project_tags, public.project_contacts,
  public.project_import_aliases, public.project_performance_daily to service_role;

revoke all on function public.sync_project_contact_from_tag_change() from public, anon, authenticated;
revoke all on function public.sync_project_contacts_from_project_tag() from public, anon, authenticated;
