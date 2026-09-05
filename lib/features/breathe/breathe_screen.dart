import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/nocturne.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../feed/feed_screen.dart';
import 'breathing_builder.dart';

/// Breathing (v0.12 back in the app, v0.13 grouped, timed and yours).
///
/// Patterns are grouped by what they are for, stress first — that is what
/// people open this page for, and the three under it are the ones the
/// research actually backs. Anything the app does not ship, the athlete
/// builds: in for x, hold for y, out for z, that many rounds.
class BreatheScreen extends ConsumerWidget {
  const BreatheScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(breathingByPurposeProvider);

    return Scaffold(
      backgroundColor: Noc.bg,
      body: SafeArea(
        bottom: false,
        child: NocIn(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Noc.gutter, 6, Noc.gutter, 32),
            children: [
              Row(children: [
                NocIconButton(
                  icon: Nx.arrowLeft,
                  tooltip: 'Back',
                  onTap: () => context.canPop() ? context.pop() : context.go('/home'),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text('Breathe', style: Noc.pageTitle)),
              ]),
              const SizedBox(height: 16),
              Text('NOT ONLY THE GYM', style: Noc.kicker),
              const SizedBox(height: 5),
              Text('Two minutes changes the set', style: Noc.screenTitle),
              const SizedBox(height: 8),
              Text(
                'Slow breathing drops your heart rate, sharpens focus and makes the next set better. Pick a pattern — '
                'the circle leads, the clock counts, you follow.',
                style: Noc.body.copyWith(color: Noc.muted),
              ),
              const SizedBox(height: 20),
              for (final entry in groups.entries) ...[
                _GroupHead(purpose: entry.key),
                const SizedBox(height: 10),
                for (final p in entry.value) ...[
                  _PatternCard(pattern: p),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 12),
              ],
              _BuildYourOwn(hasOwn: groups.containsKey(BreathePurpose.mine)),
              const SizedBox(height: 14),
              Text(
                'Cyclic sighing beat box breathing and mindfulness meditation over a month of five-minute daily practice '
                '(Balban et al., Cell Reports Medicine, 2023). Breathing is not medical treatment — if you feel faint, stop and breathe normally.',
                style: Noc.small,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupHead extends StatelessWidget {
  const _GroupHead({required this.purpose});
  final BreathePurpose purpose;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(purpose.label.toUpperCase(), style: Noc.kickerAccent),
          const SizedBox(height: 2),
          Text(purpose.note, style: Noc.small),
        ],
      );
}

class _PatternCard extends ConsumerWidget {
  const _PatternCard({required this.pattern});
  final BreathingPattern pattern;

  static IconData iconFor(BreathingPattern p) {
    if (p.custom) return Nx.sparkle;
    return switch (p.id) {
      'box' => Nx.clock,
      '478' => Nx.heart,
      'coherent' => Nx.heartbeat,
      'exhale46' => Nx.heartbeat,
      'power' => Nx.fire,
      _ => Nx.heart,
    };
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final gone = await showDialog<bool>(
      context: context,
      barrierColor: Noc.scrim,
      builder: (dialog) => AlertDialog(
        backgroundColor: Noc.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Noc.muted)),
        content: Text('Remove ${pattern.name}?', style: Noc.body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Keep it', style: TextStyle(fontFamily: 'Inter', color: Noc.dim))),
          TextButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Remove', style: TextStyle(fontFamily: 'Inter', color: Noc.accent))),
        ],
      ),
    );
    if (gone != true) return;
    await ref.read(customBreathingProvider.notifier).remove(pattern.id);
    if (context.mounted) nocToast(context, '${pattern.name} removed.');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = pattern;
    return NocCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      border: p.custom ? Border.all(color: Noc.accent700) : null,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BreathingSession(pattern: p))),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Noc.accent900, borderRadius: BorderRadius.circular(Noc.rControl)),
            // CanvasKit has no emoji font on the web build, so the pattern
            // wears a Phosphor glyph rather than a tofu box.
            child: Icon(iconFor(p), size: 20, color: Noc.accent300),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, style: Noc.cardTitle),
                const SizedBox(height: 2),
                Text(p.tagline, style: Noc.small, maxLines: 3),
                const SizedBox(height: 7),
                Row(children: [
                  NocTag(p.rhythm),
                  const SizedBox(width: 6),
                  NocTag('${p.cycles} rounds', style: NocTagStyle.neutral),
                  const SizedBox(width: 6),
                  NocTag(p.clock, style: NocTagStyle.neutral),
                ]),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (p.custom)
            NocIconButton(icon: Nx.x, size: 30, tooltip: 'Remove', onTap: () => _remove(context, ref))
          else
            const Icon(Nx.play, size: 16, color: Noc.accent400),
        ],
      ),
    );
  }
}

/// The way to a pattern the app does not ship.
class _BuildYourOwn extends ConsumerWidget {
  const _BuildYourOwn({required this.hasOwn});
  final bool hasOwn;

