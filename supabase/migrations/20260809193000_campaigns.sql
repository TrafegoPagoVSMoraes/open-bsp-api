-- Durable WhatsApp campaigns. The database owns recipient deduplication,
-- suppression and the immutable send ceiling; Edge Functions only orchestrate.

create table public.campaigns (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  organization_address text not null,
  name text not null,
  status text not null default 'draft'
    check (status in ('draft', 'running', 'cancel_requested', 'cancelled', 'completed', 'failed')),
  template_id text not null,
  template_name text not null,
  template_language text not null,
  template_category text not null check (template_category = 'UTILITY'),
  template_status text not null check (template_status = 'APPROVED'),
  template_snapshot jsonb not null check (jsonb_typeof(template_snapshot) = 'object'),
  template_payload jsonb not null check (jsonb_typeof(template_payload) = 'object'),
  tracking_project_id uuid references public.tracking_projects(id) on delete set null,
  tracking_destination_url text,
  total_cap integer not null check (total_cap between 1 and 100000),
  is_test boolean not null default false,
  started_at timestamptz,
  cancel_requested_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint campaigns_org_address_fkey foreign key (organization_id, organization_address)
    references public.organizations_addresses(organization_id, address),
  constraint campaigns_tracking_destination check (
    tracking_destination_url is null or tracking_destination_url ~ '^https://'
  )
);

create table public.campaign_recipients (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  phone text not null check (phone ~ '^[1-9][0-9]{9,14}$'),
  display_name text,
  variables jsonb not null default '{}'::jsonb check (jsonb_typeof(variables) = 'object'),
  status text not null default 'queued'
    check (status in ('queued', 'processing', 'submitted', 'suppressed', 'failed', 'ambiguous', 'cancelled')),
  message_id uuid not null default gen_random_uuid(),
  tracking_link_id uuid references public.tracking_links(id) on delete set null,
  error_code text,
  claimed_at timestamptz,
  submitted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (campaign_id, phone),
  unique (message_id)
);

create index campaigns_org_created_idx
  on public.campaigns (organization_id, created_at desc);
create index campaign_recipients_claim_idx
  on public.campaign_recipients (campaign_id, status, created_at)
  where status = 'queued';
create index campaign_recipients_org_phone_idx
  on public.campaign_recipients (organization_id, phone);

alter table public.campaigns enable row level security;
alter table public.campaign_recipients enable row level security;

create policy "members can read their org campaigns"
on public.campaigns for select to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('member')));

create policy "members can read their org campaign recipients"
on public.campaign_recipients for select to authenticated, anon
using (organization_id in (select public.get_authorized_orgs('member')));

grant select on public.campaigns, public.campaign_recipients to authenticated, anon;
grant all on public.campaigns, public.campaign_recipients to service_role;

create function public.protect_campaign_ceiling() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and new.total_cap <> old.total_cap then
    raise exception using errcode = 'P0001', message = 'Campaign total_cap is immutable';
  end if;
  return new;
end;
$$;

create trigger protect_campaign_ceiling
before update on public.campaigns for each row execute function public.protect_campaign_ceiling();

create function public.validate_campaign_recipient() returns trigger
language plpgsql security definer set search_path = '' as $$
declare _campaign public.campaigns%rowtype;
begin
  select * into _campaign from public.campaigns where id = new.campaign_id;
  if not found or _campaign.organization_id <> new.organization_id then
    raise exception using errcode = 'P0001', message = 'Invalid campaign organization';
  end if;
  if _campaign.status <> 'draft' then
    raise exception using errcode = 'P0001', message = 'Recipients are immutable after campaign start';
  end if;
  return new;
end;
$$;

create trigger validate_campaign_recipient
before insert on public.campaign_recipients for each row
execute function public.validate_campaign_recipient();

-- One lock and one set-based insert per import avoids count-on-every-row.
create function public.insert_campaign_recipients(
  p_campaign_id uuid,
  p_organization_id uuid,
  p_recipients jsonb
) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  _campaign public.campaigns%rowtype;
  _input_count integer;
  _existing_count integer;
  _inserted integer;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'Campaign recipient insert denied';
  end if;
  if p_recipients is null or jsonb_typeof(p_recipients) <> 'array' then
    raise exception using errcode = '22023', message = 'Invalid campaign recipients';
  end if;
  select * into _campaign from public.campaigns
  where id = p_campaign_id and organization_id = p_organization_id
  for update;
  if not found or _campaign.status <> 'draft' then
    raise exception using errcode = 'P0001', message = 'Campaign is not mutable';
  end if;
  _input_count := jsonb_array_length(p_recipients);
  select count(*) into _existing_count
  from public.campaign_recipients where campaign_id = p_campaign_id;
  if _input_count < 1 or _existing_count + _input_count > _campaign.total_cap then
    raise exception using errcode = 'P0001', message = 'Campaign recipient ceiling reached';
  end if;
  insert into public.campaign_recipients (
    campaign_id, organization_id, phone, display_name, variables
  )
  select p_campaign_id, p_organization_id, item.phone, item.display_name,
    coalesce(item.variables, '{}'::jsonb)
  from jsonb_to_recordset(p_recipients) as item(
    phone text, display_name text, variables jsonb
  );
  get diagnostics _inserted = row_count;
  return _inserted;
end;
$$;

revoke all on function public.insert_campaign_recipients(uuid, uuid, jsonb)
from public, anon, authenticated;
grant execute on function public.insert_campaign_recipients(uuid, uuid, jsonb)
to service_role;

