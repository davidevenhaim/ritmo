# Handoff: Nocturne Fit — workout social app

## Overview
A mobile fitness social app on a dark, low-chroma interface. Progress is the front door: weekly streak, volume, steps and resting HR, goals, the week's shape, then the plan and the follow feed. A raised **Start** button in the middle of the bottom bar opens a routine picker (resume / your routines / recommended / friends' shared / create new). Routines are built by dragging exercises onto a proportional session timeline, with an AI assist that drafts a block. A Community tab carries studio classes (with paid booking), coaches' workouts, and a prompt-based AI coach. Exercise library and a coach-side dashboard sit under Me.

## About the design files
`Nocturne Fit.dc.html` in this bundle is a **design reference created in HTML** — a working prototype of the intended look and behavior, not production code to copy. Recreate these screens in your app's existing environment (React Native, Swift/SwiftUI, Kotlin/Compose, Flutter, React web) using its established components, navigation and state patterns. If the app has no UI conventions yet, pick the framework that fits the product and implement there.

It is a single-file component with an inline-styled template plus a logic class holding all state — treat the template as markup spec and the logic class as behavior spec. Everything is inline-styled on purpose (streaming preview constraint); in a real codebase, move these values into your theme/token layer.

## Fidelity
**High-fidelity.** Colors, type sizes, radii, spacing and interaction states are final and should be matched. Two deliberate exceptions:
- **Exercise media is placeholder.** Every diagonal-striped grey tile is where a looping exercise GIF goes (theme hero art, library tiles, timeline thumbnails, coach avatars, studio headers). Sizes and radii are correct; swap in real media.
- Avatars are initials-in-a-circle placeholders.

## Design tokens
From the Nocturne design system (full sheet in `reference/nocturne-styles.css`).

**Color**
| Role | Value |
| --- | --- |
| Page ground | `#161826` |
| Surface / card | `#232532` |
| Sunken surface (inner rows, tiles) | `#292b31` |
| Sheet ground | `#1d1f2c` |
| Text | `#e9e9ed` |
| Text muted | `#9397ab` |
| Text dim / labels | `#75798c` |
| Hairline border | `#3f424d` |
| Divider (inside cards) | `#292b31` |
| Accent | `#9184d9` |
| Accent hover / light | `#a396e8`, `#b5abfc`, `#d2cefd`, `#e7e5fe` |
| Accent pressed / deep | `#796cbf`, `#5d5294`, `#423a6a`, `#2b2741` |
| Backdrop scrim | `rgba(15,17,28,.74)` + `backdrop-filter: blur(3px)` |

Ramps are OKLCH-generated; on this dark ground use 700–900 for tinted fills, 500 as base, 100–300 for text on tints. Never pure black or white.

**Type** — Inter, weights 400/500/600. Headings are weight **500 only** (never bolder); hierarchy is size and space.
Screen title 26px/-.025em · section title 15px · card title 14–15px · body 13px · meta 11–11.5px · uppercase kicker 10.5–11px with .10–.12em tracking · tab label 9.5px · big numeral 40px/-.03em (streak), 19–22px (stats).

**Spacing** — dense, 0.7× scale: 2.8 / 5.6 / 8.4 / 11.2 / 16.8 / 22.4px. Screen gutter 18px. Card padding 13–16px. Gaps 8–12px. Section separation 20–24px.

**Radius** — 48px phone shell · 24px sheet top corners · 16–18px cards · 13–14px inner rows · 11–12px small controls · 9–10px icon buttons · 50% circles.

**Elevation** — a hairline plus ambient darkness, never stacked shadows.
- Card: `box-shadow: 0 0 0 1px #3f424d`
- Accent-lifted card: `0 0 0 1px #423a6a` or `#5d5294`
- Hover on tappable card: `0 0 0 1px #9184d9`
- Dialog: `0 0 0 1px #9397ab, 0 16px 40px rgba(0,0,0,.65)`
- Start button: `0 0 0 5px #161826, 0 0 28px rgba(145,132,217,.55)`

