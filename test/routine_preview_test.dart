import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ritmo/core/exercise_repository.dart';
import 'package:ritmo/core/local_store.dart';
import 'package:ritmo/core/models.dart';
import 'package:ritmo/core/providers.dart';
import 'package:ritmo/core/routine_insight.dart';
import 'package:ritmo/core/social_repository.dart';
import 'package:ritmo/features/routines/routine_preview_screen.dart';

const bodyweightAthlete = UserProfile(
  id: 'me', name: 'Test Athlete', handle: 'test', emoji: '🙂',
  heightCm: 175, weightKg: 70, age: 30, goal: Goal.buildMuscle,
  diet: [], equipment: ['body only'], daysPerWeek: 3,
  experience: ExperienceLevel.beginner,
);

ExerciseRepository loadCatalogue() {
  final raw = File('assets/data/exercises.json').readAsStringSync();
  return ExerciseRepository((jsonDecode(raw) as List).map((e) => Exercise.fromJson(Map<String, dynamic>.from(e as Map))).toList());
}

void main() {
  late ExerciseRepository repo;
  setUpAll(() => repo = loadCatalogue());

  // ------------------------------------------------------------- insight
  group('reading a shared routine', () {
    test('resolves every exercise into a grade, a muscle list and kit', () {
      final i = RoutineInsight.of(SeedData.pushPullLegs, repo);

      expect(i.graded, SeedData.pushPullLegs.exerciseCount, reason: 'the whole seed routine is in the catalogue');
      expect(i.ungraded, 0);
      expect(i.level, ExerciseLevel.intermediate);
      expect(i.equipment, contains('barbell'));
      expect(i.muscles, isNotEmpty);
      expect(i.minutes, greaterThan(0));
      expect(i.dayMinutes.length, SeedData.pushPullLegs.days.length);
      expect(i.dayMinutes.fold<int>(0, (a, b) => a + b), i.minutes);
      expect(i.share(ExerciseLevel.intermediate), greaterThan(0.5));
    });

    test('says what kit the athlete has not got and where the routine sits', () {
      final i = RoutineInsight.of(SeedData.pushPullLegs, repo);

      expect(i.missingEquipment(bodyweightAthlete), contains('barbell'));
      expect(i.verdict(bodyweightAthlete), 'A step above your level');
      expect(
        i.verdict(bodyweightAthlete.copyWith(experience: ExperienceLevel.intermediate)),
        'Sits where you train',
      );
    });

    test('an unknown exercise is counted, not hidden', () {
      final r = SeedData.pushPullLegs.copyWith(days: [
        const RoutineDay(title: 'Day', focus: '', items: [
          RoutineItem(exerciseId: 'not_in_the_catalogue', exerciseName: 'Mystery Lift'),
        ]),
      ]);
      final i = RoutineInsight.of(r, repo);

      expect(i.ungraded, 1);
      expect(i.graded, 0);
      expect(i.level, isNull);
      expect(i.verdict(bodyweightAthlete), isNull);
    });
  });

  // ------------------------------------------------------------ levelling
  group('levelling somebody else\'s routine', () {
    LevelledRoutine level(Routine r, ExerciseLevel t, {List<String> owned = const ['body only']}) =>
        RoutineLeveller.to(routine: r, repo: repo, target: t, owned: owned);

    test('keeps the author\'s shape and only changes the movements', () {
      final lv = level(SeedData.pushPullLegs, ExerciseLevel.beginner);

      expect(lv.routine.days.length, SeedData.pushPullLegs.days.length);
      for (var d = 0; d < lv.routine.days.length; d++) {
        expect(lv.routine.days[d].title, SeedData.pushPullLegs.days[d].title);
        expect(lv.routine.days[d].items.length, SeedData.pushPullLegs.days[d].items.length);
      }
      expect(lv.swaps.length, SeedData.pushPullLegs.exerciseCount);
      expect(lv.swapped, greaterThan(0));
      expect(lv.source, ExerciseLevel.intermediate);
      expect(lv.target, ExerciseLevel.beginner);
      expect(lv.routine.name, contains('Beginner'));
    });

    test('every swapped-in exercise is actually graded at the target level', () {
      for (final target in ExerciseLevel.values) {
        for (final r in [SeedData.pushPullLegs, SeedData.pullStrength, SeedData.kettlebellBurner]) {
          final lv = level(r, target);
          for (final s in lv.swaps.where((s) => s.changed)) {
            expect(
              ExerciseLevel.of(s.toExercise!.level),
              target,
              reason: '${s.to.exerciseName} was offered as ${target.label}',
            );
          }
        }
      }
    });

    test('a swap trains the same muscle as the exercise it replaces', () {
      final lv = level(SeedData.pushPullLegs, ExerciseLevel.advanced);

      for (final s in lv.swaps.where((s) => s.changed)) {
        final from = s.fromExercise!.primary.toSet();
        final to = s.toExercise!.primary.toSet();
        expect(
          to.intersection(from).isNotEmpty || to.intersection(s.fromExercise!.secondary.toSet()).isNotEmpty,
          isTrue,
          reason: '${s.from.exerciseName} -> ${s.to.exerciseName} left the muscle behind',
        );
      }
    });

    test('a stretch is never swapped for a deadlift', () {
      const mobility = {'stretching', 'yoga'};
      for (final target in ExerciseLevel.values) {
        final lv = level(SeedData.morningMobility, target);
        for (final s in lv.swaps.where((s) => s.changed)) {
          expect(
            mobility.contains(s.toExercise!.category),
            mobility.contains(s.fromExercise!.category),
            reason: '${s.from.exerciseName} (${s.fromExercise!.category}) '
                '-> ${s.to.exerciseName} (${s.toExercise!.category}) crossed out of its discipline',
          );
        }
      }
    });

    test('never repeats an exercise the routine already has', () {
      for (final target in ExerciseLevel.values) {
        final lv = level(SeedData.pushPullLegs, target);
        final ids = [for (final d in lv.routine.days) for (final i in d.items) i.exerciseId];
        expect(ids.toSet().length, ids.length, reason: 'a levelled routine repeated a movement');
      }
    });

    test('sets and rest carry the difficulty the movement cannot', () {
      final easier = level(SeedData.pushPullLegs, ExerciseLevel.beginner);
      final harder = level(SeedData.pushPullLegs, ExerciseLevel.advanced);
      final first = SeedData.pushPullLegs.days.first.items.first;

      expect(easier.routine.days.first.items.first.sets, first.sets - 1);
      expect(easier.routine.days.first.items.first.restSec, first.restSec + 15);
      expect(harder.routine.days.first.items.first.sets, first.sets + 1);
      expect(harder.routine.days.first.items.first.restSec, first.restSec - 15);
      // Reps are the author's prescription and stay put.
      expect(easier.routine.days.first.items.first.reps, first.reps);
    });

    test('says so when the library has nothing at that level', () {
      // Nothing in the catalogue is graded advanced for the forearms, so the
      // farmer\'s walk in this programme has to stay.
      final lv = level(SeedData.pullStrength, ExerciseLevel.advanced);
      final walk = lv.swaps.firstWhere((s) => s.from.exerciseName == 'Farmers Walk');

      expect(SwapKind.values, contains(walk.kind));
      if (walk.kind == SwapKind.unavailable) {
        expect(walk.to.exerciseId, walk.from.exerciseId);
        expect(walk.reason, contains('advanced'));
      }
      expect(lv.summary, isNotEmpty);
    });

    test('prefers kit the athlete owns', () {
      final owned = level(SeedData.pushPullLegs, ExerciseLevel.beginner, owned: ['body only', 'dumbbell']);
      final none = level(SeedData.pushPullLegs, ExerciseLevel.beginner, owned: ['body only']);
      bool bare(String e) => const {'none', 'other', 'body only'}.contains(e);

      int usable(LevelledRoutine lv, List<String> kit) => lv.swaps
          .where((s) => s.changed && (bare(s.toExercise!.equipment) || kit.contains(s.toExercise!.equipment)))
          .length;

      expect(usable(owned, ['body only', 'dumbbell']), greaterThanOrEqualTo(usable(none, ['body only'])));
      expect(usable(none, ['body only']), greaterThan(0));
    });

    test('is pure — the same routine levels the same way twice', () {
      final a = level(SeedData.pullStrength, ExerciseLevel.beginner);
      final b = level(SeedData.pullStrength, ExerciseLevel.beginner);

      expect(
        [for (final d in a.routine.days) for (final i in d.items) i.exerciseId],
        [for (final d in b.routine.days) for (final i in d.items) i.exerciseId],
      );
    });
  });

  // -------------------------------------------------------------- screen
  group('the preview screen', () {
    Future<void> pump(WidgetTester tester, Routine routine, {UserProfile profile = bodyweightAthlete}) async {
      SharedPreferences.setMockInitialValues({});
      final store = await LocalStore.open();
      await store.put('profile', profile.toJson());
      await tester.pumpWidget(ProviderScope(
        overrides: [
          storeProvider.overrideWithValue(store),
          exerciseRepoProvider.overrideWith((ref) => repo),
        ],
        child: MaterialApp(home: RoutinePreviewScreen(routineId: routine.id, routine: routine)),
      ));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('shows who shared it, what it costs and every exercise', (tester) async {
      tester.view.physicalSize = const Size(430, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pump(tester, SeedData.pullStrength);

      expect(find.text('COACH PROGRAMME'), findsOneWidget);
      expect(find.text('Pull strength — week 4'), findsOneWidget);
      expect(find.text('Dario Okafor'), findsOneWidget);
      expect(find.text('EXERCISES'), findsOneWidget);
      expect(find.text('LEVEL'), findsOneWidget);
      expect(find.textContaining('you train beginner'), findsOneWidget);
      // Every exercise is on the page, with its own grade next to it.
      for (final item in SeedData.pullStrength.days.first.items) {
        expect(find.text(item.exerciseName), findsOneWidget);
      }
      expect(find.text('Beginner'), findsWidgets);
      expect(find.text('Accept'), findsOneWidget);
    });

    testWidgets('offers the athlete their own level before they ask', (tester) async {
      tester.view.physicalSize = const Size(430, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // The programme is intermediate; this athlete trains beginner.
      await pump(tester, SeedData.pullStrength);
      expect(find.byKey(const Key('levelNudge')), findsOneWidget);

      await tester.tap(find.byKey(const Key('levelNudge')));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const Key('levelNudge')), findsNothing);
      expect(find.textContaining('swapped for beginner ones'), findsOneWidget);

      // An athlete who trains where the routine sits is not nudged at all.
      await pump(tester, SeedData.pullStrength,
          profile: bodyweightAthlete.copyWith(experience: ExperienceLevel.intermediate));
      expect(find.byKey(const Key('levelNudge')), findsNothing);
    });

    testWidgets('the level switcher rebuilds the session and says what moved', (tester) async {
      tester.view.physicalSize = const Size(430, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pump(tester, SeedData.pullStrength);
      expect(find.textContaining('swapped for beginner'), findsNothing);

      await tester.tap(find.byKey(const Key('level-beginner')));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('swapped for beginner ones'), findsOneWidget);
      expect(find.textContaining('Swapped for Pullups'), findsOneWidget);
      expect(find.text('Accept beginner'), findsOneWidget);
      expect(find.text('Pullups'), findsNothing, reason: 'the intermediate movement is gone from the list');

      // Picking the grade it was shared at is how you get the author's own
      // version back.
      await tester.tap(find.byKey(const Key('level-intermediate')));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('swapped for'), findsNothing);
      expect(find.text('Pullups'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
    });

    testWidgets('accepting copies it into my routines', (tester) async {
      tester.view.physicalSize = const Size(430, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pump(tester, SeedData.morningMobility);

      await tester.tap(find.byKey(const Key('acceptRoutine')));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('In your routines'), findsOneWidget);
      expect(find.textContaining('is in your routines'), findsOneWidget, reason: 'the toast confirms it');
    });
  });
}
