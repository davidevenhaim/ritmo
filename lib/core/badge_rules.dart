import 'models.dart';

/// Badge catalogue and the rules that award them (v0.4). Mirrors
/// `public.badges` and `award_badges()` in the migration so the on-device demo
/// earns exactly what the hosted graph would. Keep the two in step.
const badgeCatalogue = <AppBadge>[
  AppBadge(code: 'first_workout', name: 'First rep', emoji: '🏁', description: 'Finished a workout in the player'),
  AppBadge(code: 'workouts_10', name: 'Regular', emoji: '🔟', description: 'Ten workouts logged', tier: 2),
  AppBadge(code: 'workouts_50', name: 'Fixture', emoji: '💪', description: 'Fifty workouts logged', tier: 3),
  AppBadge(code: 'step_streak_7', name: 'One week on foot', emoji: '🔥', description: 'Hit your step goal seven days running'),
  AppBadge(code: 'step_streak_30', name: 'Thirty on foot', emoji: '🌋', description: 'Hit your step goal thirty days running', tier: 3),
  AppBadge(code: 'week_100k', name: '100k week', emoji: '👟', description: 'A hundred thousand steps in one week', tier: 2),
  AppBadge(code: 'first_post', name: 'Said hello', emoji: '📣', description: 'Shared something with the gym'),
  AppBadge(code: 'first_video', name: 'On camera', emoji: '🎬', description: 'Posted a clip', tier: 2),
  AppBadge(code: 'tried_10', name: 'Copied', emoji: '📋', description: 'Ten people tried your routines', tier: 2),
  AppBadge(code: 'league_win', name: 'League winner', emoji: '🥇', description: 'Finished first in a weekly league', tier: 2),
  AppBadge(code: 'league_podium', name: 'Podium', emoji: '🏅', description: 'Finished top three in a weekly league'),
  AppBadge(code: 'early_bird', name: 'Early bird', emoji: '🌅', description: 'Finished a workout before 7 am'),
];

AppBadge? badgeByCode(String code) => badgeCatalogue.where((b) => b.code == code).firstOrNull;

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Consecutive goal days ending today or yesterday (today may be in progress).
int stepStreak(List<StepDay> days, int goal, {DateTime? today}) {
  final byDay = {for (final d in days) _dateOnly(d.date): d.steps};
  var d = _dateOnly(today ?? DateTime.now());
  final t = byDay[d];
  if (t == null || t < goal) d = d.subtract(const Duration(days: 1));
  var n = 0;
  while (true) {
    final s = byDay[d];
    if (s == null || s < goal) break;
    n++;
    d = d.subtract(const Duration(days: 1));
    if (n > 3660) break;
  }
  return n;
}

/// Longest run of goal days ever.
int stepStreakBest(List<StepDay> days, int goal) {
  final sorted = [...days]..sort((a, b) => a.date.compareTo(b.date));
  var best = 0, run = 0;
  DateTime? prev;
  for (final d in sorted) {
    final day = _dateOnly(d.date);
    if (d.steps >= goal && (prev == null || day.difference(prev).inDays == 1)) {
      run++;
    } else if (d.steps >= goal) {
      run = 1;
    } else {
      run = 0;
    }
    if (run > best) best = run;
    prev = day;
  }
  return best;
}

/// Consecutive weeks (ending this week or last) with at least [need] workouts.
int workoutStreak(List<WorkoutLog> logs, int need, {DateTime? today}) {
  if (need <= 0) return 0;
  var wk = weekStart(today ?? DateTime.now());
  int count(DateTime start) => logs.where((l) => !l.completedAt.isBefore(start) && l.completedAt.isBefore(start.add(const Duration(days: 7)))).length;
  if (count(wk) < need) wk = wk.subtract(const Duration(days: 7));
  var n = 0;
  while (count(wk) >= need) {
    n++;
    wk = wk.subtract(const Duration(days: 7));
    if (n > 520) break;
  }
  return n;
}

Streaks computeStreaks({required List<StepDay> days, required List<WorkoutLog> logs, required UserProfile me, DateTime? today}) {
  final now = today ?? DateTime.now();
  final wk = weekStart(now);
  return Streaks(
    stepStreak: stepStreak(days, me.stepGoal, today: now),
    stepBest: stepStreakBest(days, me.stepGoal),
    workoutStreak: workoutStreak(logs, me.daysPerWeek, today: now),
    weekWorkouts: logs.where((l) => !l.completedAt.isBefore(wk)).length,
    weekSteps: days.where((d) => !_dateOnly(d.date).isBefore(wk)).fold(0, (n, d) => n + d.steps),
    totalWorkouts: logs.length,
  );
}

/// Everything the member currently qualifies for. The caller diffs against
/// what is already earned.
Set<String> qualifyingBadges({
  required List<StepDay> days,
  required List<WorkoutLog> logs,
  required UserProfile me,
  int posts = 0,
  int videoPosts = 0,
  int triesReceived = 0,
  int bestLeagueRank = 0,
}) {
  final out = <String>{};
  if (logs.isNotEmpty) out.add('first_workout');
  if (logs.length >= 10) out.add('workouts_10');
  if (logs.length >= 50) out.add('workouts_50');
  final best = stepStreakBest(days, me.stepGoal);
  if (best >= 7) out.add('step_streak_7');
  if (best >= 30) out.add('step_streak_30');
  final byWeek = <DateTime, int>{};
  for (final d in days) {
    final w = weekStart(d.date);
    byWeek[w] = (byWeek[w] ?? 0) + d.steps;
  }
  if (byWeek.values.any((v) => v >= 100000)) out.add('week_100k');
  if (posts > 0) out.add('first_post');
  if (videoPosts > 0) out.add('first_video');
  if (triesReceived >= 10) out.add('tried_10');
  if (bestLeagueRank == 1) out.add('league_win');
  if (bestLeagueRank >= 1 && bestLeagueRank <= 3) out.add('league_podium');
  if (logs.any((l) => l.completedAt.hour < 7)) out.add('early_bird');
  return out;
}
