// SoGym video edge function (v0.3).
//
// Uploads go straight from the phone to Cloudflare Stream or Mux; this
// function only hands out one-time upload tickets and receives the provider's
// webhook when transcoding finishes. It is the only writer of the `videos`
// table (service role).
//
//   POST /functions/v1/video/create     Authorization: Bearer <supabase jwt>
//        { "filename": "clip.mp4", "duration_sec": 42, "exercise_ids": ["Pushups"] }
//     -> { "video_id": "…", "upload_url": "…", "method": "form" | "put", "provider": "cloudflare" }
//   POST /functions/v1/video/delete     Authorization: Bearer <supabase jwt>
//        { "video_id": "…" }
//   POST /functions/v1/video/webhook    (Cloudflare Webhook-Signature / Mux-Signature)
//
// Secrets: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY,
//          VIDEO_PROVIDER + provider keys (see _shared/video_provider.ts),
//          ANTHROPIC_API_KEY (optional, enables automated screening),
//          VIDEO_UPLOADS_OPEN=1 to let every member upload (default: creators only)
// Deploy:  supabase functions deploy video --no-verify-jwt
//          (the webhook has no user JWT; /create validates its own)

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { MAX_DURATION_SEC, providerFromEnv, type ReadyEvent, type VideoProvider } from "../_shared/video_provider.ts";
import { screenFrames } from "../_shared/screen.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const route = new URL(req.url).pathname.split("/").filter(Boolean).pop() ?? "";
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  let provider: VideoProvider;
  try {
    provider = providerFromEnv((k) => Deno.env.get(k));
  } catch (e) {
    return json({ error: (e as Error).message }, 500);
  }

  try {
    switch (route) {
      case "create":
        return await create(req, admin, provider);
      case "delete":
        return await remove(req, admin, provider);
      case "webhook":
        return await webhook(req, admin, provider);
      default:
        return json({ error: `unknown route ${route}` }, 404);
    }
  } catch (e) {
    console.error(e);
    return json({ error: (e as Error).message }, 500);
  }
});

// ------------------------------------------------------------------ create
async function create(req: Request, admin: SupabaseClient, provider: VideoProvider): Promise<Response> {
  const user = await callerId(req);
  if (!user) return json({ error: "Sign in to upload video" }, 401);

  const { data: profile } = await admin.from("profiles").select("creator, banned").eq("id", user).single();
  if (!profile) return json({ error: "Profile not found" }, 404);
  if (profile.banned) return json({ error: "This account cannot upload" }, 403);
  const open = Deno.env.get("VIDEO_UPLOADS_OPEN") === "1";
  if (!open && !profile.creator) {
    return json({ error: "Video uploads are open to creators first. Apply from Creator studio.", code: "creators_only" }, 403);
  }

  let body: { filename?: string; duration_sec?: number; exercise_ids?: string[] };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Body must be JSON" }, 400);
  }
  const duration = Number(body.duration_sec ?? 0);
  if (duration > MAX_DURATION_SEC + 0.5) {
    return json({ error: `Clips are capped at ${MAX_DURATION_SEC} seconds. Trim it and try again.`, code: "too_long" }, 400);
  }
  const exerciseIds = (body.exercise_ids ?? []).filter((s) => typeof s === "string").slice(0, 8);

  const { data: row, error } = await admin
    .from("videos")
    .insert({ author_id: user, provider: provider.name, status: "uploading", duration_sec: duration || null, exercise_ids: exerciseIds })
    .select("id")
    .single();
  if (error || !row) return json({ error: `Could not register video: ${error?.message}` }, 500);

  try {
    const ticket = await provider.createUpload({ userId: user, videoId: row.id, filename: body.filename ?? "clip.mp4" });
    await admin.from("videos").update({ provider_uid: ticket.providerUid, upload_id: ticket.uploadId, status: "processing" }).eq("id", row.id);
    return json({ video_id: row.id, upload_url: ticket.uploadUrl, method: ticket.method, provider: provider.name });
  } catch (e) {
    await admin.from("videos").update({ status: "failed", error: (e as Error).message }).eq("id", row.id);
    throw e;
  }
}