**Buttons** — primary is an accent **outline**, never a solid fill (`color/border: #9184d9`, transparent ground; hover `rgba(145,132,217,.12)`, active `.22`). The Start circle is the one intentional accent fill. Focus is `outline: 2px solid #9184d9; outline-offset: 2px` — never the browser default.

**Icons** — Phosphor regular, inline SVG on `currentColor`, `viewBox="0 0 256 256"`. Used: barbell, users-three, user, user-plus, list, clipboard-text, caret-right, caret-down, arrow-left, x, check, plus, fire, footprints, heartbeat, heart, sparkle, play, dots-six-vertical, arrows-out-simple, paper-plane-tilt. Install `@phosphor-icons/*` for your platform rather than copying paths.

**Motion**
| Name | Definition | Used for |
| --- | --- | --- |
| `nfIn` | 12px rise + fade, 260–340ms ease | screen enter, sheet body, chat bubbles, toast |
| `nfPop` | scale .92 → 1 + fade, 200–300ms ease | dialogs, timeline rows (60ms stagger by index), goal cards, exercise tiles |
| `nfPulse` | opacity .3 ⇄ .9, 1–2s ease-in-out infinite | "looping GIF" dot on media placeholders, today's streak dot, chat typing dots |
| `nfSweep` | gradient bar sliding left→right, 1s linear infinite | AI assist drafting bar |
| Timeline segment width | `transition: width .35s ease` | proportional session bar |
| Toggle knob | `transition: left .2s`, track `background .2s` | switches |
| Goals chevron | `transform: rotate(180deg)`, `.2s` | expand/collapse |

## Device shell
Prototype frame: 392 × 844, radius 48px, `overflow: hidden`. Status bar 46px. Scroll area `flex:1`, padding `0 18px 108px`. Bottom bar absolutely positioned, 88px tall, `linear-gradient(to top, rgba(22,24,38,.98) 40%, rgba(22,24,38,.72))` + `backdrop-filter: blur(14px)`, top border `#292b31`, home indicator 132×5 at `bottom:8px`. In a real app use safe-area insets instead of these fixed numbers.

## Navigation
Three tabs; **Start is the middle item and is not a screen** — it opens a bottom sheet.

| Tab | Icon | Screen |
| --- | --- | --- |
| Me | `user` | `me` |
| Start | `barbell` in a filled 54px accent circle | opens Start sheet |
| Community | `users-three` | `community` |

Tab column: icon 21px, label 9.5px, gap 5px, `padding: 11px 10px 0`. Active label/icon `#e9e9ed`, inactive `#75798c`. The Start column keeps a 21px-tall spacer box so all five labels share one baseline; the circle is absolutely positioned at `top:-38px` inside it, so it protrudes above the bar and its 5px ring clears the label. Start's label is always `#b5abfc`, weight 500.

Sub-screens (`exercises`, `coach`, `aicoach`, `build`) are pushed views with a 32px back button (`arrow-left`, 11px radius, surface ground). The **Me** tab stays lit while in `exercises` or `coach`; **Community** stays lit while in `aicoach`.

## Screens

### 1. Me (`me`) — the home screen
Purpose: see progress first, then the week, then the plan, then other people. Order is deliberate — do not reshuffle.

