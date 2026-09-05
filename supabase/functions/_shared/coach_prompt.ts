// Shared coach persona, tool schemas and profile formatting.
// Keep this in lockstep with lib/core/ai_coach.dart: the on-device demo coach
// and the hosted coach must behave identically so evals apply to both.

import type Anthropic from "npm:@anthropic-ai/sdk@0.123.0";

export const COACH_MODEL = "claude-opus-5";

export const SYSTEM_PROMPT = `You are the SoGym Coach: a friendly, precise personal trainer and nutrition guide living inside a social workout app.

How you work:
- Ground every exercise recommendation in the app catalogue. Use the search_exercises tool to find exercises by muscle, equipment, or name, and only reference exercise_ids that came back from that tool.
- Respect the athlete's equipment list, training days, and diet restrictions exactly. Never suggest food that violates a listed restriction.
- When the athlete asks for a plan, program, routine, or schedule, build it and call save_plan once with the complete plan. Keep the number of days equal to their training days per week. After saving, summarise the plan in a few short lines.
- For medical issues, pain, injuries, or eating disorders, give conservative advice and tell them to see a professional.
- Be concise and motivating. Use plain language, short paragraphs, no markdown headers. Metric units.
`;

export const COACH_TOOLS: Anthropic.Beta.BetaToolUnion[] = [
  {
    name: "search_exercises",
    description:
      "Search the SoGym exercise catalogue (1,443 exercises, each graded beginner, intermediate or advanced). Returns up to 12 matches with ids, primary muscles, equipment and level. Call it with a muscle group, an equipment type, or a free-text name.",
    input_schema: {
      type: "object",
      properties: {
        query: { type: "string", description: 'Free text, e.g. "squat", "chest press". Empty string allowed.' },
        muscle: {
          type: "string",
          description:
            "One of: abdominals, abductors, adductors, biceps, calves, chest, forearms, glutes, hamstrings, lats, lower back, middle back, neck, quadriceps, shoulders, traps, triceps. Empty string for any.",
        },
        equipment: {
          type: "string",
          description:
            "One of: body only, dumbbell, barbell, kettlebells, bands, cable, machine, medicine ball, exercise ball, foam roll, other. Empty string for any.",
        },
        category: {
          type: "string",
          description: "strength, stretching, cardio, plyometrics, powerlifting, olympic weightlifting, strongman. Empty string for any.",
        },
      },
      required: ["query", "muscle", "equipment", "category"],
      additionalProperties: false,
    },
    strict: true,
  },
  {
    name: "save_plan",
    description:
      "Save a complete training plan into the athlete's routines. Call exactly once per plan, only with exercise_ids returned by search_exercises.",
    input_schema: {
      type: "object",
      properties: {
        name: { type: "string" },
        description: { type: "string", description: "One or two sentences on who this plan is for and why." },
        days: {
          type: "array",
          items: {
            type: "object",
            properties: {
              title: { type: "string", description: 'e.g. "Day 1 - Push"' },
              focus: { type: "string", description: 'e.g. "Chest, shoulders, triceps"' },
              exercises: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    exercise_id: { type: "string" },
                    sets: { type: "integer" },
                    reps: { type: "integer" },
                    rest_sec: { type: "integer" },
                    notes: { type: "string" },
                  },
                  required: ["exercise_id", "sets", "reps", "rest_sec", "notes"],
                  additionalProperties: false,
                },
              },
            },
            required: ["title", "focus", "exercises"],
            additionalProperties: false,
          },
        },
        nutrition_notes: { type: "string", description: "Short diet guidance respecting the restrictions." },
        weekly_step_goal: { type: "integer", description: "Suggested daily steps target." },
      },
      required: ["name", "description", "days", "nutrition_notes", "weekly_step_goal"],
      additionalProperties: false,
    },
    strict: true,
  },
];

export interface Profile {
  id: string;
  name: string;
  handle: string;
  age: number | null;
  height_cm: number | null;
  weight_kg: number | null;
  target_weight_kg: number | null;
  goal: string;
  days_per_week: number;
  equipment: string[];
  diet: string[];
  step_goal: number;
}

const GOAL_LABELS: Record<string, string> = {
  loseFat: "Lose fat",
  buildMuscle: "Build muscle",
  getStronger: "Get stronger",
  endurance: "Endurance",
  mobility: "Mobility & flexibility",
  generalHealth: "General health",
};

export function profileSummary(p: Profile, stepsAvg?: number): string {
  const h = p.height_cm ?? 0;
  const w = p.weight_kg ?? 0;
  const bmi = h > 0 && w > 0 ? (w / ((h / 100) ** 2)).toFixed(1) : "unknown";
  return [
    `Name: ${p.name} (@${p.handle}), age ${p.age ?? "unknown"}`,
    `Height: ${h || "unknown"} cm, weight: ${w || "unknown"} kg, BMI ${bmi}${p.target_weight_kg ? `, target weight ${p.target_weight_kg} kg` : ""}`,
    `Goal: ${GOAL_LABELS[p.goal] ?? p.goal}`,
    `Training days per week: ${p.days_per_week}`,
    `Available equipment: ${p.equipment?.length ? p.equipment.join(", ") : "body only"}`,
    `Diet restrictions: ${p.diet?.length ? p.diet.join(", ") : "none"}`,
    `Daily step goal: ${p.step_goal}${stepsAvg ? `, 7-day average ${Math.round(stepsAvg)} steps` : ""}`,
  ].join("\n");
}
