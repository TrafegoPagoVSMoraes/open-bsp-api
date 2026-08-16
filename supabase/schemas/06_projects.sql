-- Declarative source for project performance, expert isolation and project attribution.
-- Keep synchronized with the additive 20260815 migrations.

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

-- Phase 2: experts reuse Supabase Auth + human agents. Project membership is
-- explicit and independent from tags.

create table public.project_memberships (
  organization_id uuid not null,
  project_id uuid not null,
  agent_id uuid not null,
  role text not null default 'expert',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (organization_id, project_id, agent_id),
  foreign key (organization_id, project_id)
    references public.projects(organization_id, id) on delete cascade,
  foreign key (agent_id) references public.agents(id) on delete cascade,
  constraint project_memberships_role_check check (role in ('expert', 'manager'))
);

create index project_memberships_agent_project_idx
on public.project_memberships (organization_id, agent_id, project_id);

create trigger set_updated_at before update on public.project_memberships
for each row execute function public.moddatetime('updated_at');

create or replace function public.is_project_expert(p_organization_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.agents a
    where a.organization_id = p_organization_id
      and a.user_id = auth.uid() and a.ai = false
      and a.extra->>'account_type' = 'expert'
      and (a.extra->'invitation' is null or a.extra->'invitation'->>'status' = 'accepted')
  );
$$;

create or replace function public.can_access_project(
  p_organization_id uuid,
  p_project_id uuid
) returns boolean language plpgsql volatile security definer set search_path = '' as $$
begin
  if not (p_organization_id in (select public.get_authorized_orgs('member'))) then
    return false;
  end if;
  if auth.uid() is null or not public.is_project_expert(p_organization_id) then
    return true;
  end if;
  return exists (
    select 1 from public.project_memberships pm
    join public.agents a on a.id = pm.agent_id
    where pm.organization_id = p_organization_id
      and pm.project_id = p_project_id and a.user_id = auth.uid()
  );
end;
$$;

create or replace function public.can_administer_projects(p_organization_id uuid)
returns boolean language sql volatile security definer set search_path = '' as $$
  select p_organization_id in (select public.get_authorized_orgs('admin'));
$$;

create or replace function public.get_current_expert_project_ids(
  p_organization_id uuid
) returns table(project_id uuid)
language sql volatile security definer set search_path = '' as $$
  select pm.project_id
  from public.project_memberships pm
  join public.agents a on a.id = pm.agent_id
  where pm.organization_id = p_organization_id
    and a.organization_id = p_organization_id
    and a.user_id = auth.uid()
    and a.ai = false
    and a.extra->>'account_type' = 'expert'
    and p_organization_id in (select public.get_authorized_orgs('member'));
$$;

alter table public.project_memberships enable row level security;

create policy "experts can read own project memberships" on public.project_memberships
for select to authenticated, anon
using (
  public.can_administer_projects(organization_id)
  or exists (
    select 1 from public.agents a
    where a.id = project_memberships.agent_id and a.user_id = auth.uid()
  )
);
create policy "admins can manage project memberships" on public.project_memberships
for all to authenticated, anon
using (public.can_administer_projects(organization_id))
with check (public.can_administer_projects(organization_id));

-- Existing invitation mechanics are preserved, while organization admins may
-- create the restricted expert account type without gaining owner powers.
create policy "admins can invite project experts" on public.agents
for insert to authenticated, anon
with check (
  public.can_administer_projects(organization_id)
  and ai = false
  and extra->>'account_type' = 'expert'
  and extra->>'role' = 'member'
  and extra->'invitation'->>'status' = 'pending'
  and nullif(extra->'invitation'->>'email', '') is not null
);

drop policy if exists "members can read their orgs agents" on public.agents;
create policy "legacy members can read their orgs agents" on public.agents
for select to authenticated, anon
using (
  organization_id in (select public.get_authorized_orgs('member'))
  and not public.is_project_expert(organization_id)
);

drop policy if exists "members can read organization projects" on public.projects;
create policy "authorized users can read projects" on public.projects
for select to authenticated, anon
using (public.can_access_project(organization_id, id));

drop policy if exists "members can read project tags" on public.project_tags;
create policy "authorized users can read project tags" on public.project_tags
for select to authenticated, anon
using (public.can_access_project(organization_id, project_id));

drop policy if exists "members can read project contacts" on public.project_contacts;
create policy "authorized users can read project contacts" on public.project_contacts
for select to authenticated, anon
using (public.can_access_project(organization_id, project_id));

drop policy if exists "members can read project aliases" on public.project_import_aliases;
create policy "authorized users can read project aliases" on public.project_import_aliases
for select to authenticated, anon
using (public.can_access_project(organization_id, project_id));

drop policy if exists "members can read project performance" on public.project_performance_daily;
create policy "authorized users can read project performance" on public.project_performance_daily
for select to authenticated, anon
using (public.can_access_project(organization_id, project_id));

