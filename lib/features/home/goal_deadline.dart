import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/nocturne.dart';

/// The date half of a goal: "do X *until* Y".
///
/// A goal without a date is a wish, so every way into the goals card offers
/// this row — the preset sheet, the exercise sheet and the goal row itself.
/// The ladder is deliberately short: four horizons, a real date picker for
/// anybody who is training towards an event, and an explicit way to say the
/// goal has no date at all.
class DeadlinePicker extends StatelessWidget {
  const DeadlinePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.suggestedDays,
    this.allowNone = true,
  });

  final DateTime? value;

  /// The template's own horizon, folded into the ladder so a squat goal opens
  /// on twelve weeks and a plank on four.
  final int? suggestedDays;

  final bool allowNone;
  final ValueChanged<DateTime?> onChanged;

  static DateTime dayAfter(int days) {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day).add(Duration(days: days));
  }

  static String horizonLabel(int days) {
    if (days % 7 == 0) {
      final w = days ~/ 7;
      return w == 1 ? '1 week' : '$w weeks';
    }
    return '$days days';
  }

  /// "Sun 1 Nov · 57 days to go".
  static String dueLine(DateTime? at) {
    if (at == null) return 'No date — it stays on the card until you get there';
    final n = DateTime.now();
    final days = DateTime(at.year, at.month, at.day).difference(DateTime(n.year, n.month, n.day)).inDays;
    final when = DateFormat('EEE d MMM').format(at);
    if (days == 0) return '$when · today';
    if (days == 1) return '$when · tomorrow';
    if (days < 0) return '$when · ${-days} days ago';
    return '$when · $days days to go';
  }

  List<int> get _ladder {
    final set = {14, 28, 56, 84, ?suggestedDays};
    return set.toList()..sort();
  }

  bool _isDays(int days) {
    if (value == null) return false;
    final n = DateTime.now();
    return DateTime(value!.year, value!.month, value!.day).difference(DateTime(n.year, n.month, n.day)).inDays == days;
  }

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: value ?? dayAfter(suggestedDays ?? 28),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 3, now.month, now.day),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Noc.accent,
            onPrimary: Noc.bg,
            surface: Noc.surface,
            onSurface: Noc.text,
          ),
          dialogTheme: const DialogThemeData(backgroundColor: Noc.surface),
        ),
        child: child!,
      ),
    );
    if (picked != null) onChanged(DateTime(picked.year, picked.month, picked.day));
  }

  @override
  Widget build(BuildContext context) {
    final custom = value != null && !_ladder.any(_isDays);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final days in _ladder)
              _WhenChip(
                label: horizonLabel(days),
                on: _isDays(days),
                onTap: () => onChanged(dayAfter(days)),
              ),
            _WhenChip(
              label: custom ? DateFormat('d MMM').format(value!) : 'Pick a date',
              icon: Nx.calendarBlank,
              on: custom,
              onTap: () => _pick(context),
            ),
            if (allowNone)
              _WhenChip(
                label: 'No date',
                on: value == null,
                onTap: () => onChanged(null),
              ),
          ],
        ),
        const SizedBox(height: 9),
        Text(dueLine(value), style: Noc.small.copyWith(color: value == null ? Noc.dim : Noc.accent300)),
      ],
    );
  }
}

class _WhenChip extends StatelessWidget {
  const _WhenChip({required this.label, required this.on, required this.onTap, this.icon});
  final String label;
  final bool on;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: on ? Noc.accent900 : Colors.transparent,
            borderRadius: BorderRadius.circular(Noc.rPill),
            border: Border.all(color: on ? Noc.accent : Noc.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: on ? Noc.accent200 : Noc.muted),
                const SizedBox(width: 6),
              ],
              Text(label, style: TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: on ? Noc.accent200 : Noc.muted)),
            ],
          ),
        ),
      );
}
