export const TRACKING_SCHEMA_VERSION = "1";

export type TrackingClassification =
  | "human_candidate"
  | "bot"
  | "preview"
  | "prefetch"
  | "unknown";

export type BrowserEventType =
  | "page_view"
  | "click"
  | "form_start"
  | "form_submit"
  | "conversion"
  | "custom";

export type BrowserTrackingEvent = {
  event_id: string;
  event_name: string;
  event_type: BrowserEventType;
  occurred_at: string;
  element_id?: string;
  page_path?: string;
  metadata?: Record<string, unknown>;
};

export type RequestMetadata = {
  browserFamily: string | null;
  osFamily: string | null;
  deviceType: string | null;
  country: string | null;
  region: string | null;
  referer: string | null;
  acceptLanguage: string | null;
  requestId: string | null;
};

const PREVIEW_USER_AGENTS = [
  /facebookexternalhit/i,
  /twitterbot/i,
  /linkedinbot/i,
  /slackbot/i,
  /discordbot/i,
  /telegrambot/i,
  /googlebot/i,
  /bingbot/i,
  /applebot/i,
];

const BOT_USER_AGENTS = [
  /\bbot\b/i,
  /crawler/i,
  /spider/i,
  /scraper/i,
  /headless/i,
  /phantom/i,
  /puppeteer/i,
  /playwright/i,
  /selenium/i,
  /webdriver/i,
  /uptime/i,
  /monitor/i,
];

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const PROJECT_KEY_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;
const EVENT_NAME_PATTERN = /^[a-z][a-z0-9_.:-]{0,63}$/;
const PAGE_PATH_PATTERN = /^\/[^?#]{0,511}$/;
const SENSITIVE_METADATA_KEY =
  /(email|e-mail|name|nome|phone|telefone|mobile|address|endereco|ip|token|session|cookie|cpf|documento)/i;
const SENSITIVE_METADATA_VALUE =
  /(?:[\w.+-]+@[\w.-]+\.[a-z]{2,}|(?:\+?\d[\s().-]*){8,})/i;
const BROWSER_EVENT_TYPES = new Set<BrowserEventType>([
  "page_view",
  "click",
  "form_start",
  "form_submit",
  "conversion",
  "custom",
]);

export function bytesToBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/u, "");
}

export function generateOpaqueToken(): string {
  return bytesToBase64Url(crypto.getRandomValues(new Uint8Array(32)));
}

export function validateOpaqueToken(token: string): boolean {
  return TOKEN_PATTERN.test(token);
}

export function validateProjectKey(key: string): boolean {
  return PROJECT_KEY_PATTERN.test(key);
}

