-- Declarative representation of the legacy click tracker introduced by
-- 20260801231000_whatsapp_click_tracking.sql. Keeping these objects here
-- prevents schema diffs from dropping existing tracking data.
create table public.whatsapp_click_links (
  id uuid primary key default gen_random_uuid(),
  token text not null unique check (token ~ '^[A-Za-z0-9_-]{20,128}$'),
  destination_url text not null check (destination_url ~ '^https://'),
  campaign text not null,
  recipient_reference text,
  message_external_id text,
  expires_at timestamptz,
  disabled_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.whatsapp_click_events (
  id bigint generated always as identity primary key,
  link_id uuid not null references public.whatsapp_click_links(id) on delete cascade,
  clicked_at timestamptz not null default now(),
  user_agent text
);

create index whatsapp_click_events_link_id_clicked_at_idx
  on public.whatsapp_click_events (link_id, clicked_at desc);

alter table public.whatsapp_click_links enable row level security;
alter table public.whatsapp_click_events enable row level security;

comment on table public.whatsapp_click_links is
  'Opaque WhatsApp link tokens. No phone number or name is embedded in the URL.';