  @override
  Widget build(BuildContext context, WidgetRef ref) => NocCard(
        color: Noc.sunken,
        border: Border.all(color: Noc.accent700),
        padding: const EdgeInsets.fromLTRB(13, 13, 13, 13),
        onTap: () async {
          final made = await showBreathingBuilder(context, ref);
          // Straight into it: somebody who has just set the numbers wants to
          // breathe them, not admire a card.
          if (made != null && context.mounted) {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => BreathingSession(pattern: made)));
          }
        },
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Noc.accent900, borderRadius: BorderRadius.circular(Noc.rIcon)),
            child: const Icon(Nx.plus, size: 16, color: Noc.accent300),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Build your own', style: TextStyle(fontFamily: 'Inter', fontSize: 13.5, fontVariations: Noc.w500, color: Noc.accent200)),
              const SizedBox(height: 1),
              Text(
                hasOwn ? 'Another rhythm, your rounds' : 'In for x, hold for y, out for z — as many rounds as you like',
                style: Noc.small,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          const Icon(Nx.caretRight, size: 15, color: Noc.accent400),
        ]),
      );
}

/// The pattern itself: one circle that grows on the inhale, holds, and falls
/// away on the exhale, with the seconds counted inside it and the clock
/// running underneath.
class BreathingSession extends ConsumerStatefulWidget {
  const BreathingSession({super.key, required this.pattern});
  final BreathingPattern pattern;
  @override
  ConsumerState<BreathingSession> createState() => _BreathingSessionState();
}

class _BreathingSessionState extends ConsumerState<BreathingSession> {
  Timer? _timer;
  int _elapsed = 0;
  bool _running = false;

  BreathingPattern get p => widget.pattern;

  /// Seconds still to run, as "4:37".
  static String clock(int seconds) {
    final s = seconds < 0 ? 0 : seconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  (String label, double scale, int secondsLeft, int cycle) get _phase {
    final cycle = _elapsed ~/ p.cycleSeconds;
    var t = _elapsed % p.cycleSeconds;
    if (t < p.inhale) return ('Inhale', 1.0, p.inhale - t, cycle);
    t -= p.inhale;
    if (t < p.holdIn) return (p.holdInLabel, 1.0, p.holdIn - t, cycle);
    t -= p.holdIn;
    if (t < p.exhale) return ('Exhale', 0.45, p.exhale - t, cycle);
    t -= p.exhale;
    return ('Hold', 0.45, p.holdOut - t, cycle);
  }

  void _toggle() {
    if (_running) {
      _timer?.cancel();
      setState(() => _running = false);
      return;
    }
    setState(() => _running = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _elapsed++);
      if (_elapsed >= p.totalSeconds) {
        t.cancel();
        setState(() => _running = false);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final done = _elapsed >= p.totalSeconds;
    final (label, scale, left, cycle) = _phase;
    final phaseDuration = switch (label) { 'Inhale' => p.inhale, 'Exhale' => p.exhale, _ => 1 };
    final remaining = p.totalSeconds - _elapsed;

    return Scaffold(
      backgroundColor: Noc.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Noc.gutter, 6, Noc.gutter, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                NocIconButton(icon: Nx.arrowLeft, tooltip: 'Back', onTap: () => Navigator.of(context).pop()),
                const SizedBox(width: 12),
                Expanded(child: Text(p.name, style: Noc.pageTitle)),
                NocTag(p.rhythm),
              ]),
              const SizedBox(height: 16),
              // The timer: what is left, how far through, which round.
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: Noc.card(),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(done ? 'DONE' : 'TIME LEFT', style: Noc.kicker),
                            const SizedBox(height: 2),
                            Text(clock(done ? 0 : remaining), style: Noc.stat, key: const Key('breatheClock')),
                          ],
                        ),
                        const Spacer(),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('ROUND', style: Noc.kicker),
                            const SizedBox(height: 2),
                            Text('${(done ? p.cycles : cycle + 1).clamp(1, p.cycles)} / ${p.cycles}', style: Noc.statSm),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 11),
                    NocBar(pct: p.totalSeconds == 0 ? 0 : _elapsed / p.totalSeconds, height: 5),
                  ],
                ),
              ),
              const Spacer(),
              Center(
                child: SizedBox(
                  width: 260,
                  height: 260,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedScale(
                        scale: done ? 1 : (_running ? scale : 0.7),
                        duration: Duration(seconds: _running ? phaseDuration : 1),
                        curve: Curves.easeInOut,
                        child: Container(
                          width: 260,
                          height: 260,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(colors: [Noc.accent400, Noc.accent800]),
                          ),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            done ? 'Done' : (_running ? label : 'Ready'),
                            style: Noc.hero.copyWith(fontSize: 30, color: Noc.accent900),
                          ),
                          if (_running && !done)
                            Text(
                              '$left',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 22,
                                fontVariations: Noc.w500,
                                color: Noc.accent900,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Text(
                done ? '${p.cycles} rounds, ${p.clock}. Notice where your shoulders are now.' : p.tagline,
                style: Noc.metaMuted,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              if (done)
                NocButton(
                  label: 'Share the calm',
                  icon: Nx.paperPlaneTilt,
                  block: true,
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    useRootNavigator: true,
                    isScrollControlled: true,
                    builder: (_) => ComposeSheet(title: '${p.name}: ${p.cycles} rounds done'),
                  ),
                )
              else
                NocButton(
                  label: _running ? 'Pause' : (_elapsed == 0 ? 'Start' : 'Resume'),
                  icon: _running ? Nx.minus : Nx.play,
                  block: true,
                  onTap: _toggle,
                ),
              const SizedBox(height: 8),
              NocButton(
                label: 'Reset',
                primary: false,
                block: true,
                onTap: () => setState(() {
                  _timer?.cancel();
                  _elapsed = 0;
                  _running = false;
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
