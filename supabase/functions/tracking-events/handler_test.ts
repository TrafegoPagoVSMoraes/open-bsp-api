import { deepEqual, equal, ok } from "node:assert/strict";

import type { BrowserTrackingEvent } from "../tracking-utils/index.ts";
import type { TrackingSession } from "../tracking-utils/store.ts";
import { createTrackingEventsHandler } from "./handler.ts";

const ORIGIN = "https://landing.example";
const SESSION_TOKEN = "S".repeat(43);
const PROJECT_KEY = crypto.randomUUID();
const SESSION: TrackingSession = {
  id: crypto.randomUUID(),
  organization_id: crypto.randomUUID(),
  project_id: crypto.randomUUID(),
  tracking_link_id: null,
  message_id: null,
  origin: ORIGIN,
  event_count: 1,
  expires_at: new Date(Date.now() + 60_000).toISOString(),
};

function event(): BrowserTrackingEvent {
  return {
    event_id: crypto.randomUUID(),
    event_name: "page_view",
    event_type: "page_view",
    occurred_at: new Date().toISOString(),
    page_path: "/campaign",
  };
}

function post(body: Record<string, unknown>, origin = ORIGIN) {
  return new Request("https://api.example/functions/v1/tracking-events", {
    method: "POST",
    headers: { "content-type": "application/json", origin },
    body: JSON.stringify(body),
  });
}

Deno.test("existing session accepts a generic event batch", async () => {
  let persisted: BrowserTrackingEvent[] = [];
  const handler = createTrackingEventsHandler({
    findSession: (_hash, origin, count) => {
      equal(origin, ORIGIN);
      equal(count, 1);
      return SESSION;
    },
    persistEvents: (events) => {
      persisted = events;
    },
  });
  const response = await handler(post({
    schema_version: "1",
    session_token: SESSION_TOKEN,
    events: [event()],
  }));
  equal(response.status, 202);
  equal(persisted.length, 1);
  equal(response.headers.get("access-control-allow-origin"), ORIGIN);
});

Deno.test("direct page visit bootstraps a project session", async () => {
  const handler = createTrackingEventsHandler({
    makeToken: () => SESSION_TOKEN,
    createSession: (key, _hash, origin, count) => {
      equal(key, PROJECT_KEY);
      equal(origin, ORIGIN);
      equal(count, 1);
      return SESSION;
    },
    persistEvents: () => undefined,
  });
  const response = await handler(post({
    schema_version: "1",
    project_key: PROJECT_KEY,
    events: [event()],
  }));
  const payload = await response.json();
  equal(response.status, 202);
  equal(payload.session_token, SESSION_TOKEN);
  ok(payload.expires_at);
});

Deno.test("origin-bound sessions do not cross projects or sites", async () => {
  let persisted = false;
  const handler = createTrackingEventsHandler({
    findSession: () => SESSION,
    persistEvents: () => {
      persisted = true;
    },
  });
  const response = await handler(post({
    schema_version: "1",
    session_token: SESSION_TOKEN,
    events: [event()],
  }, "https://other.example"));
  const payload = await response.json();
  equal(response.status, 202);
  deepEqual(payload, { accepted: true, received: 1, ignored: 1 });
  equal(persisted, false);
});

Deno.test("preflight is cacheable but actual writes remain server-validated", async () => {
  const handler = createTrackingEventsHandler();
  const response = await handler(
    new Request(
      "https://api.example/functions/v1/tracking-events",
      { method: "OPTIONS", headers: { origin: ORIGIN } },
    ),
  );
  equal(response.status, 204);
  equal(response.headers.get("access-control-allow-origin"), ORIGIN);
});
