# Exercise data sources and obligations

`assets/data/exercises.json` is **generated**, not hand-written. Rebuild it with:

```
python3 tool/build_catalogue.py
```

1,443 exercises from three open sources plus 36 written in-house. Each outside
source carries an obligation that the app satisfies through the in-app credits
screen (`/credits`, linked from Settings).

Every exercise is graded **beginner / intermediate / advanced** — the app
filters, groups and recommends by that grade, so the build script normalises the
sources' own vocabularies ("expert", ungraded) into those three and refuses to
write a row without one.

| Source | Items kept | Licence | What we must do |
| --- | --- | --- | --- |
| [free-exercise-db](https://github.com/yuhonas/free-exercise-db) | 876 | Unlicense (public domain) | Nothing required. Mirror the images to our own storage before launch. |
| [RepDB free tier](https://github.com/RepDB/exercise-dataset) | 484 | RepDB Free Tier Licence v1.0 | **Visible credit** "Exercise data by RepDB (repdb.co)". Commercial in-app use is allowed. **Redistribution as a dataset is not.** No generative-AI derivation from the images. Do not ship anything from `premium-samples/`. |
| [yoga-api](https://github.com/alexcumplido/yoga-api) | 47 | MIT (code); images CC0 and Flaticon | Credit Alexandre C., plus the two Flaticon authors: **monkik** (easy icons) and **dDara** (yoga icons). No AI restyling of those icons. |
| SoGym editorial | 36 | Ours | Nothing owed to anyone. Written to fill the ends of the ladder the open sources leave thin: supported sit-to-stands, kneeling planks, wall hinges and heel slides at the beginner end, long-lever and single-leg work at the advanced end. No photos yet, so they render on the striped placeholder. |

## The one decision left for the repo owner

RepDB's licence forbids redistributing its rows **as a dataset**. Shipping them
inside the app binary is explicitly fine; committing the merged
`assets/data/exercises.json` to a **public** git repository is arguably not.
Note that the catalogue is now also *curated* — hand-graded levels and the 36
editorial rows live only in that file, so `build_catalogue.py` treats it as
authoritative and only appends what the sources add (`--fresh` throws the
curation away). Losing the file means losing the grading, not just a download.

Two safe options:

1. Keep the repository private. Nothing else to do.
2. Make the repo public and add `assets/data/exercises.json` to `.gitignore`,
   then run `python3 tool/build_catalogue.py` as a build step (CI and local
   setup both need network access the first time).

Until that call is made, the file stays where it is and this note records why.

## Rejected sources, and why

Checked and turned down so nobody re-litigates them:

- **wger** — only body-part categories, no yoga or stretching category, and
  per-record CC-BY-SA/ODbL licences that would infect a merged file. Still used
  live in Explore, where attribution is per-exercise.
- **everkinetic/data** — 293 items, all gym strength, CC-BY-SA share-alike.
  Adds nothing we lack.
- **exercemus/exercises** — a copy of free-exercise-db with YouTube links.
- **hasaneyldrm/exercises-dataset** — 1,324 items, but the media is
  "© Gym visual" under private permission to that author only. Unusable.
- **exercisedb (RapidAPI)** — needs a key.
- **Stuwert/yoga-builder**, **rebeccaestes/yoga_api**, **HF omergoshen/yoga_poses**
  — richer yoga data but **no licence at all**, or images taken from a
  commercial app. Do not ship.
- **Breathwork** — no open dataset exists anywhere. The breathing patterns in
  `lib/core/models.dart` are hand-authored from public technique descriptions,
  which are uncopyrightable facts.
