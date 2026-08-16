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

type JsonObject = Record<string, unknown>;
type ExpertRecord = {
  id: string;
  organization_id: string;
  name: string;
  user_id: string | null;
  ai: boolean;
  extra: {
    account_type?: string;
    invitation?: {
      email?: string | null;
      status?: string;
      organization_name?: string;
    };
  } | null;
};

function response(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: HEADERS });
}

function emailValue(value: unknown): string | null {
  const email = String(value ?? "").trim().toLocaleLowerCase();
  if (!email) return null;
  return /^\S+@\S+\.\S+$/u.test(email) ? email : null;
}

function uniqueIds(value: unknown): string[] {
  return [
    ...new Set(
      (Array.isArray(value) ? value : []).map(String).filter(Boolean),
    ),
  ];
}

async function validateProjects(
  service: any,
  organizationId: string,
  projectIds: string[],
) {
  if (!projectIds.length) return;
  const { data, error } = await service.from("projects").select("id")
    .eq("organization_id", organizationId).in("id", projectIds);
  if (error || (data ?? []).length !== projectIds.length) {
    throw new Error("invalid_projects");
  }
}

async function replaceMemberships(
  service: any,
  organizationId: string,
  expertId: string,
  projectIds: string[],
) {
  await validateProjects(service, organizationId, projectIds);
  const current = await service.from("project_memberships").select("project_id")
    .eq("organization_id", organizationId).eq("agent_id", expertId);
  if (current.error) throw new Error("expert_membership_failed");
  const remove = (current.data ?? []).map((item: { project_id: string }) =>
    item.project_id
  ).filter((id: string) => !projectIds.includes(id));
  if (remove.length) {
    const removed = await service.from("project_memberships").delete()
      .eq("organization_id", organizationId).eq("agent_id", expertId)
      .in("project_id", remove);
    if (removed.error) throw new Error("expert_membership_failed");
  }
  if (projectIds.length) {
    const upserted = await service.from("project_memberships").upsert(
      projectIds.map((projectId) => ({
        organization_id: organizationId,
        project_id: projectId,
        agent_id: expertId,
        role: "expert",
      })),
      { onConflict: "organization_id,project_id,agent_id" },
    );
    if (upserted.error) throw new Error("expert_membership_failed");
  }
}

async function getExpert(
  service: any,
  organizationId: string,
  expertId: string,
): Promise<ExpertRecord> {
  const { data, error } = await service.from("agents")
    .select("id,organization_id,name,user_id,ai,extra")
    .eq("organization_id", organizationId).eq("id", expertId).single();
  if (
    error || !data || data.ai !== false ||
    data.extra?.account_type !== "expert"
  ) throw new Error("expert_not_found");
  return data as ExpertRecord;
}

