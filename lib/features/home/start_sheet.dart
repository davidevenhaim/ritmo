import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/nocturne.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/session_theme.dart';
import '../../core/social_repository.dart';
import '../build/build_screen.dart';

/// Start a workout (Nocturne handoff, section 2).
///
/// The handoff opens this from a raised middle tab; this app has no such tab,
/// so it is what the + button opens. Sections are in the handoff's order:
/// resume, your routines, recommended, shared by friends, create new.
Future<void> showStartSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Noc.sheet,
      barrierColor: Noc.scrim,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Noc.rSheet), bottom: Radius.circular(48)),
      ),
      builder: (_) => const _StartSheet(),
    );

class _StartSheet extends ConsumerWidget {
  const _StartSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(profileProvider)!;
    final mine = ref.watch(routinesProvider);
    final social = ref.watch(socialProvider);
    final schedule = ref.watch(upcomingWorkoutsProvider);

    // Resume: the nearest scheduled session that is due and not done.
    final resume = schedule.where((s) => s.at.isBefore(DateTime.now().add(const Duration(hours: 12)))).firstOrNull;

    final ready = SeedData.readyMade.where((r) => mine.every((m) => m.name != r.name)).toList();
    final shared = [
      for (final p in social.posts)
        if (p.routine != null && p.authorId != me.id) (p.routine!, social.users[p.authorId]),
    ];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      maxChildSize: 0.86,
      builder: (context, scroll) => NocIn(
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 36),
          children: [
            Center(
              child: Container(width: 38, height: 4, decoration: BoxDecoration(color: Noc.line, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: Text('Start a workout', style: Noc.pageTitle.copyWith(fontSize: 20))),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                behavior: HitTestBehavior.opaque,
                child: const SizedBox(width: 28, height: 28, child: Icon(Nx.x, size: 17, color: Noc.dim)),
              ),
            ]),
            if (resume != null) ...[
              const SizedBox(height: 14),
              _ResumeCard(session: resume),
            ],
            const SizedBox(height: 18),
            const _BuildRoutineCard(),
            const SizedBox(height: 18),
            const _SuggestionCard(),
            const SizedBox(height: 18),
            _SectionHead(
              label: 'YOUR ROUTINES',
              onAdd: () {
                Navigator.pop(context);
                context.push('/build');
              },
            ),
            if (mine.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Nothing built yet. Create one below.', style: Noc.metaDim),
              )
            else
              for (final r in mine) _RoutineRow(routine: r, theme: _themeOf(r)),
            const SizedBox(height: 18),
            _SectionHead(label: 'BECAUSE YOU TRAIN ${todayLabel()}'),
            for (final r in ready.take(3)) _RoutineRow(routine: r, showTag: false),
            if (shared.isNotEmpty) ...[
              const SizedBox(height: 18),
              const _SectionHead(label: 'SHARED BY FRIENDS'),
              for (final (r, author) in shared.take(3)) _SharedRow(routine: r, author: author),
            ],
          ],
        ),
      ),
    );
  }

  static SessionTheme? _themeOf(Routine r) {
    for (final t in SessionTheme.values) {
      if (r.tags.any((tag) => tag.toLowerCase() == t.name.toLowerCase())) return t;
    }
    return null;
  }

  /// "Because you train pulling on Fridays" in the handoff. Ours names the
  /// day the session is being started on.
  static String todayLabel() {
    const names = ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY'];
    return 'ON ${names[DateTime.now().weekday - 1]}S';
  }
}

// ========================================================= build your own
/// Building a routine by hand is the first thing offered, above the session
/// the app picked: somebody who came here to build already knows what they
/// want, and should not have to scroll past a suggestion to get to it.
class _BuildRoutineCard extends StatelessWidget {
  const _BuildRoutineCard();

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Navigator.pop(context);
          context.push('/build');
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Noc.rRow),
            border: Border.all(color: Noc.accent700),
          ),
          child: Row(children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Noc.accent900, borderRadius: BorderRadius.circular(Noc.rIcon)),
              child: const Icon(Nx.plus, size: 16, color: Noc.accent300),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Build your routine', style: TextStyle(fontFamily: 'Inter', fontSize: 13.5, fontVariations: Noc.w500, color: Noc.accent200)),
                  Text('Pick a theme, build it on the timeline, or let AI draft it', style: Noc.small, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const Icon(Nx.caretRight, size: 15, color: Noc.accent400),
          ]),
        ),
      );
}

// ============================================================== suggestion
/// The session the Start button picks for this athlete. Everything on the
/// card is derived from the profile — goal, gear, experience, age and body
/// stats — and from what they trained in the last two days; the chips say so
/// out loud, because a recommendation nobody can interrogate is a horoscope.
class _SuggestionCard extends ConsumerWidget {
  const _SuggestionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(profileProvider)!;
    final s = ref.watch(suggestionProvider);
    final loading = ref.watch(exerciseRepoProvider).isLoading;

