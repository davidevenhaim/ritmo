// Video hosting adapters (v0.3). Cloudflare Stream is the default; Mux is the
// alternative. Both give the client a one-time direct-upload URL so bytes never
// pass through our servers, then call back a webhook when transcoding is done.
//
//   VIDEO_PROVIDER=cloudflare  CF_ACCOUNT_ID, CF_STREAM_TOKEN, CF_WEBHOOK_SECRET
//   VIDEO_PROVIDER=mux         MUX_TOKEN_ID, MUX_TOKEN_SECRET, MUX_WEBHOOK_SECRET

export const MAX_DURATION_SEC = 60;

export type UploadTicket = {
  /** Where the client sends the file. */
  uploadUrl: string;
  /** `form` = multipart POST with a `file` field (Cloudflare); `put` = raw PUT body (Mux). */
  method: "form" | "put";
  providerUid: string | null;
  uploadId: string | null;
};

export type ReadyEvent = {
  kind: "ready";
  providerUid: string;
  uploadId: string | null;
  durationSec: number | null;
  width: number | null;
  height: number | null;
  playbackUrl: string;
  thumbnailUrl: string;
  /** Extra stills at fixed points for screening. */
  frames: string[];
};
export type FailedEvent = { kind: "failed"; providerUid: string | null; uploadId: string | null; error: string };
export type LinkEvent = { kind: "link"; providerUid: string; uploadId: string };
export type IgnoredEvent = { kind: "ignored"; reason: string };
export type WebhookEvent = ReadyEvent | FailedEvent | LinkEvent | IgnoredEvent;

export interface VideoProvider {
  readonly name: "cloudflare" | "mux";
  createUpload(opts: { userId: string; videoId: string; filename: string }): Promise<UploadTicket>;
  verifyWebhook(req: Request, rawBody: string): Promise<boolean>;
  parseWebhook(rawBody: string): WebhookEvent;
  remove(providerUid: string): Promise<void>;
}

// ------------------------------------------------------------------ helpers
export function parseSignatureHeader(header: string | null): Record<string, string> {
  const out: Record<string, string> = {};
  for (const part of (header ?? "").split(",")) {
    const i = part.indexOf("=");
    if (i > 0) out[part.slice(0, i).trim()] = part.slice(i + 1).trim();
  }
  return out;
}

export async function hmacHex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/**
 * Both providers sign `${timestamp}.${rawBody}` with HMAC-SHA256 and send
 * `time=…,sig1=…` (Cloudflare, header Webhook-Signature) or `t=…,v1=…` (Mux,
 * header Mux-Signature). Timestamps older than five minutes are rejected.
 */
export async function verifySignedWebhook(opts: {
  header: string | null;
  rawBody: string;
  secret: string;
  timeKey: string;
  sigKey: string;
  now?: number;
  toleranceSec?: number;
}): Promise<boolean> {
  const parts = parseSignatureHeader(opts.header);
  const ts = Number(parts[opts.timeKey]);
  const sig = parts[opts.sigKey];
  if (!ts || !sig) return false;
  const now = Math.floor((opts.now ?? Date.now()) / 1000);
  if (Math.abs(now - ts) > (opts.toleranceSec ?? 300)) return false;
  const expected = await hmacHex(opts.secret, `${ts}.${opts.rawBody}`);
  return timingSafeEqual(expected, sig.toLowerCase());
}

// --------------------------------------------------------------- cloudflare
export class CloudflareStream implements VideoProvider {
  readonly name = "cloudflare" as const;
  constructor(private accountId: string, private token: string, private webhookSecret: string) {}

  private get base() {
    return `https://api.cloudflare.com/client/v4/accounts/${this.accountId}/stream`;
  }

