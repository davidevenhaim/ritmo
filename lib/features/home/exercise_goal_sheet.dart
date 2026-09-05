import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/nocturne.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../build/build_screen.dart' show ExerciseMedia;
import 'goal_deadline.dart';

/// Make one exercise out of the catalogue a goal: "10 strict pull-ups",
/// "60s hollow hold", "100 kg squat".
///
/// The goal keeps the exercise on it, so the goals card can show the movement
/// and open it, rather than carrying a sentence somebody typed once.
Future<bool> showExerciseGoalSheet(BuildContext context, WidgetRef ref, Exercise exercise) async {
  final done = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    // The sheet draws the handoff's own handle; the theme's Material one
    // would sit above it as a second pill.
    showDragHandle: false,
    backgroundColor: Noc.sheet,
    barrierColor: Noc.scrim,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Noc.rSheet))),
    builder: (_) => _ExerciseGoalSheet(exercise: exercise),
  );
  return done ?? false;
}

class _ExerciseGoalSheet extends ConsumerStatefulWidget {
  const _ExerciseGoalSheet({required this.exercise});
  final Exercise exercise;
  @override
  ConsumerState<_ExerciseGoalSheet> createState() => _ExerciseGoalSheetState();
}

class _ExerciseGoalSheetState extends ConsumerState<_ExerciseGoalSheet> {
  late GoalMetric _metric = _defaultMetric(widget.exercise);
  late double _target = _metric.defaultTarget;

  /// Eight weeks is the default horizon for a movement goal: long enough for
  /// a rep number to actually move, short enough to stay in view.
  DateTime? _deadline = DeadlinePicker.dayAfter(56);

  /// A stretch or a plank is held; everything else is counted in reps until
  /// the athlete says otherwise.
  static GoalMetric _defaultMetric(Exercise e) {
    final n = e.name.toLowerCase();
    if (e.category == 'stretching' || e.category == 'yoga' || n.contains('plank') || n.contains('hold') || n.contains('hang')) {
      return GoalMetric.seconds;
    }
    return GoalMetric.reps;
  }

  double get _step => switch (_metric) {
        GoalMetric.reps => 1,
        GoalMetric.seconds => 5,
        GoalMetric.kilos => 2.5,
      };

  String get _value {
    final v = _target;
    final n = v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
    return '$n${_metric.unit}';
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.exercise;
    return SafeArea(
      top: false,
      // The deadline row makes this sheet tall enough to reach the top of a
      // small phone, so the whole thing scrolls rather than overflowing.
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: Noc.line, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Row(children: [
                ExerciseMedia(exercise: e, height: 44, radius: 11, dot: false),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('MAKE IT A GOAL', style: Noc.kickerAccent),
                      const SizedBox(height: 2),
                      Text(e.name, style: Noc.cardTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 18),
              Text('COUNTED IN', style: Noc.columnLabel),
              const SizedBox(height: 8),
              Row(children: [
                for (final m in GoalMetric.values) ...[
                  if (m != GoalMetric.values.first) const SizedBox(width: 8),
                  _MetricChip(
                    label: m.label,
                    on: m == _metric,
                    onTap: () => setState(() {
                      _metric = m;
                      _target = m.defaultTarget;
                    }),
                  ),
                ],
              ]),
              const SizedBox(height: 18),
              Text('TARGET', style: Noc.columnLabel),
              const SizedBox(height: 8),
              Row(children: [
                NocIconButton(icon: Nx.minus, size: 38, outlined: true, tooltip: 'Less', onTap: () => setState(() => _target = (_target - _step).clamp(_step, 999))),
                Expanded(child: Center(child: Text(_value, style: Noc.hero.copyWith(fontSize: 30)))),
                NocIconButton(icon: Nx.plus, size: 38, outlined: true, tooltip: 'More', onTap: () => setState(() => _target = (_target + _step).clamp(_step, 999))),
              ]),
              const SizedBox(height: 18),
              Text('BY WHEN', style: Noc.columnLabel),
              const SizedBox(height: 9),
              DeadlinePicker(
                value: _deadline,
                suggestedDays: 56,
                onChanged: (d) => setState(() => _deadline = d),
              ),
              const SizedBox(height: 18),
              NocButton(
                label: 'Set the goal',
                icon: Nx.target,
                block: true,
                onTap: () async {
                  await ref.read(customGoalsProvider.notifier).add(
                        name: e.name,
                        target: _target,
                        unit: _metric.unit,
                        note: 'From the exercise library · track it as you train',
                        exerciseId: e.id,
                        exerciseName: e.name,
                        deadline: _deadline,
                      );
                  if (context.mounted) Navigator.pop(context, true);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? Noc.accent900 : Colors.transparent,
              borderRadius: BorderRadius.circular(Noc.rControl),
              border: Border.all(color: on ? Noc.accent : Noc.line),
            ),
            child: Text(label, style: TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: on ? Noc.accent200 : Noc.muted)),
          ),
        ),
      );
}
