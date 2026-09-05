# SoGym

The gym has a feed now. SoGym is a social workout app: share workouts, routines, daily steps,
breathing sessions and diet wins, copy routines from friends, and let an AI coach build a plan
from your body and your gear.

Built with Flutter (iOS, Android, web demo). Full plan and build report: `docs/plan.html`.

## Features

v0.1 (on-device MVP)

- Feed with follow, like, recommend and "Try it" on any routine post; Hot and Weird filters; inline video cards
- Steps from Apple Health / Health Connect (read-only), 7-day chart, one-tap share (demo data on web)
- 1,443-exercise offline library (free-exercise-db, RepDB, yoga-api and 36 written in-house), every exercise graded beginner / intermediate / advanced, plus live wger community browse
- Routine builder (multi-day, sets/reps/rest) and a set-by-set workout player with rest timer
- Five guided breathing patterns
- AI coach on Claude with `search_exercises` and `save_plan` tools; offline rule-based coach without a key
- Profile with height, weight, BMI, target, goal, diet restrictions and equipment

v0.2 (real social graph)

- Supabase backend: Apple / Google / magic-link sign-in, Postgres schema for profiles, follows, routines,
  posts, likes, recommends, comments, routine tries and notifications, all behind row-level security
- Comments on every post, an Activity screen with unread badge, realtime feed refresh
- Hosted coach: the Claude tool loop runs in a Supabase edge function that holds the API key, streams
  the reply as server-sent events, logs tool calls for evals and enforces 5 free messages a week
- Push relay edge function (FCM HTTP v1) fed by a database webhook on notifications
- The app still runs fully on-device with the seeded community when no backend is configured

v0.3 (video and creators)

- Video posts: pick a clip from the camera roll, 60-second cap checked on device, in the function and by
  the provider; direct upload to Cloudflare Stream or Mux with a one-time ticket; signed webhook flips the
  card from processing to playable; up to eight exercise tags per clip that link into the catalogue
- Creator gating and studio: apply, get approved by a moderator, upload; stats tiles, seven-day views,
  per-post views/likes/tries from one SQL function; public profile for every member at `/u/:id`
- Trust: report posts, comments and members; three open reports auto-hide a post; moderation queue with
  dismiss, hide, restore, warn, remove and suspend; every ready clip is screened by Claude from three stills
  and flagged clips are hidden with an automated report for a human decision
- Demo build simulates uploads, approves creators instantly and lets everyone open the queue

v0.4 (steps leagues, streaks, badges)

- Weekly step leagues: create with a six-letter invite code, join by code, Monday-to-Sunday standings with a
  per-member seven-day strip; daily counts visible only inside a shared league; pg_cron closes the week on
  Monday, records ranks, notifies members and awards podium badges
- Health sync on open, refresh and foreground resume through one `sync_steps()` call that also awards badges
  and returns streaks; the workout player logs finished sessions
- Step streak, best streak and weekly workout streak, identical maths in SQL and Dart
- Twelve badges on the profile; `my_league_ranks()` is the data contract for watch complications
- Demo seeds two leagues (join Deadlift Club with IRON77); closed-app background sync and the watch targets are native work still to do

## Run

```bash
flutter pub get
flutter run -d chrome     # web demo, on-device data
flutter run -d ios        # enable HealthKit capability in Xcode once (entitlements file included)
flutter run -d android    # requires the Health Connect app on the device
flutter test              # 34 tests: catalogue, coaches, social backend, video, moderation, streaks, badges, leagues
```

### With the hosted backend

```bash
# one-time project setup
supabase link --project-ref <ref>
supabase db push                                   # applies supabase/migrations
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...  # coach
supabase secrets set FCM_SERVICE_ACCOUNT="$(cat service-account.json)"   # push (optional)
supabase functions deploy coach
supabase functions deploy push --no-verify-jwt
# dashboard: enable Apple + Google providers, add io.sogym://login-callback to redirect URLs,
# add a Database Webhook: insert on public.notifications -> functions/v1/push

# video (v0.3)
supabase secrets set VIDEO_PROVIDER=cloudflare CF_ACCOUNT_ID=... CF_STREAM_TOKEN=... CF_WEBHOOK_SECRET=...
#   or: VIDEO_PROVIDER=mux MUX_TOKEN_ID=... MUX_TOKEN_SECRET=... MUX_WEBHOOK_SECRET=...
supabase functions deploy video --no-verify-jwt
# register https://<ref>.supabase.co/functions/v1/video/webhook with the provider once
# (Cloudflare: PUT /accounts/{id}/stream/webhook; Mux: dashboard -> Webhooks)
# VIDEO_UPLOADS_OPEN=1 opens uploads to everyone; otherwise creators only
# first moderator: update public.profiles set moderator = true where handle = '<you>';
cd supabase/functions && deno test video/provider_test.ts   # webhook signatures and payload mapping

flutter run --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
            --dart-define=SUPABASE_KEY=<publishable key>
```

Signed out, or without those defines, everything stays on the device and the offline coach answers.
Me → Settings → paste an Anthropic API key to use Claude directly from the device (demo only).

Push delivery to devices still needs the Firebase client (`firebase_messaging` plus the platform
config files) to register tokens into `push_tokens`; the server side is complete.

## Layout

- `lib/core/` models, providers, exercise catalogue, health, coaches (`ai_coach.dart`, `remote_coach.dart`),
  social backends (`social_backend.dart`: local seed and Supabase), backend config and auth (`backend.dart`)
- `lib/features/` one folder per screen: feed (with comments and report sheets), explore, coach, breathe,
  routines, steps, profile, notifications, auth, onboarding, video (card, composer), creator (public
  profile, studio), moderation (queue)
- `lib/core/video_service.dart` clip picking and measuring, demo and hosted uploaders
- `lib/core/badge_rules.dart` badge catalogue, streak maths and award rules shared by the demo backend and tests
- `lib/features/leagues/` league list, create/join sheet, weekly table
- `supabase/migrations/` social graph; video, creators, reports and moderation; leagues, streaks and badges
- `supabase/functions/coach` streaming coach; `functions/push` FCM relay; `functions/video` upload
  tickets and provider webhooks; `functions/_shared` prompt, tools, catalogue search, Cloudflare/Mux
  adapters and Claude screening

## Data and licenses

- free-exercise-db (Unlicense), bundled at `assets/data/exercises.json`, images from the project CDN
- wger.de (AGPL code, CC-BY-SA content), consumed via public API
