// Catalogue search and plan conversion, mirroring lib/core/exercise_repository.dart
// and planToRoutine in lib/core/ai_coach.dart.

export interface CatalogueItem {
  id: string;
  name: string;
  category: string;
  equipment: string;
  primary: string[];
  secondary: string[];
  level: string | null;
}

const BODYWEIGHT = new Set(["body only", "none", "other"]);

export interface SearchOptions {
  query?: string;
  muscle?: string;
  equipment?: string;
  category?: string;
  allowedEquipment?: string[];
  limit?: number;
}

function nz(s?: string): string | null {
  const t = (s ?? "").trim().toLowerCase();
  return t ? t : null;
}

export function searchExercises(items: CatalogueItem[], o: SearchOptions): CatalogueItem[] {
  const q = nz(o.query);
  const muscle = nz(o.muscle);
  const equipment = nz(o.equipment);
  const category = nz(o.category);
  const allowed = (o.allowedEquipment ?? []).map((e) => e.toLowerCase());
  const allowedSet = allowed.length ? new Set([...allowed, ...BODYWEIGHT]) : null;
  const limit = o.limit ?? 50;

  const scored: { e: CatalogueItem; score: number }[] = [];
  for (const e of items) {
    if (muscle && !e.primary.includes(muscle) && !e.secondary.includes(muscle)) continue;
    if (equipment && e.equipment !== equipment) continue;
    if (category && e.category !== category) continue;
    if (allowedSet && !allowedSet.has(e.equipment)) continue;
    let score = 0;
    if (q) {
      const name = e.name.toLowerCase();
      if (name === q) score = 3;
      else if (name.startsWith(q)) score = 2;
      else if (name.includes(q)) score = 1;
      else continue;
    }
    if (muscle && e.primary.includes(muscle)) score += 0.5;
    scored.push({ e, score });
  }
  scored.sort((a, b) => b.score - a.score || a.e.name.localeCompare(b.e.name));
  return scored.slice(0, limit).map((s) => s.e);
}

export interface RoutineItem {
  exerciseId: string;
  exerciseName: string;
  sets: number;
  reps: number;
  restSec: number;
  notes: string;
}
export interface RoutineDay {
  title: string;
  focus: string;
  items: RoutineItem[];
}
/** Routine JSON in the exact shape lib/core/models.dart Routine.fromJson reads. */
export interface RoutineJson {
  id: string;
  name: string;
  description: string;
  authorId: string;
  authorName: string;
  days: RoutineDay[];
  createdAt: string;
  tags: string[];
  source: string;
}

export function planToRoutine(
  plan: Record<string, unknown>,
  items: CatalogueItem[],
  owner: { id: string; name: string; goal: string },
): RoutineJson {
  const byId = new Map(items.map((e) => [e.id, e]));
  const days: RoutineDay[] = [];
  for (const d of (plan.days as Record<string, unknown>[] | undefined) ?? []) {
    const out: RoutineItem[] = [];
    for (const ex of (d.exercises as Record<string, unknown>[] | undefined) ?? []) {
      const e = byId.get(String(ex.exercise_id ?? ""));
      if (!e) continue; // unknown ids are dropped, never invented
      out.push({
        exerciseId: e.id,
        exerciseName: e.name,
        sets: Number(ex.sets ?? 3),
        reps: Number(ex.reps ?? 10),
        restSec: Number(ex.rest_sec ?? 60),
        notes: String(ex.notes ?? ""),
      });
    }
    if (out.length) days.push({ title: String(d.title ?? `Day ${days.length + 1}`), focus: String(d.focus ?? ""), items: out });
  }
  const nutrition = String(plan.nutrition_notes ?? "");
  return {
    id: "",
    name: String(plan.name ?? "AI plan"),
    description: [String(plan.description ?? ""), nutrition ? `Nutrition: ${nutrition}` : ""].filter(Boolean).join("\n"),
    authorId: owner.id,
    authorName: `SoGym Coach for ${owner.name}`,
    days,
    createdAt: new Date().toISOString(),
    tags: ["ai", owner.goal],
    source: "ai",
  };
}
