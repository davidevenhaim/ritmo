import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../feed/feed_screen.dart';
import '../home/exercise_goal_sheet.dart';

class ExerciseDetailScreen extends ConsumerStatefulWidget {
  const ExerciseDetailScreen({super.key, required this.exerciseId, this.exercise});
  final String exerciseId;
  final Exercise? exercise;
  @override
  ConsumerState<ExerciseDetailScreen> createState() => _ExerciseDetailScreenState();
}

class _ExerciseDetailScreenState extends ConsumerState<ExerciseDetailScreen> {
  int _frame = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 900), (_) => setState(() => _frame++));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(exerciseRepoProvider).value;
    final e = widget.exercise ?? repo?.byId(widget.exerciseId);
    if (e == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final t = Theme.of(context).textTheme;
    final img = e.imageUrl(_frame);
    return Scaffold(
      appBar: AppBar(
        title: Text(e.name, style: t.titleMedium),
        actions: [
          IconButton(
            tooltip: 'Share to feed',
            icon: const Icon(Icons.ios_share),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => ComposeSheet(title: 'Just did ${e.name}'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Container(
              color: Colors.white,
              height: 260,
              child: img == null
                  ? const Center(child: Icon(Icons.fitness_center, size: 48, color: SoColors.muted))
                  : Image.network(img, fit: BoxFit.contain, gaplessPlayback: true,
                      errorBuilder: (_, _, _) => const Center(child: Icon(Icons.image_not_supported_outlined, color: SoColors.muted))),
            ),
          ),
          if (e.images.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Animated from ${e.images.length} frames · ${e.source}', style: t.bodySmall, textAlign: TextAlign.center),
            ),
          const SizedBox(height: 16),
          Text(e.name, style: t.headlineMedium),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final m in e.primary) TagChip(m, color: SoColors.coral),
              for (final m in e.secondary) TagChip(m),
              TagChip(e.equipment, color: SoColors.amber),
              TagChip(e.category, color: SoColors.violet),
              if (e.level != null) TagChip(e.level!, color: SoColors.mint),
              if (e.mechanic != null) TagChip(e.mechanic!),
              if (e.force != null) TagChip('force: ${e.force}'),
            ],
          ),
          const SizedBox(height: 20),
          const SectionTitle('How to do it'),
          if (e.instructions.isEmpty)
            Text('No instructions in the dataset yet. Community edits coming in v0.3.', style: t.bodySmall)
          else
            for (var i = 0; i < e.instructions.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(color: SoColors.surface2, shape: BoxShape.circle),
                      child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(e.instructions[i], style: t.bodyMedium)),
                  ],
                ),
              ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _addToRoutine(context, e),
            icon: const Icon(Icons.playlist_add),
            label: const Text('Add to a routine'),
          ),
          const SizedBox(height: 8),
          // Any exercise can become a goal: pick what it is counted in and
          // the number, and it lands on the Me page with the others.
          Builder(builder: (context) {
            final already = ref.watch(customGoalsProvider).any((g) => g.exerciseId == e.id);
            return OutlinedButton.icon(
              onPressed: already
                  ? () => toast(context, 'Already one of your goals. Track it from the Me page.')
                  : () async {
                      final added = await showExerciseGoalSheet(context, ref, e);
                      if (added && context.mounted) toast(context, '${e.name} is a goal now.');
                    },
              icon: Icon(already ? Icons.flag : Icons.flag_outlined),
              label: Text(already ? 'Already a goal' : 'Make this a goal'),
            );
          }),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => context.push('/coach'),
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Ask the coach about this'),
          ),
        ],
      ),
    );
  }

  Future<void> _addToRoutine(BuildContext context, Exercise e) async {
    final mine = ref.read(routinesProvider);
    final me = ref.read(profileProvider)!;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text('Add to…', style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.add_circle_outline, color: SoColors.coral),
            title: const Text('New routine'),
            onTap: () => Navigator.of(ctx).pop('__new__'),
          ),
          for (final r in mine)
            ListTile(
              leading: const Icon(Icons.list_alt, color: SoColors.amber),
              title: Text(r.name),
              subtitle: Text('${r.days.length} days · ${r.exerciseCount} exercises'),
              onTap: () => Navigator.of(ctx).pop(r.id),
            ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    final item = RoutineItem(exerciseId: e.id, exerciseName: e.name);
    if (choice == '__new__') {
      final r = Routine(
        id: 'mine_${DateTime.now().millisecondsSinceEpoch}',
        name: '${e.name} day',
        description: '',
        authorId: me.id,
        authorName: me.name,
        days: [RoutineDay(title: 'Day 1', focus: e.primary.join(', '), items: [item])],
        createdAt: DateTime.now(),
      );
      await ref.read(routinesProvider.notifier).upsert(r);
      if (context.mounted) context.push('/workout/${r.id}', extra: r);
    } else {
      final r = mine.firstWhere((x) => x.id == choice);
      final days = [...r.days];
      days[days.length - 1] = days.last.copyWith(items: [...days.last.items, item]);
      await ref.read(routinesProvider.notifier).upsert(r.copyWith(days: days));
      if (context.mounted) toast(context, 'Added to ${r.name}');
    }
  }
}