grant select, insert, update, delete on public.project_memberships to authenticated, anon;
grant all on public.project_memberships to service_role;
revoke all on function public.is_project_expert(uuid) from public;
revoke all on function public.can_access_project(uuid, uuid) from public;
revoke all on function public.can_administer_projects(uuid) from public;
revoke all on function public.get_current_expert_project_ids(uuid) from public;
grant execute on function public.is_project_expert(uuid) to authenticated, anon, service_role;
grant execute on function public.can_access_project(uuid, uuid) to authenticated, anon, service_role;
grant execute on function public.can_administer_projects(uuid) to authenticated, anon, service_role;
grant execute on function public.get_current_expert_project_ids(uuid) to authenticated, anon, service_role;

-- Phase 2A: explicit project context for conversations/messages. Existing rows
-- remain nullable and therefore remain available to administrators only until
-- classified. A contact and a conversation may belong to multiple projects.

create table public.project_conversations (
  organization_id uuid not null,
  project_id uuid not null,
  conversation_id uuid not null,
  source text not null default 'inferred',
  created_at timestamptz not null default now(),
  primary key (organization_id, project_id, conversation_id),
  foreign key (organization_id, project_id)
    references public.projects(organization_id, id) on delete cascade,
  foreign key (conversation_id)
    references public.conversations(id) on delete cascade,
  constraint project_conversations_source_check
    check (source in ('inferred', 'manual', 'outgoing', 'campaign'))
);

create index project_conversations_conversation_idx
on public.project_conversations (organization_id, conversation_id, project_id);

alter table public.messages add column project_id uuid;
alter table public.messages add constraint messages_project_fkey
foreign key (organization_id, project_id)
references public.projects(organization_id, id) on delete no action;
create index messages_project_timestamp_idx
on public.messages (organization_id, project_id, timestamp desc)
where project_id is not null;

alter table public.campaigns add column project_id uuid;
alter table public.campaigns add constraint campaigns_project_fkey
foreign key (organization_id, project_id)
references public.projects(organization_id, id) on delete no action;
create index campaigns_project_created_idx
on public.campaigns (organization_id, project_id, created_at desc);

create function public.get_project_campaign_summaries(
  p_organization_id uuid,
  p_project_id uuid
) returns table (
  id uuid, name text, status text, total bigint, pending bigint,
  accepted bigint, sent bigint, delivered bigint, read bigint,
  failed bigint, skipped bigint, created_at timestamptz
)
language sql stable security definer set search_path = '' as $$
  with classified as (
    select c.id, c.name, c.status, c.total_cap, c.created_at,
      r.id as recipient_id,
      case
        when r.status in ('suppressed', 'cancelled') then 'skipped'
        when coalesce(m.status, '{}'::jsonb) ? 'read' then 'read'
        when coalesce(m.status, '{}'::jsonb) ? 'delivered' then 'delivered'
        when coalesce(m.status, '{}'::jsonb) ? 'sent' then 'sent'
        when coalesce(m.status, '{}'::jsonb) ? 'accepted'
          or m.external_id is not null then 'accepted'
        when r.status in ('failed', 'ambiguous')
          or coalesce(m.status, '{}'::jsonb) ? 'failed' then 'failed'
        else 'pending'
      end as delivery_state
    from public.campaigns c
    left join public.campaign_recipients r on r.campaign_id = c.id
    left join public.messages m on m.id = r.message_id
    where c.organization_id = p_organization_id
      and c.project_id = p_project_id
  )
  select id, name, status, max(total_cap)::bigint,
    count(recipient_id) filter (where delivery_state = 'pending'),
    count(recipient_id) filter (where delivery_state = 'accepted'),
    count(recipient_id) filter (where delivery_state = 'sent'),
    count(recipient_id) filter (where delivery_state = 'delivered'),
    count(recipient_id) filter (where delivery_state = 'read'),
    count(recipient_id) filter (where delivery_state = 'failed'),
    count(recipient_id) filter (where delivery_state = 'skipped'),
    max(created_at)
  from classified
  group by id, name, status
  order by max(created_at) desc
  limit 100;
$$;

create or replace function public.can_access_contact(
  p_organization_id uuid, p_contact_id uuid
) returns boolean language sql stable security definer set search_path = '' as $$
  select p_organization_id in (select public.get_authorized_orgs('member'))
    and (
      not public.is_project_expert(p_organization_id)
      or exists (
        select 1 from public.project_contacts pc
        where pc.organization_id = p_organization_id
          and pc.contact_id = p_contact_id
          and public.can_access_project(pc.organization_id, pc.project_id)
      )
    );
$$;

create or replace function public.can_access_contact_address(
  p_organization_id uuid, p_service public.service, p_address text
) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.contacts_addresses ca
    where ca.organization_id = p_organization_id
      and ca.service = p_service and ca.address = p_address
      and ca.contact_id is not null
      and public.can_access_contact(ca.organization_id, ca.contact_id)
  );
