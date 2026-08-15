-- Phase 2: experts reuse Supabase Auth + human agents. Project membership is
-- explicit and independent from tags.

create table public.project_memberships (
  organization_id uuid not null,
  project_id uuid not null,
  agent_id uuid not null,
  role text not null default 'expert',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (organization_id, project_id, agent_id),
  foreign key (organization_id, project_id)
    references public.projects(organization_id, id) on delete cascade,
  foreign key (agent_id) references public.agents(id) on delete cascade,
  constraint project_memberships_role_check check (role in ('expert', 'manager'))
);

create index project_memberships_agent_project_idx
on public.project_memberships (organization_id, agent_id, project_id);

create trigger set_updated_at before update on public.project_memberships
for each row execute function public.moddatetime('updated_at');

create or replace function public.is_project_expert(p_organization_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.agents a
    where a.organization_id = p_organization_id
      and a.user_id = auth.uid() and a.ai = false
      and a.extra->>'account_type' = 'expert'
      and (a.extra->'invitation' is null or a.extra->'invitation'->>'status' = 'accepted')
  );
$$;

create or replace function public.can_access_project(
  p_organization_id uuid,
  p_project_id uuid
) returns boolean language plpgsql volatile security definer set search_path = '' as $$
begin
  if not (p_organization_id in (select public.get_authorized_orgs('member'))) then
    return false;
  end if;
  if auth.uid() is null or not public.is_project_expert(p_organization_id) then
    return true;
  end if;
  return exists (
    select 1 from public.project_memberships pm
    join public.agents a on a.id = pm.agent_id
    where pm.organization_id = p_organization_id
      and pm.project_id = p_project_id and a.user_id = auth.uid()
  );
end;
$$;

create or replace function public.can_administer_projects(p_organization_id uuid)
returns boolean language sql volatile security definer set search_path = '' as $$
  select p_organization_id in (select public.get_authorized_orgs('admin'));
$$;

create or replace function public.get_current_expert_project_ids(
  p_organization_id uuid
) returns table(project_id uuid)
language sql volatile security definer set search_path = '' as $$
  select pm.project_id
  from public.project_memberships pm
  join public.agents a on a.id = pm.agent_id
  where pm.organization_id = p_organization_id
    and a.organization_id = p_organization_id
    and a.user_id = auth.uid()
    and a.ai = false
    and a.extra->>'account_type' = 'expert'
    and p_organization_id in (select public.get_authorized_orgs('member'));
$$;

alter table public.project_memberships enable row level security;

create policy "experts can read own project memberships" on public.project_memberships
for select to authenticated, anon
using (
  public.can_administer_projects(organization_id)
  or exists (
    select 1 from public.agents a
    where a.id = project_memberships.agent_id and a.user_id = auth.uid()
  )
);
create policy "admins can manage project memberships" on public.project_memberships
for all to authenticated, anon
using (public.can_administer_projects(organization_id))
with check (public.can_administer_projects(organization_id));

-- Existing invitation mechanics are preserved, while organization admins may
-- create the restricted expert account type without gaining owner powers.
create policy "admins can invite project experts" on public.agents
for insert to authenticated, anon
with check (
  public.can_administer_projects(organization_id)
  and ai = false
  and extra->>'account_type' = 'expert'
  and extra->>'role' = 'member'
  and extra->'invitation'->>'status' = 'pending'
  and nullif(extra->'invitation'->>'email', '') is not null
);

drop policy if exists "members can read their orgs agents" on public.agents;
create policy "legacy members can read their orgs agents" on public.agents
for select to authenticated, anon
using (
  organization_id in (select public.get_authorized_orgs('member'))
  and not public.is_project_expert(organization_id)
);

drop policy if exists "members can read organization projects" on public.projects;
create policy "authorized users can read projects" on public.projects
for select to authenticated, anon
using (public.can_access_project(organization_id, id));

drop policy if exists "members can read project tags" on public.project_tags;
create policy "authorized users can read project tags" on public.project_tags
for select to authenticated, anon
using (public.can_access_project(organization_id, project_id));

drop policy if exists "members can read project contacts" on public.project_contacts;
create policy "authorized users can read project contacts" on public.project_contacts
for select to authenticated, anon
using (public.can_access_project(organization_id, project_id));

drop policy if exists "members can read project aliases" on public.project_import_aliases;
create policy "authorized users can read project aliases" on public.project_import_aliases
for select to authenticated, anon
using (public.can_access_project(organization_id, project_id));

drop policy if exists "members can read project performance" on public.project_performance_daily;
create policy "authorized users can read project performance" on public.project_performance_daily
for select to authenticated, anon
using (public.can_access_project(organization_id, project_id));

grant select, insert, update, delete on public.project_memberships to authenticated, anon;
grant all on public.project_memberships to service_role;
revoke all on function public.is_project_expert(uuid) from public;
revoke all on function public.can_access_project(uuid, uuid) from public;
revoke all on function public.can_administer_projects(uuid) from public;
revoke all on function public.get_current_expert_project_ids(uuid) from public;
grant execute on function public.is_project_expert(uuid) to authenticated, anon, service_role;
grant execute on function public.can_access_project(uuid, uuid) to authenticated, anon, service_role;
grant execute on function public.can_administer_projects(uuid) to authenticated, anon, service_role;
grant execute on function public.get_current_expert_project_ids(uuid) to authenticated, anon, service_role;
