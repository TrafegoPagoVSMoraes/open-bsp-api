-- Authenticated, paginated activity history. PII remains organization-scoped.

alter table public.tracking_projects
  drop constraint tracking_projects_retention;
alter table public.tracking_projects
  add constraint tracking_projects_retention
  check (retention_days between 1 and 3650);

create function public.get_tracking_activity_private(
  p_organization_id uuid,
  p_project_id uuid default null,
  p_from timestamptz default now() - interval '30 days',
  p_to timestamptz default now(),
  p_limit integer default 100,
  p_offset integer default 0
) returns table (
  event_id uuid,
  project_id uuid,
  message_id uuid,
  event_name text,
  event_type public.tracking_event_type,
  element_id text,
  page_path text,
  occurred_at timestamptz,
  contact_address text,
  contact_address_masked text
)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not exists (
    select 1 from public.get_authorized_orgs('member') authorized(organization_id)
    where organization_id = p_organization_id
  ) then
    raise exception using errcode = '42501', message = 'Tracking activity access denied';
  end if;
  if p_limit < 1 or p_limit > 200 or p_offset < 0 or p_offset > 100000 then
    raise exception using errcode = '22023', message = 'Invalid tracking activity page';
  end if;

  return query
  select event.event_id, event.project_id, event.message_id, event.event_name,
    event.event_type, event.element_id, event.page_path, event.occurred_at,
    message.contact_address,
    case
      when message.contact_address is null then null
      when length(message.contact_address) <= 4 then repeat('*', length(message.contact_address))
      else repeat('*', greatest(length(message.contact_address) - 4, 0))
        || right(message.contact_address, 4)
    end
  from public.tracking_events event
  left join public.messages message on message.id = event.message_id
  where event.organization_id = p_organization_id
    and (p_project_id is null or event.project_id = p_project_id)
    and event.occurred_at >= p_from and event.occurred_at < p_to
  order by event.occurred_at desc, event.event_id desc
  limit p_limit offset p_offset;
end;
$$;

revoke all on function public.get_tracking_activity_private(
  uuid, uuid, timestamptz, timestamptz, integer, integer
) from public;
grant execute on function public.get_tracking_activity_private(
  uuid, uuid, timestamptz, timestamptz, integer, integer
) to authenticated, anon;
