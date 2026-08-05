import {
  createClient,
  createUnsecureClient,
} from "../_shared/supabase_client.ts";
import {
  destinationOrigin,
  normalizeDestination,
  normalizeOrigin,
  sanitizeMetadata,
  tokenHashAsBytea,
  validateOpaqueToken,
} from "../tracking-utils/index.ts";

const CORS_HEADERS = {
  "access-control-allow-headers": "authorization, content-type, x-client-info",
  "access-control-allow-methods": "GET, POST, PATCH, OPTIONS",
  "access-control-allow-origin": "*",
  "cache-control": "no-store, max-age=0",
  "content-type": "application/json",
};
const MAX_BODY_BYTES = 32 * 1024;
const SLUG_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

function response(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: CORS_HEADERS,
  });
}

function routePath(url: URL) {
  const marker = "/tracking-management";
  const index = url.pathname.indexOf(marker);
  return index >= 0
    ? url.pathname.slice(index + marker.length) || "/"
    : url.pathname;
}

async function bodyAsObject(request: Request) {
  const declaredLength = Number(request.headers.get("content-length") ?? 0);
  if (declaredLength > MAX_BODY_BYTES) throw new Error("body_too_large");
  const text = await request.text();
  if (new TextEncoder().encode(text).length > MAX_BODY_BYTES) {
    throw new Error("body_too_large");
  }
  const parsed: unknown = JSON.parse(text);
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("invalid_body");
  }
  return parsed as Record<string, unknown>;
}

function requiredString(
  body: Record<string, unknown>,
  key: string,
  maximum: number,
) {
  const value = body[key];
  if (typeof value !== "string") throw new Error(`invalid_${key}`);
  const trimmed = value.trim();
  if (!trimmed || trimmed.length > maximum) throw new Error(`invalid_${key}`);
  return trimmed;
}

function projectInput(body: Record<string, unknown>) {
  const name = requiredString(body, "name", 120);
  const slug = requiredString(body, "slug", 80).toLowerCase();
  if (!SLUG_PATTERN.test(slug)) throw new Error("invalid_slug");
  if (!Array.isArray(body.allowed_origins)) {
    throw new Error("invalid_allowed_origins");
  }
  const allowedOrigins = [
    ...new Set(body.allowed_origins.map((item) => {
      if (typeof item !== "string") throw new Error("invalid_allowed_origins");
      const origin = normalizeOrigin(item.trim());
      if (!origin) throw new Error("invalid_allowed_origins");
      return origin;
    })),
  ];
  if (allowedOrigins.length < 1 || allowedOrigins.length > 20) {
    throw new Error("invalid_allowed_origins");
  }
  const defaultDestination = body.default_destination_url === undefined ||
      body.default_destination_url === null ||
      body.default_destination_url === ""
    ? null
    : normalizeDestination(String(body.default_destination_url));
  if (
    body.default_destination_url &&
    (!defaultDestination ||
      !allowedOrigins.includes(destinationOrigin(defaultDestination) ?? ""))
  ) throw new Error("invalid_default_destination_url");

  const sessionTtl = body.session_ttl_minutes === undefined
    ? 30
    : Number(body.session_ttl_minutes);
  const retentionDays = body.retention_days === undefined
    ? 90
    : Number(body.retention_days);
  const directSessionRateLimit =
    body.direct_session_rate_limit_per_minute === undefined
      ? 600
      : Number(body.direct_session_rate_limit_per_minute);
  if (!Number.isInteger(sessionTtl) || sessionTtl < 5 || sessionTtl > 1440) {
    throw new Error("invalid_session_ttl_minutes");
  }
  if (
    !Number.isInteger(retentionDays) || retentionDays < 1 ||
    retentionDays > 365
  ) throw new Error("invalid_retention_days");
  if (
    !Number.isInteger(directSessionRateLimit) ||
    directSessionRateLimit < 10 || directSessionRateLimit > 10_000
  ) throw new Error("invalid_direct_session_rate_limit_per_minute");

  return {
    name,
    slug,
    allowed_origins: allowedOrigins,
    default_destination_url: defaultDestination,
    session_ttl_minutes: sessionTtl,
    direct_session_rate_limit_per_minute: directSessionRateLimit,
    retention_days: retentionDays,
  };
}

