// send-push — fan a notification row out to a user's devices via FCM HTTP v1.
//
// Invoked by the Database Webhook on insert into public.notifications (payload
// `{ type, table, record, old_record }`), or called directly with the
// notification fields at the top level. Looks up the target user's tokens in
// public.user_devices (service role) and sends each one a message that carries
// both a `notification` block (shown by the OS in background/terminated) and a
// `data` block (for in-app tap routing).
//
// Deploy:   supabase functions deploy send-push --no-verify-jwt
// Secrets:  supabase secrets set \
//             FIREBASE_PROJECT_ID=... \
//             FIREBASE_CLIENT_EMAIL=...@...iam.gserviceaccount.com \
//             FIREBASE_PRIVATE_KEY="$(cat service-account-private-key.pem)"
//   (SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const FIREBASE_PROJECT_ID = Deno.env.get("FIREBASE_PROJECT_ID")!;
const FIREBASE_CLIENT_EMAIL = Deno.env.get("FIREBASE_CLIENT_EMAIL")!;
// Secrets store the PEM with literal "\n"; restore real newlines.
const FIREBASE_PRIVATE_KEY = (Deno.env.get("FIREBASE_PRIVATE_KEY") ?? "")
  .replace(/\\n/g, "\n");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function b64url(input: ArrayBuffer | string): string {
  const bytes = typeof input === "string"
    ? new TextEncoder().encode(input)
    : new Uint8Array(input);
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const der = Uint8Array.from(
    atob(
      pem
        .replace("-----BEGIN PRIVATE KEY-----", "")
        .replace("-----END PRIVATE KEY-----", "")
        .replace(/\s+/g, ""),
    ),
    (c) => c.charCodeAt(0),
  );
  return await crypto.subtle.importKey(
    "pkcs8",
    der.buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

// Mint a short-lived OAuth access token for the FCM scope from the service
// account, by signing a JWT (RS256) and exchanging it at Google's token endpoint.
let cachedToken: { value: string; exp: number } | null = null;
async function getAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.exp - 60 > now) return cachedToken.value;

  const header = { alg: "RS256", typ: "JWT" };
  const claim = {
    iss: FIREBASE_CLIENT_EMAIL,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };
  const unsigned = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(claim))}`;
  const key = await importPrivateKey(FIREBASE_PRIVATE_KEY);
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const jwt = `${unsigned}.${b64url(sig)}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  const body = await res.json();
  if (!res.ok) throw new Error(`token exchange failed: ${JSON.stringify(body)}`);
  cachedToken = { value: body.access_token, exp: now + 3600 };
  return body.access_token;
}

// Returns { invalid } — invalid means the token is dead and should be pruned.
async function sendToToken(
  accessToken: string,
  token: string,
  title: string,
  body: string,
  data: Record<string, unknown>,
): Promise<{ invalid: boolean }> {
  const strData: Record<string, string> = {};
  for (const [k, v] of Object.entries(data ?? {})) {
    strData[k] = typeof v === "string" ? v : JSON.stringify(v);
  }
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data: strData,
          android: {
            priority: "high",
            notification: { channel_id: "high_importance_channel" },
          },
          apns: {
            payload: { aps: { sound: "default", "content-available": 1 } },
          },
        },
      }),
    },
  );
  if (res.ok) return { invalid: false };
  const err = await res.json().catch(() => ({}));
  const status = err?.error?.status;
  // A stale/unregistered token is permanently dead — prune it.
  const invalid = res.status === 404 ||
    status === "NOT_FOUND" ||
    status === "UNREGISTERED";
  console.error(`FCM send failed (${res.status}/${status})`);
  return { invalid };
}

Deno.serve(async (req) => {
  try {
    const payload = await req.json().catch(() => ({}));
    // Webhook wraps the row in `record`; a direct call may pass fields flat.
    const record = payload.record ?? payload;
    const userId: string | undefined = record.user_id;
    const title: string | undefined = record.title;
    const body: string = record.body ?? "";
    const data: Record<string, unknown> = record.data ?? {};

    if (!userId || !title) {
      return json({ error: "user_id and title are required" }, 400);
    }

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
    const { data: devices, error } = await supabase
      .from("user_devices")
      .select("fcm_token")
      .eq("user_id", userId);
    if (error) throw error;

    const tokens = (devices ?? []).map((d) => d.fcm_token as string);
    if (tokens.length === 0) return json({ sent: 0, reason: "no devices" });

    const accessToken = await getAccessToken();
    const results = await Promise.all(
      tokens.map((t) => sendToToken(accessToken, t, title, body, data)),
    );

    // Prune tokens FCM rejected as permanently invalid.
    const dead = tokens.filter((_, i) => results[i].invalid);
    if (dead.length > 0) {
      await supabase.from("user_devices").delete().in("fcm_token", dead);
    }

    // Stamp the source notification row as sent (webhook path only).
    if (record.id) {
      await supabase
        .from("notifications")
        .update({ sent_at: new Date().toISOString() })
        .eq("id", record.id);
    }

    const sent = results.filter((r) => !r.invalid).length;
    return json({ sent, pruned: dead.length });
  } catch (e) {
    console.error(e);
    return json({ error: String(e) }, 500);
  }
});
