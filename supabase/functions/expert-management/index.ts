import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {
  createClient,
  createUnsecureClient,
} from "../_shared/supabase_client.ts";

const HEADERS = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers":
    "authorization, content-type, x-client-info, apikey",
  "access-control-allow-methods": "POST, OPTIONS",
  "content-type": "application/json",
};

function response(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: HEADERS });
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: HEADERS });
  }
  if (request.method !== "POST") {
    return response({ error: "method_not_allowed" }, 405);
  }
  if (!request.headers.get("authorization")) {
    return response({ error: "unauthorized" }, 401);
  }
  try {
    const client = createClient(request);
    const { data: { user }, error: userError } = await client.auth.getUser();
    if (userError || !user) return response({ error: "unauthorized" }, 401);
    const body = await request.json() as Record<string, unknown>;
    const organizationId = String(body.organization_id ?? "");
    const name = String(body.name ?? "").trim();
    const email = String(body.email ?? "").trim().toLocaleLowerCase();
    const projectIds = [
      ...new Set(
        (Array.isArray(body.project_ids) ? body.project_ids : []).map(String),
      ),
    ];
    if (!organizationId || !name || !/^\S+@\S+\.\S+$/u.test(email)) {
      return response({ error: "invalid_input" }, 400);
    }
    const { data: organizations, error: authError } = await client
      .rpc("get_authorized_orgs", { role: "admin" });
    if (authError || !(organizations ?? []).includes(organizationId)) {
      return response({ error: "forbidden" }, 403);
    }

    const service = createUnsecureClient() as any;
    if (projectIds.length) {
      const { data: projects, error } = await service.from("projects").select(
        "id",
      )
        .eq("organization_id", organizationId).in("id", projectIds);
      if (error || (projects ?? []).length !== projectIds.length) {
        return response({ error: "invalid_projects" }, 400);
      }
    }
    const { data: organization } = await service.from("organizations")
      .select("name").eq("id", organizationId).single();
    const { data: agent, error: agentError } = await service.from("agents")
      .insert({
        organization_id: organizationId,
        name,
        ai: false,
        extra: {
          role: "member",
          account_type: "expert",
          invitation: {
            organization_name: organization?.name ?? "",
            email,
            status: "pending",
          },
        },
      }).select("id,user_id").single();
    if (agentError || !agent) {
      return response({ error: "expert_create_failed" }, 409);
    }

    if (!agent.user_id) {
      const { error: inviteError } = await service.auth.admin.inviteUserByEmail(
        email,
      );
      if (inviteError) {
        await service.from("agents").delete().eq("id", agent.id);
        return response({ error: "auth_invite_failed" }, 502);
      }
    }
    if (projectIds.length) {
      const { error: membershipError } = await service.from(
        "project_memberships",
      )
        .insert(projectIds.map((projectId) => ({
          organization_id: organizationId,
          project_id: projectId,
          agent_id: agent.id,
          role: "expert",
        })));
      if (membershipError) {
        await service.from("agents").delete().eq("id", agent.id);
        return response({ error: "expert_membership_failed" }, 500);
      }
    }
    return response({ data: { id: agent.id } }, 201);
  } catch (error) {
    console.error("Expert management failed", {
      reason: error instanceof Error ? error.message : "request_failed",
    });
    return response({ error: "request_failed" }, 500);
  }
});
