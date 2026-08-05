alter table public.tracking_sessions enable row level security;

-- Session hashes are short-lived capabilities and stay server-side.
create policy "service role can manage tracking sessions"
on public.tracking_sessions
as permissive for all
to service_role
using (true)
with check (true);

revoke all on table public.tracking_sessions from anon, authenticated;
grant all on table public.tracking_sessions to service_role;