async function ensureUniqueEmail(
  service: any,
  organizationId: string,
  expertId: string | null,
  email: string,
) {
  let query = service.from("agents").select("id")
    .eq("organization_id", organizationId)
    .filter("extra->invitation->>email", "ilike", email);
  if (expertId) query = query.neq("id", expertId);
  const { data, error } = await query.limit(1);
  if (error) throw new Error("expert_lookup_failed");
  if (data?.length) throw new Error("expert_email_exists");
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

    const body = await request.json() as JsonObject;
    const action = String(body.action ?? "create");
    const organizationId = String(body.organization_id ?? "");
    if (!organizationId) return response({ error: "invalid_input" }, 400);

    const { data: organizations, error: authError } = await client
      .rpc("get_authorized_orgs", { role: "admin" });
    if (authError || !(organizations ?? []).includes(organizationId)) {
      return response({ error: "forbidden" }, 403);
    }

    const service = createUnsecureClient() as any;
    const { data: organization, error: organizationError } = await service
      .from("organizations").select("name").eq("id", organizationId).single();
    if (organizationError || !organization) {
      return response({ error: "invalid_organization" }, 400);
    }

    if (action === "create") {
      const name = String(body.name ?? "").trim();
      const rawEmail = String(body.email ?? "").trim();
      const email = emailValue(rawEmail);
      const projectIds = uniqueIds(body.project_ids);
      if (!name || (rawEmail && !email)) {
        return response({ error: "invalid_input" }, 400);
      }
      if (email) await ensureUniqueEmail(service, organizationId, null, email);
      await validateProjects(service, organizationId, projectIds);

      const status = email ? "pending" : "draft";
      const { data: expert, error } = await service.from("agents").insert({
        organization_id: organizationId,
        user_id: null,
        name,
        ai: false,
        extra: {
          role: "member",
          account_type: "expert",
          invitation: {
            organization_name: organization.name ?? "",
            email,
            status,
          },
        },
      }).select("id,user_id").single();
      if (error || !expert) {
        return response({ error: "expert_create_failed" }, 409);
      }

      let invitedUserId: string | null = expert.user_id;
      let createdAuthUser = false;
      if (email && !invitedUserId) {
        const invited = await service.auth.admin.inviteUserByEmail(email);
        if (invited.error || !invited.data.user) {
          await service.from("agents").delete().eq("id", expert.id);
          return response({ error: "auth_invite_failed" }, 502);
        }
        invitedUserId = invited.data.user.id;
        createdAuthUser = true;
      }
      if (invitedUserId && invitedUserId !== expert.user_id) {
        const linked = await service.from("agents").update({
          user_id: invitedUserId,
        }).eq("id", expert.id);
        if (linked.error) {
          if (createdAuthUser) {
            await service.auth.admin.deleteUser(invitedUserId);
          }
          return response({ error: "expert_link_failed" }, 500);
        }
      }
      try {
        await replaceMemberships(
          service,
          organizationId,
          expert.id,
          projectIds,
        );
      } catch {
        await service.from("agents").delete().eq("id", expert.id);
        if (createdAuthUser && invitedUserId) {
          await service.auth.admin.deleteUser(invitedUserId);
        }
        return response({ error: "expert_membership_failed" }, 500);
      }
      return response({ data: { id: expert.id, status } }, 201);
    }

    const expertId = String(body.expert_id ?? "");
    if (!expertId) return response({ error: "invalid_input" }, 400);
    const expert = await getExpert(service, organizationId, expertId);
    const invitation = expert.extra?.invitation ?? {};
    const currentStatus = String(invitation.status ?? "");
    const currentEmail = emailValue(invitation.email);

    if (action === "update") {
      const changes: JsonObject = {};
      if (body.name !== undefined) {
        const name = String(body.name ?? "").trim();
        if (!name) return response({ error: "invalid_input" }, 400);
        changes.name = name;
      }
      if (body.email !== undefined) {
        const rawEmail = String(body.email ?? "").trim();
        const email = emailValue(rawEmail);
        if (rawEmail && !email) {
          return response({ error: "invalid_input" }, 400);
        }
        if (currentStatus !== "draft" && email !== currentEmail) {
          return response({ error: "expert_email_locked" }, 409);
        }
        if (email) {
          await ensureUniqueEmail(service, organizationId, expertId, email);
        }
        changes.extra = {
          invitation: {
            ...invitation,
            email,
            status: currentStatus,
            organization_name: invitation.organization_name ??
              organization.name ?? "",
          },
        };
      }
      if (Object.keys(changes).length) {
        const updated = await service.from("agents").update(changes).eq(
          "id",
          expertId,
        );
        if (updated.error) {
          return response({ error: "expert_update_failed" }, 409);
        }
      }
      if (body.project_ids !== undefined) {
        await replaceMemberships(
          service,
          organizationId,
          expertId,
          uniqueIds(body.project_ids),
        );
      }
      return response({ data: { id: expertId, status: currentStatus } });
    }

    if (action === "activate") {
      if (currentStatus !== "draft" || expert.user_id) {
        return response({ error: "expert_not_draft" }, 409);
      }
      const mode = String(body.mode ?? "invite");
      const email = emailValue(body.email ?? currentEmail);
      if (!email || !["invite", "password"].includes(mode)) {
        return response({ error: "invalid_activation" }, 400);
      }
      const activationPassword = typeof body.password === "string"
        ? body.password
        : "";
      if (mode === "password" && activationPassword.length < 8) {
        return response({ error: "invalid_password" }, 400);
      }
      await ensureUniqueEmail(service, organizationId, expertId, email);
      if (body.project_ids !== undefined) {
        await replaceMemberships(
          service,
          organizationId,
          expertId,
          uniqueIds(body.project_ids),
        );
      }
      const emailUpdate = await service.from("agents").update({
        extra: {
          invitation: {
            ...invitation,
            email,
            status: currentStatus,
            organization_name: invitation.organization_name ??
              organization.name ?? "",
          },
        },
      }).eq("id", expertId);
      if (emailUpdate.error) {
        return response({ error: "expert_update_failed" }, 409);
      }

      let authUserId: string;
      if (mode === "invite") {
        const invited = await service.auth.admin.inviteUserByEmail(email);
        if (invited.error || !invited.data.user) {
          return response({ error: "auth_invite_failed" }, 502);
        }
        authUserId = invited.data.user.id;
      } else {
        const created = await service.auth.admin.createUser({
          email,
          password: activationPassword,
          email_confirm: true,
          user_metadata: { full_name: expert.name },
        });
        if (created.error || !created.data.user) {
          return response({ error: "auth_create_failed" }, 502);
        }
        authUserId = created.data.user.id;
      }

      const nextStatus = mode === "invite" ? "pending" : "accepted";
      const activated = await service.from("agents").update({
        user_id: authUserId,
        extra: {
          invitation: {
            ...invitation,
            email,
            status: nextStatus,
            organization_name: invitation.organization_name ??
              organization.name ?? "",
          },
        },
      }).eq("id", expertId);
      if (activated.error) {
        await service.from("agents").update({ user_id: null }).eq(
          "id",
          expertId,
        );
        await service.auth.admin.deleteUser(authUserId);
        return response({ error: "expert_activation_failed" }, 500);
      }
      return response({ data: { id: expertId, status: nextStatus } });
    }

    if (action === "set_password") {
      const password = typeof body.password === "string" ? body.password : "";
      if (
        !expert.user_id || currentStatus !== "accepted" || password.length < 8
      ) {
        return response({ error: "invalid_password" }, 400);
      }
      const changed = await service.auth.admin.updateUserById(expert.user_id, {
        password,
      });
      if (changed.error) {
        return response({ error: "password_update_failed" }, 502);
      }
      return response({ data: { id: expertId, status: currentStatus } });
    }

    return response({ error: "invalid_action" }, 400);
  } catch (error) {
    const reason = error instanceof Error ? error.message : "request_failed";
    const known = new Set([
      "invalid_projects",
      "expert_not_found",
      "expert_email_exists",
      "expert_membership_failed",
    ]);
    console.error("Expert management failed", { reason });
    return response(
      { error: known.has(reason) ? reason : "request_failed" },
      known.has(reason) ? 400 : 500,
    );
  }
});
