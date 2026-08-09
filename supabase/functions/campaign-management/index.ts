import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {
  createApiClient,
  createClient,
  createUnsecureClient,
} from "../_shared/supabase_client.ts";

const API_VERSION = "v24.0";
const DEFAULT_ACCESS_TOKEN =
  Deno.env.get("META_SYSTEM_USER_ACCESS_TOKEN")?.trim() || "";
const JSON_HEADERS = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, content-type, x-client-info",
  "access-control-allow-methods": "POST, OPTIONS",
  "content-type": "application/json",
};
const MAX_RECIPIENTS = 100_000;
const PAGE_SIZE = 1_000;

type JsonObject = Record<string, unknown>;
type RecipientInput = {
  phone?: unknown;
  whatsapp?: unknown;
  name?: unknown;
  first_name?: unknown;
  email?: unknown;
  source?: unknown;
  variables?: unknown;
};
type NormalizedRecipient = {
  phone: string;
  display_name: string | null;
  source: JsonObject;
};
type VariableMapping = Record<string, { source?: unknown; constant?: unknown }>;
type MetaTemplateComponent = {
  type?: unknown;
  text?: unknown;
  format?: unknown;
  buttons?: unknown;
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

function normalizePhone(value: unknown): string | null {
  let phone = String(value ?? "").replace(/\D/gu, "");
  if (phone.startsWith("00")) phone = phone.slice(2);
  if (phone.length === 10 || phone.length === 11) phone = `55${phone}`;
  if (!/^[1-9][0-9]{9,14}$/u.test(phone)) return null;
  return phone;
}

function normalizeName(value: unknown): string | null {
  const name = String(value ?? "").trim().replace(/\s+/gu, " ");
  if (!name) return null;
  const particles = new Set(["da", "das", "de", "do", "dos", "e"]);
  return name.toLocaleLowerCase("pt-BR").split(" ").map((part, index) =>
    index > 0 && particles.has(part)
      ? part
      : part.charAt(0).toLocaleUpperCase("pt-BR") + part.slice(1)
  ).join(" ");
}

function normalizeRecipients(input: unknown) {
  if (!Array.isArray(input)) throw new Error("invalid_recipients");
  if (input.length > MAX_RECIPIENTS) throw new Error("recipient_limit_exceeded");
  const unique = new Map<string, NormalizedRecipient>();
  let invalid = 0;
  let duplicates = 0;
  for (const raw of input as RecipientInput[]) {
    if (!raw || typeof raw !== "object") {
      invalid++;
      continue;
    }
    const phone = normalizePhone(raw.phone ?? raw.whatsapp);
    if (!phone) {
      invalid++;
      continue;
    }
    if (unique.has(phone)) {
      duplicates++;
      continue;
    }
    const displayName = normalizeName(raw.name);
    const source = raw.source && typeof raw.source === "object" &&
        !Array.isArray(raw.source)
      ? raw.source as JsonObject
      : {};
    const supplied = raw.variables && typeof raw.variables === "object" &&
        !Array.isArray(raw.variables)
      ? raw.variables as JsonObject
      : {};
    unique.set(phone, {
      phone,
      display_name: displayName,
      source: {
        ...source,
        ...supplied,
        email: raw.email ?? source.email ?? null,
        nome_completo: displayName,
        primeiro_nome: normalizeName(raw.first_name) ?? displayName?.split(" ")[0] ?? null,
      },
    });
  }
  return { recipients: [...unique.values()], invalid, duplicates };
}

async function authorize(request: Request, organizationId: string) {
  const token = request.headers.get("authorization")?.replace(/^Bearer\s+/iu, "").trim();
  if (!token) throw new Error("unauthorized");
  if (token.startsWith("eyJ")) {
    const client = createClient(request);
    const { data: { user }, error } = await client.auth.getUser();
    if (error || !user) throw new Error("unauthorized");
    const { data, error: orgError } = await client.rpc("get_authorized_orgs", {
      role: "member",
    });
    if (orgError || !(data ?? []).includes(organizationId)) throw new Error("forbidden");
    return;
  }
  const client = createApiClient(request);
  const { data, error } = await client.from("api_keys").select("organization_id,role")
    .eq("key", token).maybeSingle();
  if (error || !data) throw new Error("unauthorized");
  if (data.organization_id !== organizationId ||
    !["member", "admin", "owner"].includes(data.role)) throw new Error("forbidden");
}

async function getTemplateSnapshot(
  service: any,
  organizationId: string,
  organizationAddress: string,
  templateId: string,
) {
  if (!templateId) throw new Error("invalid_template");
  const { data: account, error } = await service.from("organizations_addresses")
    .select("access_token:extra->>access_token")
    .eq("organization_id", organizationId).eq("address", organizationAddress)
    .eq("service", "whatsapp").single();
  if (error || !account) throw new Error("whatsapp_account_not_found");
  const accessToken = account.access_token?.trim() || DEFAULT_ACCESS_TOKEN;
  if (!accessToken) throw new Error("whatsapp_credentials_missing");
  const url = new URL(`https://graph.facebook.com/${API_VERSION}/${templateId}`);
  url.searchParams.set("fields", "id,name,status,category,language,components");
  const response = await fetch(url, { headers: { authorization: `Bearer ${accessToken}` } });
  if (!response.ok) throw new Error(`template_validation_failed_${response.status}`);
  const snapshot = await response.json() as JsonObject;
  if (String(snapshot.id) !== templateId) throw new Error("template_identity_mismatch");
  if (snapshot.status !== "APPROVED" || snapshot.category !== "UTILITY") {
    throw new Error("template_must_be_approved_utility");
  }
  if (!snapshot.name || !snapshot.language || !Array.isArray(snapshot.components)) {
    throw new Error("invalid_template_snapshot");
  }
  return snapshot;
}

function placeholders(text: unknown) {
  return [...String(text ?? "").matchAll(/\{\{\s*([^}]+?)\s*\}\}/gu)]
    .map((match) => match[1]);
}

