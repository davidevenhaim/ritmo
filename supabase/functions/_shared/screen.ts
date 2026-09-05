// Automated screening of a freshly transcoded clip (v0.3).
//
// Claude looks at three stills and answers through one strict tool call. A
// flagged clip is not deleted: its post is hidden and an `automated` report
// lands in the moderation queue for a human decision. No key, no screening.

import Anthropic from "npm:@anthropic-ai/sdk@0.123.0";

export const SCREEN_MODEL = "claude-opus-5";

export type ScreenVerdict = {
  safe: boolean;
  categories: string[];
  note: string;
  model: string;
  at: string;
};

const SCREEN_TOOL: Anthropic.Tool = {
  name: "screen_video",
  description: "Record the moderation verdict for the clip shown in the stills.",
  strict: true,
  input_schema: {
    type: "object",
    additionalProperties: false,
    required: ["safe", "categories", "note"],
    properties: {
      safe: { type: "boolean", description: "true when the clip can be shown to everyone in a fitness app" },
      categories: {
        type: "array",
        description: "Empty when safe. Otherwise the policy areas that apply.",
        items: { type: "string", enum: ["nudity", "sexual", "violence", "self_harm", "hate", "dangerous_stunt", "spam", "not_fitness", "minor"] },
      },
      note: { type: "string", description: "One sentence a moderator can act on." },
    },
  },
};

const SYSTEM = `You screen short workout clips for SoGym, a social fitness app. You see up to three stills from one clip.
Flag nudity or sexual content, graphic violence or injury, self-harm, hate symbols, obviously dangerous stunts presented for imitation, spam or ads with no exercise, and clips that appear to feature a child alone.
Sportswear, bare torsos in a gym or outdoor training context, sweat, and grimacing under load are normal and safe.
When the stills are too dark, blurry or ambiguous to judge, mark safe and say so in the note; a human reviews reports anyway.
Answer only by calling screen_video.`;

export async function screenFrames(apiKey: string, frames: string[]): Promise<ScreenVerdict> {
  const anthropic = new Anthropic({ apiKey });
  const content: Anthropic.ContentBlockParam[] = [
    ...frames.map((url) => ({ type: "image" as const, source: { type: "url" as const, url } })),
    { type: "text", text: `Screen this clip (${frames.length} stills).` },
  ];
  const message = await anthropic.beta.messages.create({
    model: SCREEN_MODEL,
    max_tokens: 1024,
    output_config: { effort: "low" },
    betas: ["server-side-fallback-2026-07-01"],
    fallbacks: "default",
    system: SYSTEM,
    tools: [SCREEN_TOOL as Anthropic.Beta.BetaTool],
    messages: [{ role: "user", content }],
  });
  const at = new Date().toISOString();
  if (message.stop_reason === "refusal") {
    // The classifier itself declined to look: treat as unsafe and let a human decide.
    return { safe: false, categories: ["unreviewed"], note: `Screening refused (${message.stop_details?.category ?? "unknown"}); needs human review.`, model: SCREEN_MODEL, at };
  }
  const call = message.content.find((b): b is Anthropic.Beta.BetaToolUseBlock => b.type === "tool_use" && b.name === "screen_video");
  if (!call) {
    return { safe: true, categories: [], note: "No verdict returned; treated as safe.", model: SCREEN_MODEL, at };
  }
  const input = call.input as { safe: boolean; categories: string[]; note: string };
  return { safe: input.safe, categories: input.categories ?? [], note: input.note ?? "", model: SCREEN_MODEL, at };
}
