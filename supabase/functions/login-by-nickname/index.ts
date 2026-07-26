import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return Response.json(body, { status, headers: corsHeaders });
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
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return json({ error: "Server configuration is incomplete" }, 500);
  }

  try {
    const body = await request.json();
    const nickname = String(body.nickname ?? "").trim().toLowerCase();
    const password = String(body.password ?? "");
    if (!/^[a-z0-9_]{3,24}$/.test(nickname) || password.length < 1) {
      return json({ error: "Invalid nickname or password" }, 400);
    }

    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });
    const { data: profile } = await adminClient
      .from("user_profiles")
      .select("email")
      .eq("nickname", nickname)
      .maybeSingle();
    const email = profile?.email;
    if (!email) {
      return json({ error: "Invalid nickname or password" }, 401);
    }

    const publicClient = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false },
    });
    const { data, error } = await publicClient.auth.signInWithPassword({
      email,
      password,
    });
    if (error || !data.session) {
      return json({ error: "Invalid nickname or password" }, 401);
    }

    return json({
      refreshToken: data.session.refresh_token,
    });
  } catch {
    return json({ error: "Invalid nickname or password" }, 401);
  }
});
