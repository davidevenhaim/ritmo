import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/models.dart';
import '../../core/providers.dart';

/// Follows, likes, recommends, comments and Try-its aimed at you (v0.2).
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});
  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Opening the screen counts as reading; the badge clears after leaving.
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) ref.read(socialProvider.notifier).markNotificationsRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    final social = ref.watch(socialProvider);
    final notifier = ref.read(socialProvider.notifier);
    final t = Theme.of(context).textTheme;
    final items = social.notifications;

    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      body: items.isEmpty
          ? const EmptyState(emoji: '🔔', title: 'Quiet for now', body: 'Share a routine or your steps and people will show up here.')
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
              itemBuilder: (_, i) {
                final n = items[i];
                final actor = n.actorId == null ? null : notifier.userOf(n.actorId!);
                final (icon, color, verb) = switch (n.kind) {
                  NotificationKind.follow => (Icons.person_add, SoColors.violet, 'started following you'),
                  NotificationKind.like => (Icons.favorite, SoColors.coral, 'liked your post'),
                  NotificationKind.recommend => (Icons.campaign, SoColors.mint, 'recommended your post'),
                  NotificationKind.comment => (Icons.mode_comment, SoColors.amber, 'commented'),
                  NotificationKind.tryIt => (Icons.play_arrow, SoColors.mint, 'tried your routine'),
                  NotificationKind.coach => (Icons.auto_awesome, SoColors.violet, 'Your coach checked in'),
                  NotificationKind.video => (Icons.movie, SoColors.coral, n.preview.isEmpty ? 'Your video is live' : n.preview),
                  NotificationKind.moderation => (Icons.shield, SoColors.amber, n.preview.isEmpty ? 'A moderator reviewed your post' : n.preview),
                  NotificationKind.creator => (Icons.verified, SoColors.mint, n.preview.isEmpty ? 'Creator application update' : n.preview),
                  NotificationKind.league => (Icons.emoji_events, SoColors.amber, n.preview.isEmpty ? 'League results are in' : n.preview),
                  NotificationKind.badge => (Icons.military_tech, SoColors.coral, n.preview.isEmpty ? 'You earned a badge' : n.preview),
                };
                return ListTile(
                  tileColor: n.read ? null : SoColors.coral.withValues(alpha: 0.06),
                  leading: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Avatar(actor?.emoji ?? '✨', size: 40),
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: SoColors.ink, width: 2)),
                          child: Icon(icon, size: 10, color: SoColors.ink),
                        ),
                      ),
                    ],
                  ),
                  title: RichText(
                    text: TextSpan(
                      style: t.bodyMedium,
                      children: [
                        if (actor != null) TextSpan(text: '${actor.name} ', style: const TextStyle(fontWeight: FontWeight.w700)),
                        TextSpan(text: verb),
                      ],
                    ),
                  ),
                  subtitle: Text(
                    [if (n.preview.isNotEmpty) n.preview, timeAgo(n.createdAt)].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    if (n.routineId != null) {
                      final r = ref.read(routinesProvider.notifier).byId(n.routineId!);
                      if (r != null) context.push('/workout/${r.id}', extra: r);
                      return;
                    }
                    if (n.kind == NotificationKind.follow && n.actorId != null) {
                      ref.read(socialProvider.notifier).toggleFollow(n.actorId!);
                      toast(context, social.following.contains(n.actorId) ? 'Unfollowed' : 'Followed back');
                    }
                  },
                );
              },
            ),
    );
  }
}
