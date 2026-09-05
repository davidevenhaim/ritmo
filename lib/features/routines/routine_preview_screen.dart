import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/nocturne.dart';
import '../../core/exercise_repository.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/routine_insight.dart';
import '../../core/social_repository.dart';
import '../build/build_screen.dart' show ExerciseMedia;

/// Look inside a routine before you accept it (v0.10).
///
/// Everything that arrives from somebody else — a friend's share, a coach's
/// programme, an invite to train together — lands here first. The athlete sees
/// every exercise, what grade the catalogue gives it, what kit it needs and
/// whether that is where they train, and only then decides.
///
/// The second half of the screen is the answer to "this looks too hard": the
/// level switcher rebuilds the same session at another grade, swapping each
/// movement for one the catalogue grades there while keeping the author's
/// shape — same days, same order, same muscle in the same slot.
class RoutinePreviewScreen extends ConsumerStatefulWidget {
  const RoutinePreviewScreen({super.key, required this.routineId, this.routine, this.focusDay});

  final String routineId;
  final Routine? routine;

  /// The day of a multi-day routine this athlete was invited to, when they
  /// arrived here from an invite rather than from a share.
  final int? focusDay;

  @override
  ConsumerState<RoutinePreviewScreen> createState() => _RoutinePreviewScreenState();
}

class _RoutinePreviewScreenState extends ConsumerState<RoutinePreviewScreen> {
  /// Null means "as shared" — the author's own version, untouched.
  ExerciseLevel? _target;

  Routine? _resolve() {
    if (widget.routine != null) return widget.routine;
    final mine = ref.read(routinesProvider).where((r) => r.id == widget.routineId).firstOrNull;
    if (mine != null) return mine;
    for (final r in [...SeedData.readyMade, ...SeedData.coachProgrammes]) {
      if (r.id == widget.routineId) return r;
    }
    return ref
        .read(socialProvider)
        .posts
        .map((p) => p.routine)
        .whereType<Routine>()
        .where((r) => r.id == widget.routineId)
        .firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final routine = _resolve();
    final repo = ref.watch(exerciseRepoProvider);
    final me = ref.watch(profileProvider);

    if (routine == null || me == null) {
      return Scaffold(
        backgroundColor: Noc.bg,
        appBar: AppBar(backgroundColor: Noc.bg, foregroundColor: Noc.text),
        body: const Center(child: Text('That routine is no longer shared.', style: Noc.bodyMuted)),
      );
    }

    return Scaffold(
      backgroundColor: Noc.bg,
      body: SafeArea(
        bottom: false,
        child: repo.when(
          loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Noc.accent)),
          error: (e, _) => Center(child: Text('Could not read the library.\n$e', style: Noc.bodyMuted, textAlign: TextAlign.center)),
          data: (repo) => _body(context, routine, repo, me),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, Routine shared, ExerciseRepository repo, UserProfile me) {
    final insight = RoutineInsight.of(shared, repo);
    // The routine's own grade is "as shared": picking it is how you undo a
    // swap, so it never re-levels the author's own version.
    final levelled = _target == null || _target == insight.level
        ? null
        : RoutineLeveller.to(routine: shared, repo: repo, target: _target!, owned: me.equipment);
    final view = levelled?.routine ?? shared;
    final viewInsight = levelled == null ? insight : RoutineInsight.of(view, repo);
    final author = ref.watch(socialProvider).users[shared.authorId];
    final mine = ref.watch(routinesProvider).any((x) => x.name == view.name);

    return Column(
      children: [
        Expanded(
          child: NocIn(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Noc.gutter, 0, Noc.gutter, 20),
              children: [
                _header(context, shared, author, me),
                const SizedBox(height: 14),
                _AboutCard(routine: shared, author: author, insight: insight, me: me),
                const SizedBox(height: 18),
                _LevelSwitcher(
                  insight: insight,
                  me: me,
                  selected: _target ?? insight.level,
                  onPick: (l) => setState(() => _target = l),
                ),
                if (levelled != null) ...[
                  const SizedBox(height: 10),
                  _SwapSummary(levelled: levelled, minutes: viewInsight.minutes),
                ] else if (insight.level != null && insight.level != me.experience.exerciseLevel) ...[
                  const SizedBox(height: 10),
                  _LevelNudge(
                    from: insight.level!,
                    to: me.experience.exerciseLevel,
                    onTap: () => setState(() => _target = me.experience.exerciseLevel),
                  ),
                ],
                const SizedBox(height: 18),
                for (var d = 0; d < view.days.length; d++) ...[
                  if (d > 0) const SizedBox(height: 18),
                  NocSectionHead(
                    view.days[d].title,
                    note: '${viewInsight.dayMinutes[d]} min',
                  ),
                  if (view.days[d].focus.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(view.days[d].focus, style: Noc.small),
                    ),
                  if (d == widget.focusDay && view.days.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('The session you were invited to', style: Noc.small.copyWith(color: Noc.accent400)),
                    ),
                  const SizedBox(height: 10),
                  for (var i = 0; i < view.days[d].items.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ExerciseRow(
                        item: view.days[d].items[i],
                        exercise: repo.byId(view.days[d].items[i].exerciseId),
                        swap: levelled?.at(d, i),
                        owned: me.equipment,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        _ActionBar(
          label: levelled == null ? 'Accept' : 'Accept ${levelled.target.label.toLowerCase()}',
          accepted: mine,
          onStart: () => context.push('/workout/${view.id}', extra: view),
          onAccept: mine ? null : () => _accept(view),
        ),
      ],
    );
  }

  Future<void> _accept(Routine routine) async {
    final me = ref.read(profileProvider)!;
    final copy = await ref.read(routinesProvider.notifier).clone(routine, me);
    if (!mounted) return;
    nocToast(context, '${copy.name} is in your routines.');
  }

  Widget _header(BuildContext context, Routine routine, SocialUser? author, UserProfile me) {
    // What the athlete is looking at, in four words. A plan the coach wrote
    // and a session the app picked are both "yours" by author, but neither is
    // something the athlete built, and saying so is the point of this screen.
    final kicker = routine.source == 'ai'
        ? 'FROM YOUR AI COACH'
        : routine.tags.contains('suggested')
            ? 'PICKED FOR YOU'
            : routine.authorId == me.id
                ? 'YOUR ROUTINE'
                : (author?.creator ?? false)
                    ? 'COACH PROGRAMME'
                    : 'SHARED WITH YOU';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          NocIconButton(
            icon: Nx.arrowLeft,
            tooltip: 'Back',
            onTap: () => context.canPop() ? context.pop() : context.go('/home'),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(kicker, style: Noc.kicker)),
        ],
      ),
    );
  }
}

// =================================================================== about
class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.routine, required this.insight, required this.me, this.author});