1. **Header row** — 42px circle avatar (initials, `linear-gradient(150deg,#423a6a,#232532)`, hairline `#595d6c`, 14px/600 `#d2cefd`), then "Good evening" 11.5px `#75798c` over "Maya Adler" 19px/500. Right: 36px `user-plus` button → invite dialog.
2. **Streak card** — 18px radius, `linear-gradient(155deg,#2b2741,#1d1f2c 70%)`, ring `#423a6a`. A 170px radial accent bloom sits at `right:-40px; top:-50px`. Kicker "WEEKLY STREAK" `#b5abfc`; "12" at 40px/500 beside "weeks unbroken" 13px `#9397ab`; 30px `fire` icon top-right. Below: seven 30px-tall day cells, gap 6px — completed `#423a6a` with a 13px `check`, missed/future `#292b31`, today transparent with `inset 0 0 0 1.5px #9184d9` and a 6px pulsing accent dot. Letters M T W T F S S 10px below.
3. **Stat row** — left card (flex 1): "Volume" + `arrows-out-simple`, then a 56px SVG ring (r=23, track `#292b31` 6px, accent arc `stroke-dasharray="104 145"`, rotated -90°) beside "72%" 22px and "of 18k kg" 10.5px. Right column (flex 1, gap 10px): two small cards — "Steps" 8,240 with an 18px `footprints` glyph in `#5d5294`, and "Resting HR" 54 bpm with `heartbeat`.
4. **Goals card (collapsible)** — header row: "Goals" 14px, subline `"{n} active · tap to see all"` (flips to "tap to collapse"), the average completion as 19px `#b5abfc`, and a `caret-down` that rotates 180° when open. Under the header, one 6px mini progress bar per goal (flex 1, gap 5px, `#292b31` track, `linear-gradient(to right,#5d5294,#9184d9)` fill). Expanded: a `#292b31` card per goal with name, value, 5px bar, note; then a dashed "Set a goal" button (`1px dashed #5d5294`) opening the goal dialog.
5. **This week** — section head "This week" + "Sep 1 – 7". Card with a 112px-tall row of seven 9px-wide bars, radius 5px, `justify-content: flex-end`. Heights: 44 / 62 / 18 / 71 / 88 / 30 / 8 %. Colors: `#3f424d` low, `#5d5294` medium, `#9184d9` peak; the peak bar carries a 9.5px pill label "4.1k kg" on `#423a6a` above it and its weekday label is `#d2cefd`.
6. **Your plan** — kicker "WEEK 36", title "Your plan" 17px; right side a 32px accent-outlined `plus` (opens builder) and a secondary "Share" button. Subline `"{n} sessions · 4h 10m · 3 themes"`. Then seven day rows separated by `1px solid #292b31`: a 44px column (weekday 11px over date 17px/500 — today in `#d2cefd`, others `#75798c`) beside the day's sessions. Session card: 14px radius, surface, a 3px × 26px accent bar, name 14px/500, meta 11px, theme `tag-accent` pill. Empty day: dashed row "Rest — add a session" with a `plus` → builder.
7. **From people you follow** — head + "See all" (→ Community). Post card: 28px initials avatar, name 12.5px, relative time 10.5px right; title 14px/500; then a stat strip above a `1px solid #292b31` top border with three columns (Volume / Time / PR), 9.5px uppercase labels over 13.5px values, PR in `#b5abfc`.
8. **Nutrition** — "Calories today" 1,840 / 2,200 with an 84% gradient bar, then three equal `#292b31` tiles: 142g Protein · 186g Carbs · 58g Fat.
9. **Account list** — one 16px-radius surface card, rows split by `1px #292b31`, each `13px 14px`, hover `#282b38`:
   - Apple Health (`heart`) + subline "Steps, heart rate, sleep, workouts" / "Not connected" + toggle.
   - Invite a friend to train (`user-plus`) → invite dialog.
   - Exercise library (`list`) → `exercises`.
   - Coach dashboard (`clipboard-text`, accent) "148 athletes · 22 published workouts" → `coach`.

Toggle spec (used in three places): 40 × 24 track, radius 12; on `#9184d9`, off `#3f424d`; 18px white-ish knob (`#e9e9ed`) at `left:3px` → `left:19px`.

### 2. Start sheet (modal, from the middle tab)
Bottom sheet: full width, `max-height: 86%`, scrollable, ground `#1d1f2c`, radius `24px 24px 48px 48px`, `box-shadow: 0 -1px 0 #423a6a`, padding `16px 18px 36px`, 38 × 4 grab handle centered. Title "Start a workout" 20px + `x`. Tapping the scrim closes; taps inside must `stopPropagation`.

