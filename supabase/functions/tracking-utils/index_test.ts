import { deepEqual, equal, match, ok } from "node:assert/strict";

import {
  destinationOrigin,
  generateOpaqueToken,
  normalizeDestination,
  normalizeOrigin,
  sanitizeMetadata,
  validateBrowserEvent,
  validateOpaqueToken,
} from "./index.ts";

Deno.test("opaque tracking tokens contain 256 bits in base64url form", () => {
  const token = generateOpaqueToken();
  equal(token.length, 43);
  match(token, /^[A-Za-z0-9_-]+$/);
  ok(validateOpaqueToken(token));
});

Deno.test("origins and destinations are normalized without domain coupling", () => {
  equal(normalizeOrigin("https://Example.COM"), "https://example.com");
  equal(normalizeOrigin("https://example.com/path"), null);
  equal(normalizeOrigin("http://example.com"), null);
  equal(
    normalizeDestination("https://Example.COM/campaign?source=test"),
    "https://example.com/campaign?source=test",
  );
  equal(
    destinationOrigin("https://example.com/path"),
    "https://example.com",
  );
});

Deno.test("generic browser events accept project-defined names", () => {
  equal(
    validateBrowserEvent({
      event_id: crypto.randomUUID(),
      event_name: "hero.cta_clicked",
      event_type: "click",
      occurred_at: new Date().toISOString(),
      element_id: "hero-primary",
      page_path: "/campaign",
      metadata: { section: "hero" },
    }),
    null,
  );
});

Deno.test("browser event validation rejects URLs and unsupported names", () => {
  equal(
    validateBrowserEvent({
      event_id: crypto.randomUUID(),
      event_name: "CTA clicked",
      event_type: "click",
      occurred_at: new Date().toISOString(),
      page_path: "/campaign?phone=123",
    }),
    "event_name is invalid",
  );
});

Deno.test("metadata sanitizer removes PII keys and PII-looking values", () => {
  deepEqual(
    sanitizeMetadata({
      section: "hero",
      phone: "5511999999999",
      arbitrary: "person@example.com",
      position: 2,
      successful: true,
    }),
    { section: "hero", position: 2, successful: true },
  );
});
