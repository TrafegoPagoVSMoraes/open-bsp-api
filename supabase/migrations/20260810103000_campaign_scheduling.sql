-- Schedule durable campaigns without creating a second delivery path.
-- The existing worker remains the only component allowed to claim recipients.

alter table public.campaigns
  add column scheduled_at timestamptz;

alter table public.campaigns drop constraint campaigns_status_check;
alter table public.campaigns add constraint campaigns_status_check
  check (status in (
    'draft', 'scheduled', 'running', 'cancel_requested',
    'cancelled', 'completed', 'failed'
  ));

alter table public.campaigns add constraint campaigns_scheduled_at_check
  check (status <> 'scheduled' or scheduled_at is not null);

create index campaigns_scheduled_idx
  on public.campaigns (scheduled_at, id)
  where status = 'scheduled';

create function public.promote_due_campaigns() returns integer
language plpgsql security definer set search_path = '' as $$
declare _count integer;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'Campaign worker access denied';
  end if;

  update public.campaigns
  set status = 'running', started_at = now(), updated_at = now()
  where status = 'scheduled' and scheduled_at <= now();

  get diagnostics _count = row_count;
  return _count;
end;
$$;

revoke all on function public.promote_due_campaigns()
from public, anon, authenticated;
grant execute on function public.promote_due_campaigns() to service_role;