  final Routine routine;
  final RoutineInsight insight;
  final UserProfile me;
  final SocialUser? author;

  @override
  Widget build(BuildContext context) {
    final missing = insight.missingEquipment(me);
    final verdict = insight.verdict(me);
    return NocCard(
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            NocFace(author?.emoji ?? '🙂', size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(author?.name ?? routine.authorName, style: Noc.cardTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (author != null)
                    Text('@${author!.handle}', style: Noc.small, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Text(routine.name, style: Noc.pageTitle),
          if (routine.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(routine.description, style: Noc.bodyMuted),
          ],
          if (routine.tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final t in routine.tags.take(4)) NocTag(t, style: NocTagStyle.neutral)],
            ),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Noc.divider), bottom: BorderSide(color: Noc.divider)),
            ),
            child: Row(children: [
              _Stat(value: '${routine.days.length}', label: routine.days.length == 1 ? 'DAY' : 'DAYS'),
              _Stat(value: '${routine.exerciseCount}', label: 'EXERCISES'),
              _Stat(value: '${insight.minutes}', label: 'MINUTES'),
              _Stat(value: insight.level?.label ?? '—', label: 'LEVEL', small: true),
            ]),
          ),
          const SizedBox(height: 12),
          _LevelBar(insight: insight),
          if (verdict != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              Icon(
                insight.level == me.experience.exerciseLevel ? Nx.check : Nx.target,
                size: 14,
                color: Noc.accent400,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '$verdict — you train ${me.experience.exerciseLevel.label.toLowerCase()}',
                  style: Noc.metaMuted,
                ),
              ),
            ]),
          ],
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Nx.barbell, size: 14, color: Noc.dim),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                insight.equipment.isEmpty ? 'No equipment needed' : 'Needs ${insight.equipment.join(' · ')}',
                style: Noc.metaMuted,
              ),
            ),
          ]),
          if (missing.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(width: 21),
              Expanded(
                child: Text(
                  'You have not said you own ${missing.join(', ')}.',
                  style: Noc.metaDim.copyWith(color: Noc.accent400),
                ),
              ),
            ]),
          ],
          if (insight.muscles.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Nx.target, size: 14, color: Noc.dim),
              const SizedBox(width: 7),
              Expanded(child: Text('Works ${insight.muscles.take(4).join(' · ')}', style: Noc.metaMuted)),
            ]),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.small = false});
  final String value;
  final String label;
  final bool small;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: small ? Noc.cardTitle : Noc.statSm,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Text(label, style: Noc.columnLabel),
          ],
        ),
      );
}

