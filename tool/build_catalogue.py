#!/usr/bin/env python3
"""Build assets/data/exercises.json from the open exercise sources.

Sources and their obligations (see docs/CREDITS.md and the in-app credits
screen — every one of these must stay attributed):

  free-exercise-db  Unlicense (public domain)   876 items, 2 photos each
  RepDB free tier   custom, commercial use OK   601 items, 2 illustrations each
                    ATTRIBUTION REQUIRED, and the licence forbids
                    redistributing the data AS A DATASET. That is why this
                    script exists: the merged file is generated, not committed.
  yoga-api          MIT (code), images CC0 +     48 poses, SVG/PNG
                    Flaticon (credit monkik and dDara)
  sogym-editorial   ours                         36 regressions and
                    progressions written in-house to fill the gaps the open
                    sources leave at the easy end (supported sit-to-stand,
                    kneeling planks, wall hinges) and at the hard end.

Curation is preserved. The existing catalogue is authoritative: a rerun keeps
every row and every field already in assets/data/exercises.json — including
hand-graded levels and the editorial rows, which exist in no source — and only
appends exercises the sources have that the catalogue does not. Pass --fresh to
throw that away and rebuild from the sources alone.

Every exercise ends up graded beginner / intermediate / advanced; that is the
vocabulary the app filters and groups by, so a row without a level is not
allowed to reach the asset.

Run:  python3 tool/build_catalogue.py [--fresh]
"""
import json
import re
import sys
import urllib.request
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "assets" / "data" / "exercises.json"

FREE_DB = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json"
REPDB = "https://raw.githubusercontent.com/RepDB/exercise-dataset/main/exercises.json"
REPDB_RAW = "https://raw.githubusercontent.com/RepDB/exercise-dataset/main/"
YOGA_POSES = "https://yoga-api-nzy4.onrender.com/v1/poses"
YOGA_CATS = "https://yoga-api-nzy4.onrender.com/v1/categories"

# RepDB names muscles anatomically; the app speaks free-exercise-db.
MUSCLES = {
    "rectus_abdominis": "abdominals", "transverse_abdominis": "abdominals",
    "obliques": "abdominals", "serratus_anterior": "chest",
    "erector_spinae": "lower back", "quadratus_lumborum": "lower back",
    "latissimus_dorsi": "lats", "trapezius": "traps", "rhomboids": "middle back",
    "anterior_deltoid": "shoulders", "lateral_deltoid": "shoulders",
    "posterior_deltoid": "shoulders", "supraspinatus": "shoulders",
    "pectoralis_major": "chest",
    "biceps_brachii": "biceps", "brachialis": "biceps",
    "triceps_brachii": "triceps",
    "brachioradialis": "forearms", "forearm_flexors": "forearms",
    "forearm_extensors": "forearms", "forearms": "forearms",
    "quadriceps": "quadriceps", "hip_flexors": "hip flexors",
    "hamstrings": "hamstrings",
    "gluteus_maximus": "glutes", "gluteus_medius": "glutes",
    "gastrocnemius": "calves", "soleus": "calves",
    "adductors": "adductors", "abductors": "abductors",
}

# Equipment the profile already knows about keeps its existing spelling.
EQUIPMENT = {
    None: "body only", "": "body only", "bodyweight": "body only",
    "kettlebell": "kettlebells", "resistance_band": "bands", "loop_band": "bands",
    "ez_bar": "e-z curl bar", "stability_ball": "exercise ball",
    "slam_ball": "medicine ball", "plates": "barbell", "flat_bench": "body only",
}