function mappedPlaceholder(key: string, mapping: VariableMapping) {
  if (!mapping[key]) throw new Error(`missing_variable_mapping:${key}`);
  return `{{${key}}}`;
}

function buildTemplatePayload(snapshot: JsonObject, mapping: VariableMapping) {
  const components: JsonObject[] = [];
  for (const component of snapshot.components as MetaTemplateComponent[]) {
    const type = String(component.type ?? "").toUpperCase();
    if (type === "HEADER" || type === "BODY") {
      const keys = placeholders(component.text);
      if (!keys.length) continue;
      if (type === "HEADER" && String(component.format ?? "TEXT") !== "TEXT") {
        throw new Error("unsupported_template_header");
      }
      components.push({
        type: type.toLocaleLowerCase(),
        parameters: keys.map((key) => ({
          type: "text",
          text: mappedPlaceholder(key, mapping),
          ...(/^\d+$/u.test(key) ? {} : { parameter_name: key }),
        })),
      });
      continue;
    }
    if (type !== "BUTTONS" || !Array.isArray(component.buttons)) continue;
    for (const [index, rawButton] of component.buttons.entries()) {
      const button = rawButton as JsonObject;
      const buttonType = String(button.type ?? "").toUpperCase();
      if (buttonType === "QUICK_REPLY") {
        const buttonText = String(button.text ?? "").trim();
        const normalizedText = buttonText.toLocaleLowerCase("pt-BR");
        const normalizedPayload = normalizedText.includes("parar") ||
            normalizedText.includes("opt-out")
          ? "OPT_OUT"
          : buttonText.toLocaleUpperCase("pt-BR").replace(/[^A-Z0-9]+/gu, "_")
            .replace(/^_+|_+$/gu, "") || `BUTTON_${index}`;
        components.push({
          type: "button",
          sub_type: "quick_reply",
          index: String(index),
          parameters: [{ type: "payload", payload: normalizedPayload }],
        });
      } else if (buttonType === "URL" && placeholders(button.url).length) {
        components.push({
          type: "button",
          sub_type: "url",
          index: String(index),
          parameters: [{ type: "text", text: "{{tracking_suffix}}" }],
        });
      }
    }
  }
  return {
    name: String(snapshot.name),
    language: { code: String(snapshot.language), policy: "deterministic" },
    ...(components.length ? { components } : {}),
  };
}