Sections in order:
1. **Resume** (only when a session is in progress) — accent-lifted card, 38px filled accent circle with `play`, kicker "RESUME", session name, "4 of 7 done · 22 min left".
2. **Your routines** — uppercase 11px header with a 28px accent-outlined `plus` on the right (→ builder). Rows: 34px media placeholder, name 13.5px/500, meta 10.5px, theme pill, `play` glyph. Seed data plus anything the user saved this session.
3. **Because you train pulling on Fridays** — recommendations (coach- and context-derived), same row shape without the theme pill.
4. **Shared by friends** — 30px initials avatar, name, "Noa Levi · 6 exercises · 52 min · 41 copies".
5. **Create a new routine** — dashed accent row with `plus`, subline "Pick a theme, build it on the timeline, or let AI draft it" → builder.

Starting any routine closes the sheet and shows a toast; a friend's routine also copies to your routines.

### 3. Routine builder (`build`) — three steps
**Step 1 — Pick a theme.** Back button, "Step 1 of 3", title "Pick a theme", note "2,183 exercises, grouped…". 2-column grid, gap 10px. Theme card: 76px hero-art placeholder (diagonal stripes + a radial accent bloom at 80% 20% + a 9px "HERO ART" label) over name 14.5px, count 10.5px `#75798c`, hint 10.5px `#5d5294`. Six themes: Bodyweight (412), Gym (906), Flexibility (238), Handstand (126), Calisthenics (314), Core (187).

**Step 2 — Build the session.** Header: back, theme name as accent kicker, "Build the session" 19px, and an "AI" pill button (`sparkle`, accent outline) opening the AI assist sheet.

*Timeline card* — 18px radius, `linear-gradient(160deg,#232532,#1c1e2b)`, ring `#423a6a` which turns accent while a drag is over it (drop target). Header "Session timeline" + total minutes. Then a 10px-tall segmented bar: one segment per exercise, width `= duration / total`, alternating `#9184d9` / `#5d5294`, 3px gaps, `transition: width .35s`. Empty state: dashed box "Drag exercises up here / or tap one to append it · or let AI draft the block". Populated: one row per exercise — index number, 34px media placeholder with a pulsing dot, name 13px/500, meta 10.5px, an `x` remove button, and a `dots-six-vertical` drag handle (`cursor: grab`); rows animate in with a 60ms-per-index stagger and the dragged row's ring goes accent. Below, a full-width accent-outline "Review & save".

*Library* — "{Theme} library" + count, then a 2-column grid of exercise tiles: 74px media placeholder with a "GIF" chip top-left and a pulsing dot bottom-right, name 12.5px, meta 10.5px ("3 × 12 · chest").

Interactions: tiles are both `draggable` (drop on the timeline card appends) and tappable (appends). Timeline rows reorder by drag — `dragStart` records the index, `dragEnter` on another row splices the item to that position and updates the recorded index.

*AI assist sheet* — bottom sheet, `sparkle` + "AI assist", note "Tell it what today should be. It drafts onto your timeline — you keep editing." Three selectable prompt rows (selected ring goes accent), a free-text input plus a "Build it" button that switches to "Drafting" and shows the `nfSweep` bar for ~1.1s, then fills the timeline with five exercises from the theme and toasts "AI drafted 5 exercises — reorder or swap any of them."

**Step 3 — Name it, then send it.** "Step 3 of 3", title "Name it, then send it". Card: "Routine name" text field (prefilled), then Theme / Exercises / Duration as three labelled facts. Second card: two toggle rows — "Share to my followers" (on by default, "They can copy it into their own week") and "Invite Noa to train it with me" (off, "Friday 18:30 · Bloc Studio"). Footer: "Back" secondary (flex 1) + "Save routine" primary (flex 2). Saving appends the routine to Saturday in the plan and to Your routines, returns to Me, and toasts "Saved to Saturday and shared to your feed." (or without the share clause).

