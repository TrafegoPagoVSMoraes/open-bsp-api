-- Scheduled TAG audiences are materialized atomically at execution time.

alter table public.campaigns
  add column audience_type text not null default 'explicit'
    check (audience_type in ('explicit', 'tags')),
  add column audience_tag_ids uuid[] not null default '{}',
  add column variable_mapping jsonb not null default '{}'::jsonb
    check (jsonb_typeof(variable_mapping) = 'object'),
  add column audience_materialized_at timestamptz;

create or replace function public.protect_campaign_ceiling() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and new.total_cap <> old.total_cap
     and not (
       old.status = 'scheduled'
       and old.audience_type = 'tags'
       and new.status in ('running', 'failed')
     ) then
    raise exception using errcode = 'P0001', message = 'Campaign total_cap is immutable';
  end if;
  return new;
end;
$$;

create or replace function public.validate_campaign_recipient() returns trigger
language plpgsql security definer set search_path = '' as $$
declare _campaign public.campaigns%rowtype;
begin
  select * into _campaign from public.campaigns where id = new.campaign_id;
  if not found or _campaign.organization_id <> new.organization_id then
    raise exception using errcode = 'P0001', message = 'Invalid campaign organization';
  end if;
  if _campaign.status <> 'draft' and not (
    _campaign.status = 'scheduled'
    and _campaign.audience_type = 'tags'
    and coalesce(auth.role(), '') = 'service_role'
  ) then
    raise exception using errcode = 'P0001', message = 'Recipients are immutable after campaign start';
  end if;
  return new;
end;
$$;

create function public.resolve_campaign_contact_variables(
  p_mapping jsonb,
  p_name text
) returns jsonb
language sql immutable set search_path = '' as $$
  with values_resolved as (
    select entry.key,
      case entry.value->>'source'
        when 'constant' then entry.value->>'constant'
        when 'first_name' then split_part(btrim(coalesce(p_name, '')), ' ', 1)
        when 'full_name' then btrim(coalesce(p_name, ''))
        else null
      end as value
    from jsonb_each(coalesce(p_mapping, '{}'::jsonb)) entry
  )
  select case
    when exists (select 1 from values_resolved where nullif(btrim(value), '') is null)
      then null
    else coalesce(jsonb_object_agg(key, value), '{}'::jsonb)
  end
  from values_resolved;
$$;

revoke all on function public.resolve_campaign_contact_variables(jsonb, text)
from public, anon, authenticated;
grant execute on function public.resolve_campaign_contact_variables(jsonb, text)
to service_role;

create function public.materialize_due_tag_campaigns() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  campaign_row public.campaigns%rowtype;
  recipient_count integer;
  materialized integer := 0;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'Campaign worker access denied';
  end if;

  for campaign_row in
    select * from public.campaigns
    where status = 'scheduled' and audience_type = 'tags'
      and scheduled_at <= now()
    order by scheduled_at, id
    for update skip locked
  loop
    delete from public.campaign_recipients
    where campaign_id = campaign_row.id and status = 'queued';

    insert into public.campaign_recipients (
      campaign_id, organization_id, phone, display_name, variables
    )
    select campaign_row.id, campaign_row.organization_id, audience.phone,
      audience.display_name, audience.variables
    from (
      select distinct on (address.address)
        address.address as phone,
        contact.name as display_name,
        public.resolve_campaign_contact_variables(
          campaign_row.variable_mapping,
          contact.name
        ) as variables
      from public.contact_tags membership
      join public.contacts contact
        on contact.organization_id = membership.organization_id
       and contact.id = membership.contact_id
      join public.contacts_addresses address
        on address.organization_id = contact.organization_id
       and address.contact_id = contact.id
       and address.service = 'whatsapp'::public.service
       and address.status = 'active'
      where membership.organization_id = campaign_row.organization_id
        and membership.tag_id = any(campaign_row.audience_tag_ids)
        and address.address ~ '^[1-9][0-9]{9,14}$'
        and not exists (
          select 1 from public.contact_opt_outs optout
          where optout.organization_id = campaign_row.organization_id
            and optout.service = 'whatsapp'::public.service
            and optout.organization_address = campaign_row.organization_address
            and optout.contact_address = address.address
        )
      order by address.address, membership.created_at
    ) audience
    where audience.variables is not null;

    get diagnostics recipient_count = row_count;
    if recipient_count = 0 then
      update public.campaigns set
        status = 'failed', completed_at = now(), updated_at = now(),
        audience_materialized_at = now()
      where id = campaign_row.id;
    else
      update public.campaigns set
        total_cap = recipient_count, status = 'running', started_at = now(),
        updated_at = now(), audience_materialized_at = now()
      where id = campaign_row.id;
    end if;
    materialized := materialized + 1;
  end loop;

  return materialized;
end;
$$;

revoke all on function public.materialize_due_tag_campaigns()
from public, anon, authenticated;
grant execute on function public.materialize_due_tag_campaigns() to service_role;

create or replace function public.promote_due_campaigns() returns integer
language plpgsql security definer set search_path = '' as $$
declare _count integer;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'Campaign worker access denied';
  end if;
  update public.campaigns
  set status = 'running', started_at = now(), updated_at = now()
  where status = 'scheduled' and scheduled_at <= now()
    and audience_type = 'explicit';
  get diagnostics _count = row_count;
  return _count;
end;
$$;
