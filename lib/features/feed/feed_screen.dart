import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/social_backend.dart';
import '../../core/video_service.dart';
import '../video/video_card.dart';
import '../video/video_compose.dart';
import 'comments_sheet.dart';
import 'report_sheet.dart';

/// Discover (v0.6): everything from everyone. Reached from the Friends tab,
/// not a tab of its own — the app is about you and the people you follow.
enum _Filter { all, hot, videos, weird, routines, diet, steps, following }

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});
  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final social = ref.watch(socialProvider);
    final profile = ref.watch(profileProvider)!;
    final steps = ref.watch(stepsProvider).value;
    final today = steps == null || steps.isEmpty ? null : steps.last.steps;

    final posts = social.posts.where((p) => switch (_filter) {
          _Filter.all => true,
          _Filter.hot => p.hot || p.kind == PostKind.video,
          _Filter.videos => p.hasVideo,
          _Filter.weird => p.kind == PostKind.weird,
          _Filter.routines => p.routine != null,
          _Filter.diet => p.kind == PostKind.diet,
          _Filter.steps => p.kind == PostKind.steps,
          _Filter.following => social.following.contains(p.authorId) || p.authorId == profile.id,
        }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.local_fire_department, color: SoColors.coral),
            SizedBox(width: 6),
            Text('Ritmo'),
          ],
        ),
        actions: [
          _StepsPill(steps: today, goal: profile.stepGoal, onTap: () => context.push('/steps')),
          _Bell(unread: social.unread, onTap: () => context.push('/notifications')),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _compose(context),
        backgroundColor: SoColors.coral,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Share'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final f in _Filter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(switch (f) {
                        _Filter.all => 'For you',
                        _Filter.hot => '🔥 Hot',
                        _Filter.videos => '🎬 Videos',
                        _Filter.weird => '🤪 Weird',
                        _Filter.routines => 'Routines',
                        _Filter.diet => 'Diet',
                        _Filter.steps => 'Steps',
                        _Filter.following => 'Following',
                      }),
                      selected: f == _filter,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (social.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(social.error!, style: const TextStyle(color: SoColors.amber)),
            ),
          if (social.loading && posts.isEmpty)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
          else if (posts.isEmpty)
            const EmptyState(emoji: '🫥', title: 'Nothing here yet', body: 'Follow a few people or share your first workout.')
          else
            for (final p in posts) ...[
              PostCard(post: p),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }

  Future<void> _compose(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const ComposeSheet(),
    );
  }
}

class _StepsPill extends StatelessWidget {
  const _StepsPill({required this.steps, required this.goal, required this.onTap});
  final int? steps;
  final int goal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pct = steps == null ? 0.0 : (steps! / goal).clamp(0.0, 1.0);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
        decoration: BoxDecoration(color: SoColors.surface2, borderRadius: BorderRadius.circular(999)),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              height: 26,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(value: pct, strokeWidth: 3, color: SoColors.mint, backgroundColor: SoColors.line),
                  const Icon(Icons.directions_walk, size: 13, color: SoColors.mint),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(steps == null ? 'Connect' : compact(steps!), style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
          ],
        ),
      ),
    );
  }
}

class _Bell extends StatelessWidget {
  const _Bell({required this.unread, required this.onTap});
  final int unread;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: onTap,
        tooltip: 'Activity',
        icon: Badge(
          isLabelVisible: unread > 0,
          label: Text('$unread'),
          backgroundColor: SoColors.coral,
          child: const Icon(Icons.notifications_outlined),
        ),
      );
}

