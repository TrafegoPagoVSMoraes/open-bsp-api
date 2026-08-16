-- Idempotently classify the existing VS Treinamentos/Sun Ju history. Existing
-- non-null project associations are never overwritten.
do $$
declare
  v_organization_id uuid;
  v_organization_name text;
  v_project_id uuid;
  v_agent_id uuid;
  v_match_count integer;
  v_foreign_messages_before bigint;
  v_foreign_campaigns_before bigint;
begin
  select count(distinct oa.organization_id),
    (array_agg(distinct oa.organization_id))[1]
    into v_match_count, v_organization_id
  from public.organizations_addresses oa
  where oa.service = 'whatsapp'::public.service
    and oa.address = '909864832221280';

  if v_match_count = 0 then
    raise notice 'Sun Ju bootstrap skipped: WhatsApp organization not present';
    return;
  end if;
  if v_match_count <> 1 or v_organization_id is null then
    raise exception 'Sun Ju bootstrap requires exactly one matching WhatsApp organization, found %', v_match_count;
  end if;

  select o.name into v_organization_name
  from public.organizations o where o.id = v_organization_id;

  if exists (
    select 1 from public.projects p
    where p.organization_id = v_organization_id
      and (p.slug = 'lc-ago-26-sun-ju' or p.name = '[LC-AGO-26 SUN-JU]')
      and (p.slug <> 'lc-ago-26-sun-ju' or p.name <> '[LC-AGO-26 SUN-JU]')
  ) then
    raise exception 'Sun Ju project name/slug collides with an existing project';
  end if;

  insert into public.projects (organization_id, name, slug, description, extra)
  values (
    v_organization_id,
    '[LC-AGO-26 SUN-JU]',
    'lc-ago-26-sun-ju',
    'Projeto legado da expert Sun Ju',
    jsonb_build_object('bootstrap_key', 'legacy_sunju_bootstrap')
  )
  on conflict (organization_id, slug) do nothing;

  select p.id into strict v_project_id
  from public.projects p
  where p.organization_id = v_organization_id and p.slug = 'lc-ago-26-sun-ju';

  select count(*), (array_agg(a.id))[1] into v_match_count, v_agent_id
  from public.agents a
  where a.organization_id = v_organization_id
    and (
      a.extra->>'bootstrap_key' = 'legacy_sunju_bootstrap'
      or (lower(btrim(a.name)) = 'sun ju' and a.extra->>'account_type' = 'expert')
    );

  if v_match_count > 1 then
    raise exception 'Sun Ju expert bootstrap matched more than one agent';
  end if;

  if v_agent_id is null then
    insert into public.agents (organization_id, user_id, name, ai, extra)
    values (
      v_organization_id,
      null,
      'Sun Ju',
      false,
      jsonb_build_object(
        'role', 'member',
        'account_type', 'expert',
        'bootstrap_key', 'legacy_sunju_bootstrap',
        'invitation', jsonb_build_object(
          'organization_name', coalesce(v_organization_name, ''),
          'email', null,
          'status', 'draft'
        )
      )
    ) returning id into v_agent_id;
  elsif exists (
    select 1 from public.agents a
    where a.id = v_agent_id and (
      a.ai is distinct from false
      or a.extra->>'account_type' is distinct from 'expert'
    )
  ) then
    raise exception 'Existing Sun Ju bootstrap agent has an incompatible identity';
  end if;

  insert into public.project_memberships (organization_id, project_id, agent_id, role)
  values (v_organization_id, v_project_id, v_agent_id, 'expert')
  on conflict do nothing;

  select count(*) into v_foreign_messages_before
  from public.messages
  where organization_id = v_organization_id
    and project_id is not null and project_id <> v_project_id;

  select count(*) into v_foreign_campaigns_before
  from public.campaigns
  where organization_id = v_organization_id
    and project_id is not null and project_id <> v_project_id;

  insert into public.project_contacts (organization_id, project_id, contact_id, source)
  select v_organization_id, v_project_id, contact.id, 'system'
  from public.contacts contact
  where contact.organization_id = v_organization_id
    and not exists (
      select 1
      from public.contact_tags contact_tag
      join public.tags tag
        on tag.organization_id = contact_tag.organization_id
       and tag.id = contact_tag.tag_id
      where contact_tag.organization_id = contact.organization_id
        and contact_tag.contact_id = contact.id
        and (lower(btrim(tag.name)) in ('test', 'teste')
          or lower(btrim(tag.slug)) in ('test', 'teste'))
    )
  on conflict do nothing;

  insert into public.project_contact_origins (
    organization_id, project_id, contact_id, source, source_key
  )
  select v_organization_id, v_project_id, contact.id, 'system', 'legacy_sunju_bootstrap'
  from public.contacts contact
  where contact.organization_id = v_organization_id
    and not exists (
      select 1
      from public.contact_tags contact_tag
      join public.tags tag
        on tag.organization_id = contact_tag.organization_id
       and tag.id = contact_tag.tag_id
      where contact_tag.organization_id = contact.organization_id
        and contact_tag.contact_id = contact.id
        and (lower(btrim(tag.name)) in ('test', 'teste')
          or lower(btrim(tag.slug)) in ('test', 'teste'))
    )
  on conflict do nothing;

  delete from public.project_contact_origins origin
  where origin.organization_id = v_organization_id
    and origin.project_id = v_project_id
    and origin.source = 'system'
    and origin.source_key = ''
    and exists (
      select 1 from public.project_contact_origins keyed
      where keyed.organization_id = origin.organization_id
        and keyed.project_id = origin.project_id
        and keyed.contact_id = origin.contact_id
        and keyed.source = 'system'
        and keyed.source_key = 'legacy_sunju_bootstrap'
    );

  insert into public.project_conversations (
    organization_id, project_id, conversation_id, source
  )
  select v_organization_id, v_project_id, conversation.id, 'manual'
  from public.conversations conversation
  where conversation.organization_id = v_organization_id
    and not exists (
      select 1
      from public.contacts_addresses address
      join public.contact_tags contact_tag
        on contact_tag.organization_id = address.organization_id
       and contact_tag.contact_id = address.contact_id
      join public.tags tag
        on tag.organization_id = contact_tag.organization_id
       and tag.id = contact_tag.tag_id
      where address.organization_id = conversation.organization_id
        and address.service = conversation.service
        and address.address = conversation.contact_address
        and (lower(btrim(tag.name)) in ('test', 'teste')
          or lower(btrim(tag.slug)) in ('test', 'teste'))
    )
  on conflict do nothing;

  update public.messages message
  set project_id = v_project_id
  where message.organization_id = v_organization_id
    and message.project_id is null
    and exists (
      select 1 from public.project_conversations project_conversation
      where project_conversation.organization_id = v_organization_id
        and project_conversation.project_id = v_project_id
        and project_conversation.conversation_id = message.conversation_id
    );

  update public.campaigns campaign
  set project_id = v_project_id
  where campaign.organization_id = v_organization_id
    and campaign.project_id is null
    and campaign.is_test = false;

  if (select count(*) from public.projects
      where organization_id = v_organization_id
        and slug = 'lc-ago-26-sun-ju'
        and name = '[LC-AGO-26 SUN-JU]') <> 1 then
    raise exception 'Sun Ju bootstrap project assertion failed';
  end if;

  if (select count(*) from public.agents
      where organization_id = v_organization_id
        and id = v_agent_id
        and ai = false
        and extra->>'account_type' = 'expert') <> 1 then
    raise exception 'Sun Ju bootstrap expert assertion failed';
  end if;

  if (select count(*) from public.project_memberships
      where organization_id = v_organization_id
        and project_id = v_project_id and agent_id = v_agent_id) <> 1 then
    raise exception 'Sun Ju bootstrap membership assertion failed';
  end if;

  if exists (
    select 1
    from public.project_contacts project_contact
    join public.contact_tags contact_tag
      on contact_tag.organization_id = project_contact.organization_id
     and contact_tag.contact_id = project_contact.contact_id
    join public.tags tag
      on tag.organization_id = contact_tag.organization_id
     and tag.id = contact_tag.tag_id
    where project_contact.organization_id = v_organization_id
      and project_contact.project_id = v_project_id
      and (lower(btrim(tag.name)) in ('test', 'teste')
        or lower(btrim(tag.slug)) in ('test', 'teste'))
  ) then
    raise exception 'Sun Ju bootstrap included a test contact';
  end if;

  if exists (
    select 1
    from public.project_conversations project_conversation
    join public.conversations conversation
      on conversation.id = project_conversation.conversation_id
    join public.contacts_addresses address
      on address.organization_id = conversation.organization_id
     and address.service = conversation.service
     and address.address = conversation.contact_address
    join public.contact_tags contact_tag
      on contact_tag.organization_id = address.organization_id
     and contact_tag.contact_id = address.contact_id
    join public.tags tag
      on tag.organization_id = contact_tag.organization_id
     and tag.id = contact_tag.tag_id
    where project_conversation.organization_id = v_organization_id
      and project_conversation.project_id = v_project_id
      and (lower(btrim(tag.name)) in ('test', 'teste')
        or lower(btrim(tag.slug)) in ('test', 'teste'))
  ) then
    raise exception 'Sun Ju bootstrap included a test conversation';
  end if;

  if exists (
    select 1 from public.campaigns
    where organization_id = v_organization_id
      and project_id = v_project_id and is_test = true
  ) then
    raise exception 'Sun Ju bootstrap included a test campaign';
  end if;

  if (select count(*) from public.messages
      where organization_id = v_organization_id
        and project_id is not null and project_id <> v_project_id)
      <> v_foreign_messages_before then
    raise exception 'Sun Ju bootstrap overwrote an existing message project';
  end if;

  if (select count(*) from public.campaigns
      where organization_id = v_organization_id
        and project_id is not null and project_id <> v_project_id)
      <> v_foreign_campaigns_before then
    raise exception 'Sun Ju bootstrap overwrote an existing campaign project';
  end if;
end;
$$;