$$;

create or replace function public.can_access_conversation(
  p_organization_id uuid, p_conversation_id uuid
) returns boolean language sql stable security definer set search_path = '' as $$
  select p_organization_id in (select public.get_authorized_orgs('member'))
    and (
      not public.is_project_expert(p_organization_id)
      or exists (
        select 1 from public.project_conversations pc
        where pc.organization_id = p_organization_id
          and pc.conversation_id = p_conversation_id
          and public.can_access_project(pc.organization_id, pc.project_id)
      )
    );
$$;

create function public.set_message_project_context() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  _project_ids uuid[];
  _contact_address text;
begin
  if new.project_id is not null then
    if not exists (
      select 1
      from public.conversations c
      join public.contacts_addresses ca
        on ca.organization_id = c.organization_id
       and ca.service = c.service
       and ca.address = coalesce(new.contact_address, c.contact_address)
      join public.project_contacts pc
        on pc.organization_id = ca.organization_id
       and pc.contact_id = ca.contact_id
       and pc.project_id = new.project_id
      where c.id = new.conversation_id
        and c.organization_id = new.organization_id
    ) then
      raise exception using errcode = '42501',
        message = 'Message project does not contain this contact';
    end if;
    return new;
  end if;

  -- New project-aware outgoing messages must carry their explicit context.
  -- Legacy administrators may still insert null and keep the baseline flow;
  -- expert RLS below rejects null outgoing rows.
  if new.direction <> 'incoming'::public.direction then
    return new;
  end if;

  select coalesce(new.contact_address, c.contact_address)
    into _contact_address
  from public.conversations c
  where c.id = new.conversation_id
    and c.organization_id = new.organization_id;

  select array_agg(distinct pc.project_id order by pc.project_id)
    into _project_ids
  from public.contacts_addresses ca
  join public.project_contacts pc
    on pc.organization_id = ca.organization_id
   and pc.contact_id = ca.contact_id
  where ca.organization_id = new.organization_id
    and ca.service = new.service
    and ca.address = _contact_address;

  if coalesce(array_length(_project_ids, 1), 0) = 1 then
    new.project_id := _project_ids[1];
  end if;
  return new;
end;
$$;

create trigger set_message_project_context
before insert on public.messages
for each row execute function public.set_message_project_context();

create function public.link_message_project_conversation() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.project_id is not null then
    insert into public.project_conversations (
      organization_id, project_id, conversation_id, source
    ) values (
      new.organization_id, new.project_id, new.conversation_id,
      case when new.direction = 'incoming'::public.direction
        then 'inferred' else 'outgoing' end
    ) on conflict do nothing;
  end if;
  return new;
end;
$$;

create trigger link_message_project_conversation
after insert on public.messages
for each row execute function public.link_message_project_conversation();

-- Existing conversations become visible only where their linked contact is
-- already an explicit member of a project. This is additive and idempotent.
insert into public.project_conversations (
  organization_id, project_id, conversation_id, source
)
select c.organization_id,
  (array_agg(distinct pc.project_id))[1], c.id, 'inferred'
from public.conversations c
join public.contacts_addresses ca
  on ca.organization_id = c.organization_id
 and ca.service = c.service
 and ca.address = c.contact_address
join public.project_contacts pc
  on pc.organization_id = ca.organization_id
 and pc.contact_id = ca.contact_id
where c.contact_address is not null
group by c.organization_id, c.id
having count(distinct pc.project_id) = 1
on conflict do nothing;

-- Backfill historical messages only when the contact resolves to exactly one
-- project. Multi-project and unresolved history deliberately remains null.
with resolved as (
  select m.id, (array_agg(distinct pc.project_id))[1] as project_id
  from public.messages m
  join public.conversations c
    on c.id = m.conversation_id and c.organization_id = m.organization_id
  join public.contacts_addresses ca
    on ca.organization_id = m.organization_id
   and ca.service = m.service
   and ca.address = coalesce(m.contact_address, c.contact_address)
  join public.project_contacts pc
    on pc.organization_id = ca.organization_id
   and pc.contact_id = ca.contact_id
  where m.project_id is null
  group by m.id
  having count(distinct pc.project_id) = 1
)
update public.messages m
set project_id = resolved.project_id
from resolved
where m.id = resolved.id;

insert into public.project_conversations (
  organization_id, project_id, conversation_id, source
)
select distinct m.organization_id, m.project_id, m.conversation_id, 'inferred'
from public.messages m
where m.project_id is not null
on conflict do nothing;

create function public.assign_message_project(
  p_message_id uuid, p_project_id uuid
) returns void language plpgsql security definer set search_path = '' as $$
declare _message public.messages%rowtype;
begin
  select * into _message from public.messages where id = p_message_id for update;
  if not found or not public.can_administer_projects(_message.organization_id) then
    raise exception using errcode = '42501', message = 'Project assignment denied';
  end if;
  update public.messages set project_id = p_project_id where id = p_message_id;
  insert into public.project_conversations (
    organization_id, project_id, conversation_id, source
  ) values (
    _message.organization_id, p_project_id, _message.conversation_id, 'manual'
  ) on conflict do nothing;
