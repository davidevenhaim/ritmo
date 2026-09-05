import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/models.dart';
import '../../core/providers.dart';

/// Inline clip in the feed (v0.3). Plays muted and looping on tap, shows the
/// processing / failed states of a hosted upload, and lists the exercises
/// tagged on the clip as chips that open the exercise page.
class VideoCard extends ConsumerStatefulWidget {
  const VideoCard({super.key, required this.post});
  final Post post;

  @override
  ConsumerState<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends ConsumerState<VideoCard> {
  VideoPlayerController? _c;
  bool _ready = false;
  bool _failed = false;
  String? _url;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(covariant VideoCard old) {
    super.didUpdateWidget(old);
    if (widget.post.playableUrl != _url) _attach();
  }

  void _attach() {
    final url = widget.post.playableUrl;
    _c?.dispose();
    _c = null;
    _ready = false;
    _failed = false;
    _url = url;
    if (url == null) return;
    final c = VideoPlayerController.networkUrl(Uri.parse(url));
    _c = c;
    c.initialize().then((_) async {
      await c.setLooping(true);
      await c.setVolume(0);
      if (mounted && _c == c) setState(() => _ready = true);
    }).catchError((_) {
      if (mounted && _c == c) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  void _toggle() {
    final c = _c;
    if (c == null || !_ready) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      c.play();
      ref.read(socialProvider.notifier).recordView(widget.post.id);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final video = post.video;
    final me = ref.watch(profileProvider);
    final mine = me?.id == post.authorId;
    final aspect = _ready ? _c!.value.aspectRatio : (video?.aspectRatio ?? 16 / 9).clamp(0.5, 2.0);
    final showAspect = aspect < 1 ? 0.8 : aspect; // tall clips stay scannable in the feed

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: showAspect,
            child: GestureDetector(
              onTap: _toggle,
              child: Stack(
                fit: StackFit.expand,
                alignment: Alignment.center,
                children: [
                  Container(color: SoColors.surface2),
                  if (video?.thumbnailUrl != null && !_ready)
                    Image.network(video!.thumbnailUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
                  if (_ready) FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: SizedBox(width: _c!.value.size.width, height: _c!.value.size.height, child: VideoPlayer(_c!))),
                  ..._overlay(video, mine),
                  if (video?.durationSec != null)
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: _Pill('${video!.durationSec!.round()}s'),
                    ),
                  if (video == null && post.videoUrl != null) const Positioned(left: 10, bottom: 10, child: _Pill('demo clip · muted')),
                ],
              ),
            ),
          ),
        ),
        if (video != null && video.exerciseIds.isNotEmpty) ...[
          const SizedBox(height: 8),
          ExerciseTags(ids: video.exerciseIds),
        ],
      ],
    );
  }

  List<Widget> _overlay(Video? video, bool mine) {
    if (video != null && !video.ready) {
      return switch (video.status) {
        VideoStatus.failed => [
            _Center(icon: Icons.error_outline, color: SoColors.coral, title: 'Upload failed', body: mine ? (video.error ?? 'Try a shorter or smaller clip.') : 'This clip is unavailable.'),
          ],
        VideoStatus.removed => [const _Center(icon: Icons.block, color: SoColors.muted, title: 'Removed', body: 'Taken down by moderation.')],
        _ => [
            _Center(
              icon: Icons.hourglass_top,
              color: SoColors.amber,
              title: 'Processing',
              body: mine ? 'Transcoding. This card updates by itself.' : 'Ready in a moment.',
              spinner: true,
            ),
          ],
      };
    }
    if (_failed) return [const _Center(icon: Icons.wifi_off, color: SoColors.muted, title: 'Video unavailable offline')];
    if (!_ready) return [const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)))];
    if (!_c!.value.isPlaying) {
      return [
        Center(
          child: Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(color: SoColors.coral, shape: BoxShape.circle),
            child: const Icon(Icons.play_arrow, size: 34, color: Colors.white),
          ),
        ),
      ];
    }
    return const [];
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
      );
}

class _Center extends StatelessWidget {
  const _Center({required this.icon, required this.color, required this.title, this.body, this.spinner = false});
  final IconData icon;
  final Color color;
  final String title;
  final String? body;
  final bool spinner;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (spinner) SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5, color: color)) else Icon(icon, color: color, size: 30),
              const SizedBox(height: 8),
              Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
              if (body != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(body!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall)),
            ],
          ),
        ),
      );
}

/// Chips for the exercises tagged on a clip. Unknown ids (wger, typos) are
/// shown as-is without a link.
class ExerciseTags extends ConsumerWidget {
  const ExerciseTags({super.key, required this.ids, this.onRemove});
  final List<String> ids;
  final void Function(String id)? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(exerciseRepoProvider).value;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final id in ids)
          () {
            final ex = repo?.byId(id);
            final label = ex?.name ?? id.replaceAll('_', ' ');
            return InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onRemove != null ? () => onRemove!(id) : (ex == null ? null : () => context.push('/exercise/$id', extra: ex)),
              child: Container(
                padding: const EdgeInsets.fromLTRB(9, 4, 9, 4),
                decoration: BoxDecoration(color: SoColors.violet.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(999)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.fitness_center, size: 12, color: SoColors.violet),
                    const SizedBox(width: 4),
                    Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: SoColors.violet)),
                    if (onRemove != null) ...[const SizedBox(width: 4), const Icon(Icons.close, size: 12, color: SoColors.violet)],
                  ],
                ),
              ),
            );
          }(),
      ],
    );
  }
}

/// Small verified-creator mark shown after a name.
class CreatorBadge extends StatelessWidget {
  const CreatorBadge({super.key, this.size = 15});
  final double size;
  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Verified creator',
        child: Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.verified, size: size, color: SoColors.mint)),
      );
}

String kindLabel(PostKind k) => switch (k) {
      PostKind.workout => 'Workout',
      PostKind.routine => 'Routine',
      PostKind.steps => 'Steps',
      PostKind.video => 'Video',
      PostKind.diet => 'Diet',
      PostKind.weird => 'Weird',
    };

/// Shortened member id for placeholders.
String shortId(String id) => id.length > 8 ? id.substring(0, 8) : id;

/// Reused in profile headers: "12.4k followers".
String followersLabel(int n) => '${compact(n)} follower${n == 1 ? '' : 's'}';
