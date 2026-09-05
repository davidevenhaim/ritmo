import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/nocturne.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../feed/feed_screen.dart';
import 'breathing_builder.dart';

/// Breathing (v0.12 back in the app, v0.13 grouped, timed and yours,
/// v0.14 redrawn).
///
/// Patterns are grouped by what they are for, stress first — that is what
/// people open this page for, and the three under it are the ones the
/// research actually backs. Anything the app does not ship, the athlete
/// builds: in for x, hold for y, out for z, that many rounds.
///
/// Every card wears its own rhythm as a bar — in, hold, out, hold, drawn to
/// scale — so the shape of a pattern is legible before it is started.
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
              const _Poster(),
              const SizedBox(height: 22),
              for (final entry in groups.entries) ...[
                _GroupHead(purpose: entry.key),
                const SizedBox(height: 11),
                for (final p in entry.value) ...[
                  _PatternCard(pattern: p),
                  const SizedBox(height: 9),
                ],
                const SizedBox(height: 14),
              ],
              _BuildYourOwn(hasOwn: groups.containsKey(BreathePurpose.mine)),
              const SizedBox(height: 16),
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

/// The one thing the page is arguing for, on its own ground.
class _Poster extends StatelessWidget {
  const _Poster();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Noc.rCardLg),
          border: Border.all(color: Noc.accent800),
          gradient: const LinearGradient(
            begin: Alignment(-0.8, -1),
            end: Alignment(0.6, 1),
            colors: [Noc.accent900, Noc.sheet],
            stops: [0, 0.8],
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('NOT ONLY THE GYM', style: Noc.kickerAccent),
                  const SizedBox(height: 6),
                  Text('Two minutes changes the set', style: Noc.screenTitle.copyWith(fontSize: 24)),
                  const SizedBox(height: 9),
                  Text(
                    'Slow breathing drops your heart rate, sharpens focus and makes the next set better. Pick a pattern — '
                    'the circle leads, the clock counts, you follow.',
                    style: Noc.body.copyWith(color: Noc.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // A still frame of what the session does: three rings, mid-inhale.
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: _Rings(size: 54),
            ),
          ],
        ),
      );
}

/// Three concentric rings — the session's orb, small enough to be a mark.
class _Rings extends StatelessWidget {
  const _Rings({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            for (final (i, f) in [1.0, 0.72, 0.44].indexed)
              Container(
                width: size * f,
                height: size * f,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == 2 ? Noc.accent700 : null,
                  border: i == 2 ? null : Border.all(color: i == 0 ? Noc.accent800 : Noc.accent700),
                ),
              ),
          ],
        ),
      );
}

class _GroupHead extends StatelessWidget {
  const _GroupHead({required this.purpose});
  final BreathePurpose purpose;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(purpose.label.toUpperCase(), style: Noc.kickerAccent),
            const SizedBox(width: 12),
            Expanded(child: Container(height: 1, color: Noc.divider)),
          ]),
          const SizedBox(height: 4),
          Text(purpose.note, style: Noc.small),
        ],
      );
}

/// One pattern, with its rhythm drawn to scale.
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
      padding: const EdgeInsets.fromLTRB(13, 13, 13, 12),
      border: p.custom ? Border.all(color: Noc.accent700) : null,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BreathingSession(pattern: p))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Noc.accent900,
                  borderRadius: BorderRadius.circular(Noc.rControl),
                  border: Border.all(color: Noc.accent800),
                ),
                // CanvasKit has no emoji font on the web build, so the pattern
                // wears a Phosphor glyph rather than a tofu box.
                child: Icon(iconFor(p), size: 19, color: Noc.accent300),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: Text(p.name, style: Noc.cardTitle)),
                        const SizedBox(width: 8),
                        Text(p.clock, style: Noc.statSm.copyWith(fontSize: 15, color: Noc.neutral300)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(p.tagline, style: Noc.small, maxLines: 3),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (p.custom)
                NocIconButton(icon: Nx.x, size: 30, tooltip: 'Remove', onTap: () => _remove(context, ref))
              else
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Icon(Nx.play, size: 15, color: Noc.accent400),
                ),
            ],
          ),
          const SizedBox(height: 12),
          RhythmBar(pattern: p),
          const SizedBox(height: 8),
          Row(children: [
            Text(p.rhythm, style: Noc.tiny.copyWith(color: Noc.muted, letterSpacing: 0.6)),
            const SizedBox(width: 8),
            Container(width: 3, height: 3, decoration: const BoxDecoration(color: Noc.line, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text('${p.cycles} rounds', style: Noc.tiny.copyWith(color: Noc.dim)),
          ]),
        ],
      ),
    );
  }
}

