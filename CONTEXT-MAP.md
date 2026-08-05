# Context map

Read only the contexts relevant to the task, plus any applicable ADRs in
`docs/adr/`.

| Context   | Purpose                                                                                  | Documentation                        |
| --------- | ---------------------------------------------------------------------------------------- | ------------------------------------ |
| Messaging | OpenBSP conversations, contacts, messages, channels, WhatsApp webhooks, and dispatch     | `docs/contexts/messaging/CONTEXT.md` |
| Tracking  | Generic projects, links, browser sessions, events, attribution, retention, and reporting | `docs/contexts/tracking/CONTEXT.md`  |
| Plugin    | OpenBSP plugin and MCP tools that expose platform operations                             | `docs/contexts/plugin/CONTEXT.md`    |

## Boundaries

- Tracking may reference a message through an optional `message_id`, but it does
  not own message delivery or WhatsApp credentials.
- Messaging must not depend on a particular external landing page.
- The plugin consumes public application interfaces; it must not bypass
  organization authorization or table policies.
