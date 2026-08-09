alter table public.tags enable row level security;
alter table public.contact_tags enable row level security;

create policy "members can read their orgs tags"
on public.tags for select to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('member')));

create policy "members can create non-system tags"
on public.tags for insert to authenticated, anon
with check (
  not is_system
  and system_key is null
  and organization_id in (select public.get_authorized_orgs('member'))
);

create policy "members can update non-system tags"
on public.tags for update to authenticated, anon
using (
  not is_system
  and organization_id in (select public.get_authorized_orgs('member'))
)
with check (
  not is_system
  and system_key is null
  and organization_id in (select public.get_authorized_orgs('member'))
);

create policy "members can delete non-system tags"
on public.tags for delete to authenticated, anon
using (
  not is_system
  and organization_id in (select public.get_authorized_orgs('member'))
);

create policy "members can read their orgs contact tags"
on public.contact_tags for select to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('member')));

create policy "members can create non-system contact tags"
on public.contact_tags for insert to authenticated, anon
with check (
  organization_id in (select public.get_authorized_orgs('member'))
  and exists (
    select 1 from public.tags t
    where t.organization_id = contact_tags.organization_id
      and t.id = contact_tags.tag_id
      and not t.is_system
  )
);

create policy "members can delete non-system contact tags"
on public.contact_tags for delete to authenticated, anon
using (
  organization_id in (select public.get_authorized_orgs('member'))
  and exists (
    select 1 from public.tags t
    where t.organization_id = contact_tags.organization_id
      and t.id = contact_tags.tag_id
      and not t.is_system
  )
);

grant select, insert, update, delete on table public.tags to authenticated, anon;
grant select, insert, delete on table public.contact_tags to authenticated, anon;
grant all on table public.tags, public.contact_tags to service_role;

