import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ritmo/core/ai_coach.dart';
import 'package:ritmo/core/exercise_repository.dart';
import 'package:ritmo/core/models.dart';
import 'package:ritmo/core/providers.dart';
import 'package:ritmo/features/coach/coach_screen.dart';

import 'home_widget_test.dart' show loadCatalogue, me, pumpApp, storeWithProfile;

/// v0.12: the coach answers presets instead of free text, and everything it
/// writes is looked at before it is taken on.
void main() {
  late ExerciseRepository repo;
  setUpAll(() => repo = loadCatalogue());

  // ------------------------------------------------------- what it answers
  test('every preset gets its own answer, not the fallback', () async {
    for (final p in CoachPrompt.values) {
      final reply = await LocalCoach().reply(
        history: [ChatMessage(role: 'user', text: p.label)],
        profile: me,
        repo: repo,
      );
      expect(reply.text, isNot(contains('Pick one below')), reason: '${p.name} fell through to the fallback');
      expect(reply.text.length, greaterThan(80), reason: '${p.name} needs a real answer');
    }
  });

  test('a plan, a short session and a dumbbell swap all come back as routines', () async {
    Future<CoachReply> ask(CoachPrompt p) => LocalCoach().reply(
          history: [ChatMessage(role: 'user', text: p.label)],
          profile: me,
          repo: repo,
        );

    final plan = await ask(CoachPrompt.plan);
    expect(plan.routine, isNotNull);
    expect(plan.routine!.days.length, me.daysPerWeek);

    // "25 minutes" is a plan question, but answering it with a week would be
    // missing the point: it is one short day.
    final short = await ask(CoachPrompt.short);
    expect(short.routine, isNotNull);
    expect(short.routine!.days.length, 1);
    expect(short.routine!.days.first.items.length, lessThanOrEqualTo(4));
    expect(short.routine!.days.first.items.every((i) => i.restSec <= 60), isTrue);

    // The swap keeps the shape and drops the barbell.
    final swap = await ask(CoachPrompt.swap);
    expect(swap.routine, isNotNull);
    for (final d in swap.routine!.days) {
      for (final i in d.items) {
        final e = repo.byId(i.exerciseId);
        expect(e?.equipment, isNot('barbell'), reason: '${i.exerciseName} still needs a barbell');
      }
    }

    // Food and joints are advice, not a routine.
    expect((await ask(CoachPrompt.food)).routine, isNull);
    expect((await ask(CoachPrompt.joints)).routine, isNull);
    expect((await ask(CoachPrompt.joints)).text.toLowerCase(), contains('physio'));
  });

  test('the plan the AI coach publishes is stable for the same athlete', () {
    final a = buildCoachPlan(me, repo, id: 'ai_coach_me');
    final b = buildCoachPlan(me, repo, id: 'ai_coach_me');
    expect(a.id, b.id);
    expect(
      a.days.map((d) => d.items.map((i) => i.exerciseId).toList()),
      b.days.map((d) => d.items.map((i) => i.exerciseId).toList()),
      reason: 'the same person must not get a different plan on every rebuild',
    );
    expect(a.source, 'ai');
  });

  // ---------------------------------------------------------- the screen
  testWidgets('the coach takes presets and the open box says soon', (tester) async {
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        storeProvider.overrideWithValue(await storeWithProfile()),
        exerciseRepoProvider.overrideWith((ref) => repo),
      ],
      child: const MaterialApp(home: CoachScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 400));

    // The coach is on, and says whose side it is on.
    expect(find.text('AI coach'), findsOneWidget);
    expect(find.text('FREE FOR TRAINEES, ALWAYS'), findsOneWidget);

    // The input is the presets. There is no text field at all.
    expect(find.byType(TextField), findsNothing);
    expect(find.text(CoachPrompt.plan.label), findsOneWidget);
    expect(find.text('Ask it anything, in your own words'), findsOneWidget);
    expect(find.text('Soon'), findsOneWidget);

    // Tapping the closed box explains itself rather than doing nothing.
    await tester.tap(find.text('Ask it anything, in your own words'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Open questions are coming soon'), findsOneWidget);
    expect(find.textContaining('free for everyone'), findsOneWidget);

    await tester.tap(find.text('Got it'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // A preset asks, and the answer carries the routine with a way in.
    await tester.tap(find.text(CoachPrompt.plan.label));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(CoachPrompt.plan.label), findsWidgets, reason: 'the ask is now also a bubble');
    expect(find.text('See the routine'), findsOneWidget);
    expect(find.text('Kept in your routines'), findsOneWidget);
  });

  testWidgets('the AI coach leads the coaches list with a plan built for you', (tester) async {
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpApp(tester, await storeWithProfile(), catalogue: true);
    await tester.tap(find.text('Community'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Coaches'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Ritmo AI Coach'), findsOneWidget);
    expect(find.textContaining('free, always'), findsOneWidget);

    // Its programme is the plan built from this profile, and it sits above
    // the human coaches.
    final plan = buildCoachPlan(me, repo, id: 'ai_coach_me');
    expect(find.text(plan.name), findsOneWidget);
    double y(String text) => tester.getTopLeft(find.text(text).first).dy;
    expect(y('Ritmo AI Coach'), lessThan(y('Dario Okafor')));
  });

}