function resolveVariables(
  recipient: NormalizedRecipient,
  mapping: VariableMapping,
): JsonObject {
  const variables: JsonObject = {};
  for (const [key, rawRule] of Object.entries(mapping)) {
    const source = String(rawRule?.source ?? "");
    let value: unknown;
    if (source === "constant") value = rawRule.constant;
    else if (source === "first_name") value = recipient.source.primeiro_nome;
    else if (source === "full_name") value = recipient.source.nome_completo;
    else if (source.startsWith("column:")) value = recipient.source[source.slice(7)];
    else throw new Error(`invalid_variable_mapping:${key}`);
    if (value === undefined || value === null || String(value).trim() === "") {
      throw new Error(`missing_variable_value:${key}`);
    }
    variables[key] = String(value);
  }
  return variables;
}

async function pagedSelect(build: (from: number, to: number) => PromiseLike<any>) {
  const rows: any[] = [];
  for (let from = 0; from < MAX_RECIPIENTS; from += PAGE_SIZE) {
    const { data, error } = await build(from, from + PAGE_SIZE - 1);
    if (error) throw error;
    rows.push(...(data ?? []));
    if ((data ?? []).length < PAGE_SIZE) break;
  }
  return rows;
}

async function optedOutPhones(
  service: any,
  organizationId: string,
  organizationAddress: string,
) {
  const data = await pagedSelect((from, to) => service.from("contact_opt_outs")
    .select("contact_address").eq("organization_id", organizationId)
    .eq("organization_address", organizationAddress).eq("service", "whatsapp")
    .range(from, to));
  return new Set(data.map((item) => normalizePhone(item.contact_address)).filter(Boolean));
}

async function availableTags(service: any, organizationId: string) {
  const tags = await pagedSelect((from, to) => service.from("tags")
    .select("id,name,color").eq("organization_id", organizationId).order("name")
    .range(from, to));
  const memberships = await pagedSelect((from, to) => service.from("contact_tags")
    .select("tag_id").eq("organization_id", organizationId).range(from, to));
  const counts = new Map<string, number>();
  for (const item of memberships) counts.set(item.tag_id, (counts.get(item.tag_id) ?? 0) + 1);
  return tags.map((tag) => ({ ...tag, contacts_count: counts.get(tag.id) ?? 0 }));
}

async function recipientsForTags(service: any, organizationId: string, rawTagIds: unknown) {
  const tagIds = Array.isArray(rawTagIds) ? [...new Set(rawTagIds.map(String).filter(Boolean))] : [];
  let contactIds: string[] | null = null;
  if (tagIds.length) {
    const { data: ownedTags, error: tagsError } = await service.from("tags").select("id")
      .eq("organization_id", organizationId).in("id", tagIds);
    if (tagsError || (ownedTags ?? []).length !== tagIds.length) throw new Error("invalid_tag_selection");
    const memberships = await pagedSelect((from, to) => service.from("contact_tags")
      .select("contact_id").eq("organization_id", organizationId).in("tag_id", tagIds)
      .range(from, to));
    contactIds = [...new Set(memberships.map((item) => item.contact_id))];
    if (!contactIds.length) return { recipients: [], invalid: 0, duplicates: 0 };
  }

  const addresses: any[] = [];
  if (contactIds) {
    for (let offset = 0; offset < contactIds.length; offset += 500) {
      const chunk = contactIds.slice(offset, offset + 500);
      const page = await pagedSelect((from, to) => service.from("contacts_addresses")
        .select("address,contact_id,contacts!inner(name,email,extra)")
        .eq("organization_id", organizationId).eq("service", "whatsapp")
        .eq("status", "active").in("contact_id", chunk).range(from, to));
      addresses.push(...page);
    }
  } else {
    addresses.push(...await pagedSelect((from, to) => service.from("contacts_addresses")
      .select("address,contact_id,contacts!inner(name,email,extra)")
      .eq("organization_id", organizationId).eq("service", "whatsapp")
      .eq("status", "active").not("contact_id", "is", null).range(from, to)));
  }
  return normalizeRecipients(addresses.map((row) => ({
    phone: row.address,
    name: row.contacts?.name,
    email: row.contacts?.email,
    source: row.contacts?.extra ?? {},
  })));
}

