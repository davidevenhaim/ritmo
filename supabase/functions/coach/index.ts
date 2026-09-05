// SoGym Coach edge function (v0.2).
//
// Moves the Claude tool loop off the device: the API key lives here, every
// reply streams back as server-sent events, tool calls are logged for evals,
// and free-tier users get a weekly message quota.
//
// Request  POST /functions/v1/coach   (Authorization: Bearer <supabase jwt>)
//   { "messages": [{ "role": "user" | "coach", "text": "..." }], "steps_avg": 8200 }
// Response text/event-stream, one JSON object per `data:` line:
//   { "type": "text",    "delta": "..." }
//   { "type": "tool",    "name": "search_exercises", "summary": "chest · dumbbell" }
//   { "type": "routine", "routine": { ...Routine JSON in the app's shape... } }
//   { "type": "done",    "remaining": 4 }
//   { "type": "error",   "message": "..." }
//
// Secrets: ANTHROPIC_API_KEY, SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY
// Deploy:  supabase functions deploy coach --no-verify-jwt=false

import Anthropic from "npm:@anthropic-ai/sdk@0.123.0";
import { createClient } from "npm:@supabase/supabase-js@2";
import catalogue from "./catalogue.json" with { type: "json" };
import { COACH_MODEL, COACH_TOOLS, SYSTEM_PROMPT, profileSummary, type Profile } from "../_shared/coach_prompt.ts";
import { searchExercises, planToRoutine, type CatalogueItem } from "../_shared/catalogue.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const FREE_MESSAGES_PER_WEEK = Number(Deno.env.get("COACH_FREE_MESSAGES_PER_WEEK") ?? "5");
const MAX_TOOL_TURNS = 8;
const MAX_HISTORY = 30;

const items = catalogue as CatalogueItem[];

type IncomingMessage = { role: string; text: string };

