-- A tag audience can include any selected tag and exclude any selected tag.
-- Exclusions are evaluated again at execution time for scheduled campaigns.

alter table public.campaigns
  add column audience_excluded_tag_ids uuid[] not null default '{}';

create or replace function public.materialize_due_tag_campaigns() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  campaign_row public.campaigns%rowtype;
  recipient_count integer;
  materialized integer := 0;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'Campaign worker access denied';
  end if;

  for campaign_row in
    select * from public.campaigns
    where status = 'scheduled' and audience_type = 'tags'
      and scheduled_at <= now()
    order by scheduled_at, id
    for update skip locked
  loop
    delete from public.campaign_recipients
    where campaign_id = campaign_row.id and status = 'queued';

    insert into public.campaign_recipients (
      campaign_id, organization_id, phone, display_name, variables
    )
    select campaign_row.id, campaign_row.organization_id, audience.phone,
      audience.display_name, audience.variables
    from (
      select distinct on (address.address)
        address.address as phone,
        contact.name as display_name,
        public.resolve_campaign_contact_variables(
          campaign_row.variable_mapping,
          contact.name
        ) as variables
      from public.contacts contact
      join public.contacts_addresses address
        on address.organization_id = contact.organization_id
       and address.contact_id = contact.id
       and address.service = 'whatsapp'::public.service
       and address.status = 'active'
      where contact.organization_id = campaign_row.organization_id
        and (
          cardinality(campaign_row.audience_tag_ids) = 0
          or exists (
            select 1 from public.contact_tags included
            where included.organization_id = contact.organization_id
              and included.contact_id = contact.id
              and included.tag_id = any(campaign_row.audience_tag_ids)
          )
        )
        and not exists (
          select 1 from public.contact_tags excluded
          where excluded.organization_id = contact.organization_id
            and excluded.contact_id = contact.id
            and excluded.tag_id = any(campaign_row.audience_excluded_tag_ids)
        )
        and address.address ~ '^[1-9][0-9]{9,14}$'
        and not exists (
          select 1 from public.contact_opt_outs optout
          where optout.organization_id = campaign_row.organization_id
            and optout.service = 'whatsapp'::public.service
            and optout.organization_address = campaign_row.organization_address
            and optout.contact_address = address.address
        )
      order by address.address, contact.id
    ) audience
    where audience.variables is not null;

    get diagnostics recipient_count = row_count;
    if recipient_count = 0 then
      update public.campaigns set
        status = 'failed', completed_at = now(), updated_at = now(),
        audience_materialized_at = now()
      where id = campaign_row.id;
    else
      update public.campaigns set
        total_cap = recipient_count, status = 'running', started_at = now(),
        updated_at = now(), audience_materialized_at = now()
      where id = campaign_row.id;
    end if;
    materialized := materialized + 1;
  end loop;

  return materialized;
end;
$$;
