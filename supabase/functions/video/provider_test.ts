// deno test supabase/functions/video/provider_test.ts
import { assertEquals } from "jsr:@std/assert@1";
import { CloudflareStream, Mux, framesAt, hmacHex, parseSignatureHeader, verifySignedWebhook } from "../_shared/video_provider.ts";

const SECRET = "whsec_test";

Deno.test("signature header parsing tolerates spaces and extra keys", () => {
  assertEquals(parseSignatureHeader("time=1700000000, sig1=abc, sig2=def"), { time: "1700000000", sig1: "abc", sig2: "def" });
  assertEquals(parseSignatureHeader(null), {});
});

Deno.test("cloudflare webhook signature verifies and rejects tampering or replay", async () => {
  const body = JSON.stringify({ uid: "abc", status: { state: "ready" } });
  const ts = 1_700_000_000;
  const sig = await hmacHex(SECRET, `${ts}.${body}`);
  const header = `time=${ts},sig1=${sig}`;
  const now = ts * 1000 + 30_000;
  assertEquals(await verifySignedWebhook({ header, rawBody: body, secret: SECRET, timeKey: "time", sigKey: "sig1", now }), true);
  assertEquals(await verifySignedWebhook({ header, rawBody: body + " ", secret: SECRET, timeKey: "time", sigKey: "sig1", now }), false);
  assertEquals(await verifySignedWebhook({ header, rawBody: body, secret: "other", timeKey: "time", sigKey: "sig1", now }), false);
  assertEquals(await verifySignedWebhook({ header, rawBody: body, secret: SECRET, timeKey: "time", sigKey: "sig1", now: now + 3_600_000 }), false);
  assertEquals(await verifySignedWebhook({ header: null, rawBody: body, secret: SECRET, timeKey: "time", sigKey: "sig1", now }), false);
});

Deno.test("cloudflare ready payload maps to playback, thumbnail and frames", () => {
  const cf = new CloudflareStream("acct", "tok", SECRET);
  const ev = cf.parseWebhook(JSON.stringify({
    uid: "vid123",
    readyToStream: true,
    status: { state: "ready" },
    duration: 40,
    input: { width: 1080, height: 1920 },
    playback: { hls: "https://customer-x.cloudflarestream.com/vid123/manifest/video.m3u8" },
    thumbnail: "https://customer-x.cloudflarestream.com/vid123/thumbnails/thumbnail.jpg",
  }));
  assertEquals(ev.kind, "ready");
  if (ev.kind !== "ready") return;
  assertEquals(ev.providerUid, "vid123");
  assertEquals(ev.durationSec, 40);
  assertEquals(ev.width, 1080);
  assertEquals(ev.frames, [
    "https://customer-x.cloudflarestream.com/vid123/thumbnails/thumbnail.jpg?time=4s",
    "https://customer-x.cloudflarestream.com/vid123/thumbnails/thumbnail.jpg?time=20s",
    "https://customer-x.cloudflarestream.com/vid123/thumbnails/thumbnail.jpg?time=36s",
  ]);
  const failed = cf.parseWebhook(JSON.stringify({ uid: "v2", status: { state: "error", errorReasonText: "corrupt" } }));
  assertEquals(failed.kind, "failed");
  assertEquals(cf.parseWebhook(JSON.stringify({ uid: "v3", status: { state: "inprogress" } })).kind, "ignored");
});

Deno.test("mux events map upload link, ready and errored", () => {
  const mux = new Mux("id", "secret", SECRET);
  assertEquals(mux.parseWebhook(JSON.stringify({ type: "video.upload.asset_created", data: { id: "up1", asset_id: "as1" } })), {
    kind: "link",
    providerUid: "as1",
    uploadId: "up1",
  });
  const ready = mux.parseWebhook(JSON.stringify({
    type: "video.asset.ready",
    data: { id: "as1", upload_id: "up1", duration: 12.5, playback_ids: [{ id: "pb1", policy: "public" }], tracks: [{ type: "video", max_width: 720, max_height: 1280 }] },
  }));
  assertEquals(ready.kind, "ready");
  if (ready.kind !== "ready") return;
  assertEquals(ready.playbackUrl, "https://stream.mux.com/pb1.m3u8");
  assertEquals(ready.thumbnailUrl, "https://image.mux.com/pb1/thumbnail.jpg?time=1");
  assertEquals(ready.height, 1280);
  assertEquals(ready.frames.length, 3);
  assertEquals(mux.parseWebhook(JSON.stringify({ type: "video.asset.errored", data: { id: "as1", errors: { messages: ["bad"] } } })).kind, "failed");
  assertEquals(mux.parseWebhook(JSON.stringify({ type: "video.asset.created", data: {} })).kind, "ignored");
});

Deno.test("frames fall back to a single still for very short or unknown clips", () => {
  assertEquals(framesAt(null, (t) => `t${t}`), ["t1"]);
  assertEquals(framesAt(2, (t) => `t${t}`), ["t1"]);
  assertEquals(framesAt(60, (t) => `t${t}`), ["t6", "t30", "t54"]);
});
