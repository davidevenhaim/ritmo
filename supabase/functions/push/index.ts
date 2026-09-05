// SoGym push relay (v0.2, kinds extended in v0.3).
//
// Wire this as a Supabase Database Webhook on `insert` into public.notifications.
// It looks up the recipient's device tokens and sends one FCM message per
// device through the HTTP v1 API. Apple devices receive FCM via APNs when
// the Firebase project has the APNs key uploaded, so one path covers both.
//
// Secrets: FCM_SERVICE_ACCOUNT (JSON of a Firebase service account),
//          SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
// Deploy:  supabase functions deploy push --no-verify-jwt
//          (webhooks call with the service role key; we verify it ourselves)

import { createClient } from "npm:@supabase/supabase-js@2";

interface WebhookPayload {
  type: "INSERT";
  table: string;
  record: {
    id: string;
    user_id: string;
    actor_id: string | null;
    kind: "follow" | "like" | "recommend" | "comment" | "try" | "coach" | "video" | "moderation" | "creator" | "league" | "badge";
    post_id: string | null;
    routine_id: string | null;
    preview: string;
  };
}

const TITLES: Record<WebhookPayload["record"]["kind"], (actor: string) => string> = {
  follow: (a) => `${a} started following you`,
  like: (a) => `${a} liked your post`,
  recommend: (a) => `${a} recommended your post`,
  comment: (a) => `${a} commented`,
  try: (a) => `${a} tried your routine`,
  coach: () => "Your coach checked in",
  video: () => "Your video",
  moderation: () => "From the SoGym moderators",
  creator: () => "Creator studio",
  league: () => "League results",
  badge: () => "New badge",
};

Deno.serve(async (req) => {
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  if (req.headers.get("Authorization") !== `Bearer ${serviceKey}`) {
    return new Response("unauthorized", { status: 401 });
  }
  const payload = (await req.json()) as WebhookPayload;
  if (payload.type !== "INSERT" || payload.table !== "notifications") return new Response("ignored");

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, serviceKey);
  const [{ data: tokens }, { data: actor }] = await Promise.all([
    admin.from("push_tokens").select("token, platform").eq("user_id", payload.record.user_id),
    payload.record.actor_id
      ? admin.from("profiles").select("name").eq("id", payload.record.actor_id).single()
      : Promise.resolve({ data: null }),
  ]);
  if (!tokens?.length) return new Response("no devices");

  const title = TITLES[payload.record.kind](actor?.name ?? "Someone");
  const body = payload.record.preview;
  const accessToken = await fcmAccessToken();
  const sa = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT")!);
  const stale: string[] = [];

  await Promise.all(
    tokens.map(async ({ token }) => {
      const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
        method: "POST",
        headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          message: {
            token,
            notification: { title, body },
            data: {
              kind: payload.record.kind,
              post_id: payload.record.post_id ?? "",
              routine_id: payload.record.routine_id ?? "",
              notification_id: payload.record.id,
            },
            apns: { payload: { aps: { sound: "default", badge: 1 } } },
            android: { priority: "high" },
          },
        }),
      });
      if (res.status === 404 || res.status === 410) stale.push(token);
    }),
  );
  if (stale.length) await admin.from("push_tokens").delete().in("token", stale);
  return new Response(`sent ${tokens.length - stale.length}, pruned ${stale.length}`);
});

// --- Google service-account OAuth (RS256 JWT -> access token), no SDK needed.
let cached: { token: string; exp: number } | null = null;

async function fcmAccessToken(): Promise<string> {
  if (cached && cached.exp > Date.now() + 60_000) return cached.token;
  const sa = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT")!);
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(
    JSON.stringify({
      iss: sa.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    }),
  );
  const key = await crypto.subtle.importKey("pkcs8", pemToDer(sa.private_key), { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claims}`));
  const jwt = `${header}.${claims}.${b64url(sig)}`;
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: jwt }),
  });
  const data = await res.json();
  cached = { token: data.access_token, exp: Date.now() + data.expires_in * 1000 };
  return cached.token;
}

function b64url(input: string | ArrayBuffer): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : new Uint8Array(input);
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToDer(pem: string): ArrayBuffer {
  const b64 = pem.replace(/-----[A-Z ]+-----/g, "").replace(/\s+/g, "");
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out.buffer;
}