/// How the routine's exercises split across the three grades, as one bar.
class _LevelBar extends StatelessWidget {
  const _LevelBar({required this.insight});
  final RoutineInsight insight;

  static const _colors = {
    ExerciseLevel.beginner: Noc.accent800,
    ExerciseLevel.intermediate: Noc.accent,
    ExerciseLevel.advanced: Noc.accent300,
  };

  @override
  Widget build(BuildContext context) {
    if (insight.graded == 0) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 7,
            child: Row(
              children: [
                for (final l in ExerciseLevel.values)
                  if (insight.levelCounts[l]! > 0)
                    Expanded(flex: insight.levelCounts[l]!, child: Container(color: _colors[l])),
              ],
            ),
          ),
        ),
        const SizedBox(height: 7),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (final l in ExerciseLevel.values)
              if (insight.levelCounts[l]! > 0)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 6, height: 6, decoration: BoxDecoration(color: _colors[l], shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text('${insight.levelCounts[l]} ${l.label.toLowerCase()}', style: Noc.small),
                ]),
            if (insight.ungraded > 0) Text('${insight.ungraded} ungraded', style: Noc.small),
          ],
        ),
      ],
    );
  }
}

// ================================================================= levels
class _LevelSwitcher extends StatelessWidget {
  const _LevelSwitcher({required this.insight, required this.me, required this.selected, required this.onPick});

  final RoutineInsight insight;
  final UserProfile me;
  final ExerciseLevel? selected;
  final ValueChanged<ExerciseLevel?> onPick;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('SEE IT AT ANOTHER LEVEL', style: Noc.kicker),
          const SizedBox(height: 4),
          Text(
            'Same days, same order, same muscle in each slot — the movements change to ones the library grades there.',
            style: Noc.small,
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final l in ExerciseLevel.values) ...[
                  if (l != ExerciseLevel.values.first) const SizedBox(width: 8),
                  _LevelPick(
                    key: Key('level-${l.name}'),
                    label: l.label,
                    note: l == insight.level
                        ? 'as shared'
                        : l == me.experience.exerciseLevel
                            ? 'your level'
                            : null,
                    on: selected == l,
                    onTap: () => onPick(l == insight.level ? null : l),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
}

class _LevelPick extends StatelessWidget {
  const _LevelPick({super.key, required this.label, required this.on, required this.onTap, this.note});
  final String label;
  final String? note;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: on ? Noc.accent900 : Colors.transparent,
            borderRadius: BorderRadius.circular(Noc.rControl),
            border: Border.all(color: on ? Noc.accent : Noc.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(
              label,
              style: TextStyle(fontFamily: 'Inter', fontSize: 12.5, fontVariations: Noc.w500, color: on ? Noc.accent200 : Noc.muted),
            ),
            if (note != null) ...[
              const SizedBox(width: 7),
              Text(note!, style: Noc.small.copyWith(color: on ? Noc.accent400 : Noc.dim)),
            ],
          ]),
        ),
      );
}

/// The offer to re-level, made before the athlete has to ask for it. A coach's
/// advanced programme in front of a beginner is the moment this feature exists
/// for, so the app says so rather than waiting to be found.
class _LevelNudge extends StatelessWidget {
  const _LevelNudge({required this.from, required this.to, required this.onTap});
  final ExerciseLevel from;
  final ExerciseLevel to;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => NocCard(
        key: const Key('levelNudge'),
        radius: Noc.rRow,
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        border: Noc.hairlineAccent,
        onTap: onTap,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Nx.sparkle, size: 15, color: Noc.accent400),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              to.index < from.index
                  ? 'Written for ${from.label.toLowerCase()} athletes. Tap to see the same session with ${to.label.toLowerCase()} movements.'
                  : 'Written for ${from.label.toLowerCase()} athletes. Tap to see it built up to ${to.label.toLowerCase()}.',
              style: Noc.metaMuted,
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Nx.caretRight, size: 14, color: Noc.dim),
        ]),
      );
}

