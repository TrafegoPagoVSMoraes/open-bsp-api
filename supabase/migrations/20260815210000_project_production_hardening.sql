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
