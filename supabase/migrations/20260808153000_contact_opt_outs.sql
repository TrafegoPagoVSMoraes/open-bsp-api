-- Persist direct-message opt-outs and enforce them at the messages boundary.
-- History rows and provider status/echo upserts have no status.pending and are
-- deliberately not blocked: they do not dispatch a new message.

create table public.contact_opt_outs (
  organization_id uuid not null,
  service public.service not null,
  organization_address text not null,
  contact_address text not null,
  source_message_id uuid,
  opted_out_at timestamp with time zone not null default now(),
  primary key (
    organization_id,
    service,
    organization_address,
    contact_address
  ),
  constraint contact_opt_outs_organization_id_fkey
    foreign key (organization_id)
    references public.organizations(id)
    on delete cascade,
  constraint contact_opt_outs_organization_address_fkey
    foreign key (organization_id, organization_address)
    references public.organizations_addresses(organization_id, address)
    on delete cascade,
  constraint contact_opt_outs_contact_address_fkey
    foreign key (organization_id, service, contact_address)
    references public.contacts_addresses(organization_id, service, address)
    on delete cascade,
  constraint contact_opt_outs_source_message_id_fkey
    foreign key (source_message_id)
    references public.messages(id)
    on delete set null
);

comment on table public.contact_opt_outs is
  'Recipients that currently must not receive newly dispatched messages.';

alter table public.contact_opt_outs enable row level security;

create policy "members can read their orgs contact opt outs"
on public.contact_opt_outs
for select
to authenticated, anon
using (
  organization_id in (
    select public.get_authorized_orgs('member')
  )
);

-- No client write policy is intentional. Consent state is changed only by the
-- SECURITY DEFINER message trigger below; service_role keeps its normal bypass.