export async function sha256Hex(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(
    new Uint8Array(digest),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}

export async function tokenHashAsBytea(token: string): Promise<string> {
  return `\\x${await sha256Hex(token)}`;
}

export function classifyRequest(request: Request): TrackingClassification {
  const purpose = [
    request.headers.get("purpose"),
    request.headers.get("sec-purpose"),
    request.headers.get("x-purpose"),
    request.headers.get("x-moz"),
  ].filter(Boolean).join(" ");
  if (/prefetch|prerender/i.test(purpose)) return "prefetch";

  const userAgent = request.headers.get("user-agent") ?? "";
  if (PREVIEW_USER_AGENTS.some((pattern) => pattern.test(userAgent))) {
    return "preview";
  }
  if (BOT_USER_AGENTS.some((pattern) => pattern.test(userAgent))) return "bot";
  if (/mozilla|chrome|safari|firefox|edg\//i.test(userAgent)) {
    return "human_candidate";
  }
  return "unknown";
}

export function extractTokenFromPath(pathname: string): string | null {
  const match = pathname.match(/\/r\/([A-Za-z0-9_-]{43})\/?$/u);
  return match?.[1] ?? null;
}

export function normalizeOrigin(value: string): string | null {
  try {
    const url = new URL(value);
    if (url.protocol !== "https:" || url.username || url.password) return null;
    if (url.pathname !== "/" || url.search || url.hash) return null;
    return url.origin;
  } catch {
    return null;
  }
}

export function normalizeDestination(value: string): string | null {
  try {
    const url = new URL(value);
    if (url.protocol !== "https:" || url.username || url.password) return null;
    return url.toString();
  } catch {
    return null;
  }
}

export function destinationOrigin(value: string): string | null {
  const destination = normalizeDestination(value);
  return destination ? new URL(destination).origin : null;
}

export function isAllowedOrigin(
  origin: string,
  allowedOrigins: readonly string[],
): boolean {
  const normalized = normalizeOrigin(origin);
  return normalized !== null && allowedOrigins.includes(normalized);
}

function limitedHeader(request: Request, name: string, limit: number) {
  const value = request.headers.get(name)?.trim();
  return value ? value.slice(0, limit) : null;
}

function sanitizeReferer(value: string | null): string | null {
  if (!value) return null;
  try {
    const url = new URL(value);
    return `${url.origin}${url.pathname}`.slice(0, 512);
  } catch {
    return null;
  }
}

function userAgentSummary(userAgent: string | null) {
  if (!userAgent) {
    return { browserFamily: null, osFamily: null, deviceType: null };
  }
  const browserFamily = /Edg\//i.test(userAgent)
    ? "Edge"
    : /Firefox\//i.test(userAgent)
    ? "Firefox"
    : /Chrome\//i.test(userAgent)
    ? "Chrome"
    : /Safari\//i.test(userAgent)
    ? "Safari"
    : "Other";
  const osFamily = /Android/i.test(userAgent)
    ? "Android"
    : /iPhone|iPad|iPod/i.test(userAgent)
    ? "iOS"
    : /Windows/i.test(userAgent)
    ? "Windows"
    : /Mac OS X/i.test(userAgent)
    ? "macOS"
    : /Linux/i.test(userAgent)
    ? "Linux"
    : "Other";
  const deviceType = /iPad|Tablet/i.test(userAgent)
    ? "tablet"
    : /Mobile|Android|iPhone|iPod/i.test(userAgent)
    ? "mobile"
    : "desktop";
  return { browserFamily, osFamily, deviceType };
}

export function requestMetadata(request: Request): RequestMetadata {
  const userAgent = limitedHeader(request, "user-agent", 512);
  return {
    ...userAgentSummary(userAgent),
    country: limitedHeader(request, "cf-ipcountry", 8),
    region: limitedHeader(request, "cf-region", 128),
    referer: sanitizeReferer(request.headers.get("referer")),
    acceptLanguage: limitedHeader(request, "accept-language", 128),
    requestId: limitedHeader(request, "cf-ray", 128),
  };
}

export function validateBrowserEvent(event: unknown): string | null {
  if (!event || typeof event !== "object") return "event must be an object";
  const candidate = event as Record<string, unknown>;
  if (
    typeof candidate.event_id !== "string" ||
    !UUID_PATTERN.test(candidate.event_id)
  ) return "event_id must be a UUID v4";
  if (
    typeof candidate.event_name !== "string" ||
    !EVENT_NAME_PATTERN.test(candidate.event_name)
  ) return "event_name is invalid";
  if (
    typeof candidate.event_type !== "string" ||
    !BROWSER_EVENT_TYPES.has(candidate.event_type as BrowserEventType)
  ) return "event_type is not supported";
  if (typeof candidate.occurred_at !== "string") {
    return "occurred_at must be an ISO timestamp";
  }
  const occurredAt = Date.parse(candidate.occurred_at);
  if (
    !Number.isFinite(occurredAt) || occurredAt > Date.now() + 5 * 60_000 ||
    occurredAt < Date.now() - 7 * 24 * 60 * 60_000
  ) return "occurred_at is outside the accepted window";
  if (
    candidate.element_id !== undefined &&
    (typeof candidate.element_id !== "string" ||
      candidate.element_id.length === 0 || candidate.element_id.length > 128)
  ) return "element_id is invalid";
  if (
    candidate.page_path !== undefined &&
    (typeof candidate.page_path !== "string" ||
      !PAGE_PATH_PATTERN.test(candidate.page_path))
  ) return "page_path is invalid";
  if (
    candidate.metadata !== undefined &&
    (!candidate.metadata || typeof candidate.metadata !== "object" ||
      Array.isArray(candidate.metadata))
  ) return "metadata must be an object";
  return null;
}

export function sanitizeMetadata(
  value: Record<string, unknown> | undefined,
): Record<string, string | number | boolean | null> {
  if (!value) return {};
  const sanitized: Record<string, string | number | boolean | null> = {};
  for (const [key, item] of Object.entries(value).slice(0, 20)) {
    if (key.length > 64 || SENSITIVE_METADATA_KEY.test(key)) continue;
    if (typeof item === "string") {
      const trimmed = item.trim().slice(0, 256);
      if (!SENSITIVE_METADATA_VALUE.test(trimmed)) sanitized[key] = trimmed;
    } else if (typeof item === "number" && Number.isFinite(item)) {
      sanitized[key] = item;
    } else if (typeof item === "boolean" || item === null) {
      sanitized[key] = item;
    }
  }
  return sanitized;
}