class PostCard extends ConsumerWidget {
  const PostCard({super.key, required this.post});
  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(profileProvider)!;
    final social = ref.watch(socialProvider);
    final author = ref.read(socialProvider.notifier).userOf(post.authorId);
    final isMe = post.authorId == me.id;
    final following = social.following.contains(post.authorId);
    final liked = social.liked.contains(post.id);
    final recommended = social.recommended.contains(post.id);
    final t = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                InkWell(
                  onTap: () => context.push('/u/${post.authorId}'),
                  borderRadius: BorderRadius.circular(999),
                  child: Avatar(author.emoji, size: 38, ring: author.creator),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: () => context.push('/u/${post.authorId}'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [Flexible(child: Text(author.name, style: t.titleMedium, overflow: TextOverflow.ellipsis)), if (author.creator) const CreatorBadge()]),
                        Text('@${author.handle} · ${timeAgo(post.createdAt)}', style: t.bodySmall),
                      ],
                    ),
                  ),
                ),
                if (post.hidden) const TagChip('HIDDEN', color: SoColors.amber) else if (post.hot) const TagChip('HOT', color: SoColors.coral),
                if (!isMe) ...[
                  const SizedBox(width: 6),
                  SizedBox(
                    height: 32,
                    child: following
                        ? OutlinedButton(
                            onPressed: () => ref.read(socialProvider.notifier).toggleFollow(post.authorId),
                            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
                            child: const Text('Following'))
                        : FilledButton(
                            onPressed: () => ref.read(socialProvider.notifier).toggleFollow(post.authorId),
                            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14), backgroundColor: SoColors.surface2),
                            child: const Text('Follow')),
                  ),
                ],
                _PostMenu(post: post, isMe: isMe),
              ],
            ),
            if (post.hidden) ...[
              const SizedBox(height: 8),
              Text('Hidden from the feed pending review. Only you can see it.', style: t.bodySmall?.copyWith(color: SoColors.amber)),
            ],
            const SizedBox(height: 12),
            Text(post.title, style: t.titleLarge?.copyWith(fontSize: 17)),
            if (post.body.isNotEmpty) ...[const SizedBox(height: 6), Text(post.body, style: t.bodyMedium)],
            if (post.hasVideo) ...[const SizedBox(height: 12), VideoCard(post: post)],
            if (post.steps != null) ...[const SizedBox(height: 12), _StepsBanner(steps: post.steps!)],
            if (post.routine != null) ...[const SizedBox(height: 12), RoutinePreview(routine: post.routine!)],
            if (post.tags.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [for (final tag in post.tags) TagChip('#$tag')]),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                _Action(
                  icon: liked ? Icons.favorite : Icons.favorite_border,
                  color: liked ? SoColors.coral : null,
                  label: compact(post.likes),
                  onTap: () => ref.read(socialProvider.notifier).toggleLike(post.id),
                ),
                _Action(icon: Icons.mode_comment_outlined, label: compact(post.comments), onTap: () => CommentsSheet.show(context, post)),
                _Action(
                  icon: recommended ? Icons.campaign : Icons.campaign_outlined,
                  color: recommended ? SoColors.mint : null,
                  label: '${compact(post.recommends)} recs',
                  onTap: () {
                    ref.read(socialProvider.notifier).recommend(post.id);
                    toast(context, 'Recommended to your followers');
                  },
                ),
                if (post.hasVideo && (post.views > 0 || isMe))
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text('${compact(post.views)} views', style: const TextStyle(color: SoColors.muted, fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                const Spacer(),
                if (post.routine != null)
                  TextButton.icon(
                    onPressed: () => context.push('/routine/${post.routine!.id}', extra: post.routine),
                    icon: const Icon(Icons.list_alt, size: 18),
                    label: const Text('See it'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap, this.color});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(children: [
            Icon(icon, size: 20, color: color ?? SoColors.muted),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(color: color ?? SoColors.muted, fontWeight: FontWeight.w600, fontSize: 13)),
          ]),
        ),
      );
}

class _StepsBanner extends StatelessWidget {
  const _StepsBanner({required this.steps});
  final int steps;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: SoColors.mintSoft, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          const Icon(Icons.directions_walk, color: SoColors.mint, size: 28),
          const SizedBox(width: 12),
          Text(steps.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},'),
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: SoColors.mint, fontFeatures: [FontFeature.tabularFigures()])),
          const SizedBox(width: 8),
          const Text('steps', style: TextStyle(color: SoColors.mint, fontWeight: FontWeight.w600)),
        ]),
      );
}

class RoutinePreview extends StatelessWidget {
  const RoutinePreview({super.key, required this.routine});
  final Routine routine;
  @override
  Widget build(BuildContext context) {
    final items = routine.days.expand((d) => d.items).take(4).toList();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: SoColors.surface2, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.list_alt, size: 18, color: SoColors.amber),
            const SizedBox(width: 6),
            Expanded(child: Text(routine.name, style: const TextStyle(fontWeight: FontWeight.w700))),
            Text('${routine.days.length}d · ${routine.exerciseCount} ex', style: Theme.of(context).textTheme.bodySmall),
          ]),
          const SizedBox(height: 8),
          for (final it in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Expanded(child: Text(it.exerciseName, maxLines: 1, overflow: TextOverflow.ellipsis)),
                Text('${it.sets}×${it.reps}', style: const TextStyle(color: SoColors.muted, fontFeatures: [FontFeature.tabularFigures()])),
              ]),
            ),
          if (routine.exerciseCount > 4) Text('+${routine.exerciseCount - 4} more', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Report, or delete your own post.
class _PostMenu extends ConsumerWidget {
  const _PostMenu({required this.post, required this.isMe});
  final Post post;
  final bool isMe;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
        color: SoColors.surface2,
        padding: EdgeInsets.zero,
        iconSize: 20,
        icon: const Icon(Icons.more_horiz, color: SoColors.muted),
        onSelected: (v) async {
          if (v == 'report') {
            await ReportSheet.show(context, target: ReportTarget.post, targetId: post.id, title: post.title);
          } else if (v == 'delete') {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Delete this post?'),
                content: Text(post.hasVideo ? 'The clip is removed from the feed too.' : 'This cannot be undone.'),
                actions: [
                  TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep')),
                  FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
                ],
              ),
            );
            if (ok == true) await ref.read(socialProvider.notifier).deletePost(post.id);
          } else if (v == 'author') {
            if (context.mounted) context.push('/u/${post.authorId}');
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'author', child: Text('View profile')),
          if (isMe) const PopupMenuItem(value: 'delete', child: Text('Delete post')) else const PopupMenuItem(value: 'report', child: Text('Report post')),
        ],
      );
}

