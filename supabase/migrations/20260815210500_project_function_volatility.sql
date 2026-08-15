-- Re-emit project authorization helpers with volatility matching their
-- authorization/session lookups. This is additive and safe for databases that
-- already applied an earlier local draft of the project migrations.

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
