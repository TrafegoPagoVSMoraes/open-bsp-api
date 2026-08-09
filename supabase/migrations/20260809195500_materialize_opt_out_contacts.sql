-- Opt-out is both a delivery prohibition and a CRM classification. Historical
-- suppressions may predate a contact link, so materialize the minimal contact
-- required to make the reserved Opt-out tag visible and queryable.

create or replace function public.sync_opt_out_tag_from_consent() returns trigger
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
      target_organization_id,
      target_service,
      target_contact_address,
      'active',
      '{"source":"opt_out"}'::jsonb
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
        jsonb_build_object(
          'source', 'opt_out',
          'contact_address', target_contact_address
        )
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
    target_organization_id,
    linked_contact_id
  );

  return null;
end;
$$;

revoke all on function public.sync_opt_out_tag_from_consent()
from public, authenticated, anon;

-- Re-fire the materialization path for existing suppressions. The trigger is
-- idempotent: existing links and tag memberships are preserved.
do $$
declare
  consent public.contact_opt_outs%rowtype;
  linked_contact_id uuid;
  created_contact_id uuid;
begin
  for consent in
    select * from public.contact_opt_outs
    order by organization_id, service, contact_address
  loop
    insert into public.contacts_addresses (
      organization_id, service, address, status, extra
    ) values (
      consent.organization_id,
      consent.service,
      consent.contact_address,
      'active',
      '{"source":"opt_out_backfill"}'::jsonb
    ) on conflict (organization_id, service, address) do nothing;

    select ca.contact_id into linked_contact_id
    from public.contacts_addresses ca
    where ca.organization_id = consent.organization_id
      and ca.service = consent.service
      and ca.address = consent.contact_address
    for update;

    if linked_contact_id is null then
      insert into public.contacts (organization_id, name, extra)
      values (
        consent.organization_id,
        null,
        jsonb_build_object(
          'source', 'opt_out_backfill',
          'contact_address', consent.contact_address
        )
      ) returning id into created_contact_id;

      update public.contacts_addresses
      set contact_id = created_contact_id
      where organization_id = consent.organization_id
        and service = consent.service
        and address = consent.contact_address
        and contact_id is null
      returning contact_id into linked_contact_id;

      if linked_contact_id is null then
        delete from public.contacts where id = created_contact_id;
        select ca.contact_id into linked_contact_id
        from public.contacts_addresses ca
        where ca.organization_id = consent.organization_id
          and ca.service = consent.service
          and ca.address = consent.contact_address;
      end if;
    end if;

    perform public.sync_contact_opt_out_tag(
      consent.organization_id,
      linked_contact_id
    );
  end loop;
end;
$$;
