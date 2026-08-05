import type {
  BrowserTrackingEvent,
  RequestMetadata,
  TrackingClassification,
} from "./index.ts";
import { sanitizeMetadata } from "./index.ts";

export type ActiveTrackingLink = {
  id: string;
  organization_id: string;
  project_id: string;
  message_id: string | null;
  destination_url: string;
  expires_at: string;
  disabled_at: string | null;
};

export type TrackingSession = {
  id: string;
  organization_id: string;
  project_id: string;
  tracking_link_id: string | null;
  message_id: string | null;
  origin: string;
  event_count: number;
  expires_at: string;
};

export type TrackingEnvironment = {
  supabaseUrl: string;
  serviceRoleKey: string;
};

export type TrackingFetch = typeof fetch;

function environment(): TrackingEnvironment {
  const supabaseUrl = Deno.env.get("SUPABASE_URL")?.replace(/\/$/u, "");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    throw new Error("Tracking storage environment is not configured");
  }
  return { supabaseUrl, serviceRoleKey };
}

async function request(
  path: string,
  init: RequestInit,
  requestFetch: TrackingFetch,
  env: TrackingEnvironment,
): Promise<Response> {
  const headers = new Headers(init.headers);
  headers.set("apikey", env.serviceRoleKey);
  headers.set("authorization", `Bearer ${env.serviceRoleKey}`);
  if (init.body) headers.set("content-type", "application/json");
  return await requestFetch(`${env.supabaseUrl}/rest/v1/${path}`, {
    ...init,
    headers,
  });
}

export async function findActiveTrackingLink(
  tokenHash: string,
  requestFetch: TrackingFetch = fetch,
  env: TrackingEnvironment = environment(),
): Promise<ActiveTrackingLink | null> {
  const query = new URLSearchParams({
    select:
      "id,organization_id,project_id,message_id,destination_url,expires_at,disabled_at",
    token_hash: `eq.${tokenHash}`,
    disabled_at: "is.null",
    limit: "1",
  });
  const response = await request(
    `tracking_links?${query}`,
    { method: "GET" },
    requestFetch,
    env,
  );
  if (!response.ok) {
    throw new Error(`Tracking link lookup failed: ${response.status}`);
  }
  const rows = await response.json() as ActiveTrackingLink[];
  const link = rows[0];
  if (!link || Date.parse(link.expires_at) <= Date.now()) return null;
  return link;
}

export async function recordTrackingOpen(
  input: {
    tokenHash: string;
    sessionTokenHash: string | null;
    eventId: string;
    classification: TrackingClassification;
    occurredAt: string;
    metadata: RequestMetadata;
  },
  requestFetch: TrackingFetch = fetch,
  env: TrackingEnvironment = environment(),
): Promise<boolean> {
  const response = await request(
    "rpc/record_tracking_open",
    {
      method: "POST",
      body: JSON.stringify({
        p_token_hash: input.tokenHash,
        p_session_token_hash: input.sessionTokenHash,
        p_event_id: input.eventId,
        p_classification: input.classification,
        p_occurred_at: input.occurredAt,
        p_browser_family: input.metadata.browserFamily,
        p_os_family: input.metadata.osFamily,
        p_device_type: input.metadata.deviceType,
        p_country: input.metadata.country,
        p_region: input.metadata.region,
        p_referer: input.metadata.referer,
        p_accept_language: input.metadata.acceptLanguage,
        p_request_id: input.metadata.requestId,
      }),
    },
    requestFetch,
    env,
  );
  if (!response.ok) {
    throw new Error(`Tracking open write failed: ${response.status}`);
  }
  const rows = await response.json() as unknown[];
  return rows.length > 0;
}

