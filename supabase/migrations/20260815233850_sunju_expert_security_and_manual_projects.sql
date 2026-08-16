-- Expert drafts are inert until explicitly activated by an organization admin.
-- This extends the legacy pending -> accepted/rejected invitation flow without
-- changing owner/admin/service-role behavior.

create or replace function public.enforce_invitation_status_flow() returns trigger
language plpgsql
set search_path to ''
as $$
declare
  old_status text := old.extra->'invitation'->>'status';
  new_status text := new.extra->'invitation'->>'status';
  old_email text := nullif(lower(btrim(old.extra->'invitation'->>'email')), '');
  new_email text := nullif(lower(btrim(new.extra->'invitation'->>'email')), '');
begin
  if old.extra->'invitation' is not null then
    if new.extra->'invitation' is null then
      raise exception 'Cannot remove invitation';
    end if;

    if old_status = 'draft' then
      if new_status not in ('draft', 'pending', 'accepted') then
        raise exception 'Draft invitation status can only remain draft or change to pending or accepted';
      end if;
      if old_email is distinct from new_email and new_status <> 'draft'
        and new_email is null then
        raise exception 'An email is required to activate an expert';
      end if;
    else
      if new_email is distinct from old_email then
        raise exception 'Cannot change invitation email';
      end if;
      if old_status is distinct from new_status then
        if old_status <> 'pending' then
          raise exception 'Cannot change invitation status from %', old_status;
        end if;
        if new_status not in ('accepted', 'rejected') then
          raise exception 'Invitation status can only be changed to accepted or rejected';
        end if;
      end if;
    end if;

    if new_status in ('pending', 'accepted') and new_email is null then
      raise exception 'An email is required to activate an expert';
    end if;
    if new_status = 'accepted' and new.user_id is null then
      raise exception 'An accepted expert must be linked to an authenticated user';
    end if;
  else
    if new.extra->'invitation' is not null then
      raise exception 'Cannot add invitation to existing agent';
    end if;
  end if;

  return new;
end;
$$;

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
    and origin.contact_id = p_contact_id
    and origin.source = 'manual'
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

  select count(*)::integer into v_count
  from public.project_contacts
  where organization_id = p_organization_id and contact_id = p_contact_id;
  return v_count;
end;
$$;

revoke all on function public.set_contact_manual_projects(uuid, uuid, uuid[]) from public, anon;
grant execute on function public.set_contact_manual_projects(uuid, uuid, uuid[])
to authenticated, service_role;

create or replace function public.enforce_expert_message_rules() returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_agent_id uuid;
  v_conversation public.conversations%rowtype;
begin
  if not public.is_project_expert(new.organization_id) then
    return new;
  end if;

  if new.direction <> 'outgoing'::public.direction then
    raise exception using errcode = '42501',
      message = 'Experts can only send outgoing messages';
  end if;

  if lower(coalesce(new.content->>'kind', '')) = 'template' then
    raise exception using errcode = '42501',
      message = 'Experts cannot initiate conversations with templates';
  end if;

  select a.id into v_agent_id
  from public.agents a
  where a.organization_id = new.organization_id
    and a.user_id = auth.uid()
    and a.ai = false
    and a.extra->>'account_type' = 'expert'
    and a.extra->'invitation'->>'status' = 'accepted';

  if v_agent_id is null or new.agent_id is distinct from v_agent_id then
    raise exception using errcode = '42501',
      message = 'Expert message sender does not match authenticated expert';
  end if;

  select conversation.* into v_conversation
  from public.conversations conversation
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

drop trigger if exists zz_enforce_expert_message_rules on public.messages;
create trigger zz_enforce_expert_message_rules
before insert on public.messages
for each row execute function public.enforce_expert_message_rules();

revoke all on function public.enforce_expert_message_rules() from public, anon, authenticated;
