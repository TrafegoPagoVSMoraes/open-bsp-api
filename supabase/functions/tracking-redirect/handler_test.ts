import { equal } from "node:assert/strict";

import type { ActiveTrackingLink } from "../tracking-utils/store.ts";
import { createTrackingRedirectHandler } from "./handler.ts";

const TOKEN = "A".repeat(43);
const SESSION_TOKEN = "B".repeat(43);
const LINK: ActiveTrackingLink = {
  id: crypto.randomUUID(),
  organization_id: crypto.randomUUID(),
  project_id: crypto.randomUUID(),
  message_id: null,
  destination_url: "https://landing.example/campaign?source=whatsapp",
  expires_at: new Date(Date.now() + 60_000).toISOString(),
  disabled_at: null,
};

function request(userAgent = "Mozilla/5.0 Chrome/125") {
  return new Request(`https://tracker.example/r/${TOKEN}`, {
    headers: { "user-agent": userAgent },
  });
}

Deno.test("valid human redirect creates a fragment-bound session", async () => {
  const handler = createTrackingRedirectHandler({
    findLink: () => LINK,
    recordOpen: () => true,
    makeToken: () => SESSION_TOKEN,
    makeEventId: () => crypto.randomUUID(),
    metadata: () => ({
      browserFamily: "Chrome",
      osFamily: "Windows",
      deviceType: "desktop",
      country: null,
      region: null,
      referer: null,
      acceptLanguage: null,
      requestId: null,
    }),
  });
  const response = await handler(request());
  equal(response.status, 302);
  equal(
    response.headers.get("location"),
    `https://landing.example/campaign?source=whatsapp#obsp=${SESSION_TOKEN}`,
  );
});

Deno.test("preview clients are recorded without receiving a session", async () => {
  const handler = createTrackingRedirectHandler({
    findLink: () => LINK,
    recordOpen: () => true,
  });
  const response = await handler(request("facebookexternalhit/1.1"));
  equal(response.status, 302);
  equal(response.headers.get("location"), LINK.destination_url);
});

Deno.test("invalid destinations fail closed", async () => {
  const handler = createTrackingRedirectHandler({
    findLink: () => ({ ...LINK, destination_url: "javascript:alert(1)" }),
  });
  equal((await handler(request())).status, 404);
});

Deno.test("analytics outage does not break a previously valid redirect", async () => {
  const handler = createTrackingRedirectHandler({
    findLink: () => LINK,
    recordOpen: () => {
      throw new Error("database unavailable");
    },
  });
  const response = await handler(request());
  equal(response.status, 302);
  equal(response.headers.get("location"), LINK.destination_url);
});