  async createUpload({ userId, videoId, filename }: { userId: string; videoId: string; filename: string }): Promise<UploadTicket> {
    const res = await fetch(`${this.base}/direct_upload`, {
      method: "POST",
      headers: { Authorization: `Bearer ${this.token}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        maxDurationSeconds: MAX_DURATION_SEC,
        creator: userId,
        meta: { name: filename, sogym_video_id: videoId },
        requireSignedURLs: false,
        thumbnailTimestampPct: 0.1,
      }),
    });
    const data = await res.json();
    if (!res.ok || !data?.success) throw new Error(`Cloudflare direct_upload failed: ${JSON.stringify(data?.errors ?? res.status)}`);
    return { uploadUrl: data.result.uploadURL, method: "form", providerUid: data.result.uid, uploadId: null };
  }

  verifyWebhook(req: Request, rawBody: string): Promise<boolean> {
    return verifySignedWebhook({
      header: req.headers.get("Webhook-Signature"),
      rawBody,
      secret: this.webhookSecret,
      timeKey: "time",
      sigKey: "sig1",
    });
  }

  parseWebhook(rawBody: string): WebhookEvent {
    const v = JSON.parse(rawBody);
    const uid: string | undefined = v.uid;
    if (!uid) return { kind: "ignored", reason: "no uid" };
    const state: string | undefined = v.status?.state;
    if (state === "error") {
      return { kind: "failed", providerUid: uid, uploadId: null, error: v.status?.errorReasonText ?? v.status?.errorReasonCode ?? "transcode error" };
    }
    if (state !== "ready" || !v.readyToStream) return { kind: "ignored", reason: `state ${state}` };
    const hls: string | undefined = v.playback?.hls;
    const thumb: string = v.thumbnail ?? (hls ? hls.replace(/manifest\/video\.m3u8.*$/, "thumbnails/thumbnail.jpg") : "");
    if (!hls) return { kind: "failed", providerUid: uid, uploadId: null, error: "no playback url" };
    const frameBase = thumb.replace(/\?.*$/, "");
    const duration = typeof v.duration === "number" ? v.duration : null;
    return {
      kind: "ready",
      providerUid: uid,
      uploadId: null,
      durationSec: duration,
      width: v.input?.width ?? null,
      height: v.input?.height ?? null,
      playbackUrl: hls,
      thumbnailUrl: thumb,
      frames: framesAt(duration, (t) => `${frameBase}?time=${t}s`),
    };
  }

  async remove(providerUid: string): Promise<void> {
    await fetch(`${this.base}/${providerUid}`, { method: "DELETE", headers: { Authorization: `Bearer ${this.token}` } });
  }
}

// ---------------------------------------------------------------------- mux
export class Mux implements VideoProvider {
  readonly name = "mux" as const;
  constructor(private tokenId: string, private tokenSecret: string, private webhookSecret: string) {}

  private get auth() {
    return `Basic ${btoa(`${this.tokenId}:${this.tokenSecret}`)}`;
  }

  async createUpload({ userId, videoId }: { userId: string; videoId: string; filename: string }): Promise<UploadTicket> {
    const res = await fetch("https://api.mux.com/video/v1/uploads", {
      method: "POST",
      headers: { Authorization: this.auth, "Content-Type": "application/json" },
      body: JSON.stringify({
        cors_origin: "*",
        timeout: 3600,
        new_asset_settings: {
          playback_policy: ["public"],
          video_quality: "basic",
          max_resolution_tier: "1080p",
          passthrough: JSON.stringify({ videoId, userId }),
        },
      }),
    });
    const data = await res.json();
    if (!res.ok || !data?.data?.url) throw new Error(`Mux upload create failed: ${JSON.stringify(data?.error ?? res.status)}`);
    return { uploadUrl: data.data.url, method: "put", providerUid: null, uploadId: data.data.id };
  }

  verifyWebhook(req: Request, rawBody: string): Promise<boolean> {
    return verifySignedWebhook({
      header: req.headers.get("Mux-Signature"),
      rawBody,
      secret: this.webhookSecret,
      timeKey: "t",
      sigKey: "v1",
    });
  }

  parseWebhook(rawBody: string): WebhookEvent {
    const e = JSON.parse(rawBody);
    const type: string = e.type ?? "";
    const d = e.data ?? {};
    if (type === "video.upload.asset_created") {
      return { kind: "link", providerUid: d.asset_id, uploadId: d.id };
    }
    if (type === "video.asset.errored") {
      return { kind: "failed", providerUid: d.id ?? null, uploadId: d.upload_id ?? null, error: d.errors?.messages?.join("; ") ?? "transcode error" };
    }
    if (type !== "video.asset.ready") return { kind: "ignored", reason: type };
    const playbackId: string | undefined = d.playback_ids?.find((p: { policy: string }) => p.policy === "public")?.id ?? d.playback_ids?.[0]?.id;
    if (!playbackId) return { kind: "failed", providerUid: d.id, uploadId: d.upload_id ?? null, error: "no public playback id" };
    const video = (d.tracks ?? []).find((t: { type: string }) => t.type === "video");
    const duration = typeof d.duration === "number" ? d.duration : null;
    return {
      kind: "ready",
      providerUid: d.id,
      uploadId: d.upload_id ?? null,
      durationSec: duration,
      width: video?.max_width ?? null,
      height: video?.max_height ?? null,
      playbackUrl: `https://stream.mux.com/${playbackId}.m3u8`,
      thumbnailUrl: `https://image.mux.com/${playbackId}/thumbnail.jpg?time=1`,
      frames: framesAt(duration, (t) => `https://image.mux.com/${playbackId}/thumbnail.jpg?time=${t}`),
    };
  }

  async remove(providerUid: string): Promise<void> {
    await fetch(`https://api.mux.com/video/v1/assets/${providerUid}`, { method: "DELETE", headers: { Authorization: this.auth } });
  }
}

/** Three stills spread across the clip (or one at 1s when duration is unknown). */
export function framesAt(duration: number | null, url: (seconds: number) => string): string[] {
  if (!duration || duration < 3) return [url(1)];
  return [0.1, 0.5, 0.9].map((pct) => url(Math.max(0, Math.floor(duration * pct))));
}

export function providerFromEnv(env: (k: string) => string | undefined): VideoProvider {
  const which = (env("VIDEO_PROVIDER") ?? "cloudflare").toLowerCase();
  if (which === "mux") {
    return new Mux(need(env, "MUX_TOKEN_ID"), need(env, "MUX_TOKEN_SECRET"), need(env, "MUX_WEBHOOK_SECRET"));
  }
  return new CloudflareStream(need(env, "CF_ACCOUNT_ID"), need(env, "CF_STREAM_TOKEN"), need(env, "CF_WEBHOOK_SECRET"));
}

function need(env: (k: string) => string | undefined, key: string): string {
  const v = env(key);
  if (!v) throw new Error(`Video hosting is not configured (missing ${key})`);
  return v;
}