async function validateTracking(
  service: any,
  organizationId: string,
  rawTracking: unknown,
) {
  if (!rawTracking || typeof rawTracking !== "object" || Array.isArray(rawTracking)) return null;
  const tracking = rawTracking as JsonObject;
  const projectId = String(tracking.project_id ?? "").trim();
  const destinationUrl = String(tracking.destination_url ?? "").trim();
  if (!projectId || !destinationUrl) throw new Error("invalid_tracking");
  let url: URL;
  try {
    url = new URL(destinationUrl);
  } catch {
    throw new Error("invalid_tracking_destination");
  }
  if (url.protocol !== "https:") throw new Error("invalid_tracking_destination");
  const { data: project, error } = await service.from("tracking_projects")
    .select("id,allowed_origins,status").eq("id", projectId)
    .eq("organization_id", organizationId).eq("status", "active").single();
  if (error || !project) throw new Error("tracking_project_unavailable");
  if (!(project.allowed_origins ?? []).includes(url.origin)) {
    throw new Error("tracking_destination_not_allowed");
  }
  return { project_id: projectId, destination_url: url.toString() };
}

async function persistImportedContacts(
  service: any,
  organizationId: string,
  recipients: NormalizedRecipient[],
  rawTagIds: unknown,
) {
  const requestedTagIds = Array.isArray(rawTagIds)
    ? [...new Set(rawTagIds.map(String).filter(Boolean))]
    : [];
  let tagIds: string[] = [];
  if (requestedTagIds.length) {
    const { data: tags, error } = await service.from("tags").select("id")
      .eq("organization_id", organizationId).eq("is_system", false)
      .in("id", requestedTagIds);
    if (error || (tags ?? []).length !== requestedTagIds.length) {
      throw new Error("invalid_import_tags");
    }
    tagIds = (tags ?? []).map((tag: { id: string }) => tag.id);
  }

  const linkedContactIds = new Set<string>();
  for (let offset = 0; offset < recipients.length; offset += 200) {
    const chunk = recipients.slice(offset, offset + 200);
    const phones = chunk.map((recipient) => recipient.phone);
    const { data: existing, error: existingError } = await service
      .from("contacts_addresses").select("address,contact_id")
      .eq("organization_id", organizationId).eq("service", "whatsapp")
      .in("address", phones);
    if (existingError) throw new Error("contact_import_lookup_failed");
    const byPhone = new Map<string, string | null>(
      (existing ?? []).map((row: { address: string; contact_id: string | null }) => [
        row.address,
        row.contact_id,
      ]),
    );
    for (const contactId of byPhone.values()) if (contactId) linkedContactIds.add(contactId);

    const unlinked = chunk.filter((recipient) => !byPhone.get(recipient.phone));
    if (!unlinked.length) continue;

    const missingAddresses = unlinked.filter((recipient) => !byPhone.has(recipient.phone));
    if (missingAddresses.length) {
      const { error: addressError } = await service.from("contacts_addresses")
        .upsert(missingAddresses.map((recipient) => ({
          organization_id: organizationId,
          service: "whatsapp",
          address: recipient.phone,
          status: "active",
        })), {
          onConflict: "organization_id,service,address",
          ignoreDuplicates: true,
        });
      if (addressError) throw new Error("contact_address_import_failed");
    }

    const { data: created, error: createError } = await service.from("contacts")
      .insert(unlinked.map((recipient) => ({
        organization_id: organizationId,
        name: recipient.display_name,
        email: recipient.source.email == null
          ? null
          : String(recipient.source.email).trim().toLocaleLowerCase(),
        extra: { campaign_import_phone: recipient.phone },
      }))).select("id,extra");
    if (createError) throw new Error("contact_import_failed");

    // Conditional linking preserves an existing contact if another import won
    // the race. Any unused contact created by this request is removed.
    await Promise.all((created ?? []).map(async (contact: {
      id: string;
      extra: JsonObject | null;
    }) => {
      const phone = String(contact.extra?.campaign_import_phone ?? "");
      const { data: linked, error: linkError } = await service
        .from("contacts_addresses").update({ contact_id: contact.id })
        .eq("organization_id", organizationId).eq("service", "whatsapp")
        .eq("address", phone).is("contact_id", null)
        .select("contact_id").maybeSingle();
      if (linkError) throw new Error("contact_link_failed");
      if (linked?.contact_id) linkedContactIds.add(linked.contact_id);
      else await service.from("contacts").delete().eq("id", contact.id)
        .eq("organization_id", organizationId);
    }));

    const { data: resolved, error: resolvedError } = await service
      .from("contacts_addresses").select("contact_id")
      .eq("organization_id", organizationId).eq("service", "whatsapp")
      .in("address", phones).not("contact_id", "is", null);
    if (resolvedError) throw new Error("contact_import_lookup_failed");
    for (const row of resolved ?? []) linkedContactIds.add(row.contact_id);
  }

  if (tagIds.length && linkedContactIds.size) {
    const memberships = [...linkedContactIds].flatMap((contactId) =>
      tagIds.map((tagId) => ({
        organization_id: organizationId,
        contact_id: contactId,
        tag_id: tagId,
        source: "campaign_import",
      }))
    );
    for (let offset = 0; offset < memberships.length; offset += 1_000) {
      const { error } = await service.from("contact_tags")
        .upsert(memberships.slice(offset, offset + 1_000), {
          onConflict: "organization_id,contact_id,tag_id",
          ignoreDuplicates: true,
        });
      if (error) throw new Error("contact_tag_import_failed");
    }
  }
}