/// Share sheet: a text post, a routine, or today's steps.
class ComposeSheet extends ConsumerStatefulWidget {
  const ComposeSheet({super.key, this.routine, this.steps, this.title});
  final Routine? routine;
  final int? steps;
  final String? title;
  @override
  ConsumerState<ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends ConsumerState<ComposeSheet> {
  Future<void> _post(UserProfile me, int? steps) async {
    if (_title.text.trim().isEmpty) return;
    Video? video;
    if (_kind == PostKind.video) {
      final clip = _clip;
      if (clip == null) return;
      setState(() {
        _uploadProgress = 0;
        _uploadError = null;
      });
      try {
        video = await ref.read(videoUploaderProvider).upload(
              clip,
              authorId: me.id,
              exerciseIds: _clipTags,
              onProgress: (p) {
                if (mounted) setState(() => _uploadProgress = p);
              },
            );
      } catch (e) {
        if (mounted) {
          setState(() {
            _uploadProgress = null;
            _uploadError = e.toString();
          });
        }
        return;
      }
    }
    final attachRoutine = _kind == PostKind.routine || _kind == PostKind.video;
    final post = Post(
      id: newUuid(),
      authorId: me.id,
      kind: _kind,
      title: _title.text.trim(),
      body: _body.text.trim(),
      createdAt: DateTime.now(),
      routine: attachRoutine ? _routine : null,
      video: video,
      steps: _attachSteps ? steps : null,
      tags: [_kind.name, if (_routine != null && attachRoutine) ...(_routine!.tags.take(2))],
    );
    await ref.read(socialProvider.notifier).publish(post);
    if (mounted) {
      Navigator.of(context).pop();
      toast(context, toastFor(_kind));
    }
  }

  late final _title = TextEditingController(text: widget.title ?? '');
  final _body = TextEditingController();
  Routine? _routine;
  bool _attachSteps = false;
  PostKind _kind = PostKind.workout;
  PickedClip? _clip;
  List<String> _clipTags = const [];
  double? _uploadProgress;
  String? _uploadError;

  @override
  void initState() {
    super.initState();
    _routine = widget.routine;
    _attachSteps = widget.steps != null;
    if (_routine != null) _kind = PostKind.routine;
    if (_attachSteps) _kind = PostKind.steps;
  }

  @override
  Widget build(BuildContext context) {
    final mine = ref.watch(routinesProvider);
    final steps = widget.steps ?? ref.watch(stepsProvider).value?.lastOrNull?.steps;
    final me = ref.watch(profileProvider)!;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Share with the gym', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final k in [PostKind.workout, PostKind.video, PostKind.routine, PostKind.diet, PostKind.weird, PostKind.steps])
                  ChoiceChip(
                    label: Text(composeKindLabel(k)),
                    selected: _kind == k,
                    onSelected: (_) => setState(() {
                      _kind = k;
                      _attachSteps = k == PostKind.steps;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(controller: _title, decoration: const InputDecoration(hintText: 'Title'), textCapitalization: TextCapitalization.sentences),
            const SizedBox(height: 8),
            TextField(controller: _body, minLines: 2, maxLines: 5, decoration: const InputDecoration(hintText: 'What happened? Be specific, people copy specifics.')),
            const SizedBox(height: 12),
            if (_kind == PostKind.video) ...[
              VideoComposer(onChanged: (clip, tags) => setState(() {
                _clip = clip;
                _clipTags = tags;
              })),
              const SizedBox(height: 12),
            ],
            if (_kind == PostKind.routine || _kind == PostKind.video || _routine != null)
              DropdownButtonFormField<String>(
                initialValue: _routine?.id,
                decoration: InputDecoration(hintText: _kind == PostKind.video ? 'Attach the routine in the clip (optional)' : 'Attach a routine'),
                dropdownColor: SoColors.surface2,
                items: [
                  if (_routine != null && !mine.any((r) => r.id == _routine!.id)) DropdownMenuItem(value: _routine!.id, child: Text(_routine!.name)),
                  for (final r in mine) DropdownMenuItem(value: r.id, child: Text(r.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (id) => setState(() => _routine = mine.where((r) => r.id == id).firstOrNull ?? _routine),
              ),
            if (_attachSteps)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: SoColors.mintSoft, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.directions_walk, color: SoColors.mint),
                  const SizedBox(width: 8),
                  Text(steps == null ? 'Connect your health app first' : '$steps steps today', style: const TextStyle(fontWeight: FontWeight.w700, color: SoColors.mint)),
                ]),
              ),
            if (_uploadError != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_uploadError!, style: const TextStyle(color: SoColors.coral, fontSize: 12.5))),
            const SizedBox(height: 16),
            if (_uploadProgress != null)
              UploadProgress(value: _uploadProgress!)
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _kind == PostKind.video && (_clip == null || !ref.watch(canUploadProvider)) ? null : () => _post(me, steps),
                  child: Text(_kind == PostKind.video ? 'Upload and post' : 'Post'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