end;
$$;

alter table public.project_conversations enable row level security;
create policy "authorized users can read project conversations"
on public.project_conversations for select to authenticated, anon
using (public.can_access_project(organization_id, project_id));
create policy "admins can manage project conversations"
on public.project_conversations for all to authenticated, anon
using (public.can_administer_projects(organization_id))
with check (public.can_administer_projects(organization_id));

drop policy if exists "members can manage their orgs contacts" on public.contacts;
create policy "authorized users can manage visible contacts"
on public.contacts for all to authenticated, anon
using (public.can_access_contact(organization_id, id))
with check (
  organization_id in (select public.get_authorized_orgs('member'))
  and not public.is_project_expert(organization_id)
);

drop policy if exists "members can read their orgs contacts addresses" on public.contacts_addresses;
create policy "authorized users can read visible contact addresses"
on public.contacts_addresses for select to authenticated, anon
using (
  contact_id is not null
  and public.can_access_contact(organization_id, contact_id)
);
drop policy if exists "members can insert contacts addresses" on public.contacts_addresses;
create policy "legacy members can insert contacts addresses"
on public.contacts_addresses for insert to authenticated, anon
with check (
  organization_id in (select public.get_authorized_orgs('member'))
  and not public.is_project_expert(organization_id)
  and (extra->'synced'->>'action') is distinct from 'add'
);
drop policy if exists "members can update contacts addresses" on public.contacts_addresses;
create policy "legacy members can update contacts addresses"
on public.contacts_addresses for update to authenticated, anon
using (
  organization_id in (select public.get_authorized_orgs('member'))
  and not public.is_project_expert(organization_id)
) with check (
  organization_id in (select public.get_authorized_orgs('member'))
  and not public.is_project_expert(organization_id)
  and public.contact_address_update_rules(
    organization_id, service, address, extra, status
  )
);
drop policy if exists "members can delete non-synced contacts addresses" on public.contacts_addresses;
create policy "legacy members can delete non-synced contacts addresses"
on public.contacts_addresses for delete to authenticated, anon
using (
  organization_id in (select public.get_authorized_orgs('member'))
  and not public.is_project_expert(organization_id)
  and (extra->'synced'->>'action') is distinct from 'add'
);

drop policy if exists "members can manage their orgs conversations" on public.conversations;
create policy "authorized users can read visible conversations"
on public.conversations for select to authenticated, anon
using (public.can_access_conversation(organization_id, id));
create policy "authorized users can update visible conversations"
on public.conversations for update to authenticated, anon
using (public.can_access_conversation(organization_id, id))
with check (public.can_access_conversation(organization_id, id));
create policy "legacy members can insert conversations"
on public.conversations for insert to authenticated, anon
with check (
  organization_id in (select public.get_authorized_orgs('member'))
  and (
    not public.is_project_expert(organization_id)
    or (contact_address is not null and
      public.can_access_contact_address(organization_id, service, contact_address))
  )
);
create policy "legacy members can delete visible conversations"
on public.conversations for delete to authenticated, anon
using (
  not public.is_project_expert(organization_id)
  and organization_id in (select public.get_authorized_orgs('member'))
);

drop policy if exists "members can read their orgs messages" on public.messages;
create policy "authorized users can read project messages"
on public.messages for select to authenticated, anon
using (
  organization_id in (select public.get_authorized_orgs('member'))
  and (
    not public.is_project_expert(organization_id)
    or (project_id is not null and public.can_access_project(organization_id, project_id))
  )
);
drop policy if exists "members can create their orgs messages" on public.messages;
create policy "authorized users can create project messages"
on public.messages for insert to authenticated, anon
with check (
  organization_id in (select public.get_authorized_orgs('member'))
  and (
    not public.is_project_expert(organization_id)
    or (
      project_id is not null
      and public.can_access_project(organization_id, project_id)
      and public.can_access_conversation(organization_id, conversation_id)
    )
  )
);

drop policy if exists "members can read their org campaigns" on public.campaigns;
create policy "authorized users can read project campaigns"
on public.campaigns for select to authenticated, anon
using (
  organization_id in (select public.get_authorized_orgs('member'))
  and (
    not public.is_project_expert(organization_id)
    or (project_id is not null and public.can_access_project(organization_id, project_id))
  )
);
drop policy if exists "members can read their org campaign recipients" on public.campaign_recipients;
create policy "authorized users can read project campaign recipients"
on public.campaign_recipients for select to authenticated, anon
using (
  exists (
    select 1 from public.campaigns c
    where c.id = campaign_recipients.campaign_id
  )
);