async function authorizedOrganizations(
  client: ReturnType<typeof createClient>,
  role: "admin" | "member",
) {
  const { data, error } = await client.rpc("get_authorized_orgs", { role });
  if (error) throw new Error("authorization_failed");
  return new Set(data ?? []);
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  let userClient: ReturnType<typeof createClient>;
  try {
    userClient = createClient(request);
    const { error } = await userClient.auth.getUser();
    if (error) return response({ error: "unauthorized" }, 401);
  } catch {
    return response({ error: "unauthorized" }, 401);
  }

  const serviceClient = createUnsecureClient();
  const url = new URL(request.url);
  const path = routePath(url);

  try {
    if (request.method === "GET" && path === "/projects") {
      const organizationId = url.searchParams.get("organization_id");
      if (!organizationId) {
        return response({ error: "invalid_organization_id" }, 400);
      }
      const { data, error } = await userClient
        .from("tracking_projects")
        .select(
          "id,organization_id,public_key,name,slug,status,allowed_origins,default_destination_url,session_ttl_minutes,direct_session_rate_limit_per_minute,retention_days,created_at,updated_at",
        )
        .eq("organization_id", organizationId)
        .order("name");
      if (error) throw new Error("projects_read_failed");
      return response({ data: data ?? [] });
    }

    if (request.method === "POST" && path === "/projects") {
      const body = await bodyAsObject(request);
      const organizationId = requiredString(body, "organization_id", 64);
      const organizations = await authorizedOrganizations(userClient, "admin");
      if (!organizations.has(organizationId)) {
        return response({ error: "forbidden" }, 403);
      }
      const input = projectInput(body);
      const { data, error } = await serviceClient
        .from("tracking_projects")
        .insert({ organization_id: organizationId, ...input })
        .select(
          "id,organization_id,public_key,name,slug,status,allowed_origins,default_destination_url,session_ttl_minutes,direct_session_rate_limit_per_minute,retention_days,created_at,updated_at",
        )
        .single();
      if (error) throw new Error("project_create_failed");
      return response({ data }, 201);
    }

    const projectMatch = path.match(/^\/projects\/([0-9a-f-]{36})$/i);
    if (request.method === "PATCH" && projectMatch) {
      const body = await bodyAsObject(request);
      const projectId = projectMatch[1];
      const { data: existing, error: readError } = await userClient
        .from("tracking_projects")
        .select("id,organization_id")
        .eq("id", projectId)
        .single();
      if (readError || !existing) return response({ error: "not_found" }, 404);
      const organizations = await authorizedOrganizations(userClient, "admin");
      if (!organizations.has(existing.organization_id)) {
        return response({ error: "forbidden" }, 403);
      }
      const input = projectInput(body);
      const status = body.status === undefined ? "active" : body.status;
      if (status !== "active" && status !== "paused" && status !== "archived") {
        throw new Error("invalid_status");
      }
      const { data, error } = await serviceClient
        .from("tracking_projects")
        .update({ ...input, status })
        .eq("id", projectId)
        .select(
          "id,organization_id,public_key,name,slug,status,allowed_origins,default_destination_url,session_ttl_minutes,direct_session_rate_limit_per_minute,retention_days,created_at,updated_at",
        )
        .single();
      if (error) throw new Error("project_update_failed");
      return response({ data });
    }

    if (request.method === "POST" && path === "/links") {
      const body = await bodyAsObject(request);
      const projectId = requiredString(body, "project_id", 64);
      const destination = normalizeDestination(
        requiredString(body, "destination_url", 2048),
      );
      if (!destination) throw new Error("invalid_destination_url");
      const idempotencyKey = requiredString(body, "idempotency_key", 200);
      if (idempotencyKey.length < 8) throw new Error("invalid_idempotency_key");

      const { data: project, error: projectError } = await userClient
        .from("tracking_projects")
        .select("id,organization_id,status,allowed_origins")
        .eq("id", projectId)
        .single();
      if (projectError || !project || project.status !== "active") {
        return response({ error: "not_found" }, 404);
      }
      const organizations = await authorizedOrganizations(userClient, "admin");
      if (!organizations.has(project.organization_id)) {
        return response({ error: "forbidden" }, 403);
      }
      if (
        !project.allowed_origins.includes(destinationOrigin(destination) ?? "")
      ) {
        throw new Error("destination_origin_not_allowed");
      }

      const token = requiredString(body, "tracking_token", 64);
      if (!validateOpaqueToken(token)) {
        throw new Error("invalid_tracking_token");
      }
      const expiresInDays = body.expires_in_days === undefined
        ? 30
        : Number(body.expires_in_days);
      if (
        !Number.isInteger(expiresInDays) || expiresInDays < 1 ||
        expiresInDays > 365
      ) throw new Error("invalid_expires_in_days");
      const expiresAt = new Date(Date.now() + expiresInDays * 86_400_000);
      const messageId =
        body.message_id === undefined || body.message_id === null
          ? null
          : requiredString(body, "message_id", 64);
      const source = body.source === undefined ? "api" : body.source;
      if (
        source !== "whatsapp" && source !== "api" && source !== "manual" &&
        source !== "other"
      ) throw new Error("invalid_source");
      const attribution = body.attribution &&
          typeof body.attribution === "object" &&
          !Array.isArray(body.attribution)
        ? sanitizeMetadata(body.attribution as Record<string, unknown>)
        : {};

      const { data, error } = await serviceClient.rpc("create_tracking_link", {
        p_organization_id: project.organization_id,
        p_project_id: project.id,
        p_token_hash: await tokenHashAsBytea(token),
        p_destination_url: destination,
        p_expires_at: expiresAt.toISOString(),
        p_idempotency_key: idempotencyKey,
        p_message_id: messageId ?? undefined,
        p_source: source,
        p_attribution: attribution,
      });
      if (error) throw new Error("link_create_failed");
      const result = data?.[0];
      if (!result?.token_matches) {
        return response({ error: "idempotency_conflict" }, 409);
      }
      const supabaseUrl = Deno.env.get("SUPABASE_URL")?.replace(/\/$/u, "");
      if (!supabaseUrl) throw new Error("tracking_url_unavailable");
      const redirectUrl =
        `${supabaseUrl}/functions/v1/tracking-redirect/r/${token}`;
      return response({
        data: {
          id: result.tracking_link_id,
          redirect_url: redirectUrl,
          tracking_token: token,
          expires_at: result.link_expires_at,
        },
      }, result.created ? 201 : 200);
    }

    if (request.method === "GET" && path === "/dashboard") {
      const organizationId = url.searchParams.get("organization_id");
      if (!organizationId) {
        return response({ error: "invalid_organization_id" }, 400);
      }
      const projectId = url.searchParams.get("project_id");
      const from = url.searchParams.get("from") ??
        new Date(Date.now() - 30 * 86_400_000).toISOString();
      const to = url.searchParams.get("to") ?? new Date().toISOString();
      const { data, error } = await userClient.rpc("get_tracking_dashboard", {
        p_organization_id: organizationId,
        p_project_id: projectId ?? undefined,
        p_from: from,
        p_to: to,
      });
      if (error) throw new Error("dashboard_read_failed");
      return response({ data });
    }

    return response({ error: "not_found" }, 404);
  } catch (error) {
    const reason = error instanceof Error ? error.message : "request_failed";
    const status = reason === "body_too_large"
      ? 413
      : reason.startsWith("invalid_") || reason.endsWith("_not_allowed")
      ? 400
      : 500;
    if (status === 500) {
      console.error("Tracking management request failed", { reason });
    }
    return response(
      { error: status === 500 ? "request_failed" : reason },
      status,
    );
  }
});
