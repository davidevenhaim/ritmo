import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/video_service.dart';
import 'video_card.dart';

/// The video part of the share sheet (v0.3): pick a clip from the camera
/// roll, check the 60-second cap, tag the exercises shown, then upload with
/// progress. The parent publishes the post once [onUploaded] fires.
class VideoComposer extends ConsumerStatefulWidget {
  const VideoComposer({super.key, required this.onChanged});

  /// Called whenever the picked clip or tags change; null clip = nothing picked.
  final void Function(PickedClip? clip, List<String> exerciseIds) onChanged;

  @override
  ConsumerState<VideoComposer> createState() => VideoComposerState();
}

class VideoComposerState extends ConsumerState<VideoComposer> {
  PickedClip? _clip;
  final List<String> _tags = [];
  String? _error;
  bool _picking = false;

  PickedClip? get clip => _clip;
  List<String> get exerciseIds => List.unmodifiable(_tags);

  Future<void> _pick() async {
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final c = await pickClip();
      if (c != null) _clip = c;
    } on ClipTooLong catch (e) {
      _error = e.toString();
    } catch (e) {
      _error = 'Could not open that file: $e';
    } finally {
      if (mounted) setState(() => _picking = false);
    }
    widget.onChanged(_clip, _tags);
  }

  void _addTag(String id) {
    if (_tags.contains(id) || _tags.length >= 8) return;
    setState(() => _tags.add(id));
    widget.onChanged(_clip, _tags);
  }

  void _removeTag(String id) {
    setState(() => _tags.remove(id));
    widget.onChanged(_clip, _tags);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final canUpload = ref.watch(canUploadProvider);
    if (!canUpload) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: SoColors.surface2, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            const Icon(Icons.verified_outlined, color: SoColors.mint),
            const SizedBox(width: 10),
            Expanded(child: Text('Video uploads are open to creators first. Apply in Creator studio; it takes a minute.', style: t.bodySmall)),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                context.push('/studio');
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_clip == null)
          OutlinedButton.icon(
            onPressed: _picking ? null : _pick,
            icon: _picking ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.video_library_outlined),
            label: Text(_picking ? 'Reading clip…' : 'Choose a clip (up to ${Video.maxSeconds}s)'),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: SoColors.surface2, borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                const Icon(Icons.movie_outlined, color: SoColors.coral),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_clip!.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        '${_clip!.seconds == 0 ? 'length unknown' : '${_clip!.seconds.toStringAsFixed(0)}s'} · ${(_clip!.bytes.length / 1048576).toStringAsFixed(1)} MB',
                        style: t.bodySmall,
                      ),
                    ],
                  ),
                ),
                TextButton(onPressed: _pick, child: const Text('Change')),
              ],
            ),
          ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, style: const TextStyle(color: SoColors.coral, fontSize: 12.5))),
        const SizedBox(height: 10),
        Text('EXERCISES IN THIS CLIP', style: t.labelSmall),
        const SizedBox(height: 6),
        if (_tags.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 6), child: ExerciseTags(ids: _tags, onRemove: _removeTag)),
        ExerciseTagPicker(onPick: _addTag, exclude: _tags),
      ],
    );
  }
}

/// Type-ahead over the bundled catalogue.
class ExerciseTagPicker extends ConsumerStatefulWidget {
  const ExerciseTagPicker({super.key, required this.onPick, this.exclude = const []});
  final void Function(String id) onPick;
  final List<String> exclude;
  @override
  ConsumerState<ExerciseTagPicker> createState() => _ExerciseTagPickerState();
}

class _ExerciseTagPickerState extends ConsumerState<ExerciseTagPicker> {
  final _q = TextEditingController();
  List<Exercise> _hits = const [];

  void _search(String q) {
    final repo = ref.read(exerciseRepoProvider).value;
    if (repo == null || q.trim().length < 2) {
      setState(() => _hits = const []);
      return;
    }
    setState(() => _hits = repo.search(query: q, limit: 6).where((e) => !widget.exclude.contains(e.id)).toList());
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _q,
            onChanged: _search,
            decoration: const InputDecoration(hintText: 'Search the catalogue, e.g. kettlebell swing', prefixIcon: Icon(Icons.search), isDense: true),
          ),
          for (final e in _hits)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: ExerciseThumb(e, size: 36, radius: 8, animate: false),
              title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${e.primary.join(', ')} · ${e.equipment}', style: Theme.of(context).textTheme.bodySmall),
              trailing: const Icon(Icons.add, color: SoColors.mint, size: 18),
              onTap: () {
                widget.onPick(e.id);
                _q.clear();
                setState(() => _hits = const []);
              },
            ),
        ],
      );
}

/// Upload progress shown in place of the Post button.
class UploadProgress extends StatelessWidget {
  const UploadProgress({super.key, required this.value});
  final double value;
  @override
  Widget build(BuildContext context) => Column(
        children: [
          LinearProgressIndicator(value: value, minHeight: 6, borderRadius: BorderRadius.circular(3), backgroundColor: SoColors.line),
          const SizedBox(height: 6),
          Text(value < 1 ? 'Uploading ${(value * 100).round()}%' : 'Uploaded. Transcoding starts now.', style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

/// Kind label reused by the share sheet chips.
String composeKindLabel(PostKind k) => switch (k) {
      PostKind.workout => 'Workout',
      PostKind.routine => 'Routine',
      PostKind.diet => 'Diet tip',
      PostKind.weird => 'Weird',
      PostKind.steps => 'Steps',
      PostKind.video => 'Video',
    };

String toastFor(PostKind k) => k == PostKind.video ? 'Posted. Your clip is transcoding.' : 'Shared to the feed';
