import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import 'plus_menu.dart';

/// Every scheduled workout, upcoming first, done and missed below.
class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(scheduleProvider);
    final now = DateTime.now();
    final upcoming = all.where((s) => !s.done && s.at.isAfter(now.subtract(const Duration(hours: 24)))).toList();
    final past = all.where((s) => s.done || !s.at.isAfter(now.subtract(const Duration(hours: 24)))).toList().reversed.toList();
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('My schedule')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showScheduleSheet(context),
        backgroundColor: SoColors.coral,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Schedule'),
      ),
      body: all.isEmpty
          ? const EmptyState(emoji: '🗓️', title: 'Nothing scheduled', body: 'Plan a workout and it shows up on your home page.')
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
              children: [
                if (upcoming.isNotEmpty) const SectionTitle('Upcoming'),
                for (final s in upcoming) _Row(item: s),
                if (past.isNotEmpty) ...[
                  const SectionTitle('Earlier'),
                  for (final s in past) _Row(item: s),
                ],
                const SizedBox(height: 8),
                Text('Swipe left to remove. Finishing a workout in the player ticks it off.', style: t.bodySmall, textAlign: TextAlign.center),
              ],
            ),
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row({required this.item});
  final ScheduledWorkout item;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final color = item.done ? SoColors.mint : item.isPast ? SoColors.coral : SoColors.amber;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Dismissible(
        key: ValueKey(item.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(color: SoColors.coralSoft, borderRadius: BorderRadius.circular(14)),
          child: const Icon(Icons.delete_outline, color: SoColors.coral),
        ),
        onDismissed: (_) => ref.read(scheduleProvider.notifier).remove(item.id),
        child: ListTile(
          tileColor: SoColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: SoColors.line)),
          leading: Icon(item.done ? Icons.check_circle : item.isPast ? Icons.error_outline : Icons.event, color: color),
          title: Text(item.routineName, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${item.dayTitle.isEmpty ? '' : '${item.dayTitle} · '}${DateFormat('EEE d MMM, h:mm a').format(item.at)}${item.note.isEmpty ? '' : ' · ${item.note}'}', style: t.bodySmall),
          trailing: item.done
              ? const TagChip('Done', color: SoColors.mint)
              : TextButton(onPressed: () => context.push('/workout/${item.routineId}?day=${item.dayIndex}'), child: const Text('Start')),
          onLongPress: item.done
              ? null
              : () async {
                  final d = await showDatePicker(context: context, initialDate: item.at, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 90)));
                  if (d == null || !context.mounted) return;
                  final tm = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(item.at));
                  if (tm == null) return;
                  await ref.read(scheduleProvider.notifier).reschedule(item.id, DateTime(d.year, d.month, d.day, tm.hour, tm.minute));
                },
        ),
      ),
    );
  }
}