drop policy if exists "members can read their orgs contact tags" on public.contact_tags;
create policy "authorized users can read visible contact tags"
on public.contact_tags for select to authenticated, anon
using (public.can_access_contact(organization_id, contact_id));

drop policy if exists "members can read their orgs tags" on public.tags;
create policy "authorized users can read visible tags"
on public.tags for select to authenticated, anon
using (
  organization_id in (select public.get_authorized_orgs('member'))
  and (
    not public.is_project_expert(organization_id)
    or exists (
      select 1 from public.project_tags pt
      where pt.organization_id = tags.organization_id
        and pt.tag_id = tags.id
        and public.can_access_project(pt.organization_id, pt.project_id)
    )
    or exists (
      select 1 from public.contact_tags ct
      where ct.organization_id = tags.organization_id
        and ct.tag_id = tags.id
        and public.can_access_contact(ct.organization_id, ct.contact_id)
    )
  )
);
drop policy if exists "members can create non-system tags" on public.tags;
create policy "legacy members can create non-system tags"
on public.tags for insert to authenticated, anon
with check (
  not is_system and system_key is null
  and organization_id in (select public.get_authorized_orgs('member'))
  and not public.is_project_expert(organization_id)
);
drop policy if exists "members can update non-system tags" on public.tags;
create policy "legacy members can update non-system tags"
on public.tags for update to authenticated, anon
using (
  not is_system
  and organization_id in (select public.get_authorized_orgs('member'))
  and not public.is_project_expert(organization_id)
) with check (
  not is_system and system_key is null
  and organization_id in (select public.get_authorized_orgs('member'))
  and not public.is_project_expert(organization_id)
);
drop policy if exists "members can delete non-system tags" on public.tags;
create policy "legacy members can delete non-system tags"
on public.tags for delete to authenticated, anon
using (
  not is_system
  and organization_id in (select public.get_authorized_orgs('member'))
  and not public.is_project_expert(organization_id)
);
drop policy if exists "members can create non-system contact tags" on public.contact_tags;
create policy "legacy members can create non-system contact tags"
on public.contact_tags for insert to authenticated, anon
with check (
  organization_id in (select public.get_authorized_orgs('member'))
  and not public.is_project_expert(organization_id)
  and exists (
    select 1 from public.tags t
    where t.organization_id = contact_tags.organization_id
      and t.id = contact_tags.tag_id and not t.is_system
  )
);
drop policy if exists "members can delete non-system contact tags" on public.contact_tags;
create policy "legacy members can delete non-system contact tags"
on public.contact_tags for delete to authenticated, anon
using (
  organization_id in (select public.get_authorized_orgs('member'))
  and not public.is_project_expert(organization_id)
  and exists (
    select 1 from public.tags t
    where t.organization_id = contact_tags.organization_id
      and t.id = contact_tags.tag_id and not t.is_system
  )
);

drop policy if exists "members can read their orgs contact opt outs" on public.contact_opt_outs;
create policy "authorized users can read visible contact opt outs"
on public.contact_opt_outs for select to authenticated, anon
using (
  public.can_access_contact_address(organization_id, service, contact_address)
);

grant select on public.project_conversations to authenticated, anon;
grant all on public.project_conversations to service_role;
revoke all on function public.can_access_contact(uuid, uuid) from public;
revoke all on function public.can_access_contact_address(uuid, public.service, text) from public;
revoke all on function public.can_access_conversation(uuid, uuid) from public;
revoke all on function public.set_message_project_context() from public;
revoke all on function public.link_message_project_conversation() from public;
revoke all on function public.assign_message_project(uuid, uuid) from public;
revoke all on function public.get_project_campaign_summaries(uuid, uuid) from public;
grant execute on function public.can_access_contact(uuid, uuid) to authenticated, anon, service_role;
grant execute on function public.can_access_contact_address(uuid, public.service, text) to authenticated, anon, service_role;
grant execute on function public.can_access_conversation(uuid, uuid) to authenticated, anon, service_role;
grant execute on function public.assign_message_project(uuid, uuid) to authenticated, service_role;
grant execute on function public.get_project_campaign_summaries(uuid, uuid) to service_role;

-- Production hardening for project-scoped contacts, conversations and campaign reporting.

create table public.project_contact_origins (
  organization_id uuid not null,
  project_id uuid not null,
  contact_id uuid not null,
  source text not null,
  source_key text not null default '',
  created_at timestamptz not null default now(),
  primary key (organization_id, project_id, contact_id, source, source_key),
  foreign key (organization_id, project_id, contact_id)
    references public.project_contacts(organization_id, project_id, contact_id)
    on delete cascade,
  constraint project_contact_origins_source_check
    check (source in ('manual', 'tag', 'import', 'system'))
);

create index project_contact_origins_contact_idx
on public.project_contact_origins (organization_id, contact_id, project_id);

insert into public.project_contact_origins (
  organization_id, project_id, contact_id, source, source_key
)
select organization_id, project_id, contact_id, source, ''
from public.project_contacts
on conflict do nothing;

