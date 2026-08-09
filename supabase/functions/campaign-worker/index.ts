import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createUnsecureClient } from "../_shared/supabase_client.ts";
import { tokenHashAsBytea } from "../tracking-utils/index.ts";

const INTERNAL_TOKEN = Deno.env.get("OPENBSP_INTERNAL_DISPATCH_TOKEN") || "";
const BATCH_SIZE = 50;

type JsonObject = Record<string, unknown>;

function opaqueToken() {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes)).replace(/\+/gu, "-")
    .replace(/\//gu, "_").replace(/=+$/gu, "");
}

function substitute(value: unknown, variables: JsonObject): unknown {
  if (typeof value === "string") {
    return value.replace(/\{\{([a-zA-Z0-9_.-]+)\}\}/gu, (_match, key: string) =>
      variables[key] === undefined || variables[key] === null
        ? ""
        : String(variables[key])
    );
  }
  if (Array.isArray(value)) return value.map((item) => substitute(item, variables));
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value as JsonObject).map(([key, item]) => [
      key,
      substitute(item, variables),
    ]));
  }
  return value;
}

Deno.serve(async (request) => {
  const token = request.headers.get("authorization")?.replace(/^Bearer\s+/iu, "").trim();
  if (!INTERNAL_TOKEN || token !== INTERNAL_TOKEN) {
    return new Response("Unauthorized", { status: 401 });
  }

  const client = createUnsecureClient() as any;
  const { data: claimed, error: claimError } = await client.rpc(
    "claim_campaign_recipient_batch",
    { p_limit: BATCH_SIZE },
  );
  if (claimError) {
    console.error("Campaign batch claim failed", { code: claimError.code });
    return Response.json({ error: "claim_failed" }, { status: 500 });
  }

  const campaigns = new Map<string, JsonObject>();
  let submitted = 0;
  let failed = 0;
  let ambiguous = 0;

  for (const recipient of claimed ?? []) {
    try {
      let campaign = campaigns.get(recipient.campaign_id);
      if (!campaign) {
        const { data, error } = await client.from("campaigns").select("*")
          .eq("id", recipient.campaign_id).single();
        if (error || !data) throw new Error("campaign_not_found");
        campaign = data;
        campaigns.set(recipient.campaign_id, data);
      }
      if (!campaign) throw new Error("campaign_not_found");
      // Cancellation is authoritative between every recipient, even when
      // multiple recipients from the same campaign are in one claimed batch.
      const { data: currentCampaign, error: currentCampaignError } = await client
        .from("campaigns").select("status").eq("id", recipient.campaign_id)
        .single();
      if (currentCampaignError || currentCampaign?.status !== "running") {
        await client.from("campaign_recipients").update({
          status: "cancelled", error_code: "campaign_cancelled",
        }).eq("id", recipient.id).eq("status", "processing");
        continue;
      }

      const variables: JsonObject = { ...(recipient.variables ?? {}) };
      let trackingLinkId: string | null = null;
      if (campaign.tracking_project_id && campaign.tracking_destination_url) {
        const trackingToken = opaqueToken();
        const { data: linkResult, error: linkError } = await client.rpc(
          "create_tracking_link",
          {
            p_organization_id: campaign.organization_id,
            p_project_id: campaign.tracking_project_id,
            p_token_hash: await tokenHashAsBytea(trackingToken),
            p_destination_url: campaign.tracking_destination_url,
            p_expires_at: new Date(Date.now() + 90 * 86_400_000).toISOString(),
            p_idempotency_key: `campaign:${campaign.id}:recipient:${recipient.id}`,
            // The message does not exist yet and tracking_links has a foreign
            // key to messages. Attach it immediately after the deterministic
            // message insert below.
            p_message_id: undefined,
            p_source: "whatsapp",
            p_attribution: {
              campaign_id: campaign.id,
              campaign_recipient_id: recipient.id,
            },
          },
        );
        if (linkError || !linkResult?.[0]?.token_matches) {
          throw new Error("tracking_link_failed");
        }
        trackingLinkId = linkResult[0].tracking_link_id;
        const base = Deno.env.get("SUPABASE_URL")?.replace(/\/$/u, "");
        if (!base) throw new Error("tracking_url_unavailable");
        const destination = new URL(String(campaign.tracking_destination_url));
        const destinationPath = destination.pathname.replace(/^\/+/, "") || "";
        variables.tracking_token = trackingToken;
        variables.tracking_url = `${base}/functions/v1/tracking-redirect/r/${trackingToken}`;
        variables.tracking_suffix =
          `${destinationPath}${destination.search}#obsp=${trackingToken}`;
      }

      const payload = substitute(campaign.template_payload, variables) as JsonObject;
      // template_payload is a server-generated immutable blueprint. Never
      // accept name/language/components from the browser at dispatch time.
      const templateData = payload;
      const { error: messageError } = await client.from("messages").insert({
        id: recipient.message_id,
        organization_id: campaign.organization_id,
        direction: "outgoing",
        service: "whatsapp",
        organization_address: campaign.organization_address,
        contact_address: recipient.phone,
        content: {
          version: "1",
          type: "data",
          kind: "template",
          data: templateData,
        },
      });
      if (messageError && messageError.code !== "23505") {
        // An unavailable database response can be ambiguous. Confirm by the
        // deterministic UUID; never put the row back in queued automatically.
        const { data: existing, error: verifyError } = await client.from("messages")
          .select("id").eq("id", recipient.message_id).maybeSingle();
        if (verifyError || !existing) throw new Error("message_insert_ambiguous");
      }
      if (trackingLinkId) {
        const { error: attachError } = await client.from("tracking_links").update({
          message_id: recipient.message_id,
        }).eq("id", trackingLinkId).is("message_id", null);
        if (attachError) throw new Error("tracking_attach_ambiguous");
      }
      const { error: updateError } = await client.from("campaign_recipients").update({
        status: "submitted", submitted_at: new Date().toISOString(),
        tracking_link_id: trackingLinkId, error_code: null,
      }).eq("id", recipient.id).eq("status", "processing");
      if (updateError) throw new Error("recipient_commit_ambiguous");
      submitted++;
    } catch (error) {
      const reason = error instanceof Error ? error.message : "worker_failed";
      const isAmbiguous = reason.includes("ambiguous");
      await client.from("campaign_recipients").update({
        status: isAmbiguous ? "ambiguous" : "failed",
        error_code: reason.slice(0, 100),
      }).eq("id", recipient.id).eq("status", "processing");
      if (isAmbiguous) ambiguous++;
      else failed++;
      console.error("Campaign recipient failed", {
        campaign_id: recipient.campaign_id,
        recipient_id: recipient.id,
        reason,
      });
    }
  }

  await client.rpc("mark_stale_campaign_claims");
  await client.rpc("finish_campaigns");
  return Response.json({ claimed: claimed?.length ?? 0, submitted, failed, ambiguous });
});
