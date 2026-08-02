import type { Database, TemplateData } from "../_shared/supabase.ts";
import type { SupabaseClient } from "@supabase/supabase-js";
import * as log from "../_shared/logger.ts";
import { HTTPException } from "jsr:@hono/hono/http-exception";
import { ContentfulStatusCode } from "jsr:@hono/hono/utils/http-status";

const API_VERSION = "v24.0";
const DEFAULT_ACCESS_TOKEN =
  Deno.env.get("META_SYSTEM_USER_ACCESS_TOKEN")?.trim() || "";

async function getBusinessCredentials(
  client: SupabaseClient<Database>,
  organization_id: string,
  organization_address: string,
): Promise<{ waba_id: string; access_token: string }> {
  const { data, error } = await client
    .from("organizations_addresses")
    .select(
      "waba_id:extra->>waba_id, access_token:extra->>access_token",
    )
    .eq("organization_id", organization_id)
    .eq("address", organization_address)
    .single();

  if (error || !data) {
    log.error("Could not fetch WhatsApp business credentials", error);
    throw new HTTPException(403, {
      message: "Could not fetch WhatsApp business credentials",
      cause: error,
    });
  }

  const credentials = data as {
    waba_id: string | null;
    access_token: string | null;
  };

  const waba_id = credentials.waba_id?.trim();
  const access_token =
    credentials.access_token?.trim() || DEFAULT_ACCESS_TOKEN;

  if (!waba_id) {
    throw new HTTPException(500, {
      message: "WhatsApp WABA ID is not configured",
    });
  }

  if (!access_token) {
    log.error("No Meta access token configured");

    throw new HTTPException(500, {
      message:
        "No Meta access token configured. Set META_SYSTEM_USER_ACCESS_TOKEN.",
    });
  }

  return { waba_id, access_token };
}

export async function listTemplates(
  client: SupabaseClient<Database>,
  organization_id: string,
  organization_address: string,
): Promise<{ data: TemplateData[] }> {
  const { waba_id, access_token } = await getBusinessCredentials(
    client,
    organization_id,
    organization_address,
  );

  type MetaTemplatesPage = {
    data?: TemplateData[];
    paging?: { cursors?: { before?: string; after?: string } };
  };

  const startedAt = performance.now();
  const templates = new Map<string, TemplateData>();
  let after: string | undefined;
  let previousCursor: string | undefined;
  let pages = 0;

  for (let page = 0; page < 100; page++) {
    const url = new URL(
      `https://graph.facebook.com/${API_VERSION}/${waba_id}/message_templates`,
    );
    url.searchParams.set("limit", "100");
    url.searchParams.set(
      "fields",
      "id,name,status,category,language,components",
    );
    if (after) url.searchParams.set("after", after);

    const response = await fetch(url, {
      method: "GET",
      headers: { Authorization: `Bearer ${access_token}` },
    });

    if (!response.ok) {
      throw new HTTPException(response.status as ContentfulStatusCode, {
        message: "Could not fetch templates",
        cause: await response.json().catch(() => ({})),
      });
    }

    const result = (await response.json()) as MetaTemplatesPage;
    pages++;
    for (const template of result.data ?? []) templates.set(template.id, template);

    const nextCursor = result.paging?.cursors?.after;
    if (
      !nextCursor ||
      nextCursor === after ||
      nextCursor === previousCursor ||
      !result.data?.length
    ) break;

    previousCursor = after;
    after = nextCursor;
  }

  log.info("Fetched WhatsApp templates", {
    pages,
    total: templates.size,
    duration_ms: Math.round(performance.now() - startedAt),
  });

  return { data: Array.from(templates.values()) };
}

export async function fetchTemplate(
  client: SupabaseClient<Database>,
  organization_id: string,
  organization_address: string,
  template: TemplateData,
): Promise<TemplateData> {
  const { access_token } = await getBusinessCredentials(
    client,
    organization_id,
    organization_address,
  );

  const response = await fetch(
    `https://graph.facebook.com/${API_VERSION}/${template.id}`,
    {
      method: "GET",
      headers: { Authorization: `Bearer ${access_token}` },
    },
  );

  if (!response.ok) {
    throw new HTTPException(response.status as ContentfulStatusCode, {
      message: "Could not fetch template",
      cause: await response.json().catch(() => ({})),
    });
  }

  return await response.json();
}

export async function createTemplate(
  client: SupabaseClient<Database>,
  organization_id: string,
  organization_address: string,
  template: TemplateData,
): Promise<{
  id: string;
  status: string;
  category: string;
}> {
  const { waba_id, access_token } = await getBusinessCredentials(
    client,
    organization_id,
    organization_address,
  );

  const { name, category, language, components } = template;

  const filteredTemplate = {
    name,
    category,
    allow_category_change: true,
    language,
    components,
  };

  const response = await fetch(
    `https://graph.facebook.com/${API_VERSION}/${waba_id}/message_templates`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${access_token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(filteredTemplate),
    },
  );

  if (!response.ok) {
    throw new HTTPException(response.status as ContentfulStatusCode, {
      message: "Could not create template",
      cause: await response.json().catch(() => ({})),
    });
  }

  return await response.json();
}

export async function editTemplate(
  client: SupabaseClient<Database>,
  organization_id: string,
  organization_address: string,
  template: TemplateData,
): Promise<{
  success: boolean;
}> {
  const { access_token } = await getBusinessCredentials(
    client,
    organization_id,
    organization_address,
  );

  const { category, components } = template;
  const filteredTemplate = { category, components };

  const response = await fetch(
    `https://graph.facebook.com/${API_VERSION}/${template.id}`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${access_token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(filteredTemplate),
    },
  );

  if (!response.ok) {
    throw new HTTPException(response.status as ContentfulStatusCode, {
      message: "Could not update template",
      cause: await response.json().catch(() => ({})),
    });
  }

  return await response.json();
}

export async function deleteTemplate(
  client: SupabaseClient<Database>,
  organization_id: string,
  organization_address: string,
  template: TemplateData,
): Promise<{
  success: boolean;
}> {
  const { waba_id, access_token } = await getBusinessCredentials(
    client,
    organization_id,
    organization_address,
  );

  const response = await fetch(
    `https://graph.facebook.com/${API_VERSION}/${waba_id}/message_templates?name=${template.name}`,
    {
      method: "DELETE",
      headers: {
        Authorization: `Bearer ${access_token}`,
      },
    },
  );

  if (!response.ok) {
    throw new HTTPException(response.status as ContentfulStatusCode, {
      message: "Could not delete template",
      cause: await response.json().catch(() => ({})),
    });
  }

  return await response.json();
}
