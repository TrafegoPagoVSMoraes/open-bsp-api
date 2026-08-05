import {
  type BrowserTrackingEvent,
  generateOpaqueToken,
  normalizeOrigin,
  requestMetadata,
  tokenHashAsBytea,
  TRACKING_SCHEMA_VERSION,
  validateBrowserEvent,
  validateOpaqueToken,
  validateProjectKey,
} from "../tracking-utils/index.ts";
import {
  createDirectTrackingSession,
  persistBrowserEvents,
  reserveTrackingSession,
  type TrackingSession,
} from "../tracking-utils/store.ts";

const MAX_BODY_BYTES = 32 * 1024;
const MAX_EVENTS = 20;

function responseHeaders(origin: string) {
  return {
    "access-control-allow-headers": "content-type",
    "access-control-allow-methods": "POST, OPTIONS",
    "access-control-allow-origin": origin,
    "access-control-max-age": "86400",
    "cache-control": "no-store, max-age=0",
    "content-type": "application/json",
    vary: "Origin",
  };
}

function jsonResponse(
  body: Record<string, unknown>,
  status: number,
  origin: string,
) {
  return new Response(JSON.stringify(body), {
    status,
    headers: responseHeaders(origin),
  });
}

async function readLimitedBody(request: Request): Promise<Uint8Array | null> {
  if (!request.body) return new Uint8Array();
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.length;
    if (size > MAX_BODY_BYTES) {
      await reader.cancel();
      return null;
    }
    chunks.push(value);
  }
  const result = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.length;
  }
  return result;
}

type EventsDependencies = {
  findSession: (
    hash: string,
    origin: string,
    eventCount: number,
  ) => TrackingSession | null | Promise<TrackingSession | null>;
  createSession: (
    publicKey: string,
    hash: string,
    origin: string,
    eventCount: number,
  ) => TrackingSession | null | Promise<TrackingSession | null>;
  persistEvents: (
    events: BrowserTrackingEvent[],
    session: TrackingSession,
    metadata: ReturnType<typeof requestMetadata>,
  ) => void | Promise<void>;
  makeToken: () => string;
  metadata: typeof requestMetadata;
};

const defaultDependencies: EventsDependencies = {
  findSession: reserveTrackingSession,
  createSession: createDirectTrackingSession,
  persistEvents: persistBrowserEvents,
  makeToken: generateOpaqueToken,
  metadata: requestMetadata,
};

type EventsBody = {
  schema_version?: unknown;
  session_token?: unknown;
  project_key?: unknown;
  events?: unknown;
};

export function createTrackingEventsHandler(
  dependencies: Partial<EventsDependencies> = {},
) {
  const deps = { ...defaultDependencies, ...dependencies };
  return async (request: Request): Promise<Response> => {
    const requestOrigin = request.headers.get("origin") ?? "";
    const origin = normalizeOrigin(requestOrigin);
    if (!origin) {
      return new Response(JSON.stringify({ error: "origin_not_allowed" }), {
        status: 403,
        headers: {
          "cache-control": "no-store, max-age=0",
          "content-type": "application/json",
        },
      });
    }

    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: responseHeaders(origin),
      });
    }
    if (request.method !== "POST") {
      return jsonResponse({ error: "method_not_allowed" }, 405, origin);
    }
    const contentType = request.headers.get("content-type") ?? "";
    if (!/^application\/json(?:\s*;|$)/i.test(contentType)) {
      return jsonResponse({ error: "invalid_content_type" }, 415, origin);
    }
    const declaredLength = Number(request.headers.get("content-length") ?? 0);
    if (declaredLength > MAX_BODY_BYTES) {
      return jsonResponse({ error: "body_too_large" }, 413, origin);
    }

    const rawBody = await readLimitedBody(request);
    if (!rawBody) return jsonResponse({ error: "body_too_large" }, 413, origin);

    let body: EventsBody;
    try {
      body = JSON.parse(new TextDecoder().decode(rawBody));
    } catch {
      return jsonResponse({ error: "invalid_json" }, 400, origin);
    }
    if (body.schema_version !== TRACKING_SCHEMA_VERSION) {
      return jsonResponse({ error: "invalid_schema_version" }, 400, origin);
    }
    if (
      !Array.isArray(body.events) || body.events.length === 0 ||
      body.events.length > MAX_EVENTS
    ) {
      return jsonResponse({ error: "invalid_batch_size" }, 400, origin);
    }

    const events: BrowserTrackingEvent[] = [];
    const uniqueEventIds = new Set<string>();
    for (const event of body.events) {
      const validationError = validateBrowserEvent(event);
      if (validationError) {
        return jsonResponse(
          { error: "invalid_event", reason: validationError },
          400,
          origin,
        );
      }
      const typedEvent = event as BrowserTrackingEvent;
      if (uniqueEventIds.has(typedEvent.event_id)) continue;
      uniqueEventIds.add(typedEvent.event_id);
      events.push(typedEvent);
    }

    let session: TrackingSession | null = null;
    let issuedToken: string | null = null;
    try {
      if (
        typeof body.session_token === "string" &&
        validateOpaqueToken(body.session_token)
      ) {
        session = await deps.findSession(
          await tokenHashAsBytea(body.session_token),
          origin,
          events.length,
        );
      } else if (
        typeof body.project_key === "string" &&
        validateProjectKey(body.project_key)
      ) {
        issuedToken = deps.makeToken();
        session = await deps.createSession(
          body.project_key,
          await tokenHashAsBytea(issuedToken),
          origin,
          events.length,
        );
      }
    } catch (error) {
      console.error("Tracking session resolution failed", {
        reason: error instanceof Error ? error.message : "unknown",
      });
      return jsonResponse({ accepted: false }, 503, origin);
    }

    if (!session || session.origin !== origin) {
      return jsonResponse(
        { accepted: true, received: events.length, ignored: events.length },
        202,
        origin,
      );
    }

    try {
      await deps.persistEvents(events, session, deps.metadata(request));
    } catch (error) {
      console.error("Tracking event persistence failed", {
        reason: error instanceof Error ? error.message : "unknown",
      });
      return jsonResponse({ accepted: false }, 503, origin);
    }

    return jsonResponse(
      {
        accepted: true,
        received: events.length,
        ignored: body.events.length - events.length,
        ...(issuedToken && {
          session_token: issuedToken,
          expires_at: session.expires_at,
        }),
      },
      202,
      origin,
    );
  };
}

export const handleTrackingEvents = createTrackingEventsHandler();
