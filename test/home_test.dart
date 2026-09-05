import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ritmo/core/local_store.dart';
import 'package:ritmo/core/models.dart';
import 'package:ritmo/core/providers.dart';
import 'package:ritmo/core/social_backend.dart';
import 'package:ritmo/core/social_repository.dart';

const me = UserProfile(
  id: 'me', name: 'Test Athlete', handle: 'test', emoji: '🙂',
  heightCm: 175, weightKg: 70, age: 30, goal: Goal.buildMuscle,
  diet: [], equipment: ['dumbbell'], daysPerWeek: 3, stepGoal: 8000,
);

Future<ProviderContainer> fresh() async {
  SharedPreferences.setMockInitialValues({});
  final store = await LocalStore.open();
  await store.put('profile', me.toJson());
  final c = ProviderContainer(overrides: [storeProvider.overrideWithValue(store)]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('profile photo', () {
    test('round-trips through json and can be cleared', () {
      final p = me.copyWith(photo: 'aGVsbG8=');
      expect(UserProfile.fromJson(p.toJson()).photo, 'aGVsbG8=');
      expect(p.copyWith(name: 'X').photo, 'aGVsbG8=', reason: 'copyWith keeps the photo by default');
      expect(p.copyWith(photo: null).photo, isNull, reason: 'explicit null clears it');
      expect(me.toJson().containsKey('photo'), isFalse);
    });
  });

  group('studio bookings', () {
    test('booking a class puts it on the plan and cancelling takes it off', () async {
      final c = await fresh();
      final n = c.read(scheduleProvider.notifier);
      final studio = SeedData.studios.first;
      final klass = studio.classes.first;

      final s = await n.book(studio: studio, klass: klass);
      expect(s.isClass, isTrue);
      expect(s.routineId, isEmpty, reason: 'the studio runs the hour, not a routine');
      expect(s.routineName, klass.name);
      expect(s.dayTitle, studio.name);
      expect(s.at.weekday, klass.weekday);
      expect(s.at.isAfter(DateTime.now()), isTrue);
      expect(c.read(bookedClassesProvider), contains(klass.id));

      // It survives a reload, and cancelling removes the plan row with it.
      expect(ScheduledWorkout.fromJson(s.toJson()).classId, klass.id);
      await n.cancelClass(klass.id);
      expect(c.read(scheduleProvider), isEmpty);
      expect(c.read(bookedClassesProvider), isEmpty);
    });
  });

  group('schedule', () {
    test('adds, sorts, ticks off on workout log, and drops stale entries from upcoming', () async {
      final c = await fresh();
      final n = c.read(scheduleProvider.notifier);
      final r = SeedData.pushPullLegs;
      final now = DateTime.now();
      await n.add(routine: r, dayIndex: 1, at: now.add(const Duration(days: 2)));
      final soon = await n.add(routine: r, dayIndex: 0, at: now.add(const Duration(hours: 1)), note: 'go light');
      await n.add(routine: r, dayIndex: 0, at: now.subtract(const Duration(days: 3)));

      final list = c.read(scheduleProvider);
      expect(list.map((s) => s.dayTitle).first, r.days[0].title);
      expect(list.first.at.isBefore(list.last.at), isTrue, reason: 'sorted by time');
      expect(c.read(upcomingWorkoutsProvider).length, 2, reason: '3-day-old entry is stale');
      expect(c.read(upcomingWorkoutsProvider).first.id, soon.id);

      await n.markDone(r.id);
      expect(c.read(scheduleProvider).firstWhere((s) => s.id == soon.id).done, isTrue, reason: 'nearest matching entry ticked');
      expect(c.read(upcomingWorkoutsProvider).length, 1);

      // Persisted.
      final again = ProviderContainer(overrides: [storeProvider.overrideWithValue(c.read(storeProvider))]);
      addTearDown(again.dispose);
      expect(again.read(scheduleProvider).length, 3);
      expect(again.read(scheduleProvider).where((s) => s.done).length, 1);
    });

    test('scheduled workout json keeps note and day index', () {
      final s = ScheduledWorkout(id: 'a', routineId: 'r', routineName: 'PPL', dayIndex: 2, dayTitle: 'Legs', at: DateTime(2026, 9, 5, 18), note: 'hi');
      final back = ScheduledWorkout.fromJson(s.toJson());
      expect(back.dayIndex, 2);
      expect(back.note, 'hi');
      expect(back.at, DateTime(2026, 9, 5, 18));
    });
  });

  group('CoG quests', () {
    test('demo friend accepts instantly and both counters add up', () async {
      final c = await fresh();
      final friend = SeedData.users['lin']!;
      final q = await c.read(questsProvider.notifier).invite(friend: friend, preset: questPresets.first);
      expect(q.accepted, isTrue, reason: 'on-device backend auto-accepts');
      expect(q.endsAt.difference(q.startsAt).inDays, 7);
      expect(q.startsAt.hour, 0, reason: 'starts at midnight today');

      // Steps provider is async; quest progress must still resolve with the friend's seed steps.
      await c.read(stepsProvider.future);
      final progress = c.read(questProgressProvider);
      expect(progress.length, 1);
      expect(progress.first.theirs, LocalSocialBackend.seedSteps('lin', q.startsAt), reason: 'one day in, one seeded day');
      expect(progress.first.mine, greaterThanOrEqualTo(0));
      expect(progress.first.pct, inInclusiveRange(0, 1));

      final text = c.read(questsProvider.notifier).inviteText(q, me);
      expect(text, contains(q.title));
      expect(text, contains('ritmo://quest/${q.id}'));

      await c.read(questsProvider.notifier).end(q.id);
      expect(c.read(questsProvider), isEmpty);
    });

    test('quest json round-trip', () {
      final q = Quest(id: 'q', title: 'T', kind: QuestKind.workouts, target: 6, friendId: 'f', friendName: 'F', friendEmoji: '🙂', startsAt: DateTime(2026, 9, 1), endsAt: DateTime(2026, 9, 8), accepted: true);
      final back = Quest.fromJson(q.toJson());
      expect(back.kind, QuestKind.workouts);
      expect(back.accepted, isTrue);
      expect(back.target, 6);
    });
  });

  group('nearby leagues', () {
    test('lists public leagues I am not in, nearest first, and hides one after joining', () async {
      SharedPreferences.setMockInitialValues({});
      final backend = LocalSocialBackend(await LocalStore.open());
      final nearby = await backend.nearbyLeagues(me);
      expect(nearby, isNotEmpty);
      expect(nearby.every((l) => l.isPublic), isTrue);
      expect(nearby.map((l) => l.id), isNot(contains('lg_walkers')), reason: 'already a member');
      expect(nearby.map((l) => l.id), isNot(contains('lg_iron')), reason: 'private, code only');
      for (var i = 1; i < nearby.length; i++) {
        expect(nearby[i - 1].distanceKm! <= nearby[i].distanceKm!, isTrue);
      }
      expect(nearby.first.memberCount, greaterThan(0));

      await backend.joinLeague(nearby.first.inviteCode, me);
      final after = await backend.nearbyLeagues(me);
      expect(after.map((l) => l.id), isNot(contains(nearby.first.id)));
      expect((await backend.myLeagues(me)).map((l) => l.id), contains(nearby.first.id));
    });

    test('pre-v0.5 installs get the public leagues added once', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      await store.putString('leagues_seeded', me.id);
      await store.put('leagues', [League(id: 'lg_mine', name: 'Mine', emoji: '🏆', ownerId: me.id, inviteCode: 'MINE01').toJson()]);
      await store.put('league_members', {'lg_mine': [me.id]});
      final backend = LocalSocialBackend(store);
      final nearby = await backend.nearbyLeagues(me);
      expect(nearby.length, 4);
      expect((await backend.myLeagues(me)).map((l) => l.id), ['lg_mine']);
      expect((await backend.nearbyLeagues(me)).length, 4, reason: 'idempotent');
    });

    test('league json keeps area and public flag', () {
      final l = League(id: 'x', name: 'N', emoji: '🌳', ownerId: 'o', inviteCode: 'ABCDEF', area: 'Park', distanceKm: 0.5, isPublic: true);
      final back = League.fromJson(l.toJson());
      expect(back.area, 'Park');
      expect(back.isPublic, isTrue);
      expect(back.distanceKm, 0.5);
      expect(leagueFromRow({'id': 'x', 'name': 'N', 'member_count': 4, 'is_public': true, 'area': 'A'}).memberCount, 4);
    });
  });
}
