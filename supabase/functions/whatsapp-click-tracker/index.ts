import { createUnsecureClient } from "../_shared/supabase.ts";

const NO_STORE = { "cache-control": "no-store" };

Deno.serve(async (request) => {
  if (request.method !== "GET") {
    return new Response("Method not allowed", {
      status: 405,
      headers: NO_STORE,
    });
  }

  const url = new URL(request.url);
  const token = url.searchParams.get("t") ?? "";

  if (!/^[A-Za-z0-9_-]{20,128}$/.test(token)) {
    return new Response("Link invalid", { status: 404, headers: NO_STORE });
  }

  const client = createUnsecureClient();
  const { data: link, error } = await client
    .from("whatsapp_click_links")
    .select("id, destination_url, expires_at, disabled_at")
    .eq("token", token)
    .maybeSingle();

  if (
    error || !link || link.disabled_at ||
    (link.expires_at && new Date(link.expires_at).getTime() < Date.now())
  ) {
    return new Response("Link unavailable", { status: 404, headers: NO_STORE });
  }

  await client.from("whatsapp_click_events").insert({
    link_id: link.id,
    user_agent: request.headers.get("user-agent")?.slice(0, 512) ?? null,
  });

  return Response.redirect(link.destination_url, 302);
});