-- SQL aggregation avoids PostgREST row limits. States are mutually exclusive;
-- "submitted" only means enqueued, never accepted by Meta.
create function public.get_campaign_summaries(
  p_organization_id uuid,
  p_campaign_id uuid default null
) returns table (
  id uuid, name text, status text, total bigint, pending bigint,
  accepted bigint, sent bigint, delivered bigint, read bigint,
  failed bigint, skipped bigint, created_at timestamptz
)
language sql stable security definer set search_path = '' as $$
  with classified as (
    select c.id, c.name, c.status, c.total_cap, c.created_at, r.id as recipient_id,
      case
        when r.status in ('suppressed', 'cancelled') then 'skipped'
        when coalesce(m.status, '{}'::jsonb) ? 'read' then 'read'
        when coalesce(m.status, '{}'::jsonb) ? 'delivered' then 'delivered'
        when coalesce(m.status, '{}'::jsonb) ? 'sent' then 'sent'
        when coalesce(m.status, '{}'::jsonb) ? 'accepted' or m.external_id is not null then 'accepted'
        when r.status in ('failed', 'ambiguous') or coalesce(m.status, '{}'::jsonb) ? 'failed' then 'failed'
        else 'pending'
      end as delivery_state
    from public.campaigns c
    left join public.campaign_recipients r on r.campaign_id = c.id
    left join public.messages m on m.id = r.message_id
    where c.organization_id = p_organization_id
      and (p_campaign_id is null or c.id = p_campaign_id)
  )
  select id, name, status, max(total_cap)::bigint,
    count(recipient_id) filter (where delivery_state = 'pending'),
    count(recipient_id) filter (where delivery_state = 'accepted'),
    count(recipient_id) filter (where delivery_state = 'sent'),
    count(recipient_id) filter (where delivery_state = 'delivered'),
    count(recipient_id) filter (where delivery_state = 'read'),
    count(recipient_id) filter (where delivery_state = 'failed'),
    count(recipient_id) filter (where delivery_state = 'skipped'),
    max(created_at)
  from classified
  group by id, name, status
  order by max(created_at) desc
  limit 100;
$$;

revoke all on function public.get_campaign_summaries(uuid, uuid)
from public, anon, authenticated;
grant execute on function public.get_campaign_summaries(uuid, uuid) to service_role;

create function public.claim_campaign_recipient_batch(p_limit integer default 25)
returns setof public.campaign_recipients
language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'Campaign worker access denied';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception using errcode = '22023', message = 'Invalid campaign batch size';
  end if;

  -- Suppression is checked again at claim time so an opt-out received after
  -- import but before dispatch is still authoritative.
  update public.campaign_recipients r
  set status = 'suppressed', error_code = 'contact_opt_out', updated_at = now()
  from public.campaigns c, public.contact_opt_outs o
  where r.campaign_id = c.id and c.status = 'running' and r.status = 'queued'
    and o.organization_id = c.organization_id
    and o.service = 'whatsapp'::public.service
    and o.organization_address = c.organization_address
    and o.contact_address = r.phone;

  return query
  with selected as (
    select r.id
    from public.campaign_recipients r
    join public.campaigns c on c.id = r.campaign_id
    where c.status = 'running' and r.status = 'queued'
    order by c.created_at, r.created_at, r.id
    for update of r skip locked
    limit p_limit
  )
  update public.campaign_recipients r
  set status = 'processing', claimed_at = now(), updated_at = now()
  from selected
  where r.id = selected.id
  returning r.*;
end;
$$;

revoke all on function public.claim_campaign_recipient_batch(integer)
from public, anon, authenticated;
grant execute on function public.claim_campaign_recipient_batch(integer) to service_role;

create function public.finish_campaigns() returns void
language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'Campaign worker access denied';
  end if;
  update public.campaign_recipients r set status = 'cancelled', updated_at = now()
  from public.campaigns c
  where r.campaign_id = c.id and c.status = 'cancel_requested' and r.status = 'queued';

  update public.campaigns c
  set status = case when c.status = 'cancel_requested' then 'cancelled' else 'completed' end,
      completed_at = now(), updated_at = now()
  where c.status in ('running', 'cancel_requested')
    and not exists (
      select 1 from public.campaign_recipients r
      where r.campaign_id = c.id and r.status in ('queued', 'processing')
    );
end;
$$;

revoke all on function public.finish_campaigns() from public, anon, authenticated;
grant execute on function public.finish_campaigns() to service_role;

-- A claimed row is never automatically returned to queued. If a worker dies
-- after claiming, the outcome is explicitly ambiguous and requires review.
create function public.mark_stale_campaign_claims() returns integer
language plpgsql security definer set search_path = '' as $$
declare _count integer;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'Campaign worker access denied';
  end if;
  update public.campaign_recipients
  set status = 'ambiguous', error_code = 'worker_interrupted', updated_at = now()
  where status = 'processing' and claimed_at < now() - interval '10 minutes';
  get diagnostics _count = row_count;
  return _count;
end;
$$;

revoke all on function public.mark_stale_campaign_claims() from public, anon, authenticated;
grant execute on function public.mark_stale_campaign_claims() to service_role;

select cron.schedule(
  'process-whatsapp-campaigns',
  '* * * * *',
  $$select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'edge_functions_url') || '/campaign-worker',
    headers := jsonb_build_object(
      'content-type', 'application/json',
      'authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'edge_functions_token')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 5000
  );$$
);

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'campaigns'
  ) then
    alter publication supabase_realtime add table public.campaigns;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'campaign_recipients'
  ) then
    alter publication supabase_realtime add table public.campaign_recipients;
  end if;
end;
$$;
