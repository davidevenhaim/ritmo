import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ritmo/core/exercise_repository.dart';
import 'package:ritmo/core/local_store.dart';
import 'package:ritmo/core/models.dart';
import 'package:ritmo/core/providers.dart';
import 'package:ritmo/core/social_repository.dart';
import 'package:ritmo/core/session_theme.dart';
import 'package:ritmo/features/build/ai_assist_sheet.dart';
import 'package:ritmo/features/build/build_screen.dart';
import 'package:ritmo/features/build/session_builder_screen.dart';
import 'package:ritmo/features/explore/exercise_detail_screen.dart';
import 'package:ritmo/app/nocturne.dart';
import 'package:ritmo/features/home/me_screen.dart';
import 'package:ritmo/main.dart';

const me = UserProfile(
  id: 'me', name: 'Test Athlete', handle: 'test', emoji: '🙂',
  heightCm: 175, weightKg: 70, age: 30, goal: Goal.buildMuscle,
  diet: [], equipment: ['dumbbell'], daysPerWeek: 3, stepGoal: 8000,
);

Future<LocalStore> storeWithProfile() async {
  SharedPreferences.setMockInitialValues({});
  final store = await LocalStore.open();
  await store.put('profile', me.toJson());
  return store;
}

/// The catalogue asset is loaded straight from disk so the widget tree has it
/// on the first frame.
ExerciseRepository loadCatalogue() {
  final raw = File('assets/data/exercises.json').readAsStringSync();
  return ExerciseRepository((jsonDecode(raw) as List).map((e) => Exercise.fromJson(Map<String, dynamic>.from(e as Map))).toList());
}

Future<void> pumpHome(WidgetTester tester, LocalStore store) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [storeProvider.overrideWithValue(store)],
    child: const MaterialApp(home: MeScreen()),
  ));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

