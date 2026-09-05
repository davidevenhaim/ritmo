import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ritmo/core/local_store.dart';
import 'package:ritmo/core/models.dart';
import 'package:ritmo/core/providers.dart';
import 'package:ritmo/features/breathe/breathe_screen.dart';

import 'home_widget_test.dart' show pumpApp, storeWithProfile;

/// v0.13: breathing is grouped by what it is for, every session runs a clock,
/// and anything the app does not ship the athlete builds.
void main() {
  // --------------------------------------------------------------- patterns
  test('the shipped patterns are grouped, timed, and the stress ones lead', () {
    expect(breathingPatterns.map((p) => p.purpose).toSet(), containsAll([BreathePurpose.stress, BreathePurpose.sleep, BreathePurpose.train]));
    expect(BreathePurpose.values.first, BreathePurpose.stress, reason: 'stress relief is what the page is opened for');

    for (final p in breathingPatterns) {
      expect(p.inhale, greaterThan(0), reason: '${p.id} has no inhale');
      expect(p.exhale, greaterThan(0), reason: '${p.id} has no exhale');
      expect(p.cycles, greaterThan(0));
      expect(p.totalSeconds, p.cycleSeconds * p.cycles);
      expect(p.rhythm, '${p.inhale}-${p.holdIn}-${p.exhale}-${p.holdOut}');
    }

    // Cyclic sighing is the researched five-minute dose, with a longer exhale
    // than inhale and a second sip rather than a hold.
    final sigh = breathingPatterns.firstWhere((p) => p.id == 'sigh');
    expect(sigh.purpose, BreathePurpose.stress);
    expect(sigh.exhale, greaterThan(sigh.inhale + sigh.holdIn));
    expect(sigh.totalSeconds, inInclusiveRange(280, 320));
    expect(sigh.holdInLabel, isNot('Hold'));

    // Every stress pattern breathes out for at least as long as it breathes
    // in — that is the whole mechanism.
    for (final p in breathingPatterns.where((p) => p.purpose == BreathePurpose.stress)) {
      expect(p.exhale, greaterThanOrEqualTo(p.inhale), reason: '${p.id} exhales too fast to settle anyone');
    }
  });

  test('the clock reads as a clock', () {
    const p = BreathingPattern(id: 'x', name: 'x', tagline: '', inhale: 4, holdIn: 0, exhale: 6, holdOut: 0, cycles: 12, emoji: '🌊');
    expect(p.cycleSeconds, 10);
    expect(p.totalSeconds, 120);
    expect(p.clock, '2:00');
    expect(const BreathingPattern(id: 'y', name: 'y', tagline: '', inhale: 3, holdIn: 1, exhale: 7, holdOut: 0, cycles: 27, emoji: '🍃').clock, '4:57');
  });

  test('a pattern built here survives the store', () async {
    final store = await storeWithProfile();
    final container = ProviderContainer(overrides: [storeProvider.overrideWithValue(store)]);
    final made = await container.read(customBreathingProvider.notifier).add(
          name: 'Evening 4-4-8',
          inhale: 4,
          holdIn: 4,
          exhale: 8,
          holdOut: 0,
          cycles: 10,
        );
    expect(made.custom, isTrue);
    expect(made.purpose, BreathePurpose.mine);
    expect(made.totalSeconds, 160);
    container.dispose();

    // Read back through a fresh container, as a relaunch would.
    final fresh = ProviderContainer(overrides: [storeProvider.overrideWithValue(await LocalStore.open())]);
    final saved = fresh.read(customBreathingProvider).single;
    expect(saved.name, 'Evening 4-4-8');
    expect(saved.rhythm, '4-4-8-0');
    expect(saved.custom, isTrue);

    // And it joins the page under "Yours".
    expect(fresh.read(breathingByPurposeProvider)[BreathePurpose.mine], [saved]);

    await fresh.read(customBreathingProvider.notifier).remove(saved.id);
    expect(fresh.read(customBreathingProvider), isEmpty);
    expect(fresh.read(breathingByPurposeProvider).containsKey(BreathePurpose.mine), isFalse);
    fresh.dispose();
  });

  // ---------------------------------------------------------- the screens
  testWidgets('breathing opens from Me, grouped, and runs a clock', (tester) async {
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpApp(tester, await storeWithProfile(), catalogue: true);

    await tester.tap(find.byKey(const Key('breatheButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Two minutes changes the set'), findsOneWidget);
    expect(find.text('STRESS RELIEF'), findsOneWidget);
    expect(find.text('AROUND TRAINING'), findsOneWidget);
    expect(find.text('Cyclic sighing'), findsOneWidget);
    expect(find.text('Build your own'), findsOneWidget);

    // Stress relief leads.
    double y(String text) => tester.getTopLeft(find.text(text).first).dy;
    expect(y('STRESS RELIEF'), lessThan(y('AROUND TRAINING')));

    // A pattern opens its session with the clock full and the round counter.
    await tester.tap(find.text('Long exhale 4-6'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The page under it still carries its own tags, so read the clock itself.
    String clock() => tester.widget<Text>(find.byKey(const Key('breatheClock'))).data!;

    expect(find.text('TIME LEFT'), findsOneWidget);
    expect(clock(), '2:00');
    expect(find.text('1 / 12'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);

    // Running it counts the clock down a second at a time.
    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(clock(), '1:59');
    expect(find.text('Inhale'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(clock(), '1:58');

    // Pause stops the clock; reset puts it back.
    await tester.tap(find.text('Pause'));
    await tester.pump(const Duration(seconds: 2));
    expect(clock(), '1:58');

    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(clock(), '2:00');
  });

  testWidgets('building a pattern sets the numbers and goes straight into it', (tester) async {
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [storeProvider.overrideWithValue(await storeWithProfile())],
      child: const MaterialApp(home: BreatheScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Build your own'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Build a pattern'), findsOneWidget);
    expect(find.text('INHALE'), findsOneWidget);
    expect(find.text('ROUNDS'), findsOneWidget);

    // It opens on 4-0-6-0 x12 and says what that costs.
    String rhythm() => tester.widget<Text>(find.byKey(const Key('builderRhythm'))).data!;
    String total() => tester.widget<Text>(find.byKey(const Key('builderClock'))).data!;
    expect(rhythm(), '4-0-6-0');
    expect(total(), '2:00');

    // Two more seconds on the exhale, and the clock follows.
    await tester.tap(find.byTooltip('More').at(2));
    await tester.pump();
    await tester.tap(find.byTooltip('More').at(2));
    await tester.pump();
    expect(rhythm(), '4-0-8-0');
    expect(total(), '2:24');

    await tester.enterText(find.byType(TextField), 'Evening reset');
    await tester.pump();

    await tester.tap(find.text('Save and breathe'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Straight into the session, with the pattern it just built.
    expect(find.text('Evening reset'), findsWidgets);
    expect(find.text('TIME LEFT'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('breatheClock'))).data, '2:24');

    // And it is on the page under Yours when you come back. (The breathe page
    // is still mounted under the session, so both back arrows match.)
    await tester.tap(find.byTooltip('Back').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('YOURS'), findsOneWidget);
    expect(find.text('Evening reset'), findsWidgets);

    final saved = (await LocalStore.open()).getList('breathing').single;
    expect(saved['name'], 'Evening reset');
    expect(saved['exhale'], 8);
    expect(saved['cycles'], 12);
  });
}
