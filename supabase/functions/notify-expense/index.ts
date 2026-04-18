import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { create, getNumericDate, type Header, type Payload } from "https://deno.land/x/djwt@v2.8/mod.ts";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-webhook-secret",
};

function pemToPkcs8Bytes(pem: string): Uint8Array {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s/g, "");
  const raw = atob(b64);
  const buf = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) buf[i] = raw.charCodeAt(i);
  return buf;
}

async function apnsJwt(): Promise<string> {
  const pem = Deno.env.get("APNS_AUTH_KEY_PEM");
  const keyId = Deno.env.get("APNS_KEY_ID");
  const teamId = Deno.env.get("APNS_TEAM_ID");
  if (!pem || !keyId || !teamId) {
    throw new Error("Missing APNS_AUTH_KEY_PEM, APNS_KEY_ID, or APNS_TEAM_ID");
  }
  const keyData = pemToPkcs8Bytes(pem);
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    keyData,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const header: Header = { alg: "ES256", kid: keyId };
  const payload: Payload = {
    iss: teamId,
    iat: getNumericDate(0),
  };
  return await create(header, payload, cryptoKey);
}

async function sendApns(
  deviceToken: string,
  topic: string,
  body: Record<string, unknown>,
): Promise<Response> {
  const jwt = await apnsJwt();
  const host = Deno.env.get("APNS_USE_SANDBOX") === "1"
    ? "https://api.sandbox.push.apple.com"
    : "https://api.push.apple.com";
  const url = `${host}/3/device/${deviceToken}`;
  return await fetch(url, {
    method: "POST",
    headers: {
      "authorization": `bearer ${jwt}`,
      "apns-topic": topic,
      "apns-push-type": "alert",
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

type WebhookBody = {
  type?: string;
  record?: {
    id?: string;
    group_id?: string;
    paid_by?: string;
    amount?: number;
    description?: string;
  };
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const webhookSecret = Deno.env.get("WEBHOOK_SECRET") ?? "";
  if (webhookSecret) {
    const headerSecret = req.headers.get("x-webhook-secret") ?? "";
    if (headerSecret !== webhookSecret) {
      return new Response(JSON.stringify({ error: "unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const topic = Deno.env.get("APNS_BUNDLE_ID")!;
  const supabase = createClient(supabaseUrl, serviceKey);

  let expenseId: string | undefined;
  try {
    const json = (await req.json()) as WebhookBody;
    expenseId = json.record?.id;
  } catch {
    return new Response(JSON.stringify({ error: "invalid json" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  if (!expenseId) {
    return new Response(JSON.stringify({ error: "missing expense id" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const { data: expense, error: expErr } = await supabase
    .from("expenses")
    .select("id, group_id, paid_by, amount, description")
    .eq("id", expenseId)
    .single();

  if (expErr || !expense) {
    return new Response(JSON.stringify({ error: expErr?.message ?? "expense not found" }), {
      status: 404,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const { data: payerProfile } = await supabase
    .from("profiles")
    .select("username")
    .eq("id", expense.paid_by)
    .single();

  const payerName = payerProfile?.username ?? "Someone";
  const amountStr = Number(expense.amount).toFixed(2);
  const title = "New expense";
  const alertBody =
    `${payerName} added ${expense.description || "an expense"} — $${amountStr}`;

  const { data: members, error: memErr } = await supabase
    .from("group_members")
    .select("user_id")
    .eq("group_id", expense.group_id)
    .neq("user_id", expense.paid_by);

  if (memErr) {
    return new Response(JSON.stringify({ error: memErr.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const userIds = (members ?? []).map((m: { user_id: string }) => m.user_id);
  if (userIds.length === 0) {
    return new Response(JSON.stringify({ ok: true, notified: 0 }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const { data: tokens, error: tokErr } = await supabase
    .from("push_tokens")
    .select("user_id, token")
    .in("user_id", userIds);

  if (tokErr) {
    return new Response(JSON.stringify({ error: tokErr.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  let notified = 0;
  const apnsBody = {
    aps: {
      alert: { title, body: alertBody },
      sound: "default",
    },
    expense_id: expense.id,
    group_id: expense.group_id,
  };

  for (const row of tokens ?? []) {
    const { user_id: uid, token } = row as { user_id: string; token: string };
    const { data: already } = await supabase
      .from("notification_log")
      .select("id")
      .eq("expense_id", expense.id)
      .eq("user_id", uid)
      .maybeSingle();
    if (already) continue;

    try {
      const apnsRes = await sendApns(token, topic, apnsBody);
      if (apnsRes.ok) {
        await supabase.from("notification_log").insert({
          expense_id: expense.id,
          user_id: uid,
        });
        notified++;
      } else {
        const t = await apnsRes.text();
        console.error("APNs error", apnsRes.status, t);
      }
    } catch (e) {
      console.error("notify failed", e);
    }
  }

  return new Response(JSON.stringify({ ok: true, notified }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});
