import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../feed/feed_screen.dart';
import '../profile/badges_row.dart';
import '../../core/social_repository.dart';

class WorkoutPlayerScreen extends ConsumerStatefulWidget {
  const WorkoutPlayerScreen({super.key, required this.routineId, this.routine, this.initialDay = 0});
  final String routineId;
  final Routine? routine;
  final int initialDay;
  @override
  ConsumerState<WorkoutPlayerScreen> createState() => _WorkoutPlayerScreenState();
}

class _WorkoutPlayerScreenState extends ConsumerState<WorkoutPlayerScreen> {
  Routine? _r;
  int _day = 0;
  int _idx = 0;
  int _setsDone = 0;
  int _rest = 0;
  Timer? _timer;
  final _start = DateTime.now();
  bool _finished = false;
  bool _logged = false;
  int _totalSets = 0;

  @override
  void initState() {
    super.initState();
    _r = ref.read(routinesProvider.notifier).byId(widget.routineId) ??
        widget.routine ??
        SeedData.readyMade.where((x) => x.id == widget.routineId).firstOrNull;
    if (_r != null && _r!.days.isNotEmpty) _day = widget.initialDay.clamp(0, _r!.days.length - 1);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _completeSet(RoutineItem it) {
    setState(() {
      _setsDone++;
      _totalSets++;
    });
    if (_setsDone >= it.sets) {
      _next();
    } else if (it.restSec > 0) {
      _startRest(it.restSec);
    }
  }

  void _startRest(int sec) {
    _timer?.cancel();
    setState(() => _rest = sec);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_rest <= 1) {
        t.cancel();
        setState(() => _rest = 0);
      } else {
        setState(() => _rest--);
      }
    });
  }

  void _next() {
    _timer?.cancel();
    final items = _r!.days[_day].items;
    setState(() {
      _rest = 0;
      _setsDone = 0;
      if (_idx + 1 < items.length) {
        _idx++;
      } else {
        _finished = true;
      }
    });
    if (_finished && !_logged) {
      _logged = true;
      final r = _r!;
      // v0.4: the session counts toward streaks and badges.
      ref
          .read(activityProvider.notifier)
          .logWorkout(routine: r, dayTitle: r.days[_day].title, duration: DateTime.now().difference(_start), sets: _totalSets)
          .then((res) {
        if (mounted) toastBadges(context, res);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    if (r == null || r.days.isEmpty) return const Scaffold(body: EmptyState(emoji: '🫥', title: 'Nothing to play'));
    final t = Theme.of(context).textTheme;
    final repo = ref.watch(exerciseRepoProvider).value;
    final items = r.days[_day].items;

    if (_finished) {
      final mins = DateTime.now().difference(_start).inMinutes;
      return Scaffold(
        appBar: AppBar(title: const Text('Done')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('🏁', style: TextStyle(fontSize: 64), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text('${r.days[_day].title} complete', style: t.headlineMedium, textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text('${items.length} exercises · ${mins < 1 ? '<1' : mins} min', style: t.bodySmall, textAlign: TextAlign.center),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => ComposeSheet(routine: r, title: 'Finished ${r.name} · ${r.days[_day].title}'),
                ),
                icon: const Icon(Icons.ios_share),
                label: const Text('Share to feed'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: () => context.pop(), child: const Text('Back')),
            ],
          ),
        ),
      );
    }

    final it = items[_idx];
    final ex = repo?.byId(it.exerciseId);
    return Scaffold(
      appBar: AppBar(
        title: Text(r.name, style: t.titleMedium),
        actions: [
          if (r.days.length > 1)
            DropdownButton<int>(
              value: _day,
              underline: const SizedBox(),
              dropdownColor: SoColors.surface2,
              items: [for (var i = 0; i < r.days.length; i++) DropdownMenuItem(value: i, child: Text(r.days[i].title))],
              onChanged: (v) => setState(() {
                _day = v ?? 0;
                _idx = 0;
                _setsDone = 0;
                _rest = 0;
              }),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(value: (_idx) / items.length, backgroundColor: SoColors.line, borderRadius: BorderRadius.circular(99)),
            const SizedBox(height: 6),
            Text('Exercise ${_idx + 1} of ${items.length}', style: t.labelSmall),
            const SizedBox(height: 16),
            if (ex != null) Center(child: ExerciseThumb(ex, size: 200, radius: 20)),
            const SizedBox(height: 16),
            Text(it.exerciseName, style: t.headlineMedium, textAlign: TextAlign.center),
            if (it.notes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(it.notes, style: t.bodySmall, textAlign: TextAlign.center)),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var s = 0; s < it.sets; s++)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: s < _setsDone ? SoColors.mint : SoColors.surface2,
                      shape: BoxShape.circle,
                    ),
                    child: Text('${s + 1}', style: TextStyle(fontWeight: FontWeight.w700, color: s < _setsDone ? SoColors.ink : SoColors.text)),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text('${it.reps} reps per set', style: t.bodySmall, textAlign: TextAlign.center),
            const Spacer(),
            if (_rest > 0) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: SoColors.mintSoft, borderRadius: BorderRadius.circular(16)),
                child: Column(children: [
                  Text('REST', style: t.labelSmall?.copyWith(color: SoColors.mint)),
                  Text('$_rest', style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w800, color: SoColors.mint, fontFeatures: [FontFeature.tabularFigures()])),
                  TextButton(onPressed: () => setState(() { _timer?.cancel(); _rest = 0; }), child: const Text('Skip rest')),
                ]),
              ),
            ] else
              FilledButton(
                onPressed: () => _completeSet(it),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
                child: Text(_setsDone + 1 >= it.sets ? 'Finish set ${_setsDone + 1} → next exercise' : 'Set ${_setsDone + 1} done'),
              ),
            const SizedBox(height: 8),
            TextButton(onPressed: _next, child: const Text('Skip exercise')),
          ],
        ),
      ),
    );
  }
}