// ------------------------------------------------------------------ delete
async function remove(req: Request, admin: SupabaseClient, provider: VideoProvider): Promise<Response> {
  const user = await callerId(req);
  if (!user) return json({ error: "Sign in" }, 401);
  const { video_id } = await req.json();
  const { data: v } = await admin.from("videos").select("id, author_id, provider_uid").eq("id", video_id).single();
  if (!v || v.author_id !== user) return json({ error: "Not your video" }, 403);
  if (v.provider_uid) await provider.remove(v.provider_uid);
  await admin.from("videos").update({ status: "removed" }).eq("id", v.id);
  return json({ ok: true });
}

// ----------------------------------------------------------------- webhook
async function webhook(req: Request, admin: SupabaseClient, provider: VideoProvider): Promise<Response> {
  const raw = await req.text();
  if (!(await provider.verifyWebhook(req, raw))) return json({ error: "bad signature" }, 401);
  const event = provider.parseWebhook(raw);

  if (event.kind === "ignored") return json({ ok: true, ignored: event.reason });

  if (event.kind === "link") {
    await admin.from("videos").update({ provider_uid: event.providerUid }).eq("upload_id", event.uploadId).eq("provider", provider.name);
    return json({ ok: true });
  }

  // Find our row by provider uid, falling back to the upload id (Mux).
  let q = admin.from("videos").select("id, author_id, status").eq("provider", provider.name);
  q = event.providerUid ? q.eq("provider_uid", event.providerUid) : q.eq("upload_id", event.uploadId!);
  const { data: video } = await q.maybeSingle();
  if (!video) return json({ ok: true, ignored: "unknown video" });
  if (video.status === "removed") return json({ ok: true, ignored: "removed" });

  if (event.kind === "failed") {
    await admin.from("videos").update({ status: "failed", error: event.error.slice(0, 300) }).eq("id", video.id);
    return json({ ok: true });
  }

  return await ready(admin, provider, video.id, event);
}

async function ready(admin: SupabaseClient, provider: VideoProvider, videoId: string, e: ReadyEvent): Promise<Response> {
  if (e.durationSec != null && e.durationSec > MAX_DURATION_SEC + 0.5) {
    // Cloudflare enforces the cap at upload; Mux does not, so enforce it here.
    await provider.remove(e.providerUid);
    await admin.from("videos").update({ status: "failed", error: `Clip is ${Math.round(e.durationSec)}s; the cap is ${MAX_DURATION_SEC}s` }).eq("id", videoId);
    return json({ ok: true, rejected: "too long" });
  }

  const patch: Record<string, unknown> = {
    status: "ready",
    provider_uid: e.providerUid,
    duration_sec: e.durationSec != null ? Math.min(e.durationSec, MAX_DURATION_SEC) : null,
    width: e.width,
    height: e.height,
    playback_url: e.playbackUrl,
    thumbnail_url: e.thumbnailUrl,
  };

  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (apiKey) {
    try {
      const verdict = await screenFrames(apiKey, e.frames);
      patch.screen = verdict;
      if (!verdict.safe) {
        // An `automated` report hides the post through the reports trigger.
        const { data: post } = await admin.from("posts").select("id").eq("video_id", videoId).maybeSingle();
        if (post) {
          await admin.from("reports").insert({
            reporter_id: null,
            target_kind: "post",
            target_id: post.id,
            reason: "automated",
            details: `${verdict.categories.join(", ")}: ${verdict.note}`.slice(0, 500),
          });
        }
      }
    } catch (err) {
      console.error("screening failed", err);
      patch.screen = { safe: true, categories: [], note: `screening error: ${(err as Error).message}`.slice(0, 300) };
    }
  }

  await admin.from("videos").update(patch).eq("id", videoId);
  return json({ ok: true });
}

// ----------------------------------------------------------------- helpers
async function callerId(req: Request): Promise<string | null> {
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) return null;
  const userClient = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user } } = await userClient.auth.getUser();
  return user?.id ?? null;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });
}
