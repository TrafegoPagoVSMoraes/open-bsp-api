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
