import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:ritmo/core/local_store.dart';
import 'package:ritmo/core/models.dart';
import 'package:ritmo/core/providers.dart';
import 'package:ritmo/core/social_repository.dart';
import 'package:ritmo/features/home/calendar_screen.dart';
import 'package:ritmo/features/home/goal_deadline.dart';

import 'home_widget_test.dart' show pumpApp, storeWithProfile;

/// v0.11: the calendar behind "This week", and goals that carry a date.
void main() {
  // --------------------------------------------------------------- the model
  test('a goal with a date counts down, and says so once the day is past', () {
    final n = DateTime.now();
    PersonalGoal at(int days, {double current = 0}) => PersonalGoal(
          id: 'g',
          name: 'Run 5 km',
          current: current,
          target: 5,
          deadline: DateTime(n.year, n.month, n.day).add(Duration(days: days)),
        );

    expect(at(12).daysLeft, 12);
    expect(at(12).dueLabel, '12 days left');
    expect(at(1).dueLabel, 'due tomorrow');
    expect(at(0).dueLabel, 'due today');
    expect(at(-3).dueLabel, '3 days over');
    expect(at(-3).overdue, isTrue);

    // Hitting the target ends the countdown, whatever the date says.
    expect(at(-3, current: 5).overdue, isFalse);
    expect(at(-3, current: 5).dueLabel, 'done');

    // A goal without a date says nothing at all.
    const open = PersonalGoal(id: 'g', name: 'Run', current: 0, target: 5);
    expect(open.daysLeft, isNull);
    expect(open.dueLabel, isNull);
  });

  test('a dated goal survives the round trip through the store', () {
    final due = DateTime(2026, 12, 24);
    final g = PersonalGoal(id: 'g', name: 'Run 5 km', current: 1, target: 5, unit: ' km', deadline: due);
    expect(PersonalGoal.fromJson(g.toJson()).deadline, due);

    // And can be dropped again, which copyWith cannot do by passing null.
    expect(g.copyWith(clearDeadline: true).deadline, isNull);
  });

  test('every preset is a number the athlete moves', () {
    final run = goalTemplates.firstWhere((t) => t.id == 'run');
    expect(run.nameFor(5), 'Run 5 km without stopping');
    expect(run.nameFor(21.5), 'Run 21.5 km without stopping');
    expect(run.target, inInclusiveRange(run.min, run.max));

    for (final t in goalTemplates) {
      expect(t.pattern, contains('{}'), reason: '${t.id} needs somewhere to put the number');
      expect(t.target, inInclusiveRange(t.min, t.max), reason: '${t.id} opens outside its own range');
      expect(t.step, greaterThan(0));
      expect(t.days, greaterThan(0));
    }
  });

  test('the deadline ladder folds in the template horizon and labels it', () {
    expect(DeadlinePicker.horizonLabel(14), '2 weeks');
    expect(DeadlinePicker.horizonLabel(7), '1 week');
    expect(DeadlinePicker.horizonLabel(10), '10 days');
    expect(DeadlinePicker.dayAfter(0), DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day));
    expect(DeadlinePicker.dueLine(null), startsWith('No date'));
    expect(DeadlinePicker.dueLine(DeadlinePicker.dayAfter(1)), endsWith('tomorrow'));
  });

  // -------------------------------------------------------------- the screen
  testWidgets('the calendar carries the month, the day that was trained and the plan', (tester) async {
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = await storeWithProfile();
    final container = ProviderContainer(overrides: [storeProvider.overrideWithValue(store)]);
    // One session logged this morning, one planned for tomorrow.
    await container.read(activityProvider.notifier).logWorkout(
          routine: SeedData.pushPullLegs,
          dayTitle: SeedData.pushPullLegs.days.first.title,
          duration: const Duration(minutes: 42),
          sets: 16,
        );
    await container.read(scheduleProvider.notifier).add(
          routine: SeedData.pushPullLegs,
          dayIndex: 1,
          at: DateTime.now().add(const Duration(days: 1)),
        );
    container.dispose();

    await tester.pumpWidget(ProviderScope(
      overrides: [storeProvider.overrideWithValue(store)],
      child: const MaterialApp(home: CalendarScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 400));

    final now = DateTime.now();
    expect(find.text('Your calendar'), findsOneWidget);
    expect(find.text(DateFormat('MMMM y').format(now)), findsOneWidget);

    // The month summary reads the log, not the schedule.
    expect(find.text('1'), findsWidgets);
    expect(find.text('session'), findsOneWidget);
    expect(find.text('day trained'), findsOneWidget);
    expect(find.text('still planned'), findsOneWidget);

    // Today is selected on open, so the day panel is today's session.
    expect(find.text(DateFormat('EEEE d MMMM').format(now)), findsOneWidget);
    expect(find.text('today'), findsOneWidget);
    expect(find.textContaining('16 sets'), findsOneWidget);

    // Paging back a month keeps the grid and offers the way home.
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pump();
    expect(find.text(DateFormat('MMMM y').format(DateTime(now.year, now.month - 1))), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);

    await tester.tap(find.text('Today'));
    await tester.pump();
    expect(find.text(DateFormat('MMMM y').format(now)), findsOneWidget);
  });

  testWidgets('a goal with a date lands on the calendar and counts down', (tester) async {
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = await storeWithProfile();
    final container = ProviderContainer(overrides: [storeProvider.overrideWithValue(store)]);
    await container.read(customGoalsProvider.notifier).add(
          name: 'Run 10 km without stopping',
          target: 10,
          unit: ' km',
          note: 'Three easy runs a week, one of them longer',
          deadline: DeadlinePicker.dayAfter(20),
        );
    container.dispose();

    await tester.pumpWidget(ProviderScope(
      overrides: [storeProvider.overrideWithValue(store)],
      child: const MaterialApp(home: CalendarScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Goals with a date'), findsOneWidget);
    expect(find.text('Run 10 km without stopping'), findsOneWidget);
    expect(find.textContaining('20 days left'), findsOneWidget);

    // Tapping it moves the calendar onto the day it is due.
    await tester.tap(find.text('Run 10 km without stopping'));
    await tester.pump();
    final due = DeadlinePicker.dayAfter(20);
    expect(find.text(DateFormat('EEEE d MMMM').format(due)), findsOneWidget);
    expect(find.text('Goal due · 0 / 10 km'), findsOneWidget);
  });

  testWidgets('the add-goal sheet tunes a preset and saves it with a date', (tester) async {
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = await storeWithProfile();
    await tester.pumpWidget(ProviderScope(
      overrides: [storeProvider.overrideWithValue(store)],
      child: const MaterialApp(home: CalendarScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Set a goal'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The chooser: the catalogue first, then the ready-made goals.
    expect(find.text('An exercise'), findsOneWidget);
    expect(find.text('Jump rope for 60s unbroken'), findsOneWidget);

    await tester.tap(find.text('Jump rope for 60s unbroken'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Tuning: the number moves in the template's own step, and the goal's
    // name moves with it.
    expect(find.text('60s'), findsOneWidget);
    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    expect(find.text('75s'), findsOneWidget);
    expect(find.text('Jump rope for 75s unbroken'), findsOneWidget);

    // Four weeks is the rope template's own horizon, so it opens selected.
    expect(find.textContaining('28 days to go'), findsOneWidget);
    await tester.tap(find.text('2 weeks'));
    await tester.pump();
    expect(find.textContaining('14 days to go'), findsOneWidget);

    await tester.tap(find.text('Set the goal'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final saved = (await LocalStore.open()).getList('goals').single;
    expect(saved['name'], 'Jump rope for 75s unbroken');
    expect(saved['target'], 75.0);
    expect(saved['unit'], 's');
    expect(DateTime.parse(saved['deadline']), DeadlinePicker.dayAfter(14));

    // And it is on the calendar the moment the sheet closes.
    expect(find.text('Jump rope for 75s unbroken'), findsOneWidget);
    expect(find.textContaining('14 days left'), findsOneWidget);
  });

  testWidgets('a goal can be given a date after the fact, from the goals card', (tester) async {
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = await storeWithProfile();
    final container = ProviderContainer(overrides: [storeProvider.overrideWithValue(store)]);
    await container.read(customGoalsProvider.notifier).add(name: 'Ring dips', target: 12, unit: ' reps');
    container.dispose();

    await tester.pumpWidget(ProviderScope(
      overrides: [storeProvider.overrideWithValue(store)],
      child: const MaterialApp(home: CalendarScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 400));

    // Undated, it is not on the calendar at all.
    expect(find.text('Ring dips'), findsNothing);

    final container2 = ProviderContainer(overrides: [storeProvider.overrideWithValue(store)]);
    final goal = container2.read(customGoalsProvider).single;
    await container2.read(customGoalsProvider.notifier).setDeadline(goal.id, DeadlinePicker.dayAfter(30));
    expect(container2.read(customGoalsProvider).single.daysLeft, 30);

    // Dropping the date again takes it back off.
    await container2.read(customGoalsProvider.notifier).setDeadline(goal.id, null, clear: true);
    expect(container2.read(customGoalsProvider).single.deadline, isNull);
    container2.dispose();
  });

  testWidgets('Me opens the calendar from the week chart', (tester) async {
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpApp(tester, await storeWithProfile());

    // The expand button sits on the section head, and the card underneath it
    // says where it goes.
    expect(find.text('Open the full calendar'), findsOneWidget);

    await tester.tap(find.byTooltip('Full calendar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Your calendar'), findsOneWidget);
    expect(find.text(DateFormat('MMMM y').format(DateTime.now())), findsOneWidget);
  });
}
