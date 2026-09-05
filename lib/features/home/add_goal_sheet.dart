import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/nocturne.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../explore/explore_screen.dart';
import 'exercise_goal_sheet.dart';
import 'goal_deadline.dart';

/// "Set a goal", as a sheet rather than the dialog it used to be.
///
/// Two steps, both inside the sheet: pick what to chase — any of the 1,443
/// exercises, or one of the ready-made goals — then tune it. Tuning is the
/// point: every preset is a number the athlete moves and a date they choose,
/// so "Run 5 km in four weeks" and "Run a half in twelve" are one row.
///
/// Returns true when a goal was actually set.
Future<bool> showAddGoalSheet(BuildContext context, WidgetRef ref) async {
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
    builder: (_) => const _AddGoalSheet(),
  );
  return done ?? false;
}

class _AddGoalSheet extends ConsumerStatefulWidget {
  const _AddGoalSheet();
  @override
  ConsumerState<_AddGoalSheet> createState() => _AddGoalSheetState();
}

class _AddGoalSheetState extends ConsumerState<_AddGoalSheet> {
  /// Null while choosing; set once a template is being tuned.
  GoalTemplate? _template;
  late double _target;
  DateTime? _deadline;

  static IconData iconFor(String id) => switch (id) {
        'run' => Nx.footprints,
        'ride' => Nx.footprints,
        'rope' => Nx.heartbeat,
        'pullup' => Nx.barbell,
        'pushup' => Nx.barbell,
        'squat' => Nx.barbell,
        'plank' => Nx.clock,
        'handstand' => Nx.sparkle,
        'split' => Nx.heart,
        _ => Nx.target,
      };

  void _open(GoalTemplate t) => setState(() {
        _template = t;
        _target = t.target;
        _deadline = DeadlinePicker.dayAfter(t.days);
      });

  /// The library in picking mode, then the exercise sheet — which carries its
  /// own metric chips, because a movement can be counted three ways.
  Future<void> _fromExercise() async {
    final picked = await Navigator.of(context, rootNavigator: true).push<Exercise>(
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          appBar: AppBar(title: const Text('Pick an exercise')),
          body: LibraryTab(onPick: (e) => Navigator.pop(ctx, e)),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    if (ref.read(customGoalsProvider.notifier).hasExercise(picked.id)) {
      nocToast(context, '${picked.name} is already a goal.');
      return;
    }
    final added = await showExerciseGoalSheet(context, ref, picked);
    if (added && mounted) Navigator.pop(context, true);
  }

  Future<void> _save() async {
    final t = _template!;
    await ref.read(customGoalsProvider.notifier).add(
          name: t.nameFor(_target),
          target: _target,
          unit: t.unit,
          note: t.note,
          deadline: _deadline,
        );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.86),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: Noc.line, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              if (_template == null) ..._chooser() else ..._tune(_template!),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- step one
  List<Widget> _chooser() => [
        Text('Set a goal', style: Noc.pageTitle),
        const SizedBox(height: 4),
        Text('Pick something to chase, then say by when.', style: Noc.bodyMuted),
        const SizedBox(height: 16),
        NocCard(
          color: Noc.accent900,
          border: Border.all(color: Noc.accent700),
          radius: Noc.rControl,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          onTap: _fromExercise,
          child: Row(children: [
            const Icon(Nx.magnifyingGlass, size: 16, color: Noc.accent300),
            const SizedBox(width: 11),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('An exercise', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: Noc.accent200)),
                SizedBox(height: 1),
                Text('Pick any of the 1,443 and set a number', style: Noc.small),
              ]),
            ),
            const Icon(Nx.caretRight, size: 14, color: Noc.accent400),
          ]),
        ),
        const SizedBox(height: 16),
        Text('OR START FROM ONE OF THESE', style: Noc.columnLabel),
        const SizedBox(height: 9),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: goalTemplates.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final t = goalTemplates[i];
              return NocCard(
                color: Noc.sunken,
                border: Border.all(color: Noc.sunken),
                radius: Noc.rRowSm,
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                onTap: () => _open(t),
                child: Row(children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: Noc.sheet, borderRadius: BorderRadius.circular(Noc.rIcon)),
                    child: Icon(iconFor(t.id), size: 15, color: Noc.accent400),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t.nameFor(t.target), style: Noc.rowTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text('${t.note} · ${DeadlinePicker.horizonLabel(t.days)}', style: Noc.small, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Nx.caretRight, size: 13, color: Noc.dim),
                ]),
              );
            },
          ),
        ),
      ];

  // ------------------------------------------------------------- step two
  List<Widget> _tune(GoalTemplate t) {
    final value = '${GoalTemplate.fmt(_target)}${t.unit}';
    return [
      Row(children: [
        NocIconButton(icon: Nx.arrowLeft, size: 32, tooltip: 'Back', onTap: () => setState(() => _template = null)),
        const SizedBox(width: 11),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('YOUR GOAL', style: Noc.kickerAccent),
            const SizedBox(height: 2),
            Text(t.nameFor(_target), style: Noc.cardTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ]),
      const SizedBox(height: 18),
      Flexible(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('HOW MUCH', style: Noc.columnLabel),
              const SizedBox(height: 8),
              Row(children: [
                NocIconButton(
                  icon: Nx.minus,
                  size: 38,
                  outlined: true,
                  tooltip: 'Less',
                  onTap: () => setState(() => _target = (_target - t.step).clamp(t.min, t.max)),
                ),
                Expanded(child: Center(child: Text(value, style: Noc.hero.copyWith(fontSize: 30)))),
                NocIconButton(
                  icon: Nx.plus,
                  size: 38,
                  outlined: true,
                  tooltip: 'More',
                  onTap: () => setState(() => _target = (_target + t.step).clamp(t.min, t.max)),
                ),
              ]),
              // The slider snaps to the template's step, but a rope goal has
              // sixty of them — drawn as ticks that is a dotted line, so the
              // ticks come off and the number above does the talking.
              SliderTheme(
                data: SliderTheme.of(context).copyWith(tickMarkShape: SliderTickMarkShape.noTickMark),
                child: Slider(
                  value: _target.clamp(t.min, t.max),
                  min: t.min,
                  max: t.max,
                  divisions: ((t.max - t.min) / t.step).round(),
                  activeColor: Noc.accent,
                  inactiveColor: Noc.sunken,
                  onChanged: (v) => setState(() => _target = (v / t.step).round() * t.step),
                ),
              ),
              const SizedBox(height: 6),
              Text('BY WHEN', style: Noc.columnLabel),
              const SizedBox(height: 9),
              DeadlinePicker(
                value: _deadline,
                suggestedDays: t.days,
                onChanged: (d) => setState(() => _deadline = d),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                decoration: BoxDecoration(color: Noc.sunken, borderRadius: BorderRadius.circular(Noc.rControl)),
                child: Row(children: [
                  const Icon(Nx.sparkle, size: 14, color: Noc.accent400),
                  const SizedBox(width: 9),
                  Expanded(child: Text(t.note, style: Noc.small)),
                ]),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      NocButton(label: 'Set the goal', icon: Nx.target, block: true, onTap: _save),
    ];
  }
}
