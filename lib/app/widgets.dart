import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/models.dart';
import 'theme.dart';

/// Emoji avatar, or the user's photo when [photo] (base64 JPEG) is set.
class Avatar extends StatelessWidget {
  const Avatar(this.emoji, {super.key, this.size = 40, this.ring = false, this.photo});
  final String emoji;
  final double size;
  final bool ring;
  final String? photo;

  static final _cache = <String, Uint8List>{};
  static Uint8List? decode(String? b64) {
    if (b64 == null || b64.isEmpty) return null;
    return _cache.putIfAbsent(b64.length.toString() + b64.substring(0, 24), () => base64Decode(b64));
  }

  @override
  Widget build(BuildContext context) {
    final bytes = decode(photo);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: SoColors.surface2,
        shape: BoxShape.circle,
        border: ring ? Border.all(color: SoColors.coral, width: 2) : Border.all(color: SoColors.line),
      ),
      child: bytes == null
          ? Text(emoji, style: TextStyle(fontSize: size * 0.48))
          : Image.memory(bytes, width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true),
    );
  }
}

class TagChip extends StatelessWidget {
  const TagChip(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? SoColors.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c)),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 0, 8),
        child: Row(
          children: [
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
            if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
          ],
        ),
      );
}

/// Thumbnail that flips between the two dataset frames so the exercise "moves".
class ExerciseThumb extends StatefulWidget {
  const ExerciseThumb(this.exercise, {super.key, this.size = 64, this.radius = 12, this.animate = true});
  final Exercise exercise;
  final double size;
  final double radius;
  final bool animate;

  @override
  State<ExerciseThumb> createState() => _ExerciseThumbState();
}

class _ExerciseThumbState extends State<ExerciseThumb> {
  int _frame = 0;

  @override
  Widget build(BuildContext context) {
    final url = widget.exercise.imageUrl(_frame);
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: Container(
        width: widget.size,
        height: widget.size,
        color: Colors.white,
        child: url == null
            ? const Center(child: Icon(Icons.fitness_center, color: SoColors.muted))
            : GestureDetector(
                onTap: widget.animate && widget.exercise.images.length > 1
                    ? () => setState(() => _frame = (_frame + 1) % widget.exercise.images.length)
                    : null,
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const Center(child: Icon(Icons.image_not_supported_outlined, color: SoColors.muted)),
                  loadingBuilder: (c, child, p) => p == null ? child : const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                ),
              ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.emoji, required this.title, this.body, this.action});
  final String emoji;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 44)),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
              if (body != null) ...[
                const SizedBox(height: 6),
                Text(body!, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
              ],
              if (action != null) ...[const SizedBox(height: 16), action!],
            ],
          ),
        ),
      );
}

String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'now';
  if (d.inHours < 1) return '${d.inMinutes}m';
  if (d.inDays < 1) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  return '${(d.inDays / 7).floor()}w';
}

String compact(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}k';
  return '$n';
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}