### 4. Community (`community`)
Title "Community" 26px, then two pill filters "Studios" / "Coaches" (selected: `rgba(145,132,217,.16)` ground, accent inset ring, `#d2cefd` text).

**AI coach card** (always above both lists) — accent-lifted 18px card with a radial bloom, 40px `#423a6a` tile holding a `sparkle`, kicker "ALWAYS ON", "Ask the AI coach", subline "Form, programming, soreness, swaps, nutrition", `caret-right`. Opens `aicoach`.

**Studios tab** — per studio: 96px striped header image placeholder with a `linear-gradient(to top,#232532,transparent 70%)` scrim, name 17px and address/distance 11px bottom-left, a `tag-outline` kind chip top-right. Then class rows split by `1px #292b31`: 52px time column (14px/500 time over 10px day), name 13px + meta ("Dana K. · 60 min · 4 spots"), and a Join button. Seeded: Bloc Studio (Ring basics Fri 18:30 ₪90; Handstand lab Sat 07:00 ₪110; Open gym Sat 11:00 ₪45) and Northline Mobility (Hip opening Mon 19:15 ₪80; Split progressions Wed 08:00 ₪95).

*Booking dialog* — centered, 20px radius, "BOOK A CLASS" kicker, class name 19px, "{studio} · {day} {time} · {meta}", then a `#292b31` receipt block: Drop-in price, "Studio credit − 20.00" in `#b5abfc`, hairline, Total 14px. Actions: "Cancel" secondary (flex 1), "Pay & join" primary (flex 2). On confirm the class button becomes a non-accent "Booked", and a toast says it was added to the week. Tapping an already-booked class just toasts the time.

**Coaches tab** — per coach: 44px avatar placeholder, name 15px, spec 11px, and a "Following" chip when followed. Then workout rows on `#292b31`: 3px `#5d5294` bar, name 13px, meta 10.5px, and a 28px accent-outlined button whose glyph is `plus` → `check` once added. Adding drops the workout into Wednesday and toasts. Seeded: Dana Katz (rings, following), Ilan Mor (handstand), Rita Shani (mobility).

### 5. AI coach (`aicoach`)
Back button, "AI COACH" kicker, "Ask anything" 19px, and a "Clear" text action.

Empty state: an accent-lifted card — "It knows your log" / "12-week streak, pulling on Fridays, handstand goal at 14s. Answers are written against that, not generic advice." — then a "TRY" header and five tappable suggestion rows (each with a 5px accent dot): wrist pain in handstands, swap the muscle-up drill, build a 30-minute pull session, protein for bodyweight, training sore hamstrings.

Thread: user bubbles right-aligned on `#2b2741` (ring `#5d5294`, text `#e7e5fe`), assistant bubbles left-aligned on `#232532` (ring `#3f424d`); `max-width: 82%`, radius 16px, 13px/1.55 text. While waiting, three pulsing accent dots (180ms stagger). Composer is sticky to the bottom with a `linear-gradient(to top,#161826 60%,transparent)` fade: text input plus a 36px filled accent send button (`paper-plane-tilt`); Enter sends.

In the prototype, replies are keyword-matched canned answers (wrist/pain, swap/easier, build/routine/30, protein/nutrition, hamstring/sore/rest) with a generic fallback, and the routine answer additionally offers an **"Open it in the builder"** button that jumps to step 2 with five exercises preloaded. In production this is your LLM call — keep the same shape: the answer is written against the user's log (streak, weekday pattern, current goal values, recent volume), and a routine answer returns a structured routine the builder can open.

### 6. Exercises (`exercises`)
Back button, "Exercises" 22px, "2,183 looping demos across six themes". A search input, then a horizontally scrolling row of six theme chips (selected chip = accent tint + accent inset ring). Head "{Theme}" / "Results" plus "{n} shown", then a 2-column grid of 82px-media exercise tiles (same tile as the builder library). Typing searches name + meta across **all** themes and deselects the theme chips; empty result shows a dashed "Nothing matches that. Try a muscle group or a movement." Tapping a tile opens the exercise detail (prototype: toast "{name} — demo, cues and 3 progressions").