    if (s == null) {
      return NocCard(
        child: Row(children: [
          Icon(loading ? Nx.sparkle : Nx.barbell, size: 17, color: Noc.dim),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              loading ? 'Reading the catalogue…' : 'Add some equipment in your profile and a session shows up here.',
              style: Noc.bodyMuted,
            ),
          ),
        ]),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: Text('PICKED FOR YOU', style: Noc.kickerAccent)),
          NocIconButton(
            icon: Nx.arrowCounterClockwise,
            size: 28,
            tooltip: 'Another session',
            onTap: () => ref.read(suggestionNudgeProvider.notifier).shuffle(),
          ),
        ]),
        const SizedBox(height: 8),
        NocCard(
          border: Border.all(color: Noc.accent700),
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(s.name, style: Noc.cardTitle, maxLines: 1, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                NocTag('${s.minutes} min'),
              ]),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final r in s.reasons) NocTag(r, style: NocTagStyle.outline, fontSize: 9.5)],
              ),
              const SizedBox(height: 11),
              for (final (i, e) in s.exercises.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/exercise/${e.id}', extra: e);
                    },
                    child: Row(children: [
                      ExerciseMedia(exercise: e, height: 30, radius: 8, dot: false),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(e.name, style: Noc.rowTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        s.items[i].notes.startsWith('Hold ')
                            ? '${s.items[i].sets} × ${s.theme.reps}s'
                            : '${s.items[i].sets} × ${s.items[i].reps}',
                        style: Noc.meta,
                      ),
                    ]),
                  ),
                ),
              const SizedBox(height: 3),
              Row(children: [
                Expanded(
                  child: NocButton(
                    label: 'Start',
                    icon: Nx.play,
                    block: true,
                    onTap: () {
                      final r = s.toRoutine(me);
                      Navigator.pop(context);
                      context.push('/workout/${r.id}', extra: r);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                // What the app suggests is looked at before it is taken on,
                // like everything else that arrives from somebody else — and
                // the preview is where it is saved (Accept) as well (v0.12).
                Expanded(
                  child: NocButton(
                    label: 'See routine',
                    primary: false,
                    block: true,
                    onTap: () {
                      final r = s.toRoutine(me);
                      Navigator.pop(context);
                      context.push('/routine/${r.id}', extra: r);
                    },
                  ),
                ),
              ]),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionHead extends StatelessWidget {
  const _SectionHead({required this.label, this.onAdd});
  final String label;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Expanded(child: Text(label, style: Noc.kicker)),
          if (onAdd != null) NocIconButton(icon: Nx.plus, size: 28, outlined: true, onTap: onAdd),
        ]),
      );
}

class _ResumeCard extends ConsumerWidget {
  const _ResumeCard({required this.session});
  final ScheduledWorkout session;

  @override
  Widget build(BuildContext context, WidgetRef ref) => NocCard(
        border: Border.all(color: Noc.accent700),
        color: Noc.accent900,
        onTap: () {
          Navigator.pop(context);
          context.push('/workout/${session.routineId}?day=${session.dayIndex}');
        },
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(color: Noc.accent, shape: BoxShape.circle),
            child: const Icon(Nx.play, size: 17, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('RESUME', style: Noc.kickerAccent),
                const SizedBox(height: 2),
                Text(session.routineName, style: Noc.cardTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(session.dayTitle.isEmpty ? 'Scheduled today' : session.dayTitle, style: Noc.small),
              ],
            ),
          ),
        ]),
      );
}

class _RoutineRow extends ConsumerWidget {
  const _RoutineRow({required this.routine, this.theme, this.showTag = true});
  final Routine routine;
  final SessionTheme? theme;
  final bool showTag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(exerciseRepoProvider).value;
    final first = routine.days.isEmpty || routine.days.first.items.isEmpty
        ? null
        : repo?.byId(routine.days.first.items.first.exerciseId);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: NocCard(
        radius: Noc.rRow,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        onTap: () {
          Navigator.pop(context);
          context.push('/workout/${routine.id}', extra: routine);
        },
        child: Row(children: [
          if (first != null)
            ExerciseMedia(exercise: first, height: 34, radius: 9, dot: false)
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: const SizedBox(width: 34, height: 34, child: NocStripes(dark: true)),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  routine.name,
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 13.5, fontWeight: FontWeight.w500, fontVariations: Noc.w500, color: Noc.text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text('${routine.exerciseCount} exercises · ${routine.days.length} day${routine.days.length == 1 ? '' : 's'}', style: Noc.small),
              ],
            ),
          ),
          if (showTag && theme != null) ...[NocTag(theme!.name), const SizedBox(width: 8)],
          const Icon(Nx.play, size: 15, color: Noc.dim),
        ]),
      ),
    );
  }
}

class _SharedRow extends ConsumerWidget {
  const _SharedRow({required this.routine, this.author});
  final Routine routine;
  final SocialUser? author;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: NocCard(
          radius: Noc.rRow,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          onTap: () async {
            final me = ref.read(profileProvider)!;
            final copy = await ref.read(routinesProvider.notifier).clone(routine, me);
            if (!context.mounted) return;
            Navigator.pop(context);
            nocToast(context, 'Copied to your routines.');
            context.push('/workout/${copy.id}', extra: copy);
          },
          child: Row(children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: Noc.line, shape: BoxShape.circle),
              child: Text(
                (author?.name ?? '?').characters.first.toUpperCase(),
                style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600, fontVariations: Noc.w600, color: Noc.neutral300),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    routine.name,
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 13.5, fontWeight: FontWeight.w500, fontVariations: Noc.w500, color: Noc.text),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text('${author?.name ?? routine.authorName} · ${routine.exerciseCount} exercises', style: Noc.small, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const Icon(Nx.play, size: 15, color: Noc.dim),
          ]),
        ),
      );
}