alter table public.project_contact_origins enable row level security;

create policy "authorized users can read project contact origins"
on public.project_contact_origins for select to authenticated, anon
using (public.can_access_project(organization_id, project_id));

create policy "project admins can manage project contact origins"
on public.project_contact_origins for all to authenticated, anon
using (public.can_administer_projects(organization_id))
with check (public.can_administer_projects(organization_id));

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

    insert into public.project_contact_origins (
      organization_id, project_id, contact_id, source, source_key
    )
    select new.organization_id, pt.project_id, new.contact_id, 'tag', new.tag_id::text
    from public.project_tags pt
    where pt.organization_id = new.organization_id and pt.tag_id = new.tag_id
    on conflict do nothing;
    return new;
  end if;

  delete from public.project_contact_origins o
  where o.organization_id = v_org and o.contact_id = v_contact
    and o.source = 'tag' and o.source_key = old.tag_id::text;

  delete from public.project_contacts pc
  where pc.organization_id = v_org and pc.contact_id = v_contact
    and not exists (
      select 1 from public.project_contact_origins o
      where o.organization_id = pc.organization_id
        and o.project_id = pc.project_id and o.contact_id = pc.contact_id
    );
  return old;
end;
$$;

create or replace function public.sync_project_contacts_from_project_tag()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    insert into public.project_contacts (organization_id, project_id, contact_id, source)
    select new.organization_id, new.project_id, ct.contact_id, 'tag'
    from public.contact_tags ct
    where ct.organization_id = new.organization_id and ct.tag_id = new.tag_id
    on conflict do nothing;

    insert into public.project_contact_origins (
      organization_id, project_id, contact_id, source, source_key
    )
    select new.organization_id, new.project_id, ct.contact_id, 'tag', new.tag_id::text
    from public.contact_tags ct
    where ct.organization_id = new.organization_id and ct.tag_id = new.tag_id
    on conflict do nothing;
    return new;
  end if;

  delete from public.project_contact_origins o
  where o.organization_id = old.organization_id
    and o.project_id = old.project_id and o.source = 'tag'
    and o.source_key = old.tag_id::text;

  delete from public.project_contacts pc
  where pc.organization_id = old.organization_id and pc.project_id = old.project_id
    and not exists (
      select 1 from public.project_contact_origins o
      where o.organization_id = pc.organization_id
        and o.project_id = pc.project_id and o.contact_id = pc.contact_id
    );
  return old;
end;
$$;

create or replace function public.add_project_contact_origins(
  p_organization_id uuid,
  p_project_id uuid,
  p_contact_ids uuid[],
  p_source text default 'import'
) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_count integer;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'Project contact import denied';
  end if;
  if p_source not in ('manual', 'import', 'system') then
    raise exception using errcode = '22023', message = 'Invalid project contact source';
  end if;

  insert into public.project_contacts (organization_id, project_id, contact_id, source)
  select p_organization_id, p_project_id, contact_id, p_source
  from unnest(coalesce(p_contact_ids, array[]::uuid[])) as contact_id
  on conflict do nothing;

  insert into public.project_contact_origins (
    organization_id, project_id, contact_id, source, source_key
  )
  select p_organization_id, p_project_id, contact_id, p_source, ''
  from unnest(coalesce(p_contact_ids, array[]::uuid[])) as contact_id
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.add_project_contact_origins(uuid, uuid, uuid[], text)
from public, anon, authenticated;
grant execute on function public.add_project_contact_origins(uuid, uuid, uuid[], text)
to service_role;

create or replace function public.can_send_project_message(
  p_organization_id uuid,
  p_project_id uuid,
  p_conversation_id uuid
) returns boolean
language sql volatile security definer set search_path = '' as $$
  select public.can_access_project(p_organization_id, p_project_id)
    and exists (
      select 1
      from public.conversations c
      join public.contacts_addresses ca
        on ca.organization_id = c.organization_id
       and ca.service = c.service
       and ca.address = c.contact_address
      join public.project_contacts pc
        on pc.organization_id = ca.organization_id
       and pc.contact_id = ca.contact_id
       and pc.project_id = p_project_id
      where c.organization_id = p_organization_id
        and c.id = p_conversation_id
    );
$$;

revoke all on function public.can_send_project_message(uuid, uuid, uuid) from public;
grant execute on function public.can_send_project_message(uuid, uuid, uuid)
to authenticated, anon, service_role;

drop policy if exists "authorized users can create project messages" on public.messages;
create policy "authorized users can create project messages"
on public.messages for insert to authenticated, anon
with check (
  organization_id in (select public.get_authorized_orgs('member'))
  and (
    not public.is_project_expert(organization_id)
    or (
      project_id is not null
      and public.can_send_project_message(organization_id, project_id, conversation_id)
    )
  )
);

