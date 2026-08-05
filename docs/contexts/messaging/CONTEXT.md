# Messaging context

## Purpose

Own OpenBSP organizations, contacts, conversations, messages, channel addresses,
inbound webhooks, and outbound dispatch.

## Boundaries

- WhatsApp credentials, WABA registration, Graph API calls, webhook handling,
  and dispatcher authentication remain in messaging.
- Tracking can attach attribution to a message through an optional `message_id`;
  it must not change delivery behavior.
- External pages are not part of this context.

## Vocabulary

- **Organization address**: an organization's address on a service, such as a
  WhatsApp Phone Number ID.
- **Incoming message**: content received from a contact.
- **Outgoing message**: content created in OpenBSP for delivery by a channel.
- **Dispatcher**: authenticated Edge Function that performs outbound delivery.

## Sources

- `supabase/schemas/03_models/`
- `supabase/functions/whatsapp-webhook/`
- `supabase/functions/whatsapp-dispatcher/`
- `supabase/functions/whatsapp-management/`