export async function createDirectTrackingSession(
  publicKey: string,
  sessionTokenHash: string,
  origin: string,
  eventCount: number,
  requestFetch: TrackingFetch = fetch,
  env: TrackingEnvironment = environment(),
): Promise<TrackingSession | null> {
  const response = await request(
    "rpc/create_tracking_session",
    {
      method: "POST",
      body: JSON.stringify({
        p_public_key: publicKey,
        p_session_token_hash: sessionTokenHash,
        p_origin: origin,
        p_event_count: eventCount,
      }),
    },
    requestFetch,
    env,
  );
  if (!response.ok) {
    throw new Error(`Tracking session creation failed: ${response.status}`);
  }
  const rows = await response.json() as Array<{
    tracking_session_id: string;
    organization_id: string;
    project_id: string;
    expires_at: string;
  }>;
  const row = rows[0];
  return row
    ? {
      id: row.tracking_session_id,
      organization_id: row.organization_id,
      project_id: row.project_id,
      tracking_link_id: null,
      message_id: null,
      origin,
      event_count: eventCount,
      expires_at: row.expires_at,
    }
    : null;
}

export async function reserveTrackingSession(
  sessionTokenHash: string,
  origin: string,
  eventCount: number,
  requestFetch: TrackingFetch = fetch,
  env: TrackingEnvironment = environment(),
): Promise<TrackingSession | null> {
  const response = await request(
    "rpc/reserve_tracking_session",
    {
      method: "POST",
      body: JSON.stringify({
        p_session_token_hash: sessionTokenHash,
        p_origin: origin,
        p_event_count: eventCount,
      }),
    },
    requestFetch,
    env,
  );
  if (!response.ok) {
    throw new Error(`Tracking session lookup failed: ${response.status}`);
  }
  const rows = await response.json() as Array<{
    tracking_session_id: string;
    organization_id: string;
    project_id: string;
    tracking_link_id: string | null;
    message_id: string | null;
    session_origin: string;
    event_count: number;
    expires_at: string;
  }>;
  const row = rows[0];
  return row
    ? {
      id: row.tracking_session_id,
      organization_id: row.organization_id,
      project_id: row.project_id,
      tracking_link_id: row.tracking_link_id,
      message_id: row.message_id,
      origin: row.session_origin,
      event_count: row.event_count,
      expires_at: row.expires_at,
    }
    : null;
}

export async function persistBrowserEvents(
  events: BrowserTrackingEvent[],
  session: TrackingSession,
  metadata: RequestMetadata,
  requestFetch: TrackingFetch = fetch,
  env: TrackingEnvironment = environment(),
): Promise<void> {
  const rows = events.map((event) => ({
    organization_id: session.organization_id,
    project_id: session.project_id,
    message_id: session.message_id,
    tracking_link_id: session.tracking_link_id,
    tracking_session_id: session.id,
    event_id: event.event_id,
    event_name: event.event_name,
    event_type: event.event_type,
    element_id: event.element_id ?? null,
    classification: "human_candidate",
    occurred_at: event.occurred_at,
    page_path: event.page_path?.slice(0, 512) ?? null,
    metadata: sanitizeMetadata(event.metadata),
    browser_family: metadata.browserFamily,
    os_family: metadata.osFamily,
    device_type: metadata.deviceType,
    country: metadata.country,
    region: metadata.region,
    referer: metadata.referer,
    accept_language: metadata.acceptLanguage,
    request_id: metadata.requestId,
  }));
  const response = await request(
    "tracking_events?on_conflict=project_id,event_id",
    {
      method: "POST",
      headers: { prefer: "resolution=ignore-duplicates,return=minimal" },
      body: JSON.stringify(rows),
    },
    requestFetch,
    env,
  );
  if (!response.ok) {
    throw new Error(`Tracking event write failed: ${response.status}`);
  }

  const query = new URLSearchParams({ id: `eq.${session.id}` });
  const updateResponse = await request(
    `tracking_sessions?${query}`,
    {
      method: "PATCH",
      body: JSON.stringify({ last_seen_at: new Date().toISOString() }),
    },
    requestFetch,
    env,
  );
  if (!updateResponse.ok) {
    throw new Error(`Tracking session update failed: ${updateResponse.status}`);
  }
}
