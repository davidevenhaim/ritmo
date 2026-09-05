import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ritmo/core/local_store.dart';
import 'package:ritmo/core/models.dart';
import 'package:ritmo/core/providers.dart';
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
  group('training invites', () {
    test('inviting friends puts them on the session, once each, and persists', () async {
      final c = await fresh();
      final n = c.read(scheduleProvider.notifier);
      final s = await n.add(
        routine: SeedData.pushPullLegs,
        dayIndex: 0,
        at: DateTime.now().add(const Duration(hours: 3)),
      );

      final maya = SeedData.users['maya']!;
      final dario = SeedData.users['dario']!;
      await n.invite(sessionId: s.id, friends: [maya, dario]);
      // A second invite for somebody already on the session is a no-op.
      final again = await n.invite(sessionId: s.id, friends: [maya]);

      expect(again.guests.map((g) => g.id), ['maya', 'dario']);
      expect(again.guests.first.emoji, maya.emoji);
      expect(again.guests.every((g) => g.accepted), isTrue, reason: 'demo friends accept on the spot');
      expect(c.read(trainingInvitesProvider).single.id, s.id);

      // Survives a reload through the store.
      final round = ScheduledWorkout.fromJson(again.toJson());
      expect(round.guests.map((g) => g.name), ['Maya Chen', 'Dario Okafor']);

      await n.uninvite(s.id, 'maya');
      expect(c.read(scheduleProvider).single.guests.map((g) => g.id), ['dario']);
    });

    test('a solo session carries no guests and stays out of the invite list', () async {
      final c = await fresh();
      final s = await c.read(scheduleProvider.notifier).add(
            routine: SeedData.pushPullLegs,
            dayIndex: 0,
            at: DateTime.now().add(const Duration(days: 1)),
          );
      expect(s.guests, isEmpty);
      expect(s.toJson().containsKey('guests'), isFalse);
      expect(c.read(trainingInvitesProvider), isEmpty);
    });

    test('the invite text names the session, the time and the deep link', () async {
      final c = await fresh();
      final n = c.read(scheduleProvider.notifier);
      final s = await n.add(
        routine: SeedData.pushPullLegs,
        dayIndex: 0,
        at: DateTime(2026, 9, 8, 18, 30),
      );
      final text = n.inviteText(s, me);
      expect(text, contains('Test Athlete invited you to train'));
      expect(text, contains(SeedData.pushPullLegs.name));
      expect(text, contains('Tue 8 Sep'));
      expect(text, contains('ritmo://training/${s.id}'));
    });

    test('past invites drop off the list', () async {
      final c = await fresh();
      final n = c.read(scheduleProvider.notifier);
      final s = await n.add(
        routine: SeedData.pushPullLegs,
        dayIndex: 0,
        at: DateTime.now().subtract(const Duration(days: 2)),
      );
      await n.invite(sessionId: s.id, friends: [SeedData.users['lin']!]);
      expect(c.read(trainingInvitesProvider), isEmpty);
    });
  });
}
