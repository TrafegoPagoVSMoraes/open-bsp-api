alter table public.tracking_events enable row level security;

-- Raw events are read through an organization-authorized aggregate RPC.
create policy "service role can manage tracking events"
on public.tracking_events
as permissive for all
to service_role
using (true)
with check (true);

revoke all on table public.tracking_events from anon, authenticated;
grant all on table public.tracking_events to service_role;
