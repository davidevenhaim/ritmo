import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../feed/feed_screen.dart';
import '../profile/badges_row.dart';

class StepsScreen extends ConsumerWidget {
  const StepsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(profileProvider)!;
    final steps = ref.watch(stepsProvider);
    final source = ref.watch(stepsSourceProvider);
    final streaks = ref.watch(streaksProvider).value ?? const Streaks();
    final ranks = ref.watch(leagueRanksProvider).value ?? const <LeagueRank>[];
    final t = Theme.of(context).textTheme;
    final sourceLabel = !source.isReal
        ? 'Demo data (${kIsWeb ? 'web' : 'desktop'} build)'
        : defaultTargetPlatform == TargetPlatform.iOS
            ? 'Apple Health'
            : 'Health Connect';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Steps'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: () => ref.read(stepsProvider.notifier).refresh())],
      ),
      body: steps.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(
          emoji: '🔒',
          title: 'Steps are locked',
          body: '$e',
          action: FilledButton(onPressed: () => ref.read(stepsProvider.notifier).connect(), child: const Text('Try again')),
        ),
        data: (days) {
          if (days.isEmpty) {
            return EmptyState(
              emoji: '👟',
              title: 'Connect $sourceLabel',
              body: 'Ritmo only reads your step count. Nothing is shared until you post it.',
              action: FilledButton.icon(
                onPressed: () => ref.read(stepsProvider.notifier).connect(),
                icon: const Icon(Icons.link),
                label: Text('Connect $sourceLabel'),
              ),
            );
          }
          final today = days.last.steps;
          final pct = (today / me.stepGoal).clamp(0.0, 1.0);
          final weekTotal = days.fold(0, (n, d) => n + d.steps);
          final best = days.reduce((a, b) => a.steps >= b.steps ? a : b);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            children: [
              Center(
                child: SizedBox(
                  width: 220,
                  height: 220,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(size: const Size(220, 220), painter: _RingPainter(pct)),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(NumberFormat.decimalPattern().format(today), style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()], letterSpacing: -1)),
                          Text('of ${NumberFormat.decimalPattern().format(me.stepGoal)} today', style: t.bodySmall),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(child: TagChip(sourceLabel, color: SoColors.mint)),
              const SizedBox(height: 12),
              Center(
                child: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                  StreakChip(days: streaks.stepStreak),
                  if (streaks.stepBest > streaks.stepStreak) TagChip('best ${streaks.stepBest} days', color: SoColors.amber),
                ]),
              ),
              const SizedBox(height: 20),
              _LeaguesStrip(ranks: ranks),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: _Stat(label: 'THIS WEEK', value: compact(weekTotal))),
                  const SizedBox(width: 10),
                  Expanded(child: _Stat(label: 'DAILY AVG', value: compact(weekTotal ~/ days.length))),
                  const SizedBox(width: 10),
                  Expanded(child: _Stat(label: 'BEST DAY', value: DateFormat.E().format(best.date))),
                ],
              ),
              const SizedBox(height: 24),
              const SectionTitle('Last 7 days'),
              _BarChart(days: days, goal: me.stepGoal),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => ComposeSheet(steps: today, title: 'Steps: ${NumberFormat.decimalPattern().format(today)} today'),
                ),
                icon: const Icon(Icons.ios_share),
                label: const Text("Share today's steps"),
              ),
              const SizedBox(height: 12),
              Text(
                'Privacy: step counts stay on your device until you tap Share. Ritmo never reads other health data types.',
                style: t.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// "You are #2 in Lunch Walkers" plus a way in (v0.4).
class _LeaguesStrip extends StatelessWidget {
  const _LeaguesStrip({required this.ranks});
  final List<LeagueRank> ranks;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => context.push('/leagues'),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: SoColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: SoColors.line)),
        child: Row(children: [
          const Icon(Icons.emoji_events_outlined, color: SoColors.amber),
          const SizedBox(width: 10),
          Expanded(
            child: ranks.isEmpty
                ? Text('Steps leagues: race friends Monday to Sunday.', style: t.bodyMedium)
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final r in ranks.take(3))
                      Text('${r.emoji} ${r.name}: #${r.rank} of ${r.of}${r.rank == 1 ? ', leading' : ', ${compact(r.gapToLeader)} behind'}', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    Text('${ranks.first.daysLeft} day${ranks.first.daysLeft == 1 ? '' : 's'} left this week', style: t.bodySmall),
                  ]),
          ),
          const Icon(Icons.chevron_right, color: SoColors.muted),
        ]),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: SoColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: SoColors.line)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
          ],
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.pct);
  final double pct;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 12;
    final bg = Paint()
      ..color = SoColors.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;
    final fg = Paint()
      ..color = SoColors.mint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r, bg);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -pi / 2, 2 * pi * pct, false, fg);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.pct != pct;
}

class _BarChart extends StatelessWidget {
  const _BarChart({required this.days, required this.goal});
  final List<StepDay> days;
  final int goal;

  @override
  Widget build(BuildContext context) {
    final maxV = max(goal, days.map((d) => d.steps).reduce(max)).toDouble();
    return Container(
      height: 170,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(color: SoColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: SoColors.line)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final d in days)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(compact(d.steps), style: const TextStyle(fontSize: 10, color: SoColors.muted, fontFeatures: [FontFeature.tabularFigures()])),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: (d.steps / maxV).clamp(0.03, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: d.steps >= goal ? SoColors.mint : SoColors.mint.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(DateFormat.E().format(d.date).substring(0, 2), style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
