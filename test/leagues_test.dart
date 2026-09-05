import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ritmo/core/badge_rules.dart';
import 'package:ritmo/core/local_store.dart';
import 'package:ritmo/core/models.dart';
import 'package:ritmo/core/social_backend.dart';

const me = UserProfile(
  id: 'me', name: 'Test Athlete', handle: 'test', emoji: '🙂',
  heightCm: 175, weightKg: 70, age: 30, goal: Goal.buildMuscle,
  diet: [], equipment: ['dumbbell'], daysPerWeek: 2, stepGoal: 8000,
);

Future<LocalStore> freshStore() async {
  SharedPreferences.setMockInitialValues({});
  return LocalStore.open();
}

final today = DateTime(2026, 9, 4); // a Friday
StepDay day(int daysAgo, int steps) => StepDay(today.subtract(Duration(days: daysAgo)), steps);
WorkoutLog log(DateTime at) => WorkoutLog(id: 'w${at.millisecondsSinceEpoch}', userId: me.id, completedAt: at, routineName: 'PPL');

void main() {
  group('streak math', () {
    test('step streak counts goal days ending today or yesterday', () {
      final days = [day(0, 3000), day(1, 9000), day(2, 8000), day(3, 8500), day(4, 100), day(5, 9000)];
      expect(stepStreak(days, 8000, today: today), 3); // today in progress does not break it
      expect(stepStreak([day(0, 9000), day(1, 9000)], 8000, today: today), 2);
      expect(stepStreak([day(1, 100), day(2, 9000)], 8000, today: today), 0);
      expect(stepStreakBest(days, 8000), 3);
      expect(stepStreakBest([day(10, 9000), day(9, 9000), day(7, 9000)], 8000), 2); // gap resets
    });

    test('workout streak counts consecutive weeks meeting days per week', () {
      final thisMonday = weekStart(today);
      final logs = [
        log(thisMonday.add(const Duration(days: 1, hours: 18))),
        log(thisMonday.subtract(const Duration(days: 6))),
        log(thisMonday.subtract(const Duration(days: 4))),
        log(thisMonday.subtract(const Duration(days: 12))),
        log(thisMonday.subtract(const Duration(days: 10))),
      ];
      // This week has one workout so far (need 2): streak counts from last week.
      expect(workoutStreak(logs, 2, today: today), 2);
      logs.add(log(thisMonday.add(const Duration(days: 3, hours: 6))));
      expect(workoutStreak(logs, 2, today: today), 3);
      expect(workoutStreak(logs, 0, today: today), 0);
      final s = computeStreaks(days: [day(0, 5000), day(1, 9000)], logs: logs, me: me, today: today);
      expect(s.weekWorkouts, 2);
      expect(s.weekSteps, 14000);
      expect(s.totalWorkouts, 6);
    });

    test('badge rules mirror the SQL function', () {
      final ten = List.generate(10, (i) => day(i, 9000));
      final earlyLog = log(DateTime(2026, 9, 3, 6, 30));
      final q = qualifyingBadges(days: ten, logs: [earlyLog], me: me, posts: 1, videoPosts: 1, triesReceived: 12, bestLeagueRank: 1);
      expect(q, containsAll(['first_workout', 'step_streak_7', 'first_post', 'first_video', 'tried_10', 'league_win', 'league_podium', 'early_bird']));
      expect(q, isNot(contains('workouts_10')));
      expect(q, isNot(contains('step_streak_30')));
      final bigWeek = List.generate(7, (i) => StepDay(weekStart(today).add(Duration(days: i)), 15000));
      expect(qualifyingBadges(days: bigWeek, logs: const [], me: me), contains('week_100k'));
      expect(qualifyingBadges(days: bigWeek, logs: const [], me: me), isNot(contains('first_workout')));
      expect(badgeCatalogue.map((b) => b.code).toSet().length, badgeCatalogue.length);
      for (final code in q) {
        expect(badgeByCode(code), isNotNull, reason: code);
      }
    });
  });

  group('local backend v0.4', () {
    test('sync awards badges once and notifies; streaks follow', () async {
      final b = LocalSocialBackend(await freshStore());
      await b.load(me);
      final r1 = await b.syncSteps(List.generate(8, (i) => StepDay(DateTime.now().subtract(Duration(days: i)), 9000)), me);
      expect(r1.newBadges, contains('step_streak_7'));
      expect(r1.streaks.stepStreak, 8);
      expect((await b.notifications()).where((n) => n.kind == NotificationKind.badge).length, r1.newBadges.length);
      final r2 = await b.syncSteps([StepDay(DateTime.now(), 9500)], me);
      expect(r2.newBadges, isEmpty);
      expect((await b.streaks(me)).stepStreak, 8);
    });

    test('logging workouts earns first_workout and drives the weekly streak', () async {
      final b = LocalSocialBackend(await freshStore());
      await b.load(me);
      final r = await b.logWorkout(WorkoutLog(id: 'w1', userId: me.id, completedAt: DateTime.now(), routineName: 'PPL', dayTitle: 'Push', sets: 12), me);
      expect(r.newBadges, contains('first_workout'));
      expect(r.streaks.weekWorkouts, 1);
      expect((await b.badges(me.id)).map((x) => x.code), contains('first_workout'));
      expect((await b.badges('ben')).map((x) => x.code), contains('first_video'));
    });

    test('seeded leagues: I am in Lunch Walkers, can join Deadlift Club by code, standings rank everyone', () async {
      final b = LocalSocialBackend(await freshStore());
      await b.load(me);
      final mine = await b.myLeagues(me);
      expect(mine.map((l) => l.name), ['Lunch Walkers']);
      expect(mine.single.memberCount, 5);

      final joined = await b.joinLeague(LocalSocialBackend.seedJoinCode.toLowerCase(), me);
      expect(joined.name, 'Deadlift Club');
      expect((await b.myLeagues(me)).length, 2);
      expect(() => b.joinLeague('NOPE00', me), throwsA(isA<StateError>()));

      await b.syncSteps([StepDay(DateTime.now(), 12000)], me);
      final rows = await b.standings(mine.single.id, me);
      expect(rows.length, 5);
      expect(rows.map((r) => r.rank), [1, 2, 3, 4, 5]);
      expect(rows.every((r) => r.days.length == 7), isTrue);
      expect(rows.firstWhere((r) => r.userId == me.id).steps, greaterThanOrEqualTo(12000));
      for (var i = 1; i < rows.length; i++) {
        expect(rows[i - 1].steps >= rows[i].steps, isTrue);
      }
      final ranks = await b.myLeagueRanks(me);
      expect(ranks.length, 2);
      expect(ranks.first.of, 5);
      expect(ranks.first.daysLeft, inInclusiveRange(1, 7));
    });

    test('create, then leave: an empty league disappears', () async {
      final b = LocalSocialBackend(await freshStore());
      await b.load(me);
      final l = await b.createLeague('Office walkers', '🏢', me);
      expect(l.inviteCode.length, 6);
      expect(l.ownerId, me.id);
      expect((await b.myLeagues(me)).map((x) => x.id), contains(l.id));
      await b.leaveLeague(l.id, me);
      expect((await b.myLeagues(me)).map((x) => x.id), isNot(contains(l.id)));
      expect(() => b.joinLeague(l.inviteCode, me), throwsA(isA<StateError>()));
    });
  });

  group('row mapping v0.4', () {
    test('league, standing, rank and streak payloads parse', () {
      final l = leagueFromRow({'id': 'a', 'name': 'X', 'emoji': '🏆', 'owner_id': 'u', 'invite_code': 'ABC123', 'max_members': 20, 'members': [{'count': 4}]});
      expect(l.memberCount, 4);
      final s = Standing.fromJson({'userId': 'u', 'name': 'Ann', 'handle': 'ann', 'emoji': '🙂', 'steps': 12000, 'rank': 1, 'days': [1, 2, 3, 4, 5, 6, 7]});
      expect(s.days.length, 7);
      final r = LeagueRank.fromJson({'leagueId': 'a', 'name': 'X', 'emoji': '🏆', 'rank': 2, 'of': 5, 'steps': 100, 'leaderSteps': 250, 'daysLeft': 3});
      expect(r.gapToLeader, 150);
      expect(Streaks.fromJson({'stepStreak': 4, 'workoutStreak': 1}).stepStreak, 4);
      expect(League.fromJson(l.toJson()).inviteCode, 'ABC123');
      for (final k in [NotificationKind.league, NotificationKind.badge]) {
        expect(AppNotification.fromJson(AppNotification(id: 'n', kind: k, createdAt: DateTime(2026)).toJson()).kind, k);
      }
    });
  });
}