create function public.enforce_contact_opt_out_on_message() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if new.direction <> 'outgoing'::public.direction
    or (new.status ->> 'pending') is null
    or new.contact_address is null
    or new.group_address is not null
  then
    return new;
  end if;

  -- Consent changes and outgoing attempts for the same recipient cannot race.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      new.organization_id::text || ':' || new.service::text || ':' ||
      new.organization_address || ':' || new.contact_address,
      0
    )
  );

  if exists (
    select 1
    from public.contact_opt_outs o
    where o.organization_id = new.organization_id
      and o.service = new.service
      and o.organization_address = new.organization_address
      and o.contact_address = new.contact_address
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'Outgoing message blocked: recipient has opted out';
  end if;

  return new;
end;
$$;

create trigger a_enforce_contact_opt_out
before insert
on public.messages
for each row
execute function public.enforce_contact_opt_out_on_message();

create function public.whatsapp_consent_command(content jsonb) returns text
language plpgsql
immutable
set search_path to ''
as $$
declare
  candidate text;
  normalized text;
begin
  foreach candidate in array array[
    content ->> 'text',
    content #>> '{data,button_reply,id}',
    content #>> '{data,button_reply,title}',
    content #>> '{data,list_reply,id}',
    content #>> '{data,list_reply,title}',
    content #>> '{data,payload}',
    content #>> '{data,text}'
  ]
  loop
    if candidate is null then
      continue;
    end if;

    normalized := pg_catalog.translate(
      pg_catalog.upper(pg_catalog.btrim(candidate)),
      'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ',
      'AAAAAEEEEIIIIOOOOOUUUUC'
    );

    if normalized in (
      'OPT_OUT',
      'PARAR DE RECEBER MENSAGENS',
      'PARAR DE RECEBER',
      'PARAR',
      'SAIR',
      'CANCELAR'
    ) then
      return 'OPT_OUT';
    elsif normalized in (
      'OPT_IN',
      'VOLTAR A RECEBER MENSAGENS',
      'VOLTAR A RECEBER',
      'VOLTAR',
      'INICIAR',
      'RECEBER'
    ) then
      return 'OPT_IN';
    end if;
  end loop;

  return null;
end;
$$;

-- Seed the durable suppression table from historical consent commands. The
-- most recent command wins, so a later OPT_IN correctly cancels an older
-- OPT_OUT. This makes the guard effective immediately after deployment.
with consent_events as (
  select
    m.organization_id,
    m.service,
    m.organization_address,
    m.contact_address,
    m.id as source_message_id,
    m.timestamp,
    m.created_at,
    public.whatsapp_consent_command(m.content) as command
  from public.messages m
  where m.direction = 'incoming'::public.direction
    and m.service = 'whatsapp'::public.service
    and m.group_address is null
    and m.contact_address is not null
    and public.whatsapp_consent_command(m.content) is not null
), latest_consent as (
  select distinct on (
    organization_id,
    service,
    organization_address,
    contact_address
  )
    organization_id,
    service,
    organization_address,
    contact_address,
    source_message_id,
    timestamp,
    command
  from consent_events
  order by
    organization_id,
    service,
    organization_address,
    contact_address,
    timestamp desc,
    created_at desc,
    source_message_id desc
)
insert into public.contact_opt_outs (
  organization_id,
  service,
  organization_address,
  contact_address,
  source_message_id,
  opted_out_at
)
select
  organization_id,
  service,
  organization_address,
  contact_address,
  source_message_id,
  timestamp
from latest_consent
where command = 'OPT_OUT'
on conflict (
  organization_id,
  service,
  organization_address,
  contact_address
) do update set
  source_message_id = excluded.source_message_id,
  opted_out_at = excluded.opted_out_at;

create function public.handle_whatsapp_consent_message() returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  command text;
  lock_key text;
begin
  -- Only live, direct WhatsApp messages can change consent. Requiring pending
  -- excludes history imports, while group messages cannot opt out an individual.
  if new.direction <> 'incoming'::public.direction
    or new.service <> 'whatsapp'::public.service
    or new.group_address is not null
    or new.contact_address is null
    or (new.status ->> 'pending') is null
    -- whatsapp-webhook writes with the service-role client. Without this
    -- check, an org member could forge an incoming OPT_IN through the API.
    or coalesce(auth.role(), '') <> 'service_role'
  then
    return null;
  end if;

  command := public.whatsapp_consent_command(new.content);

  if command is null then
    return null;
  end if;

  lock_key := new.organization_id::text || ':' || new.service::text || ':' ||
    new.organization_address || ':' || new.contact_address;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(lock_key, 0)
  );

  -- Removing first makes repeated OPT_OUT commands idempotent without any
  -- externally forgeable bypass. The transaction and advisory lock ensure no
  -- other outgoing attempt can pass through this temporary absence.
  delete from public.contact_opt_outs o
  where o.organization_id = new.organization_id
    and o.service = new.service
    and o.organization_address = new.organization_address
    and o.contact_address = new.contact_address;

  if command = 'OPT_OUT' then
    insert into public.messages (
      organization_id,
      conversation_id,
      direction,
      contact_address,
      service,
      organization_address,
      content
    ) values (
      new.organization_id,
      new.conversation_id,
      'outgoing'::public.direction,
      new.contact_address,
      new.service,
      new.organization_address,
      jsonb_build_object(
        'version', '1',
        'type', 'data',
        'kind', 'interactive',
        'data', jsonb_build_object(
          'type', 'button',
          'body', jsonb_build_object(
            'text', E'✅ Tudo certo! A partir de agora, este número não receberá mais mensagens. 🛑💚\n\nSe mudar de ideia, toque no botão abaixo e volte quando quiser. 😊'
          ),
          'action', jsonb_build_object(
            'buttons', jsonb_build_array(
              jsonb_build_object(
                'type', 'reply',
                'reply', jsonb_build_object(
                  'id', 'OPT_IN',
                  'title', 'Voltar a receber'
                )
              )
            )
          )
        )
      )
    );

    insert into public.contact_opt_outs (
      organization_id,
      service,
      organization_address,
      contact_address,
      source_message_id
    ) values (
      new.organization_id,
      new.service,
      new.organization_address,
      new.contact_address,
      new.id
    );
  else
    insert into public.messages (
      organization_id,
      conversation_id,
      direction,
      contact_address,
      service,
      organization_address,
      content
    ) values (
      new.organization_id,
      new.conversation_id,
      'outgoing'::public.direction,
      new.contact_address,
      new.service,
      new.organization_address,
      jsonb_build_object(
        'version', '1',
        'type', 'text',
        'kind', 'text',
        'text', '🎉 Que bom ter você de volta! A partir de agora, este número voltará a receber nossas mensagens. Obrigado por continuar com a gente! 💚📲'
      )
    );
  end if;

  return null;
end;
$$;

-- Alphabetical ordering makes consent handling run before agent-client is
-- notified by handle_incoming_message_to_agent for the same incoming row.
create trigger a_handle_whatsapp_consent_message
after insert
on public.messages
for each row
execute function public.handle_whatsapp_consent_message();

-- Consent commands are terminal control messages, not prompts for the agent.
-- Preserve the original trigger for every other incoming message.
drop trigger handle_incoming_message_to_agent on public.messages;

create trigger handle_incoming_message_to_agent
after insert
on public.messages
for each row
when (
  new.direction = 'incoming'::public.direction
  and (new.status ->> 'pending') is not null
  and not (
    new.service = 'whatsapp'::public.service
    and new.group_address is null
    and public.whatsapp_consent_command(new.content) is not null
  )
)
execute function public.edge_function('/agent-client', 'post');
