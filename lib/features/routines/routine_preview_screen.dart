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
import '../community/community_screen.dart' show compactCount;

/// Look inside a routine before you accept it (v0.10, redesigned v0.14).
///
/// Everything that arrives from somebody else — a friend's share, a coach's
/// programme, an invite to train together — lands here first. The athlete sees
/// every exercise, what grade the catalogue gives it, what kit it needs and
/// whether that is where they train, and only then decides.
///
/// The page opens on the session itself: a full-bleed grid of the movements it
/// is made of, which starts the workout when it is tapped, with the name and
/// the four numbers that matter sitting on top of it. Everything that explains
/// the session — who wrote it, what it costs you, what it needs — reads down
/// the page under that.
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
    final day = view.days.isEmpty ? 0 : (widget.focusDay ?? 0).clamp(0, view.days.length - 1);

    return Column(
      children: [
        Expanded(
          child: NocIn(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 20),
              children: [
                _header(context, shared, author, me, saved: mine),
                const SizedBox(height: 12),
                // The session itself, and the way into it: the grid is the
                // play button.
                _Hero(
                  routine: view,
                  insight: viewInsight,
                  repo: repo,
                  day: day,
                  onPlay: () => context.push('/workout/${view.id}', extra: view),
                ),
                const SizedBox(height: 18),
                _Gutter(child: _AuthorRow(routine: shared, author: author, me: me)),
                if (shared.description.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _Gutter(child: Text(shared.description, style: Noc.body.copyWith(color: Noc.muted))),
                ],
                if (shared.tags.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _Gutter(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [for (final t in shared.tags.take(4)) NocTag(t, style: NocTagStyle.neutral, fontSize: 11)],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _Gutter(child: Container(height: 1, color: Noc.divider)),
                const SizedBox(height: 14),
                _Gutter(child: _FitsYou(insight: insight, me: me)),
                const SizedBox(height: 14),
                _Gutter(child: _LevelBar(insight: viewInsight)),
                const SizedBox(height: 20),
                _Gutter(
                  child: _LevelSwitcher(
                    insight: insight,
                    me: me,
                    selected: _target ?? insight.level,
                    onPick: (l) => setState(() => _target = l),
                  ),
                ),
                if (levelled != null) ...[
                  const SizedBox(height: 10),
                  _Gutter(child: _SwapSummary(levelled: levelled, minutes: viewInsight.minutes)),
                ] else if (insight.level != null && insight.level != me.experience.exerciseLevel) ...[
                  const SizedBox(height: 10),
                  _Gutter(
                    child: _LevelNudge(
                      from: insight.level!,
                      to: me.experience.exerciseLevel,
                      onTap: () => setState(() => _target = me.experience.exerciseLevel),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                for (var d = 0; d < view.days.length; d++) ...[
                  if (d > 0) const SizedBox(height: 18),
                  _Gutter(
                    child: NocSectionHead(
                      view.days[d].title,
                      note: '${viewInsight.dayMinutes[d]} min${view.days[d].focus.isEmpty ? '' : ' · ${view.days[d].focus.toLowerCase()}'}',
                    ),
                  ),
                  if (d == widget.focusDay && view.days.length > 1)
                    _Gutter(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('The session you were invited to', style: Noc.small.copyWith(color: Noc.accent400)),
                      ),
                    ),
                  const SizedBox(height: 10),
                  for (var i = 0; i < view.days[d].items.length; i++)
                    _Gutter(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _ExerciseRow(
                          index: i + 1,
                          item: view.days[d].items[i],
                          exercise: repo.byId(view.days[d].items[i].exerciseId),
                          swap: levelled?.at(d, i),
                          owned: me.equipment,
                        ),
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

  Widget _header(BuildContext context, Routine routine, SocialUser? author, UserProfile me, {required bool saved}) {
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
    return _Gutter(
      child: Padding(
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
            // The mock's top-right pill: it says where the routine already
            // stands, and the accept button below is what changes that.
            if (saved)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Noc.rControl),
                  border: Border.all(color: Noc.accent700),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Nx.check, size: 12, color: Noc.accent300),
                  SizedBox(width: 6),
                  Text('Saved', style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: Noc.accent300)),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

/// Screen-gutter padding. The page scrolls edge to edge so the hero can bleed
/// into both margins; everything else asks for the gutter itself.
class _Gutter extends StatelessWidget {
  const _Gutter({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: Noc.gutter), child: child);
}

// ==================================================================== hero
/// The session as a wall of its own movements, with the name and the four
/// numbers reading out of the bottom of it. Tapping anywhere starts it.
class _Hero extends StatelessWidget {
  const _Hero({required this.routine, required this.insight, required this.repo, required this.day, required this.onPlay});

  final Routine routine;
  final RoutineInsight insight;
  final ExerciseRepository repo;
  final int day;
  final VoidCallback onPlay;

  static const _height = 320.0;
  static const _gap = 2.0;

  @override
  Widget build(BuildContext context) {
    final items = routine.days.isEmpty ? const <RoutineItem>[] : routine.days[day].items;
    final lead = items.isEmpty ? null : items.first;
    // Three movements sit beside the lead one, and the fourth cell is the
    // clock: how long the whole thing takes, and the way into it.
    final rest = items.skip(1).take(3).toList();
    final cells = <Widget>[
      for (final item in rest) _HeroTile(item: item, exercise: repo.byId(item.exerciseId)),
      _PlayTile(minutes: insight.minutes),
    ];

    return GestureDetector(
      key: const Key('heroPlay'),
      behavior: HitTestBehavior.opaque,
      onTap: onPlay,
      child: SizedBox(
        height: _height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Row(
              children: [
                Expanded(
                  flex: 5,
                  child: lead == null
                      ? const NocStripes(bloom: true)
                      : _HeroTile(item: lead, exercise: repo.byId(lead.exerciseId), big: true),
                ),
                const SizedBox(width: _gap),
                Expanded(flex: 6, child: _grid(cells)),
              ],
            ),
            // The name sits on the media, so the media fades out under it.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  height: 190,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00161826), Color(0xCC161826), Noc.bg, Noc.bg],
                      stops: [0, 0.5, 0.82, 1],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: Noc.gutter,
              right: Noc.gutter,
              bottom: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    routine.name,
                    style: Noc.hero.copyWith(fontSize: 30, height: 1.05),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 14),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _Stat(value: '${insight.minutes}', label: 'MINUTES'),
                    _Stat(value: '${routine.exerciseCount}', label: 'EXERCISES'),
                    if (routine.days.length > 1)
                      _Stat(value: '${routine.days.length}', label: 'DAYS')
                    else
                      _Stat(value: insight.level?.label ?? '—', label: 'LEVEL', small: true),
                    _Stat(
                      value: routine.days.length > 1
                          ? (insight.level?.label ?? '—')
                          : (insight.equipment.isEmpty ? 'None' : _sentence(insight.equipment.first)),
                      label: routine.days.length > 1 ? 'LEVEL' : 'EQUIPMENT',
                      small: true,
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The cells beside the lead movement, two to a row.
  Widget _grid(List<Widget> cells) {
    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 2) {
      final pair = cells.skip(i).take(2).toList();
      rows.add(
        Expanded(
          child: Row(
            children: [
              for (final (j, cell) in pair.indexed) ...[
                if (j > 0) const SizedBox(width: _gap),
                Expanded(child: cell),
              ],
              // A lone cell on the last row still takes half the width, so the
              // grid keeps its shape rather than stretching one tile wide.
              if (pair.length == 1) ...[const SizedBox(width: _gap), const Spacer()],
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final (i, row) in rows.indexed) ...[
          if (i > 0) const SizedBox(height: _gap),
          row,
        ],
      ],
    );
  }

  static String _sentence(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

/// One movement in the hero grid: its own image, its name, and — on the lead
/// tile — what it is prescribed at.
class _HeroTile extends StatelessWidget {
  const _HeroTile({required this.item, this.exercise, this.big = false});
  final RoutineItem item;
  final Exercise? exercise;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final url = exercise?.imageUrl(0);
    final hold = item.notes.toLowerCase().contains('hold');
    return Stack(
      fit: StackFit.expand,
      children: [
        NocStripes(bloom: big),
        if (url != null)
          Image.network(
            url,
            fit: BoxFit.cover,
            frameBuilder: (_, child, frame, _) => AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 220),
              child: child,
            ),
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        // A wash off the top-left corner so the label reads over any frame.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xB3161826), Color(0x00161826)],
              stops: [0, 0.75],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(big ? 14 : 11, big ? 13 : 11, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.exerciseName,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: big ? 14.5 : 12,
                  fontWeight: FontWeight.w500,
                  fontVariations: Noc.w500,
                  color: Noc.text,
                  height: 1.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (big) ...[
                const SizedBox(height: 3),
                Text(
                  [
                    hold ? '${item.sets} × hold' : '${item.sets} × ${item.reps}',
                    if (item.notes.isNotEmpty) item.notes,
                  ].join(' · '),
                  style: Noc.small.copyWith(color: Noc.neutral400),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The last cell of the grid: the clock, and the reason the grid is tappable.
class _PlayTile extends StatelessWidget {
  const _PlayTile({required this.minutes});
  final int minutes;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Noc.sheet,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Nx.play, size: 15, color: Noc.accent400),
              const SizedBox(width: 7),
              Text(
                '$minutes MIN',
                style: const TextStyle(fontFamily: 'Inter', fontSize: 11, letterSpacing: 1.1, color: Noc.neutral400),
              ),
            ],
          ),
        ),
      );
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
              style: small ? Noc.statSm.copyWith(fontSize: 16) : Noc.stat,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Text(label, style: Noc.columnLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      );
}

// ================================================================== author
/// Who wrote it, and the one thing you can do about them from here.
class _AuthorRow extends ConsumerWidget {
  const _AuthorRow({required this.routine, required this.me, this.author});

  final Routine routine;
  final UserProfile me;
  final SocialUser? author;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = author;
    final following = a != null && ref.watch(socialProvider).following.contains(a.id);
    return Row(children: [
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: a == null ? null : () => context.push('/u/${a.id}'),
        child: NocFace(a?.emoji ?? '🙂', size: 38),
      ),
      const SizedBox(width: 11),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(a?.name ?? routine.authorName, style: Noc.planTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (a != null)
              Text(
                '@${a.handle}${a.followers > 0 ? ' · ${compactCount(a.followers)} athletes' : ''}',
                style: Noc.small,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
      if (a != null && a.id != me.id) ...[
        const SizedBox(width: 8),
        NocButton(
          label: following ? 'Following' : 'Follow',
          primary: !following,
          dense: true,
          onTap: () => ref.read(socialProvider.notifier).toggleFollow(a.id),
        ),
      ],
    ]);
  }
}

// ============================================================== does it fit
/// The three honest sentences: where the session sits against how you train,
/// what kit it wants, and what it works.
class _FitsYou extends StatelessWidget {
  const _FitsYou({required this.insight, required this.me});
  final RoutineInsight insight;
  final UserProfile me;

  @override
  Widget build(BuildContext context) {
    final missing = insight.missingEquipment(me);
    final verdict = insight.verdict(me);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (verdict != null)
          _Line(
            icon: insight.level == me.experience.exerciseLevel ? Nx.check : Nx.target,
            accent: true,
            text: '$verdict — you train ${me.experience.exerciseLevel.label.toLowerCase()}',
          ),
        _Line(
          icon: Nx.barbell,
          text: insight.equipment.isEmpty ? 'No equipment needed' : 'Needs ${insight.equipment.join(' · ')}',
          note: missing.isEmpty ? null : 'You have not said you own ${missing.join(', ')}.',
        ),
        if (insight.muscles.isNotEmpty)
          _Line(icon: Nx.target, text: 'Works ${insight.muscles.take(4).join(' · ')}'),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text, this.note, this.accent = false});
  final IconData icon;
  final String text;
  final String? note;
  final bool accent;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 15, color: accent ? Noc.accent400 : Noc.dim),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: Noc.body.copyWith(color: Noc.text, height: 1.35)),
                if (note != null) ...[
                  const SizedBox(height: 2),
                  Text(note!, style: Noc.metaMuted.copyWith(color: Noc.accent400)),
                ],
              ],
            ),
          ),
        ]),
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
          const SizedBox(height: 5),
          Text(
            'Same days, same order, same muscle in each slot — the movements change to ones the library grades there.',
            style: Noc.small,
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              for (final l in ExerciseLevel.values) ...[
                if (l != ExerciseLevel.values.first) const SizedBox(width: 8),
                Expanded(
                  child: _LevelPick(
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
                ),
              ],
            ],
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 52,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: on ? Noc.accent900 : Colors.transparent,
            borderRadius: BorderRadius.circular(Noc.rControl),
            border: Border.all(color: on ? Noc.accent : Noc.line),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontVariations: Noc.w500, color: on ? Noc.accent200 : Noc.muted),
              ),
              if (note != null) ...[
                const SizedBox(height: 2),
                Text(note!, style: Noc.tiny.copyWith(color: on ? Noc.accent400 : Noc.dim), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ],
          ),
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
  const _ExerciseRow({required this.index, required this.item, required this.owned, this.exercise, this.swap});

  final int index;
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
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
      border: changed ? Noc.hairlineAccent : null,
      onTap: e == null ? null : () => context.push('/exercise/${e.id}', extra: e),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 46,
            height: 46,
            child: e == null
                ? ClipRRect(borderRadius: BorderRadius.circular(10), child: const NocStripes(dark: true))
                : ExerciseMedia(exercise: e, height: 46, radius: 10, dot: false),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text('$index', style: Noc.tiny.copyWith(color: Noc.dim)),
                  const SizedBox(width: 7),
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
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