async function previewAudience(service: any, body: JsonObject) {
  const organizationId = String(body.organization_id);
  const audience = body.audience && typeof body.audience === "object"
    ? body.audience as JsonObject
    : null;
  const normalized = audience?.type === "tags"
    ? await recipientsForTags(service, organizationId, audience.tag_ids)
    : normalizeRecipients(body.records ?? audience?.records ?? []);
  const address = normalizePhone(body.organization_address);
  const suppressed = address
    ? await optedOutPhones(service, organizationId, address)
    : new Set<string>();
  return {
    total: normalized.recipients.length + normalized.invalid + normalized.duplicates,
    eligible: normalized.recipients.filter((item) => !suppressed.has(item.phone)).length,
    invalid: normalized.invalid,
    duplicates: normalized.duplicates,
    opted_out: normalized.recipients.filter((item) => suppressed.has(item.phone)).length,
    ...(body.include_available_tags ? { tags: await availableTags(service, organizationId) } : {}),
  };
}

async function createCampaign(service: any, body: JsonObject, test: boolean) {
  const organizationId = String(body.organization_id);
  const organizationAddress = normalizePhone(body.organization_address);
  if (!organizationAddress) throw new Error("invalid_organization_address");
  const audience = body.audience && typeof body.audience === "object"
    ? body.audience as JsonObject
    : null;
  const normalized = test
    ? normalizeRecipients([body.test_recipient])
    : audience?.type === "tags"
    ? await recipientsForTags(service, organizationId, audience.tag_ids)
    : normalizeRecipients(audience?.records ?? body.records ?? []);
  const suppressed = await optedOutPhones(service, organizationId, organizationAddress);
  const eligible = normalized.recipients.filter((item) => !suppressed.has(item.phone));
  if (!eligible.length) throw new Error("no_eligible_recipients");

  if (!test && audience?.type === "import") {
    await persistImportedContacts(
      service,
      organizationId,
      normalized.recipients,
      audience.tag_ids,
    );
  }

  const templateInput = body.template && typeof body.template === "object"
    ? body.template as JsonObject
    : null;
  const snapshot = await getTemplateSnapshot(
    service,
    organizationId,
    organizationAddress,
    String(templateInput?.id ?? "").trim(),
  );
  const mapping = body.variable_mapping && typeof body.variable_mapping === "object" &&
      !Array.isArray(body.variable_mapping)
    ? body.variable_mapping as VariableMapping
    : {};
  const templatePayload = buildTemplatePayload(snapshot, mapping);
  const tracking = await validateTracking(service, organizationId, body.tracking);
  const recipientRows = eligible.map((item) => ({
    phone: item.phone,
    display_name: item.display_name,
    variables: resolveVariables(item, mapping),
  }));

  const { data: campaign, error } = await service.from("campaigns").insert({
    organization_id: organizationId,
    organization_address: organizationAddress,
    name: test ? `Teste: ${String(snapshot.name)}` : String(body.name ?? snapshot.name).trim(),
    template_id: String(snapshot.id),
    template_name: String(snapshot.name),
    template_language: String(snapshot.language),
    template_category: "UTILITY",
    template_status: "APPROVED",
    template_snapshot: snapshot,
    template_payload: templatePayload,
    tracking_project_id: tracking?.project_id ?? null,
    tracking_destination_url: tracking?.destination_url ?? null,
    total_cap: recipientRows.length,
    is_test: test,
  }).select("id,total_cap,status").single();
  if (error || !campaign) throw new Error("campaign_create_failed");
  const { error: recipientError } = await service.rpc("insert_campaign_recipients", {
    p_campaign_id: campaign.id,
    p_organization_id: organizationId,
    p_recipients: recipientRows,
  });
  if (recipientError) {
    await service.from("campaigns").delete().eq("id", campaign.id);
    throw new Error("campaign_recipient_create_failed");
  }
  if (test) {
    const { error: startError } = await service.from("campaigns").update({
      status: "running", started_at: new Date().toISOString(),
    }).eq("id", campaign.id).eq("status", "draft");
    if (startError) throw new Error("campaign_start_failed");
  }
  return {
    ...campaign,
    status: test ? "running" : campaign.status,
    excluded_opt_outs: normalized.recipients.length - eligible.length,
    invalid: normalized.invalid,
    duplicates: normalized.duplicates,
  };
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: JSON_HEADERS });
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  if (!request.headers.get("authorization")) {
    return json({ error: "unauthorized" }, 401);
  }
  try {
    const body = await request.json() as JsonObject;
    const action = String(body.action ?? "");
    const organizationId = String(body.organization_id ?? "");
    if (!organizationId) throw new Error("invalid_organization_id");
    await authorize(request, organizationId);
    const service = createUnsecureClient() as any;

    if (action === "preview_import") {
      return json({ data: await previewAudience(service, body) });
    }
    if (action === "audience_preview") {
      return json({ data: await previewAudience(service, {
        ...body,
        audience: { type: "tags", tag_ids: body.tag_ids },
      }) });
    }
    if (action === "create_campaign") return json({ data: await createCampaign(service, body, false) }, 201);
    if (action === "create_test") return json({ data: await createCampaign(service, body, true) }, 201);

    if (action === "list_campaigns") {
      const { data, error } = await service.rpc("get_campaign_summaries", {
        p_organization_id: organizationId,
      });
      if (error) throw new Error("campaign_list_failed");
      return json({ data: data ?? [] });
    }
    const campaignId = String(body.campaign_id ?? "");
    if (!campaignId) throw new Error("invalid_campaign_id");
    const { data: campaign, error: readError } = await service.from("campaigns")
      .select("*").eq("id", campaignId).eq("organization_id", organizationId).single();
    if (readError || !campaign) return json({ error: "not_found" }, 404);

    if (action === "get_campaign") {
      const page = Math.max(0, Number(body.page ?? 0) || 0);
      const { data: summary, error: summaryError } = await service.rpc("get_campaign_summaries", {
        p_organization_id: organizationId,
        p_campaign_id: campaignId,
      });
      const { data: recipients, error } = await service.from("campaign_recipients")
        .select("id,phone,display_name,status,message_id,error_code,submitted_at,created_at")
        .eq("campaign_id", campaignId).order("created_at")
        .range(page * PAGE_SIZE, (page + 1) * PAGE_SIZE - 1);
      if (error || summaryError) throw new Error("campaign_recipients_read_failed");
      return json({ data: { ...campaign, summary: summary?.[0] ?? null, recipients: recipients ?? [], page } });
    }
    if (action === "start_campaign") {
      const { count, error: countError } = await service.from("campaign_recipients")
        .select("id", { count: "exact", head: true }).eq("campaign_id", campaignId);
      if (countError || count !== campaign.total_cap) throw new Error("campaign_ceiling_mismatch");
      const { data, error } = await service.from("campaigns").update({
        status: "running", started_at: new Date().toISOString(),
      }).eq("id", campaignId).eq("status", "draft").select("*").maybeSingle();
      if (error || !data) throw new Error("campaign_not_startable");
      return json({ data });
    }
    if (action === "cancel_campaign") {
      const { data, error } = await service.from("campaigns").update({
        status: "cancel_requested", cancel_requested_at: new Date().toISOString(),
      }).eq("id", campaignId).eq("status", "running").select("*").maybeSingle();
      if (error || !data) throw new Error("campaign_not_cancellable");
      return json({ data });
    }
    return json({ error: "unknown_action" }, 400);
  } catch (error) {
    const reason = error instanceof Error ? error.message : "request_failed";
    const status = reason === "unauthorized" ? 401 : reason === "forbidden" ? 403
      : reason.startsWith("invalid_") || reason.startsWith("missing_") ||
          reason.includes("limit") || reason.includes("eligible") ||
          reason.includes("template_") || reason.startsWith("tracking_") ? 400 : 500;
    if (status === 500) console.error("Campaign management failed", { reason });
    return json({ error: status === 500 ? "request_failed" : reason }, status);
  }
});
