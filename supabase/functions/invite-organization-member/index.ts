import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return Response.json(body, { status, headers: corsHeaders });
}

function invitationError(error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  const lower = message.toLowerCase();
  let code = "invitation_failed";
  if (lower.includes("invitation_nickname_conflict") ||
      (lower.includes("nickname") &&
        (lower.includes("registered") || lower.includes("duplicate")))) {
    code = "nickname_conflict";
  } else if (lower.includes("invitation_email_conflict") ||
      (lower.includes("email") && lower.includes("pending"))) {
    code = "email_conflict";
  } else if (lower.includes("invitation_user_already_member") ||
      (lower.includes("already") && lower.includes("organization"))) {
    code = "already_member";
  } else if (lower.includes("invitation_seat_limit") ||
      (lower.includes("seat") && lower.includes("limit"))) {
    code = "seat_limit";
  } else if (lower.includes("invitation_access_denied") ||
      lower.includes("administration access")) {
    code = "access_denied";
  } else if (lower.includes("invitation_invalid_email")) {
    code = "invalid_email";
  } else if (lower.includes("invitation_invalid_nickname")) {
    code = "invalid_nickname";
  } else if (lower.includes("pgrst202")) {
    code = "server_not_ready";
  }
  return { code, message };
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const authorization = request.headers.get("Authorization");
  if (!supabaseUrl || !anonKey || !serviceRoleKey || !authorization) {
    return json({ error: "Server configuration is incomplete" }, 500);
  }

  try {
    const body = await request.json();
    const organizationId = String(body.organizationId ?? "");
    const email = String(body.email ?? "").trim().toLowerCase();
    const nickname = String(body.nickname ?? "").trim().toLowerCase();
    const displayName = String(body.displayName ?? "").trim();
    const role = String(body.role ?? "");
    const customerId = String(body.customerId ?? "").trim();
    const functions = Array.isArray(body.functions)
      ? body.functions.map(String)
      : [];
    const redirectUrl = String(body.redirectUrl ?? "").trim();

    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false },
    });
    const { data: invitation, error: invitationError } =
      await callerClient.rpc("create_organization_invitation_v1", {
        target_organization: organizationId,
        target_email: email,
        target_nickname: nickname,
        target_display_name: displayName,
        target_role: role,
        target_functions: functions,
      });
    if (invitationError) throw invitationError;

    const invitationId = String(invitation.invitation_id);
    if (customerId) {
      const { error: customerLinkError } = await callerClient.rpc(
        "attach_organization_invitation_customer_v1",
        {
          target_invitation: invitationId,
          target_customer: customerId,
        },
      );
      if (customerLinkError) {
        await callerClient.rpc("cancel_organization_invitation_v1", {
          target_invitation: invitationId,
        });
        throw customerLinkError;
      }
    }
    const effectiveNickname = String(invitation.nickname);
    const isRegistered = invitation.is_registered === true;
    const existingUserId = invitation.user_id
      ? String(invitation.user_id)
      : null;
    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });
    const redirectOptions = redirectUrl
      ? { emailRedirectTo: redirectUrl }
      : {};

    let deliveryError: Error | null = null;
    if (isRegistered) {
      if (existingUserId) {
        const { data: existingUser, error: readUserError } =
          await adminClient.auth.admin.getUserById(existingUserId);
        if (readUserError) {
          deliveryError = readUserError;
        } else {
          const metadata = existingUser.user.user_metadata ?? {};
          const { error: updateUserError } =
            await adminClient.auth.admin.updateUserById(existingUserId, {
              user_metadata: {
                ...metadata,
                nickname: metadata.nickname || effectiveNickname,
                display_name: metadata.display_name || displayName,
                organization_invite_setup: true,
              },
            });
          deliveryError = updateUserError;
        }
      }
      const publicClient = createClient(supabaseUrl, anonKey, {
        auth: { persistSession: false },
      });
      if (!deliveryError) {
        const { error } = await publicClient.auth.signInWithOtp({
          email,
          options: {
            shouldCreateUser: false,
            ...redirectOptions,
          },
        });
        deliveryError = error;
      }
    } else {
      const { error } = await adminClient.auth.admin.inviteUserByEmail(email, {
        data: {
          nickname: effectiveNickname,
          display_name: displayName,
          organization_invite_setup: true,
        },
        ...(redirectUrl ? { redirectTo: redirectUrl } : {}),
      });
      deliveryError = error;
    }

    await adminClient
      .from("organization_invitations")
      .update({
        delivery_status: deliveryError ? "failed" : "sent",
        delivery_error: deliveryError ? deliveryError.message : null,
        updated_at: new Date().toISOString(),
      })
      .eq("id", invitationId);

    if (deliveryError) {
      return json(
        {
          error: "Invitation was saved, but the email could not be sent",
          code: "delivery_failed",
          details: deliveryError.message,
          invitationId,
        },
        502,
      );
    }

    return json({
      invitationId,
      email,
      nickname: effectiveNickname,
      isRegistered,
      emailSent: true,
      recovered: invitation.recovered === true,
      customerId: customerId || null,
    });
  } catch (error) {
    const failure = invitationError(error);
    return json(
      {
        error: failure.message,
        code: failure.code,
      },
      400,
    );
  }
});
