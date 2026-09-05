import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/nocturne.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/session_theme.dart';

/// Build, step 1 of 3 — pick a theme (Nocturne handoff, section 3).
///
/// Every count is the real number of exercises the theme matches in the
/// bundled catalogue, and the hero art is a real exercise image rather than
/// the handoff's striped placeholder.
class BuildScreen extends ConsumerWidget {
  const BuildScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(exerciseRepoProvider);

    return Scaffold(
      backgroundColor: Noc.bg,
      body: SafeArea(
        bottom: false,
        child: NocIn(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Noc.gutter, 8, Noc.gutter, 32),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Build is opened from Start, so it carries its own way back.
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: NocIconButton(
                        icon: Nx.arrowLeft,
                        tooltip: 'Back',
                        onTap: () => context.canPop() ? context.pop() : context.go('/home'),
                      ),
                    ),
                    Text('STEP 1 OF 3', style: Noc.kicker),
                    const SizedBox(height: 4),
                    Text('Pick a theme', style: Noc.screenTitle),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: 260,
                      child: Text(
                        repo.hasValue
                            ? '${repo.value!.all.length} exercises, grouped. Every theme carries its own library, cues and progressions.'
                            : 'Loading the catalogue…',
                        style: const TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: Noc.dim, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.35,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                children: [
                  for (final t in SessionTheme.values)
                    _ThemeCard(
                      theme: t,
                      count: repo.value?.countFor(t),
                      hero: repo.value?.forTheme(t).where((e) => e.images.isNotEmpty).firstOrNull,
                    ),
                  // Breathing sits with the themes because it is a session
                  // too: the app is not only the gym (v0.12).
                  const _BreatheCard(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({required this.theme, this.count, this.hero});
  final SessionTheme theme;
  final int? count;
  final Exercise? hero;

  @override
  Widget build(BuildContext context) => NocCard(
        padding: EdgeInsets.zero,
        onTap: () => context.push('/build/${theme.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(Noc.rCard - 1)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const NocStripes(bloom: true),
                    if (hero?.imageUrl(0) case final url?)
                      Image.network(
                        url,
                        fit: BoxFit.cover,
                        // Stripes stay visible until the frame arrives, so the
                        // card never flashes empty.
                        frameBuilder: (_, child, frame, _) => AnimatedOpacity(
                          opacity: frame == null ? 0 : 1,
                          duration: const Duration(milliseconds: 200),
                          child: child,
                        ),
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Noc.surface, Noc.surface.withValues(alpha: 0)],
                          stops: const [0.0, 0.45],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 10, 11, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    theme.name,
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 14.5, fontWeight: FontWeight.w500, fontVariations: Noc.w500, color: Noc.text),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(count == null ? '…' : '$count exercises', style: Noc.small),
                  const SizedBox(height: 1),
                  Text(theme.hint, style: Noc.small.copyWith(color: Noc.accent700), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      );
}

/// Breathing, shaped like a theme card. It opens the patterns rather than the
/// library, because there is nothing to pick sets and reps for.
class _BreatheCard extends StatelessWidget {
  const _BreatheCard();

  @override
  Widget build(BuildContext context) => NocCard(
        padding: EdgeInsets.zero,
        border: Border.all(color: Noc.accent700),
        onTap: () => context.push('/breathe'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(Noc.rCard - 1)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const NocStripes(bloom: true),
                    Center(
                      child: Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: Noc.accent900, shape: BoxShape.circle, border: Border.all(color: Noc.accent700)),
                        child: const Icon(Nx.heartbeat, size: 20, color: Noc.accent300),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Noc.surface, Noc.surface.withValues(alpha: 0)],
                          stops: const [0.0, 0.45],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 10, 11, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Breathing',
                    style: TextStyle(fontFamily: 'Inter', fontSize: 14.5, fontWeight: FontWeight.w500, fontVariations: Noc.w500, color: Noc.text),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text('${breathingPatterns.length} patterns', style: Noc.small),
                  const SizedBox(height: 1),
                  Text('Box · 4-7-8 · coherent', style: Noc.small.copyWith(color: Noc.accent700), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      );
}

/// The exercise media frame used across the builder: real image where we have
/// one, the handoff's striped placeholder where we do not.
class ExerciseMedia extends StatelessWidget {
  const ExerciseMedia({super.key, required this.exercise, this.height = 74, this.radius = 9, this.chip = false, this.dot = true, this.fill = false});
  final Exercise exercise;

  /// Fixed frame height; ignored when [fill] lets the media take the space
  /// its parent leaves.
  final double height;

  /// Expand into the parent instead of using [height].
  final bool fill;
  final double radius;
  final bool chip;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final url = exercise.imageUrl(0);
    final stack = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        height: fill ? null : height,
        // Small tiles are square thumbnails sitting in a row; anything taller
        // is the card media and takes the width it is given.
        width: fill || height > 48 ? double.infinity : height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            NocStripes(dark: height <= 40),
            if (url != null)
              Image.network(
                url,
                fit: BoxFit.cover,
                frameBuilder: (_, child, frame, _) => AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  child: child,
                ),
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            if (chip && exercise.images.length > 1)
              Positioned(
                left: 7,
                top: 7,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(color: Noc.bg.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(5)),
                  child: const Text('GIF', style: TextStyle(fontFamily: 'Inter', fontSize: 8.5, letterSpacing: 0.85, color: Noc.muted)),
                ),
              ),
            if (dot && url != null)
              Positioned(
                right: height <= 40 ? 3 : 7,
                bottom: height <= 40 ? 3 : 7,
                child: NocPulse(
                  period: const Duration(milliseconds: 1600),
                  child: Container(
                    width: height <= 40 ? 5 : 6,
                    height: height <= 40 ? 5 : 6,
                    decoration: const BoxDecoration(color: Noc.accent, shape: BoxShape.circle),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return fill ? Expanded(child: stack) : stack;
  }
}