/// What the switch actually did, said plainly, including what it could not do.
class _SwapSummary extends StatelessWidget {
  const _SwapSummary({required this.levelled, required this.minutes});
  final LevelledRoutine levelled;
  final int minutes;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        decoration: BoxDecoration(
          color: Noc.accent900,
          borderRadius: BorderRadius.circular(Noc.rRow),
          border: Border.all(color: Noc.accent700),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Nx.arrowCounterClockwise, size: 15, color: Noc.accent400),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(levelled.summary, style: Noc.metaMuted.copyWith(color: Noc.accent200)),
                const SizedBox(height: 3),
                Text('About $minutes minutes at this level.', style: Noc.small.copyWith(color: Noc.accent400)),
              ],
            ),
          ),
        ]),
      );
}

// =============================================================== exercises
class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.item, required this.owned, this.exercise, this.swap});

  final RoutineItem item;
  final Exercise? exercise;
  final ExerciseSwap? swap;
  final List<String> owned;

  @override
  Widget build(BuildContext context) {
    final e = exercise;
    final level = ExerciseLevel.of(e?.level);
    final changed = swap?.changed ?? false;
    final part = e == null ? '' : (e.primary.isNotEmpty ? e.primary.first : e.category);
    final kit = e == null || const {'none', 'other', 'body only'}.contains(e.equipment) ? '' : e.equipment;
    final hold = item.notes.toLowerCase().contains('hold');

    return NocCard(
      radius: Noc.rRow,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      border: changed ? Noc.hairlineAccent : null,
      onTap: e == null ? null : () => context.push('/exercise/${e.id}', extra: e),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: e == null
                ? ClipRRect(borderRadius: BorderRadius.circular(9), child: const NocStripes(dark: true))
                : ExerciseMedia(exercise: e, height: 44, dot: false),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(item.exerciseName, style: Noc.rowTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                  if (level != null) ...[
                    const SizedBox(width: 8),
                    NocTag(
                      level.label,
                      style: level == ExerciseLevel.advanced ? NocTagStyle.outline : NocTagStyle.accent,
                      fontSize: 9.5,
                    ),
                  ],
                ]),
                const SizedBox(height: 3),
                Text(
                  [
                    hold ? '${item.sets} × hold' : '${item.sets} × ${item.reps}',
                    if (item.restSec > 0) '${item.restSec}s rest',
                    if (part.isNotEmpty) part,
                    if (kit.isNotEmpty) kit,
                  ].join(' · '),
                  style: Noc.small,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.notes.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(item.notes, style: Noc.small.copyWith(color: Noc.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
                if (kit.isNotEmpty && !owned.contains(kit)) ...[
                  const SizedBox(height: 2),
                  Text('You don\'t own a $kit', style: Noc.small.copyWith(color: Noc.accent600)),
                ],
                if (changed) ...[
                  const SizedBox(height: 5),
                  Text(
                    'Swapped for ${swap!.from.exerciseName} · ${swap!.reason}',
                    style: Noc.small.copyWith(color: Noc.accent400),
                    maxLines: 2,
                  ),
                ] else if (swap?.kind == SwapKind.unavailable) ...[
                  const SizedBox(height: 5),
                  Text(swap!.reason, style: Noc.small.copyWith(color: Noc.dim), maxLines: 2),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ================================================================== accept
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.label, required this.accepted, required this.onStart, this.onAccept});

  final String label;
  final bool accepted;
  final VoidCallback onStart;
  final VoidCallback? onAccept;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.fromLTRB(Noc.gutter, 12, Noc.gutter, 12 + MediaQuery.paddingOf(context).bottom),
        decoration: const BoxDecoration(
          color: Noc.bg,
          border: Border(top: BorderSide(color: Noc.divider)),
        ),
        child: Row(children: [
          Expanded(child: NocButton(label: 'Start now', icon: Nx.play, primary: false, block: true, onTap: onStart)),
          const SizedBox(width: 10),
          Expanded(
            child: NocButton(
              key: const Key('acceptRoutine'),
              label: accepted ? 'In your routines' : label,
              icon: accepted ? Nx.check : Nx.plus,
              block: true,
              onTap: onAccept,
            ),
          ),
        ]),
      );
}
