-- Authenticated tracking report with optional PII. The public dashboard remains
-- masked; this RPC still requires membership in the requested organization.

create or replace function public.get_tracking_dashboard_private(
  p_organization_id uuid,
  p_project_id uuid default null,
  p_from timestamptz default now() - interval '30 days',
  p_to timestamptz default now()
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  result jsonb;
  recent jsonb;
begin
  if not exists (
    select 1
    from public.get_authorized_orgs('member') authorized(organization_id)
    where organization_id = p_organization_id
  ) then
    raise exception using errcode = '42501', message = 'Tracking dashboard access denied';
  end if;

  result := public.get_tracking_dashboard(
    p_organization_id,
    p_project_id,
    p_from,
    p_to
  );

  select coalesce(
    jsonb_agg(to_jsonb(activity) order by activity.occurred_at desc),
    '[]'::jsonb
  )
  into recent
  from (
    select
      event.event_id,
      event.project_id,
      event.message_id,
      event.event_name,
      event.event_type,
      event.element_id,
      event.page_path,
      event.occurred_at,
      message.contact_address,
      case
        when message.contact_address is null then null
        when length(message.contact_address) <= 4
          then repeat('*', length(message.contact_address))
        else repeat('*', greatest(length(message.contact_address) - 4, 0))
          || right(message.contact_address, 4)
      end as contact_address_masked
    from public.tracking_events event
    left join public.messages message on message.id = event.message_id
    where event.organization_id = p_organization_id
      and (p_project_id is null or event.project_id = p_project_id)
      and event.occurred_at >= p_from
      and event.occurred_at < p_to
    order by event.occurred_at desc
    limit 50
  ) activity;

  return jsonb_set(
    jsonb_set(result, '{recent_activity}', recent, true),
    '{permissions}',
    jsonb_build_object('can_view_pii', true),
    true
  ) || jsonb_build_object('can_view_pii', true);
end;
$$;

revoke all on function public.get_tracking_dashboard_private(
  uuid, uuid, timestamptz, timestamptz
) from public;
grant execute on function public.get_tracking_dashboard_private(
  uuid, uuid, timestamptz, timestamptz
) to authenticated, anon;