/// One cycle of a pattern, drawn to scale: inhale, hold, exhale, hold. The
/// widths *are* the seconds, so a long exhale looks like a long exhale.
class RhythmBar extends StatelessWidget {
  const RhythmBar({super.key, required this.pattern, this.active = -1, this.height = 8});

  final BreathingPattern pattern;

  /// Which phase is running (0 in, 1 hold, 2 out, 3 hold), or -1 for none.
  final int active;
  final double height;

  static const _colors = [Noc.accent, Noc.accent800, Noc.accent400, Noc.accent900];

  @override
  Widget build(BuildContext context) {
    final spans = [pattern.inhale, pattern.holdIn, pattern.exhale, pattern.holdOut];
    return Row(
      children: [
        for (final (i, s) in spans.indexed)
          if (s > 0) ...[
            if (i > 0 && spans.take(i).any((x) => x > 0)) const SizedBox(width: 3),
            Expanded(
              flex: s,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                height: active == i ? height + 4 : height,
                decoration: BoxDecoration(
                  color: active < 0 || active == i ? _colors[i] : _colors[i].withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(height),
                ),
              ),
            ),
          ],
      ],
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

/// The pattern itself: one orb that fills on the inhale, holds, and falls
/// away on the exhale, with the seconds counted inside it, the session's own
/// progress drawn around it, and the rhythm lit up underneath.
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

  (String label, double scale, int secondsLeft, int cycle, int phase) get _phase {
    final cycle = _elapsed ~/ p.cycleSeconds;
    var t = _elapsed % p.cycleSeconds;
    if (t < p.inhale) return ('Inhale', 1.0, p.inhale - t, cycle, 0);
    t -= p.inhale;
    if (t < p.holdIn) return (p.holdInLabel, 1.0, p.holdIn - t, cycle, 1);
    t -= p.holdIn;
    if (t < p.exhale) return ('Exhale', 0.45, p.exhale - t, cycle, 2);
    t -= p.exhale;
    return ('Hold', 0.45, p.holdOut - t, cycle, 3);
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
    final (label, scale, left, cycle, phase) = _phase;
    final phaseDuration = switch (label) { 'Inhale' => p.inhale, 'Exhale' => p.exhale, _ => 1 };
    final remaining = p.totalSeconds - _elapsed;
    final progress = p.totalSeconds == 0 ? 0.0 : (_elapsed / p.totalSeconds).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Noc.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Noc.gutter, 6, Noc.gutter, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                NocIconButton(icon: Nx.arrowLeft, tooltip: 'Back', onTap: () => Navigator.of(context).pop()),
                const SizedBox(width: 12),
                Expanded(child: Text(p.name, style: Noc.pageTitle, maxLines: 1, overflow: TextOverflow.ellipsis)),
                NocTag(p.rhythm),
              ]),
              const SizedBox(height: 14),
              // What is left, and which round it is left in.
              Container(
                padding: const EdgeInsets.fromLTRB(15, 12, 15, 12),
                decoration: BoxDecoration(
                  color: Noc.sheet,
                  borderRadius: BorderRadius.circular(Noc.rCard),
                  border: Border.all(color: Noc.divider),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(done ? 'DONE' : 'TIME LEFT', style: Noc.kicker),
                        const SizedBox(height: 3),
                        Text(clock(done ? 0 : remaining), style: Noc.stat, key: const Key('breatheClock')),
                      ],
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('ROUND', style: Noc.kicker),
                        const SizedBox(height: 3),
                        Text('${(done ? p.cycles : cycle + 1).clamp(1, p.cycles)} / ${p.cycles}', style: Noc.statSm),
                      ],
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Center(
                child: _Orb(
                  label: done ? 'Done' : (_running ? label : 'Ready'),
                  count: _running && !done ? left : null,
                  scale: done ? 1 : (_running ? scale : 0.62),
                  seconds: _running ? phaseDuration : 1,
                  progress: progress,
                ),
              ),
              const SizedBox(height: 30),
              // The pattern, lit where you are in it.
              RhythmBar(pattern: p, active: _running && !done ? phase : -1, height: 9),
              const SizedBox(height: 12),
              Text(
                done ? '${p.cycles} rounds, ${p.clock}. Notice where your shoulders are now.' : p.tagline,
                style: Noc.metaMuted,
                textAlign: TextAlign.center,
              ),
              const Spacer(),
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
              const SizedBox(height: 9),
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

/// The breathing orb: a fixed outer ring you are filling towards, the arc of
/// the session drawn on it, a soft bloom, and the body itself, which is the
/// only part that moves.
class _Orb extends StatelessWidget {
  const _Orb({required this.label, required this.scale, required this.seconds, required this.progress, this.count});