function sse(obj: unknown): Uint8Array {
  return new TextEncoder().encode(`data: ${JSON.stringify(obj)}\n\n`);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) return json({ error: "Coach is not configured (missing ANTHROPIC_API_KEY)" }, 500);

  // 1. Who is asking? Validate the caller's JWT with the anon client.
  const authHeader = req.headers.get("Authorization") ?? "";
  const userClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authHeader } } });
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) return json({ error: "Sign in to talk to the coach" }, 401);

  // 2. Profile + quota via the service client (bypasses RLS, never exposed to the browser).
  const admin = createClient(supabaseUrl, serviceKey);
  const { data: profile, error: profileError } = await admin.from("profiles").select("*").eq("id", user.id).single();
  if (profileError || !profile) return json({ error: "Profile not found" }, 404);

  const { data: remaining, error: quotaError } = await admin.rpc("consume_coach_message", {
    p_user: user.id,
    p_free_per_week: FREE_MESSAGES_PER_WEEK,
  });
  if (quotaError) return json({ error: `Quota check failed: ${quotaError.message}` }, 500);
  if ((remaining as number) <= 0) {
    return json({ error: `You have used your ${FREE_MESSAGES_PER_WEEK} free coach messages this week. SoGym Plus removes the limit.`, code: "quota" }, 429);
  }

  // 3. Parse the conversation.
  let body: { messages?: IncomingMessage[]; steps_avg?: number };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Body must be JSON" }, 400);
  }
  const history = (body.messages ?? []).filter((m) => typeof m.text === "string" && m.text.trim()).slice(-MAX_HISTORY);
  if (history.length === 0 || history[history.length - 1].role !== "user") {
    return json({ error: "messages must end with a user message" }, 400);
  }

  const requestId = crypto.randomUUID();
  const log = (kind: string, payload: unknown) =>
    admin.from("coach_events").insert({ user_id: user.id, request_id: requestId, kind, payload }).then(() => {});
  await log("request", { turns: history.length, last: history[history.length - 1].text.slice(0, 500) });

  const anthropic = new Anthropic({ apiKey });
  const messages: Anthropic.MessageParam[] = history.map((m) => ({
    role: m.role === "user" ? "user" : "assistant",
    content: m.text,
  }));
  // The persona block is frozen and cached; the profile block varies per user
  // and sits after the cache breakpoint.
  const system: Anthropic.TextBlockParam[] = [
    { type: "text", text: SYSTEM_PROMPT, cache_control: { type: "ephemeral" } },
    { type: "text", text: `Athlete profile:\n${profileSummary(profile as Profile, body.steps_avg)}` },
  ];

  // 4. Stream the tool loop back to the client.
  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      const emit = (o: unknown) => controller.enqueue(sse(o));
      const textOut: string[] = [];
      try {
        for (let turn = 0; turn < MAX_TOOL_TURNS; turn++) {
          const run = anthropic.beta.messages.stream({
            model: COACH_MODEL,
            max_tokens: 16000,
            output_config: { effort: "medium" },
            betas: ["server-side-fallback-2026-07-01"],
            fallbacks: "default",
            system,
            tools: COACH_TOOLS,
            messages,
          });
          run.on("text", (delta) => {
            textOut.push(delta);
            emit({ type: "text", delta });
          });
          const message = await run.finalMessage();

          if (message.stop_reason === "refusal") {
            await log("refusal", { category: message.stop_details?.category ?? null });
            if (textOut.length === 0) {
              emit({ type: "text", delta: "I can't help with that one, but I'm happy to work on your training or nutrition." });
            }
            break;
          }

          const toolUses = message.content.filter((b): b is Anthropic.Beta.BetaToolUseBlock => b.type === "tool_use");
          if (message.stop_reason !== "tool_use" || toolUses.length === 0) break;

          messages.push({ role: "assistant", content: message.content as Anthropic.ContentBlockParam[] });
          const results: Anthropic.ToolResultBlockParam[] = [];
          for (const tu of toolUses) {
            const input = tu.input as Record<string, unknown>;
            await log("tool_use", { name: tu.name, input });
            let result: string;
            if (tu.name === "search_exercises") {
              const hits = searchExercises(items, {
                query: String(input.query ?? ""),
                muscle: String(input.muscle ?? ""),
                equipment: String(input.equipment ?? ""),
                category: String(input.category ?? ""),
                allowedEquipment: (profile.equipment as string[]) ?? [],
                limit: 12,
              });
              result = hits.length === 0
                ? "No matches. Try a broader query or different equipment."
                : hits.map((e) => `${e.id} | ${e.name} | ${e.primary.join("/")} | ${e.equipment} | ${e.level ?? ""}`).join("\n");
              emit({ type: "tool", name: tu.name, summary: [input.muscle, input.equipment, input.query].filter(Boolean).join(" · ") });
            } else if (tu.name === "save_plan") {
              const routine = planToRoutine(input, items, { id: user.id, name: profile.name, goal: profile.goal });
              const { data: saved, error: saveError } = await admin
                .from("routines")
                .insert({
                  author_id: user.id,
                  name: routine.name,
                  description: routine.description,
                  days: routine.days,
                  tags: routine.tags,
                  source: "ai",
                })
                .select("id, created_at")
                .single();
              if (saveError || !saved) {
                result = `Could not save the plan: ${saveError?.message ?? "unknown error"}`;
              } else {
                routine.id = saved.id;
                routine.createdAt = saved.created_at;
                emit({ type: "routine", routine });
                result = `Saved routine "${routine.name}" with ${routine.days.length} days and ${routine.days.reduce((n, d) => n + d.items.length, 0)} exercises.`;
              }
            } else {
              result = "Unknown tool";
            }
            await log("tool_result", { name: tu.name, result: result.slice(0, 2000) });
            results.push({ type: "tool_result", tool_use_id: tu.id, content: result });
          }
          messages.push({ role: "user", content: results });
        }
        await log("reply", { text: textOut.join("").slice(0, 4000) });
        emit({ type: "done", remaining });
      } catch (err) {
        const message = err instanceof Anthropic.RateLimitError
          ? "The coach is busy right now, try again in a minute."
          : err instanceof Anthropic.APIError
          ? `Coach error ${err.status}: ${err.message}`
          : `Coach error: ${(err as Error).message}`;
        await log("error", { message });
        emit({ type: "error", message });
      } finally {
        controller.close();
      }
    },
  });

  return new Response(stream, {
    headers: { ...CORS, "Content-Type": "text/event-stream", "Cache-Control": "no-cache", Connection: "keep-alive" },
  });
});

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), { status, headers: { ...CORS, "Content-Type": "application/json" } });
}
