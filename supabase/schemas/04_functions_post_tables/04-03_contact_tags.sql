create function public.ensure_system_tag(
  target_organization_id uuid,
  target_system_key text,
  target_name text,
  target_color text
) returns uuid
language plpgsql
security definer
set search_path to ''
as $$
declare
  result_id uuid;
begin
  insert into public.tags (
    organization_id, name, slug, color, is_system, system_key
  ) values (
    target_organization_id,
    target_name,
    replace(target_system_key, '_', '-'),
    target_color,
    true,
    target_system_key
  )
  on conflict (organization_id, system_key) where system_key is not null
  do update set name = excluded.name, color = excluded.color
  returning id into result_id;

  return result_id;
end;
$$;

create function public.sync_contact_opt_out_tag(
  target_organization_id uuid,
  target_contact_id uuid
) returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  opt_out_tag_id uuid;
  is_opted_out boolean;
begin
  if target_contact_id is null then return; end if;

  select exists (
    select 1
    from public.contacts_addresses ca
    join public.contact_opt_outs o
      on o.organization_id = ca.organization_id
      and o.service = ca.service
      and o.contact_address = ca.address
    where ca.organization_id = target_organization_id
      and ca.contact_id = target_contact_id
  ) into is_opted_out;

  select t.id into opt_out_tag_id
  from public.tags t
  where t.organization_id = target_organization_id
    and t.system_key = 'opt_out';

  if is_opted_out then
    if opt_out_tag_id is null then
      opt_out_tag_id := public.ensure_system_tag(
        target_organization_id, 'opt_out', 'Opt-out', '#dc2626'
      );
    end if;

    insert into public.contact_tags (
      organization_id, contact_id, tag_id, source
    ) values (
      target_organization_id, target_contact_id, opt_out_tag_id, 'system'
    ) on conflict do nothing;
  elsif opt_out_tag_id is not null then
    delete from public.contact_tags ct
    where ct.organization_id = target_organization_id
      and ct.contact_id = target_contact_id
      and ct.tag_id = opt_out_tag_id;
  end if;
end;
$$;

create function public.sync_opt_out_tag_from_consent() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  linked_contact_id uuid;
  created_contact_id uuid;
  target_organization_id uuid;
  target_service public.service;
  target_contact_address text;
begin
  if tg_op = 'INSERT' then
    target_organization_id := new.organization_id;
    target_service := new.service;
    target_contact_address := new.contact_address;

    insert into public.contacts_addresses (
      organization_id, service, address, status, extra
    ) values (
      target_organization_id, target_service, target_contact_address,
      'active', '{"source":"opt_out"}'::jsonb
    ) on conflict (organization_id, service, address) do nothing;

    select ca.contact_id into linked_contact_id
    from public.contacts_addresses ca
    where ca.organization_id = target_organization_id
      and ca.service = target_service
      and ca.address = target_contact_address
    for update;

    if linked_contact_id is null then
      insert into public.contacts (organization_id, name, extra)
      values (
        target_organization_id,
        null,
        jsonb_build_object('source', 'opt_out', 'contact_address', target_contact_address)
      ) returning id into created_contact_id;

      update public.contacts_addresses
      set contact_id = created_contact_id
      where organization_id = target_organization_id
        and service = target_service
        and address = target_contact_address
        and contact_id is null
      returning contact_id into linked_contact_id;

      if linked_contact_id is null then
        delete from public.contacts where id = created_contact_id;
        select ca.contact_id into linked_contact_id
        from public.contacts_addresses ca
        where ca.organization_id = target_organization_id
          and ca.service = target_service
          and ca.address = target_contact_address;
      end if;
    end if;
  else
    target_organization_id := old.organization_id;
    target_service := old.service;
    target_contact_address := old.contact_address;

    select ca.contact_id into linked_contact_id
    from public.contacts_addresses ca
    where ca.organization_id = target_organization_id
      and ca.service = target_service
      and ca.address = target_contact_address;
  end if;

  perform public.sync_contact_opt_out_tag(
    target_organization_id, linked_contact_id
  );
  return null;
end;
$$;

create trigger sync_opt_out_tag_from_consent
after insert or delete on public.contact_opt_outs
for each row execute function public.sync_opt_out_tag_from_consent();

create function public.sync_opt_out_tag_from_contact_address() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if tg_op = 'UPDATE' and old.contact_id is not null then
    perform public.sync_contact_opt_out_tag(old.organization_id, old.contact_id);
  end if;
  if new.contact_id is not null then
    perform public.sync_contact_opt_out_tag(new.organization_id, new.contact_id);
  end if;
  return null;
end;
$$;

create trigger sync_opt_out_tag_from_contact_address
after update of contact_id on public.contacts_addresses
for each row
when (old.contact_id is distinct from new.contact_id)
execute function public.sync_opt_out_tag_from_contact_address();

create trigger sync_opt_out_tag_from_contact_address_insert
after insert on public.contacts_addresses
for each row
when (new.contact_id is not null)
execute function public.sync_opt_out_tag_from_contact_address();

revoke all on function public.ensure_system_tag(uuid, text, text, text)
from public, authenticated, anon;
revoke all on function public.sync_contact_opt_out_tag(uuid, uuid)
from public, authenticated, anon;
revoke all on function public.sync_opt_out_tag_from_consent()
from public, authenticated, anon;
revoke all on function public.sync_opt_out_tag_from_contact_address()
from public, authenticated, anon;

create function public.get_tag_report(p_organization_id uuid)
returns table (
  tag_id uuid,
  tag_name text,
  tag_color text,
  contact_count bigint,
  opt_out_count bigint
)
language plpgsql
security invoker
set search_path to ''
as $$
begin
  if not exists (
    select 1
    from public.get_authorized_orgs('member') as authorized(organization_id)
    where authorized.organization_id = p_organization_id
  ) then
    raise exception using
      errcode = '42501',
      message = 'Not authorized to read tag report for this organization';
  end if;

  return query
  select
    t.id,
    t.name,
    t.color,
    count(distinct ct.contact_id),
    count(distinct ct.contact_id) filter (
      where exists (
        select 1
        from public.contacts_addresses ca
        join public.contact_opt_outs o
          on o.organization_id = ca.organization_id
          and o.service = ca.service
          and o.contact_address = ca.address
        where ca.organization_id = ct.organization_id
          and ca.contact_id = ct.contact_id
      )
    )
  from public.tags t
  left join public.contact_tags ct
    on ct.organization_id = t.organization_id
    and ct.tag_id = t.id
  where t.organization_id = p_organization_id
  group by t.id, t.name, t.color
  order by count(distinct ct.contact_id) desc, t.name;
end;
$$;

revoke all on function public.get_tag_report(uuid) from public;
grant execute on function public.get_tag_report(uuid) to authenticated, anon;