/// The whole app, router and tab bar included.
Future<void> pumpApp(WidgetTester tester, LocalStore store, {bool catalogue = false}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      storeProvider.overrideWithValue(store),
      if (catalogue) exerciseRepoProvider.overrideWith((ref) => loadCatalogue()),
    ],
    child: const RitmoApp(),
  ));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('Me leads with the user and keeps the handoff section order', (tester) async {
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpHome(tester, await storeWithProfile());

    expect(find.text('Test Athlete'), findsOneWidget);
    expect(find.textContaining('Good '), findsOneWidget, reason: 'time-of-day greeting');
    expect(find.text('WEEKLY STREAK'), findsOneWidget);
    expect(find.text('Goals'), findsOneWidget);
    expect(find.text('This week'), findsWidgets);
    expect(find.text('Your plan'), findsOneWidget);
    expect(find.text('From people you follow'), findsOneWidget);
    expect(find.text('Nutrition'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);

    // The handoff calls the order deliberate: progress, week, plan, people.
    double y(String text) => tester.getTopLeft(find.text(text).first).dy;
    expect(y('WEEKLY STREAK'), lessThan(y('Goals')));
    expect(y('Goals'), lessThan(y('Your plan')));
    expect(y('Your plan'), lessThan(y('From people you follow')));
    expect(y('From people you follow'), lessThan(y('Nutrition')));
    expect(y('Nutrition'), lessThan(y('Account')));

    // Social is not the front door.
    expect(find.text('Feed'), findsNothing);
  });

  testWidgets('goals card starts collapsed, opens to the derived goals and a Set a goal row', (tester) async {
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpHome(tester, await storeWithProfile());

    expect(find.text('Set a goal'), findsNothing);
    expect(find.textContaining('tap to see all'), findsOneWidget);

    await tester.tap(find.text('Goals'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('tap to collapse'), findsOneWidget);
    expect(find.text('Train 3x a week'), findsOneWidget, reason: 'derived from days per week');
    expect(find.text('Walk 8,000 steps a day'), findsOneWidget, reason: 'derived from the step goal');
    expect(find.text('Set a goal'), findsOneWidget);
  });

  testWidgets('nutrition card shows a target computed from the profile', (tester) async {
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpHome(tester, await storeWithProfile());

    expect(find.text('Calories today'), findsOneWidget);
    expect(find.text('0 / ${NumberFormat.decimalPattern().format(calorieTarget(me))}'), findsOneWidget);
    expect(find.text('Protein'), findsOneWidget);
  });

  testWidgets('Build opens on the six themes with real catalogue counts', (tester) async {
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = await storeWithProfile();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        storeProvider.overrideWithValue(store),
        exerciseRepoProvider.overrideWith((ref) async => loadCatalogue()),
      ],
      child: const MaterialApp(home: BuildScreen()),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('STEP 1 OF 3'), findsOneWidget);
    expect(find.text('Pick a theme'), findsOneWidget);
    final repo = loadCatalogue();
    for (final t in SessionTheme.values) {
      expect(find.text(t.name), findsOneWidget, reason: '${t.name} card missing');
      expect(repo.countFor(t), greaterThan(20), reason: '${t.name} is too thin to offer');
    }
  });

  testWidgets('the timeline starts empty, a tapped tile appends, and the total tracks it', (tester) async {
    tester.view.physicalSize = const Size(430, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = await storeWithProfile();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        storeProvider.overrideWithValue(store),
        exerciseRepoProvider.overrideWith((ref) async => loadCatalogue()),
      ],
      child: const MaterialApp(home: SessionBuilderScreen(theme: SessionTheme.core)),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Session timeline'), findsOneWidget);
    expect(find.text('Drag exercises up here'), findsOneWidget);
    expect(find.text('Review & save'), findsNothing, reason: 'nothing to save yet');

    // The library arrives split into the three grades, with a filter chip per
    // grade over it and the whole library grouped underneath.
    expect(find.text('All'), findsOneWidget);
    for (final l in ExerciseLevel.values) {
      expect(find.text(l.label), findsWidgets, reason: '${l.label} chip');
      expect(find.text(l.label.toUpperCase()), findsOneWidget, reason: '${l.label} heading');
    }
    double y(String text) => tester.getTopLeft(find.text(text).first).dy;
    expect(y('BEGINNER'), lessThan(y('INTERMEDIATE')));
    expect(y('INTERMEDIATE'), lessThan(y('ADVANCED')));

    final first = loadCatalogue().forTheme(SessionTheme.core).first;
    await tester.tap(find.text(first.name).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Drag exercises up here'), findsNothing);
    expect(find.text('Review & save'), findsOneWidget);
    expect(find.text('${SessionTheme.core.minutesFor()} min'), findsOneWidget, reason: 'total tracks the timeline');
  });

  test('the AI draft picks from the theme and answers the prompt', () {
    final repo = loadCatalogue();
    final library = repo.forTheme(SessionTheme.bodyweight);

    final normal = draftBlock(library: library, prompt: null, equipment: const ['body only']);
    expect(normal.length, 5);
    expect(normal.every(SessionTheme.bodyweight.has), isTrue);
    expect(normal.map((e) => e.id).toSet().length, 5, reason: 'no duplicates');

    final short = draftBlock(library: library, prompt: AiPrompt.short, equipment: const ['body only']);
    expect(short.length, 4, reason: 'a 25-minute ask gets fewer exercises');

    final gentle = draftBlock(library: repo.forTheme(SessionTheme.gym), prompt: AiPrompt.gentle, equipment: const ['barbell']);
    expect(gentle.every((e) => e.equipment == 'body only' || e.equipment == 'none' || e.category == 'stretching' || e.category == 'yoga'), isTrue);

    final heavy = draftBlock(library: repo.forTheme(SessionTheme.gym), prompt: AiPrompt.heavy, equipment: const ['barbell']);
    expect(heavy.every((e) => e.mechanic == 'compound'), isTrue);
  });

  testWidgets('a scheduled workout shows on its day under Your plan', (tester) async {
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = await storeWithProfile();
    final container = ProviderContainer(overrides: [storeProvider.overrideWithValue(store)]);
    await container.read(scheduleProvider.notifier).add(
          routine: SeedData.pushPullLegs,
          dayIndex: 0,
          at: DateTime.now().add(const Duration(hours: 2)),
        );
    container.dispose();

    await pumpHome(tester, store);

    expect(find.text(SeedData.pushPullLegs.name), findsOneWidget);
    expect(find.textContaining('session'), findsWidgets, reason: 'plan summary line');
    expect(find.text('Rest — add a session'), findsWidgets, reason: 'the other six days');
  });

  testWidgets('the raised Start button opens the sheet in the handoff order', (tester) async {
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpApp(tester, await storeWithProfile());

    // The handoff's bar: Me, the raised Start button carrying the barbell,
    // and Community.
    expect(find.text('Me'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Community'), findsOneWidget);
    expect(find.text('Friends'), findsNothing);
    expect(find.text('Build'), findsNothing, reason: 'Build is what Start opens, not a tab');

    await tester.tap(find.byKey(const Key('startButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Start a workout'), findsOneWidget);
    expect(find.text('YOUR ROUTINES'), findsOneWidget);
    expect(find.textContaining('BECAUSE YOU TRAIN'), findsOneWidget);
    expect(find.text('Build your routine'), findsOneWidget);

    // Building by hand comes before the saved routines. (This pump has no
    // catalogue, so the picked session is a placeholder here; the ordering
    // against it is asserted in the test below, which loads one.)
    double y(String text) => tester.getTopLeft(find.text(text).first).dy;
    expect(y('Build your routine'), lessThan(y('YOUR ROUTINES')));

    // The old four-option menu is gone.
    expect(find.text('Join a league nearby'), findsNothing);
    expect(find.text('Change configuration'), findsNothing);
  });

  testWidgets('the header pill opens Friends, invite first then the feed', (tester) async {
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpApp(tester, await storeWithProfile());

    await tester.tap(find.byIcon(Nx.userPlus));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Friends'), findsOneWidget);
    expect(find.text('Invite to a training'), findsOneWidget);
    expect(find.text('WHO'), findsOneWidget);
    expect(find.text('WHEN'), findsOneWidget);

    double y(String text) => tester.getTopLeft(find.text(text).first).dy;
    expect(y('Invite to a training'), lessThan(y('Their week')), reason: 'invite comes before the feed');
  });

  testWidgets('tapping a library tile says so on the tile', (tester) async {
    tester.view.physicalSize = const Size(430, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = await storeWithProfile();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        storeProvider.overrideWithValue(store),
        exerciseRepoProvider.overrideWith((ref) async => loadCatalogue()),
      ],
      child: const MaterialApp(home: SessionBuilderScreen(theme: SessionTheme.core)),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final first = loadCatalogue().forTheme(SessionTheme.core).first;
    expect(find.text('On the timeline · tap to add again'), findsNothing);

    // .last is the library tile: once it is on the timeline, the name is on
    // screen twice.
    await tester.tap(find.text(first.name).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The tile itself answers, not just the timeline card above it.
    expect(find.text('On the timeline · tap to add again'), findsOneWidget);
    expect(find.text('×2'), findsNothing);

    await tester.tap(find.text(first.name).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('×2'), findsOneWidget, reason: 'a second tap counts');
  });

  testWidgets('the exercise page turns an exercise into a goal', (tester) async {
    tester.view.physicalSize = const Size(430, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = await storeWithProfile();
    final repo = loadCatalogue();
    final pullups = repo.byId('Pullups')!;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        storeProvider.overrideWithValue(store),
        exerciseRepoProvider.overrideWith((ref) async => repo),
      ],
      child: MaterialApp(home: ExerciseDetailScreen(exerciseId: pullups.id, exercise: pullups)),
    ));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Make this a goal'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Counted in reps by default, at ten, and the number moves.
    expect(find.text('MAKE IT A GOAL'), findsOneWidget);
    expect(find.text('10 reps'), findsOneWidget);
    await tester.tap(find.byIcon(Nx.plus));
    await tester.pump();
    expect(find.text('11 reps'), findsOneWidget);

    await tester.tap(find.text('Set the goal'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The page now says so instead of offering it twice.
    expect(find.text('Already a goal'), findsOneWidget);
    final saved = (await LocalStore.open()).getList('goals');
    expect(saved.single['exerciseId'], 'Pullups');
    expect(saved.single['target'], 11);
    expect(saved.single['unit'], ' reps');
  });

  testWidgets('an exercise can be made a goal and lands on the goals card', (tester) async {
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = await storeWithProfile();
    final container = ProviderContainer(overrides: [storeProvider.overrideWithValue(store)]);
    await container.read(customGoalsProvider.notifier).add(
          name: 'Pullups',
          target: 10,
          unit: ' reps',
          note: 'From the exercise library · track it as you train',
          exerciseId: 'Pullups',
          exerciseName: 'Pullups',
        );
    expect(container.read(customGoalsProvider.notifier).hasExercise('Pullups'), isTrue);
    container.dispose();

    await pumpApp(tester, store, catalogue: true);
    await tester.tap(find.text('Goals'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Pullups'), findsOneWidget);
    expect(find.text('0 / 10 reps'), findsOneWidget);
    expect(find.text('An exercise'), findsNothing, reason: 'the picker lives behind Set a goal');
  });

  testWidgets('onboarding says the app is free for trainees before it asks anything', (tester) async {
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // No profile: the app opens on onboarding.
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await tester.pumpWidget(ProviderScope(
      overrides: [storeProvider.overrideWithValue(store)],
      child: const RitmoApp(),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Free to use for trainees. Always.'), findsOneWidget);
    expect(find.textContaining('No subscription, no paywall'), findsOneWidget);
    expect(find.textContaining('studios, clubs and personal trainers are the paying side'), findsOneWidget);

    // And it is above the first thing the app asks for.
    expect(
      tester.getTopLeft(find.text('Free to use for trainees. Always.')).dy,
      lessThan(tester.getTopLeft(find.text('PICK AN AVATAR')).dy),
    );
  });

  testWidgets('Community carries the AI coach, the studios and the coaches', (tester) async {
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpApp(tester, await storeWithProfile());
    await tester.tap(find.text('Community'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The AI coach sits above both tabs because it is the always-on one.
    expect(find.text('Ask the AI coach'), findsOneWidget);
    expect(find.text('ALWAYS ON'), findsOneWidget);

    // Studios first, with their real timetable.
    expect(find.text('Bloc Studio'), findsOneWidget);
    expect(find.text('Ring basics'), findsOneWidget);
    expect(find.text('Join'), findsWidgets);

    double y(String text) => tester.getTopLeft(find.text(text).first).dy;
    expect(y('Ask the AI coach'), lessThan(y('Bloc Studio')));

    // Booking a class asks first, then flips the row.
    await tester.tap(find.text('Join').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Drop-in price'), findsOneWidget);
    expect(find.textContaining('never asks for card details'), findsOneWidget);

    await tester.tap(find.text('Book the spot'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Booked'), findsOneWidget);

    // Coaches are the app's own creators, with their programmes.
    await tester.tap(find.text('Coaches'));
    await tester.pump();
    expect(find.text('Dario Okafor'), findsOneWidget);
    expect(find.text('Pull strength — week 4'), findsOneWidget);
    expect(find.text('Bloc Studio'), findsNothing);
  });

  testWidgets('Start picks a session from the profile and can run it', (tester) async {
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpApp(tester, await storeWithProfile(), catalogue: true);

    await tester.tap(find.byKey(const Key('startButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('PICKED FOR YOU'), findsOneWidget);
    // The chips explain the pick: the goal, the kit, the level.
    expect(find.text('Build muscle'), findsOneWidget);
    expect(find.text('Beginner-friendly'), findsOneWidget);
    expect(find.text('Start'), findsWidgets);

    double y(String text) => tester.getTopLeft(find.text(text).first).dy;
    expect(y('Build your routine'), lessThan(y('PICKED FOR YOU')), reason: 'building by hand is offered first');
    expect(y('PICKED FOR YOU'), lessThan(y('YOUR ROUTINES')));
  });

  testWidgets('inviting a friend to a session lists it under Training together', (tester) async {
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = await storeWithProfile();
    final container = ProviderContainer(overrides: [storeProvider.overrideWithValue(store)]);
    await container.read(scheduleProvider.notifier).add(
          routine: SeedData.pushPullLegs,
          dayIndex: 0,
          at: DateTime.now().add(const Duration(hours: 4)),
        );
    container.dispose();

    await pumpApp(tester, store);
    await tester.tap(find.byIcon(Nx.userPlus));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Nobody picked yet: the button asks for a friend, not a session.
    expect(find.text('Pick a friend'), findsOneWidget);

    await tester.tap(find.text('Dario'));
    await tester.pump();
    expect(find.text('Invite Dario'), findsOneWidget);

    await tester.tap(find.text('Invite Dario'));
    await tester.pump();
    // The clipboard channel never answers under test; the send waits it out.
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('Training together'), findsOneWidget);
    expect(find.textContaining('Dario'), findsWidgets);
    expect(find.text('Pick a friend'), findsOneWidget, reason: 'the picker resets after sending');

    // Back on Me, the session on the plan carries the guest's face.
    await tester.tap(find.byIcon(Nx.arrowLeft));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final dario = SeedData.users['dario']!;
    expect(find.text('Your plan'), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w is NocFace && w.emoji == dario.emoji),
      findsWidgets,
      reason: 'the plan row shows who is coming',
    );
  });
}
