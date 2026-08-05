import {
  classifyRequest,
  extractTokenFromPath,
  generateOpaqueToken,
  normalizeDestination,
  requestMetadata,
  tokenHashAsBytea,
  validateOpaqueToken,
} from "../tracking-utils/index.ts";
import {
  type ActiveTrackingLink,
  findActiveTrackingLink,
  recordTrackingOpen,
} from "../tracking-utils/store.ts";

const NO_STORE_HEADERS = {
  "cache-control": "no-store, max-age=0",
  pragma: "no-cache",
  "referrer-policy": "no-referrer",
  "x-content-type-options": "nosniff",
};

function unavailable() {
  return new Response("Link unavailable", {
    status: 404,
    headers: NO_STORE_HEADERS,
  });
}

function redirect(location: string) {
  return new Response(null, {
    status: 302,
    headers: { ...NO_STORE_HEADERS, location },
  });
}

type RedirectDependencies = {
  findLink: (
    tokenHash: string,
  ) => ActiveTrackingLink | null | Promise<ActiveTrackingLink | null>;
  recordOpen: (
    input: Parameters<typeof recordTrackingOpen>[0],
  ) => boolean | Promise<boolean>;
  makeToken: () => string;
  makeEventId: () => string;
  now: () => Date;
  metadata: typeof requestMetadata;
};

const defaultDependencies: RedirectDependencies = {
  findLink: findActiveTrackingLink,
  recordOpen: recordTrackingOpen,
  makeToken: generateOpaqueToken,
  makeEventId: crypto.randomUUID.bind(crypto),
  now: () => new Date(),
  metadata: requestMetadata,
};

export function createTrackingRedirectHandler(
  dependencies: Partial<RedirectDependencies> = {},
) {
  const deps = { ...defaultDependencies, ...dependencies };
  return async (request: Request): Promise<Response> => {
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method not allowed", {
        status: 405,
        headers: { ...NO_STORE_HEADERS, allow: "GET, HEAD" },
      });
    }

    const token = extractTokenFromPath(new URL(request.url).pathname);
    if (!token || !validateOpaqueToken(token)) return unavailable();

    const tokenHash = await tokenHashAsBytea(token);
    let link: ActiveTrackingLink | null;
    try {
      link = await deps.findLink(tokenHash);
    } catch (error) {
      console.error("Tracking link lookup failed", {
        reason: error instanceof Error ? error.message : "unknown",
      });
      return new Response("Tracking temporarily unavailable", {
        status: 503,
        headers: NO_STORE_HEADERS,
      });
    }

    const destination = link
      ? normalizeDestination(link.destination_url)
      : null;
    if (!link || !destination) return unavailable();

    const classification = classifyRequest(request);
    const sessionToken = classification === "human_candidate"
      ? deps.makeToken()
      : null;
    const sessionTokenHash = sessionToken
      ? await tokenHashAsBytea(sessionToken)
      : null;

    let recorded = false;
    let persistenceFailed = false;
    try {
      recorded = await deps.recordOpen({
        tokenHash,
        sessionTokenHash,
        eventId: deps.makeEventId(),
        classification,
        occurredAt: deps.now().toISOString(),
        metadata: deps.metadata(request),
      });
    } catch (error) {
      persistenceFailed = true;
      console.error("Tracking open persistence failed", {
        reason: error instanceof Error ? error.message : "unknown",
      });
    }

    if (!recorded && !persistenceFailed) return unavailable();
    if (persistenceFailed || !sessionToken) return redirect(destination);

    const target = new URL(destination);
    target.hash = `obsp=${sessionToken}`;
    return redirect(target.toString());
  };
}

export const handleTrackingRedirect = createTrackingRedirectHandler();
