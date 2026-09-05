import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../feed/feed_screen.dart';
import '../feed/report_sheet.dart';
import '../video/video_card.dart';

/// Public profile of any member (v0.3): header, follow, and everything they
/// posted with videos first. Reached by tapping a name anywhere.
class CreatorProfileScreen extends ConsumerStatefulWidget {
  const CreatorProfileScreen({super.key, required this.userId});
  final String userId;

  @override
  ConsumerState<CreatorProfileScreen> createState() => _CreatorProfileScreenState();
}

class _CreatorProfileScreenState extends ConsumerState<CreatorProfileScreen> {
  late Future<List<Post>> _posts;
  bool _videosFirst = true;

  @override
  void initState() {
    super.initState();
    _posts = ref.read(socialProvider.notifier).postsBy(widget.userId);
    Future.microtask(() => ref.read(socialProvider.notifier).loadUser(widget.userId));
  }

  @override
  Widget build(BuildContext context) {
    final social = ref.watch(socialProvider);
    final me = ref.watch(profileProvider)!;
    final user = ref.read(socialProvider.notifier).userOf(widget.userId);
    final isMe = widget.userId == me.id;
    final following = social.following.contains(widget.userId);
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('@${user.handle}'),
        actions: [
          if (!isMe)
            PopupMenuButton<String>(
              color: SoColors.surface2,
              onSelected: (_) => ReportSheet.show(context, target: ReportTarget.profile, targetId: widget.userId, title: '@${user.handle}'),
              itemBuilder: (_) => const [PopupMenuItem(value: 'report', child: Text('Report member'))],
            ),
        ],
      ),
      body: FutureBuilder<List<Post>>(
        future: _posts,
        builder: (context, snap) {
          final posts = [...(snap.data ?? const <Post>[])];
          if (_videosFirst) posts.sort((a, b) => (b.hasVideo ? 1 : 0) - (a.hasVideo ? 1 : 0));
          final videoCount = posts.where((p) => p.hasVideo).length;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              Row(
                children: [
                  Avatar(user.emoji, size: 72, ring: user.creator),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [Flexible(child: Text(user.name, style: t.headlineMedium, overflow: TextOverflow.ellipsis)), if (user.creator) const CreatorBadge(size: 20)]),
                        Text('${user.goal.emoji} ${user.goal.label}', style: t.bodySmall),
                        if (user.bio.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(user.bio, style: t.bodyMedium)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _Count(label: 'Followers', value: compact(isMe ? social.users.length : user.followers + (following ? 1 : 0))),
                  _Count(label: 'Posts', value: '${posts.length}'),
                  _Count(label: 'Videos', value: '$videoCount'),
                ],
              ),
              const SizedBox(height: 14),
              if (isMe)
                OutlinedButton.icon(onPressed: () => context.push('/studio'), icon: const Icon(Icons.insights_outlined), label: const Text('Creator studio'))
              else
                SizedBox(
                  width: double.infinity,
                  child: following
                      ? OutlinedButton(onPressed: () => ref.read(socialProvider.notifier).toggleFollow(widget.userId), child: const Text('Following'))
                      : FilledButton(onPressed: () => ref.read(socialProvider.notifier).toggleFollow(widget.userId), child: const Text('Follow')),
                ),
              if (user.diet.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(spacing: 6, runSpacing: 6, children: [for (final d in user.diet) TagChip(d, color: SoColors.mint)]),
              ],
              const SizedBox(height: 8),
              SectionTitle(
                'Posts',
                action: _videosFirst ? 'Newest first' : 'Videos first',
                onAction: () => setState(() => _videosFirst = !_videosFirst),
              ),
              if (snap.connectionState != ConnectionState.done)
                const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
              else if (snap.hasError)
                Text('Could not load posts: ${snap.error}', style: const TextStyle(color: SoColors.amber))
              else if (posts.isEmpty)
                EmptyState(emoji: '📭', title: isMe ? 'You have not posted yet' : 'Nothing posted yet', body: isMe ? 'Share a workout from the feed.' : null)
              else
                for (final p in posts) ...[PostCard(post: p), const SizedBox(height: 12)],
            ],
          );
        },
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ]),
      );
}