### 7. Coach dashboard (`coach`)
Back button, "COACH MODE" kicker, "Your athletes" 23px. Three equal stat cards: 148 Athletes · 86% Completion · 22 Published (accent numeral). "Published workouts" head with a 30px accent-outlined `plus` (→ builder). Per workout: name 14px, meta 10.5px, `tag-neutral` theme chip; below a `1px #292b31` divider, "Sent to 148 athletes · 86% done" and a "Send again" accent-outline button (toasts).

### Toast
Absolute, `left/right: 16px; bottom: 100px`, radius 14px, `#2b2741`, ring `#5d5294`, drop shadow, 12.5px `#e7e5fe`, enters with `nfIn`, auto-dismisses after 2.6s (each new toast cancels the previous timer). Used for every confirm/undoable action.

## State
Single view-model in the prototype; split per feature in production.

| State | Type | Notes |
| --- | --- | --- |
| `screen` | `'me' \| 'build' \| 'community' \| 'aicoach' \| 'exercises' \| 'coach'` | tab + pushed views |
| `step`, `theme`, `timeline[]`, `name`, `share`, `friend` | builder | `timeline` items are `{id,name,meta,dur}`; `dur` in minutes drives segment widths |
| `dragFrom`, `pending`, `dragOver` | drag/drop | `pending` = library item being dragged in; `dragFrom` = timeline index being reordered |
| `plan` | 7 days × sessions | starts from a seeded week; builder saves into Saturday, coach workouts into Wednesday |
| `saved[]` | routines the user built | appended to "Your routines" |
| `goals[]`, `goalsOpen`, `showGoal` | goals | `pct` drives both the mini bars and the average |
| `booked{}`, `added{}` | id → true | class bookings, coach workouts added |
| `communityTab` | `'studios' \| 'coaches'` | |
| `chat[]`, `chatDraft`, `chatThinking`, `chatOffer` | AI coach | `chatOffer` shows the "Open it in the builder" button |
| `showStart`, `showAi`, `showPay`, `showInvite` | overlays | one at a time |
| `health`, `friendPick`, `exTheme`, `exQuery`, `toast` | misc | |

Real data this needs behind it: HealthKit/Health Connect (steps, resting HR, sleep, workouts), an exercise catalogue with looping media and theme/muscle metadata, routines and weekly plans (own + shared + copy counts), a social graph and workout-receipt feed, studios with class schedules/capacity and payments, coach publishing with per-athlete completion, goals, nutrition logs, and an LLM endpoint for the coach and the builder draft.

## Assets
- **Icons**: Phosphor regular — install the package for your platform.
- **Font**: Inter 400/500/600.
- **Exercise media**: none included. Every striped grey rectangle is a placeholder for a looping GIF/short video; keep the frame sizes (76px theme hero, 74–82px library tile, 34px timeline/routine row, 96px studio header, 44px coach avatar).

## Screenshots
`screenshots/` — 16 captures of the states described above, in order:
01–03 Me (top / plan / feed & account) · 04 Start sheet · 05 builder step 1 (themes) · 06 builder step 2 (empty timeline + library) · 07 timeline with three exercises · 08 AI assist sheet · 09 Community (studios) · 10 booking dialog · 11 Coaches tab · 12 AI coach empty state · 13 AI coach thread · 14 Me (Account list) · 15 Exercises · 16 Coach dashboard.

The left-hand column in each capture is prototype scaffolding notes, not part of the app.

## Files
- `Nocturne Fit.dc.html` — the full prototype (all screens, all interactions).
- `reference/nocturne-styles.css` — the Nocturne design-system token + component sheet the design is built on.

Open the prototype in a browser to click through it: it runs standalone apart from the stylesheet path, which points at the design-system folder — repoint the `<link>` to `reference/nocturne-styles.css` if you move the file.
