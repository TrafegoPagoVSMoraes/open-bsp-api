begin;

do $$
declare
  _organization_id uuid := '6df7a183-66c6-45e5-993d-2d2d34f46d31';
  _campaign_id uuid;
  _contact_id uuid;
  _claimed integer;
  _inserted integer;
begin
  insert into public.organizations (id, name)
  values (_organization_id, 'Campaign integration test');

  insert into public.organizations_addresses (
    organization_id, service, address, status
  ) values (
    _organization_id, 'whatsapp', '5516999999999', 'connected'
  );

  insert into public.contacts (organization_id, name, email)
  values (_organization_id, 'mARIA DA silVA', ' MARIA@EXAMPLE.COM ')
  returning id into _contact_id;

  if (select name from public.contacts where id = _contact_id) <> 'Maria da Silva'
    or (select email from public.contacts where id = _contact_id) <> 'maria@example.com'
  then
    raise exception 'contact normalization failed';
  end if;

  insert into public.contacts_addresses (
    organization_id, service, address, status, contact_id
  ) values (
    _organization_id, 'whatsapp', '5516988888888', 'active', _contact_id
  );

  insert into public.contacts_addresses (
    organization_id, service, address, status
  ) values (
    _organization_id, 'whatsapp', '5516966666666', 'active'
  );

  insert into public.contact_opt_outs (
    organization_id, service, organization_address, contact_address
  ) values (
    _organization_id, 'whatsapp', '5516999999999', '5516988888888'
  );

  if not exists (
    select 1
    from public.contact_tags ct
    join public.tags t on t.id = ct.tag_id
    where ct.organization_id = _organization_id
      and ct.contact_id = _contact_id
      and t.system_key = 'opt_out'
  ) then
    raise exception 'opt-out system tag was not assigned';
  end if;

  insert into public.contact_opt_outs (
    organization_id, service, organization_address, contact_address
  ) values (
    _organization_id, 'whatsapp', '5516999999999', '5516966666666'
  );

  if not exists (
    select 1
    from public.contacts_addresses ca
    join public.contact_tags ct
      on ct.organization_id = ca.organization_id
      and ct.contact_id = ca.contact_id
    join public.tags t on t.id = ct.tag_id
    where ca.organization_id = _organization_id
      and ca.service = 'whatsapp'
      and ca.address = '5516966666666'
      and ca.contact_id is not null
      and t.system_key = 'opt_out'
  ) then
    raise exception 'unlinked opt-out was not materialized and tagged';
  end if;

  insert into public.campaigns (
    organization_id, organization_address, name, template_id,
    template_name, template_language, template_category, template_status,
    template_snapshot, template_payload, total_cap
  ) values (
    _organization_id, '5516999999999', 'Integration campaign', 'template-id',
    'utility_template', 'pt_BR', 'UTILITY', 'APPROVED',
    '{}'::jsonb, '{}'::jsonb, 2
  ) returning id into _campaign_id;

  perform set_config('request.jwt.claim.role', 'service_role', true);

  select public.insert_campaign_recipients(
    _campaign_id,
    _organization_id,
    '[{"phone":"5516988888888","display_name":"Maria","variables":{}},
      {"phone":"5516977777777","display_name":"Joao","variables":{}}]'::jsonb
  ) into _inserted;

  if _inserted <> 2 then
    raise exception 'recipient batch insert failed';
  end if;

  begin
    update public.campaigns set total_cap = 3 where id = _campaign_id;
    raise exception 'campaign total cap was mutable';
  exception when sqlstate 'P0001' then
    null;
  end;

  update public.campaigns
  set status = 'running', started_at = now()
  where id = _campaign_id;

  select count(*) into _claimed
  from public.claim_campaign_recipient_batch(10);

  if _claimed <> 1 then
    raise exception 'claim did not suppress the opted-out recipient';
  end if;

  if (select status from public.campaign_recipients
      where campaign_id = _campaign_id and phone = '5516988888888') <> 'suppressed'
    or (select status from public.campaign_recipients
        where campaign_id = _campaign_id and phone = '5516977777777') <> 'processing'
  then
    raise exception 'recipient states are inconsistent after claim';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.insert_campaign_recipients(uuid,uuid,jsonb)',
    'EXECUTE'
  ) then
    raise exception 'authenticated role can execute internal campaign insert';
  end if;
end;
$$;

rollback;