create or replace function public.guard_expert_conversation_update()
returns trigger language plpgsql set search_path = '' as $$
begin
  if public.is_project_expert(old.organization_id) and (
    new.organization_id is distinct from old.organization_id
    or new.id is distinct from old.id
    or new.service is distinct from old.service
    or new.organization_address is distinct from old.organization_address
    or new.contact_address is distinct from old.contact_address
    or new.group_address is distinct from old.group_address
    or new.created_at is distinct from old.created_at
  ) then
    raise exception using errcode = '42501',
      message = 'Experts cannot change conversation routing fields';
  end if;
  return new;
end;
$$;

drop trigger if exists guard_expert_conversation_update on public.conversations;
create trigger guard_expert_conversation_update
before update on public.conversations
for each row execute function public.guard_expert_conversation_update();

create or replace function public.get_campaign_summaries(
  p_organization_id uuid,
  p_campaign_id uuid default null
) returns table (
  id uuid, name text, status text, total bigint, pending bigint,
  accepted bigint, sent bigint, delivered bigint, read bigint,
  failed bigint, skipped bigint, created_at timestamptz
)
language sql stable security definer set search_path = '' as $$
  with classified as (
    select c.id, c.name, c.status, c.total_cap, c.created_at, r.id as recipient_id,
      case
        when r.status in ('suppressed', 'cancelled') then 'skipped'
        when coalesce(m.status, '{}'::jsonb) ? 'read' then 'read'
        when coalesce(m.status, '{}'::jsonb) ? 'delivered' then 'delivered'
        when coalesce(m.status, '{}'::jsonb) ? 'sent' then 'sent'
        when coalesce(m.status, '{}'::jsonb) ? 'accepted' or m.external_id is not null then 'accepted'
        when r.status in ('failed', 'ambiguous') or coalesce(m.status, '{}'::jsonb) ? 'failed' then 'failed'
        else 'pending'
      end as delivery_state
    from public.campaigns c
    left join public.campaign_recipients r on r.campaign_id = c.id
    left join public.messages m on m.id = r.message_id
    where c.organization_id = p_organization_id
      and (p_campaign_id is null or c.id = p_campaign_id)
  )
  select id, name, status, max(total_cap)::bigint,
    count(recipient_id) filter (where delivery_state = 'pending'),
    count(recipient_id) filter (where delivery_state = 'accepted'),
    count(recipient_id) filter (where delivery_state = 'sent'),
    count(recipient_id) filter (where delivery_state = 'delivered'),
    count(recipient_id) filter (where delivery_state = 'read'),
    count(recipient_id) filter (where delivery_state = 'failed'),
    count(recipient_id) filter (where delivery_state = 'skipped'),
    max(created_at)
  from classified
  group by id, name, status
  order by max(created_at) desc
  limit 100;
$$;

revoke all on function public.get_campaign_summaries(uuid, uuid)
from public, anon, authenticated;
grant execute on function public.get_campaign_summaries(uuid, uuid) to service_role;

-- Re-emit project authorization helpers with volatility matching their
-- authorization/session lookups. This is additive and safe for databases that
-- already applied an earlier local draft of the project migrations.

create or replace function public.can_access_project(
  p_organization_id uuid,
  p_project_id uuid
) returns boolean language plpgsql volatile security definer set search_path = '' as $$
begin
  if not (p_organization_id in (select public.get_authorized_orgs('member'))) then
    return false;
  end if;
  if auth.uid() is null or not public.is_project_expert(p_organization_id) then
    return true;
  end if;
  return exists (
    select 1 from public.project_memberships pm
    join public.agents a on a.id = pm.agent_id
    where pm.organization_id = p_organization_id
      and pm.project_id = p_project_id and a.user_id = auth.uid()
  );
end;
$$;

create or replace function public.can_administer_projects(p_organization_id uuid)
returns boolean language sql volatile security definer set search_path = '' as $$
  select p_organization_id in (select public.get_authorized_orgs('admin'));
$$;

create or replace function public.get_current_expert_project_ids(
  p_organization_id uuid
) returns table(project_id uuid)
language sql volatile security definer set search_path = '' as $$
  select pm.project_id
  from public.project_memberships pm
  join public.agents a on a.id = pm.agent_id
  where pm.organization_id = p_organization_id
    and a.organization_id = p_organization_id
    and a.user_id = auth.uid()
    and a.ai = false
    and a.extra->>'account_type' = 'expert'
    and p_organization_id in (select public.get_authorized_orgs('member'));
$$;

-- Preserve explicit project-contact provenance for direct/manual writes.
create or replace function public.sync_explicit_project_contact_origin()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.source <> 'tag' then
    insert into public.project_contact_origins (
      organization_id, project_id, contact_id, source, source_key
    ) values (
      new.organization_id, new.project_id, new.contact_id, new.source, ''
    ) on conflict do nothing;
  end if;
  return new;
end;
$$;

create trigger sync_explicit_project_contact_origin
after insert or update of source on public.project_contacts
for each row execute function public.sync_explicit_project_contact_origin();