  final String label;
  final int? count;

  /// Where the breath is: 1 at the top of the inhale, 0.45 at the bottom.
  final double scale;

  /// How long this phase lasts — the body takes exactly that long to move.
  final int seconds;

  /// The whole session, 0-1, drawn as an arc on the outer ring.
  final double progress;

  static const _size = 288.0;

  @override
  Widget build(BuildContext context) {
    final duration = Duration(seconds: seconds);
    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The room the breath has: a still ring, and the session's own arc.
          TweenAnimationBuilder<double>(
            tween: Tween(end: progress),
            duration: const Duration(milliseconds: 900),
            curve: Curves.linear,
            builder: (context, value, _) => CustomPaint(
              size: const Size.square(_size),
              painter: _ArcPainter(value),
            ),
          ),
          // A bloom that leads the body by a hair, so the edge is never hard.
          AnimatedScale(
            scale: scale * 1.06,
            duration: duration,
            curve: Curves.easeInOut,
            child: Container(
              width: _size - 26,
              height: _size - 26,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x5A9184D9), Color(0x00161826)],
                  stops: [0.55, 1],
                ),
              ),
            ),
          ),
          AnimatedScale(
            scale: scale,
            duration: duration,
            curve: Curves.easeInOut,
            child: Container(
              width: _size - 46,
              height: _size - 46,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Noc.accent400, Noc.accent700, Noc.accent800],
                  stops: [0, 0.62, 1],
                  center: Alignment(-0.25, -0.35),
                ),
                boxShadow: [BoxShadow(color: Color(0x59423A6A), blurRadius: 44, spreadRadius: 6)],
              ),
            ),
          ),
          // The words never scale — only the breath does.
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: Noc.hero.copyWith(fontSize: 28, color: Noc.accent100, letterSpacing: -0.5),
              ),
              if (count != null) ...[
                const SizedBox(height: 6),
                Text(
                  '$count',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 20,
                    fontVariations: Noc.w500,
                    color: Noc.accent200,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  _ArcPainter(this.pct);
  final double pct;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = (size.width - 3) / 2;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = Noc.accent900
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    if (pct <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -1.5707963,
      6.2831853 * pct.clamp(0.0, 1.0),
      false,
      Paint()
        ..color = Noc.accent400
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.pct != pct;
}
