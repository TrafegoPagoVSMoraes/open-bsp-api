create type public.direction as enum ('incoming', 'outgoing', 'internal');

create type public.service as enum (
  'whatsapp',
  'instagram',
  'local',
  'slack',
  'discord',
  'teams',
  'whatsapp-web'
);

create type public.webhook_operation as enum ('insert', 'update');

create type public.webhook_table as enum (
  'messages',
  'conversations',
  'organizations_addresses',
  'contacts',
  'contacts_addresses',
  'logs'
);

create type public.role as enum ('owner', 'admin', 'member');

create type public.tracking_event_type as enum (
  'link_open',
  'page_view',
  'click',
  'form_start',
  'form_submit',
  'conversion',
  'custom'
);

create type public.tracking_classification as enum (
  'human_candidate',
  'bot',
  'preview',
  'prefetch',
  'unknown'
);