-- Admin-only replacement of manual contact/project classifications. Origins
-- from tags, imports and system bootstraps remain untouched.
create or replace function public.set_contact_manual_projects(
  p_organization_id uuid,
  p_contact_id uuid,
  p_project_ids uuid[]
) returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_project_ids uuid[];
  v_count integer;
begin
  if not public.can_administer_projects(p_organization_id) then
    raise exception using errcode = '42501',
      message = 'Only organization admins can change contact projects';
  end if;
  if not exists (
    select 1 from public.contacts c
    where c.organization_id = p_organization_id and c.id = p_contact_id
  ) then
    raise exception using errcode = '22023', message = 'Contact does not belong to organization';
  end if;

  select coalesce(array_agg(distinct project_id order by project_id), array[]::uuid[])
    into v_project_ids
  from unnest(coalesce(p_project_ids, array[]::uuid[])) as requested(project_id);
  if exists (
    select 1 from unnest(v_project_ids) requested(project_id)
    where not exists (
      select 1 from public.projects p
      where p.organization_id = p_organization_id and p.id = requested.project_id
    )
  ) then
    raise exception using errcode = '22023', message = 'Project does not belong to organization';
  end if;

  insert into public.project_contacts (organization_id, project_id, contact_id, source)
  select p_organization_id, project_id, p_contact_id, 'manual'
  from unnest(v_project_ids) requested(project_id)
  on conflict do nothing;
  insert into public.project_contact_origins (
    organization_id, project_id, contact_id, source, source_key
  )
  select p_organization_id, project_id, p_contact_id, 'manual', ''
  from unnest(v_project_ids) requested(project_id)
  on conflict do nothing;

  delete from public.project_contact_origins origin
  where origin.organization_id = p_organization_id
    and origin.contact_id = p_contact_id and origin.source = 'manual'
    and not (origin.project_id = any(v_project_ids));
  delete from public.project_contacts contact_project
  where contact_project.organization_id = p_organization_id
    and contact_project.contact_id = p_contact_id
    and not exists (
      select 1 from public.project_contact_origins origin
      where origin.organization_id = contact_project.organization_id
        and origin.project_id = contact_project.project_id
        and origin.contact_id = contact_project.contact_id
    );

  select count(*)::integer into v_count from public.project_contacts
  where organization_id = p_organization_id and contact_id = p_contact_id;
  return v_count;
end;
$$;

revoke all on function public.set_contact_manual_projects(uuid, uuid, uuid[]) from public, anon;
grant execute on function public.set_contact_manual_projects(uuid, uuid, uuid[])
to authenticated, service_role;

-- Experts may only reply as themselves. WhatsApp replies require an incoming
-- message strictly inside the current 24-hour customer-service window.
create or replace function public.enforce_expert_message_rules() returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_agent_id uuid;
  v_conversation public.conversations%rowtype;
begin
  if not public.is_project_expert(new.organization_id) then return new; end if;
  if new.direction <> 'outgoing'::public.direction then
    raise exception using errcode = '42501', message = 'Experts can only send outgoing messages';
  end if;
  if lower(coalesce(new.content->>'kind', '')) = 'template' then
    raise exception using errcode = '42501',
      message = 'Experts cannot initiate conversations with templates';
  end if;
  select a.id into v_agent_id from public.agents a
  where a.organization_id = new.organization_id and a.user_id = auth.uid()
    and a.ai = false and a.extra->>'account_type' = 'expert'
    and a.extra->'invitation'->>'status' = 'accepted';
  if v_agent_id is null or new.agent_id is distinct from v_agent_id then
    raise exception using errcode = '42501',
      message = 'Expert message sender does not match authenticated expert';
  end if;
  select conversation.* into v_conversation from public.conversations conversation
  where conversation.organization_id = new.organization_id
    and conversation.id = new.conversation_id;
  if v_conversation.id is null
    or new.service is distinct from v_conversation.service
    or new.organization_address is distinct from v_conversation.organization_address
    or new.contact_address is distinct from v_conversation.contact_address
    or new.group_address is distinct from v_conversation.group_address then
    raise exception using errcode = '42501',
      message = 'Expert message routing does not match the conversation';
  end if;
  if v_conversation.service = 'whatsapp'::public.service and not exists (
    select 1 from public.messages incoming
    where incoming.organization_id = new.organization_id
      and incoming.conversation_id = new.conversation_id
      and incoming.direction = 'incoming'::public.direction
      and incoming.timestamp > now() - interval '24 hours'
      and incoming.timestamp <= now()
  ) then
    raise exception using errcode = '42501',
      message = 'WhatsApp 24-hour customer service window is closed';
  end if;
  return new;
end;
$$;

create trigger zz_enforce_expert_message_rules
before insert on public.messages
for each row execute function public.enforce_expert_message_rules();
revoke all on function public.enforce_expert_message_rules() from public, anon, authenticated;