def fetch(url):
    print(f"  fetching {url}")
    req = urllib.request.Request(url, headers={"User-Agent": "sogym-catalogue-build"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.loads(r.read().decode())


def norm_muscles(values):
    out = []
    for v in values or []:
        m = MUSCLES.get(v, v.replace("_", " "))
        if m not in out:
            out.append(m)
    return out


def norm_equipment(v):
    if v in EQUIPMENT:
        return EQUIPMENT[v]
    return (v or "body only").replace("_", " ")


def key(name):
    """Loose name key so the same exercise from two sources merges."""
    return re.sub(r"[^a-z0-9]", "", name.lower())


def from_free(x):
    return {
        "id": x["id"],
        "name": x["name"],
        "category": x.get("category", "strength"),
        "equipment": x.get("equipment") or "body only",
        "primary": x.get("primaryMuscles", []),
        "secondary": x.get("secondaryMuscles", []),
        "instructions": x.get("instructions", []),
        "images": x.get("images", []),
        "level": x.get("level"),
        "mechanic": x.get("mechanic"),
        "force": x.get("force"),
        "source": "free-exercise-db",
    }


def from_repdb(x):
    frames = (x.get("images") or {}).get("flat") or {}
    images = [REPDB_RAW + p for p in [frames.get("start"), frames.get("peak")] if p]
    return {
        "id": "repdb_" + x["id"],
        "name": x["name_en"],
        # RepDB calls weightlifting "olympic"; the app already says the long form.
        "category": "olympic weightlifting" if x.get("category") == "olympic" else x.get("category", "strength"),
        "equipment": norm_equipment(x.get("equipment")),
        "primary": norm_muscles(x.get("primary_muscles")),
        "secondary": norm_muscles(x.get("secondary_muscles")),
        "instructions": list(x.get("instructions_en") or []) + list(x.get("tips_en") or []),
        "images": images,
        "level": x.get("difficulty"),
        "mechanic": x.get("mechanic"),
        "force": x.get("force_type"),
        "source": "repdb",
    }


def from_yoga(p, category):
    desc = (p.get("pose_description") or "").strip()
    benefits = (p.get("pose_benefits") or "").strip()
    images = [u for u in [p.get("url_png"), p.get("url_svg")] if u]
    name = p["english_name"].strip()
    if not name.lower().endswith("pose"):
        name = f"{name} Pose"
    return {
        "id": f"yoga_{p['id']}",
        "name": name,
        "category": "yoga",
        "equipment": "body only",
        "primary": [],
        "secondary": [],
        "instructions": [s for s in [desc, f"Benefits: {benefits}" if benefits else ""] if s],
        "images": images,
        "level": None,
        "mechanic": None,
        "force": "static",
        "source": "yoga-api",
        "sanskrit": p.get("sanskrit_name_adapted"),
        "yogaCategory": category,
    }


# The three levels the app speaks. Sources disagree ("expert", missing), so
# everything is mapped on the way in; the fallback is deliberately cautious and
# meant to be reviewed by hand, which is what the curated grading in the asset
# is a record of.
LEVELS = ("beginner", "intermediate", "advanced")


def norm_level(value, category):
    v = (value or "").strip().lower()
    if v in LEVELS:
        return v
    if v in ("expert", "elite", "hard", "advance"):
        return "advanced"
    if v in ("novice", "easy"):
        return "beginner"
    if v in ("medium", "moderate"):
        return "intermediate"
    return "beginner" if category in ("yoga", "stretching") else "intermediate"


def main():
    fresh = "--fresh" in sys.argv
    print("Building the SoGym exercise catalogue" + (" (fresh, curation discarded)" if fresh else ""))
    free = [from_free(x) for x in fetch(FREE_DB)]
    print(f"  free-exercise-db: {len(free)}")

    rep_raw = fetch(REPDB)
    rep = [from_repdb(x) for x in rep_raw["exercises"]]
    print(f"  repdb: {len(rep)} ({rep_raw['license']})")

    cats = fetch(YOGA_CATS)
    where = {}
    for c in cats:
        for p in c.get("poses", []):
            where[p["id"]] = c.get("category_name", "Yoga")
    yoga = [from_yoga(p, where.get(p["id"], "Yoga")) for p in fetch(YOGA_POSES)]
    print(f"  yoga-api: {len(yoga)}")

    # Yoga is merged before RepDB so a pose keeps its yoga record rather than
    # RepDB's stretching duplicate of the same movement.
    merged, seen = [], set()
    for group in (free, yoga, rep):
        added = 0
        for e in group:
            k = key(e["name"])
            if k in seen:
                continue
            seen.add(k)
            merged.append(e)
            added += 1
        print(f"  +{added} kept from {group[0]['source']}")

    # Anything named after a yoga pose belongs to the yoga goal, whichever
    # source it came from.
    pose_words = {key(p["name"].replace(" Pose", "")) for p in yoga}
    promoted = 0
    for e in merged:
        if e["category"] == "yoga":
            continue
        k = key(e["name"])
        if (len(k) > 4 and k in pose_words) or "pose" in e["name"].lower():
            e["category"] = "yoga"
            promoted += 1
    print(f"  {promoted} exercises retagged as yoga by pose name")

    for e in merged:
        e["level"] = norm_level(e.get("level"), e.get("category"))

    # Curation wins. Rows already in the catalogue keep every field they have,
    # rows that exist only there (the editorial ones) are kept, and the sources
    # can only add exercises nobody has seen before.
    if OUT.exists() and not fresh:
        current = json.loads(OUT.read_text())
        by_key = {key(e["name"]): e for e in current}
        kept, added = list(current), 0
        for e in merged:
            if key(e["name"]) in by_key:
                continue
            kept.append(e)
            added += 1
        print(f"  curation preserved: {len(current)} kept, +{added} new from the sources")
        merged = kept
        for e in merged:
            e["level"] = norm_level(e.get("level"), e.get("category"))

    merged.sort(key=lambda e: e["name"])
    OUT.write_text(json.dumps(merged, ensure_ascii=False))
    counts, levels, sources = {}, {}, {}
    for e in merged:
        counts[e["category"]] = counts.get(e["category"], 0) + 1
        levels[e["level"]] = levels.get(e["level"], 0) + 1
        sources[e["source"]] = sources.get(e["source"], 0) + 1
    print(f"\nWrote {len(merged)} exercises to {OUT}")
    for c, n in sorted(counts.items(), key=lambda kv: -kv[1]):
        print(f"  {c:24} {n}")
    print("  levels: " + ", ".join(f"{lv} {levels.get(lv, 0)}" for lv in LEVELS))
    print("  sources: " + ", ".join(f"{s} {n}" for s, n in sorted(sources.items(), key=lambda kv: -kv[1])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
