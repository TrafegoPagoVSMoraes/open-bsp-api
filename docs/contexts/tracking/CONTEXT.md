# Tracking context

## Purpose

Provide domain-independent attribution and analytics for message links and
external pages through projects, opaque links, short-lived browser sessions,
generic events, retention, and aggregate reporting.

## Boundaries

- External pages remain independent applications. They only call the public
  tracking endpoint and define their own event names.
- `message_id` is optional attribution. Tracking does not send messages or
  manage WhatsApp credentials.
- Raw tokens are never stored; only SHA-256 hashes reach Postgres.
- Raw IP addresses, full user agents, full URLs, and form contents are outside
  the data model.

## Vocabulary

- **Tracking project**: organization-scoped installation with allowed HTTPS
  origins and retention settings.
- **Tracking link**: opaque capability that records an open before redirecting
  to an allowed destination.
- **Tracking session**: short-lived browser capability bound to a project and
  origin.
- **Tracking event**: generic page or interaction fact such as `page_view`,
  `click`, `form_submit`, or `conversion`.

## Sources

- `supabase/functions/tracking-*`
- `supabase/schemas/03_models/03-13_tracking_projects.sql`
- `supabase/schemas/03_models/03-14_tracking_links.sql`
- `supabase/schemas/03_models/03-15_tracking_sessions.sql`
- `supabase/schemas/03_models/03-16_tracking_events.sql`
- `docs/TRACKING_INTEGRATION.md`
- `docs/adr/0001-project-scoped-generic-tracking.md`
- `docs/adr/0002-opaque-capabilities-and-data-minimization.md`
