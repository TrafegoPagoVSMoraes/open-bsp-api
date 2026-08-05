alter table public.tracking_projects enable row level security;

create policy "members can read their tracking projects"
on public.tracking_projects
as permissive for select
to authenticated
using (
  organization_id in (select public.get_authorized_orgs('member'))
);

create policy "service role can manage tracking projects"
on public.tracking_projects
as permissive for all
to service_role
using (true)
with check (true);

revoke all on table public.tracking_projects from anon, authenticated;
grant select on table public.tracking_projects to authenticated;
grant all on table public.tracking_projects to service_role;
