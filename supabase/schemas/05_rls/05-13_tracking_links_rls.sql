alter table public.tracking_links enable row level security;

-- Link hashes are capabilities and are intentionally not exposed directly.
create policy "service role can manage tracking links"
on public.tracking_links
as permissive for all
to service_role
using (true)
with check (true);

revoke all on table public.tracking_links from anon, authenticated;
grant all on table public.tracking_links to service_role;
