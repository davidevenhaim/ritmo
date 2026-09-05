import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/badge_rules.dart';
import '../../core/models.dart';
import '../../core/providers.dart';

/// Earned badges as a shelf; the rest of the catalogue greyed out (v0.4).
class BadgeShelf extends ConsumerWidget {
  const BadgeShelf({super.key, required this.userId, this.compactShelf = false});
  final String userId;
  final bool compactShelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final earned = ref.watch(badgesProvider(userId)).value ?? const <UserBadge>[];
    final have = {for (final b in earned) b.code: b};
    final list = compactShelf ? badgeCatalogue.where((b) => have.containsKey(b.code)).toList() : badgeCatalogue;
    if (list.isEmpty) return Text('No badges yet. Finish a workout or hit your step goal.', style: Theme.of(context).textTheme.bodySmall);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final b in list)
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _show(context, b, have[b.code]),
            child: Opacity(
              opacity: have.containsKey(b.code) ? 1 : 0.35,
              child: Container(
                width: 64,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: SoColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: have.containsKey(b.code) ? _tierColor(b.tier) : SoColors.line),
                ),
                child: Column(children: [
                  Text(b.emoji, style: const TextStyle(fontSize: 24)),
                  const SizedBox(height: 2),
                  Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ),
      ],
    );
  }

  static Color _tierColor(int tier) => switch (tier) { 3 => SoColors.amber, 2 => SoColors.violet, _ => SoColors.mint };

  void _show(BuildContext context, AppBadge b, UserBadge? earned) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${b.emoji} ${b.name}'),
          content: Text(earned == null ? '${b.description}. Not earned yet.' : '${b.description}. Earned ${timeAgo(earned.earnedAt)} ago.'),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
        ),
      );
}

/// Flame chip: "🔥 12-day streak".
class StreakChip extends StatelessWidget {
  const StreakChip({super.key, required this.days, this.label = 'streak'});
  final int days;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: days > 0 ? SoColors.coralSoft : SoColors.surface2, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(days > 0 ? '🔥' : '🕯️', style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              '$days-day $label',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: days > 0 ? SoColors.coral : SoColors.muted),
            ),
          ),
        ]),
      );
}

/// Snackbar for badges a sync or workout just earned.
void toastBadges(BuildContext context, SyncResult? r) {
  if (r == null || r.newBadges.isEmpty) return;
  final names = r.newBadges.map((c) => badgeByCode(c)).whereType<AppBadge>().map((b) => '${b.emoji} ${b.name}').join(', ');
  toast(context, 'New badge: $names');
}
