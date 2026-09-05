import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/nocturne.dart';
import '../../core/models.dart';
import '../../core/exercise_repository.dart';
import '../../core/providers.dart';
import '../../core/session_theme.dart';
import '../../core/social_backend.dart';
import 'ai_assist_sheet.dart';
import 'build_screen.dart';

/// One exercise on the session timeline. [minutes] drives the width of its
/// segment in the proportional bar.
class TimelineItem {
  TimelineItem({required this.key, required this.exercise, required this.minutes, required this.meta});
  final String key;
  final Exercise exercise;
  final int minutes;
  final String meta;
}

/// Build, steps 2 and 3 (Nocturne handoff, section 3).
///
/// Step 2 is the timeline: the card is the drop target and its ring goes
/// accent while a drag is over it, library tiles are both draggable and
/// tappable, and rows reorder by dragging their handle. Step 3 names it and
/// sends it.
class SessionBuilderScreen extends ConsumerStatefulWidget {
  const SessionBuilderScreen({super.key, required this.theme, this.draft = false});
  final SessionTheme theme;

  /// Enter with the AI sheet already open (the coach's "open it in the
  /// builder" hand-off).
  final bool draft;

  @override
  ConsumerState<SessionBuilderScreen> createState() => _SessionBuilderScreenState();
}

class _SessionBuilderScreenState extends ConsumerState<SessionBuilderScreen> {
  /// Null shows the whole library grouped by grade; a level filters to it.
  ExerciseLevel? _level;

  final _timeline = <TimelineItem>[];

  bool _dragOver = false;

  /// Index of the timeline row currently being dragged, so its ring can go
  /// accent while it moves.
  int? _dragIndex;
  int _step = 2;
  late final _name = TextEditingController(text: '${widget.theme.name} · ${DateFormat.E().format(DateTime.now())}');
  bool _share = true;
  bool _invite = false;
  bool _saving = false;

  SessionTheme get theme => widget.theme;
  int get totalMinutes => _timeline.fold(0, (n, i) => n + i.minutes);

  @override
  void initState() {
    super.initState();
    if (widget.draft) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openAi());
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _append(Exercise e) {
    setState(() {
      _timeline.add(TimelineItem(key: '${e.id}-${DateTime.now().microsecondsSinceEpoch}', exercise: e, minutes: theme.minutesFor(), meta: theme.metaFor(e)));
    });
  }

  void _remove(String key) => setState(() => _timeline.removeWhere((i) => i.key == key));

  void _reorder(int from, int to) => setState(() {
    _timeline.insert(to, _timeline.removeAt(from));
    _dragIndex = to;
  });

  Future<void> _openAi() async {
    final picks = await showAiAssistSheet(context, theme: theme, ref: ref);
    if (picks == null || !mounted) return;
    setState(() {
      _timeline
        ..clear()
        ..addAll(
          picks.map(
            (e) => TimelineItem(
              key: '${e.id}-${DateTime.now().microsecondsSinceEpoch}-${picks.indexOf(e)}',
              exercise: e,
              minutes: theme.minutesFor(),
              meta: theme.metaFor(e),
            ),
          ),
        );
    });
    nocToast(context, 'AI drafted ${picks.length} exercises — reorder or swap any of them.');
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final me = ref.read(profileProvider)!;
    final routine = Routine(
      id: newUuid(),
      name: _name.text.trim().isEmpty ? theme.name : _name.text.trim(),
      description: '${_timeline.length} exercises · ~$totalMinutes min',
      authorId: me.id,
      authorName: me.name,
      createdAt: DateTime.now(),
      tags: [theme.name.toLowerCase()],
      days: [
        RoutineDay(title: theme.name, focus: theme.hint, items: [for (final i in _timeline) theme.itemFor(i.exercise)]),
      ],
    );
    final saved = await ref.read(routinesProvider.notifier).upsert(routine);

    // The handoff drops a saved routine onto Saturday.
    final now = DateTime.now();
    final saturday = now.add(Duration(days: (DateTime.saturday - now.weekday) % 7));
    await ref.read(scheduleProvider.notifier).add(routine: saved, dayIndex: 0, at: DateTime(saturday.year, saturday.month, saturday.day, 10));

    var shared = false;
    if (_share) {
      try {
        await ref
            .read(socialProvider.notifier)
            .publish(
              Post(
                id: newUuid(),
                authorId: me.id,
                kind: PostKind.routine,
                title: saved.name,
                body: 'Built on the timeline: ${_timeline.length} exercises, about $totalMinutes minutes.',
                createdAt: DateTime.now(),
                routine: saved,
                tags: [theme.name.toLowerCase()],
              ),
            );
        shared = true;
      } catch (e) {
        debugPrint('share failed: $e');
      }
    }

    if (_invite) {
      final friend = ref.read(socialProvider).users.values.where((u) => u.id != me.id).firstOrNull;
      if (friend != null) {
        await ref.read(questsProvider.notifier).invite(friend: friend, preset: questPresets[2]);
      }
    }

    if (!mounted) return;
    context.go('/home');
    nocToast(context, shared ? 'Saved to Saturday and shared to your feed.' : 'Saved to Saturday.');
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(exerciseRepoProvider);
    return Scaffold(
      backgroundColor: Noc.bg,
      body: SafeArea(bottom: false, child: NocIn(child: _step == 2 ? _buildStep2(repo) : _buildStep3())),
    );
  }

  // ------------------------------------------------------------- step two
  Widget _buildStep2(AsyncValue<ExerciseRepository> repo) {
    final me = ref.watch(profileProvider)!;
    final library = repo.value?.forTheme(theme, level: _level) ?? const <Exercise>[];
    final counts = repo.value?.levelCounts(theme) ?? const <ExerciseLevel, int>{};

    return ListView(
      padding: const EdgeInsets.fromLTRB(Noc.gutter, 8, Noc.gutter, 108),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            children: [
              NocIconButton(icon: Nx.arrowLeft, size: 32, color: Noc.neutral300, onTap: () => context.pop()),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(theme.name.toUpperCase(), style: Noc.kicker.copyWith(color: Noc.accent, fontSize: 10.5)),
                    Text('Build the session', style: Noc.name),
                  ],
                ),
              ),
              NocButton(label: 'AI', icon: Nx.sparkle, dense: true, onTap: _openAi),
            ],
          ),
        ),
        _timelineCard(),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: Text('${theme.name} library', style: Noc.cardTitle)),
            Text('${library.length} exercises', style: Noc.meta),
          ],
        ),
        const SizedBox(height: 9),
        // The library splits by grade: All groups it under three headings,
        // a chip narrows to one. The athlete's own level keeps an accent dot
        // so they can see where they sit without being locked to it.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _LevelChip(label: 'All', count: counts.values.fold(0, (a, b) => a + b), on: _level == null, onTap: () => setState(() => _level = null)),
              for (final l in ExerciseLevel.values) ...[
                const SizedBox(width: 8),
                _LevelChip(
                  label: l.label,
                  count: counts[l] ?? 0,
                  on: _level == l,
                  mine: me.experience.exerciseLevel == l,
                  onTap: () => setState(() => _level = _level == l ? null : l),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 11),
        if (repo.isLoading)
          const Padding(
            padding: EdgeInsets.all(30),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Noc.accent)),
          )
        else if (_level != null)
          _libraryGrid(library.take(40).toList(), me)
        else
          for (final l in ExerciseLevel.values)
            if (_group(library, l).isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Row(
                  children: [
                    Expanded(child: Text(l.label.toUpperCase(), style: Noc.kicker)),
                    Text('${counts[l] ?? 0}', style: Noc.small),
                  ],
                ),
              ),
              _libraryGrid(_group(library, l), me),
              const SizedBox(height: 14),
            ],
      ],
    );
  }

  /// Up to fourteen per grade when the whole library is on screen, so a group
  /// reads as a shelf rather than a scroll.
  List<Exercise> _group(List<Exercise> library, ExerciseLevel level) => library.where((e) => ExerciseLevel.of(e.level) == level).take(14).toList();

  Widget _libraryGrid(List<Exercise> items, UserProfile me) => GridView.count(
    crossAxisCount: 2,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    childAspectRatio: 1.42,
    crossAxisSpacing: 10,
    mainAxisSpacing: 10,
    children: [
      for (final e in items)
        _LibraryTile(
          exercise: e,
          theme: theme,
          onAdd: () => _append(e),
          mine: me.equipment.contains(e.equipment),
          onTimeline: _timeline.where((i) => i.exercise.id == e.id).length,
        ),
    ],
  );

  Widget _timelineCard() => DragTarget<Exercise>(
    onWillAcceptWithDetails: (_) {
      setState(() => _dragOver = true);
      return true;
    },
    onLeave: (_) => setState(() => _dragOver = false),
    onAcceptWithDetails: (d) {
      setState(() => _dragOver = false);
      _append(d.data);
    },
    builder: (context, _, _) => AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Noc.rCardLg),
        gradient: const LinearGradient(begin: Alignment(-0.8, -1), end: Alignment(0.6, 1), colors: [Noc.surface, Color(0xFF1C1E2B)]),
        border: Border.all(color: _dragOver ? Noc.accent : Noc.accent800),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Expanded(
                child: Text(
                  'Session timeline',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w500, fontVariations: Noc.w500, color: Noc.text),
                ),
              ),
              Text(totalMinutes == 0 ? '—' : '$totalMinutes min', style: Noc.meta),
            ],
          ),
          const SizedBox(height: 11),
          _segments(),
          if (_timeline.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Noc.rRowSm),
                  border: Border.all(color: _dragOver ? Noc.accent : Noc.line),
                ),
                child: Column(
                  children: [
                    Text('Drag exercises up here', style: Noc.metaMuted.copyWith(fontSize: 12.5)),
                    const SizedBox(height: 4),
                    Text('or tap one to append it · or let AI draft the block', style: Noc.meta, textAlign: TextAlign.center),
                  ],
                ),
              ),
            )
          else ...[
            const SizedBox(height: 11),
            _rows(),
            const SizedBox(height: 12),
            NocButton(label: 'Review & save', block: true, onTap: () => setState(() => _step = 3)),
          ],
        ],
      ),
    ),
  );

  /// One segment per exercise, width proportional to its minutes.
  Widget _segments() => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: Container(
      height: 10,
      color: const Color(0xFF1A1C28),
      child: _timeline.isEmpty
          ? null
          : Row(
              children: [
                for (final (i, item) in _timeline.indexed) ...[
                  if (i > 0) const SizedBox(width: 3),
                  Expanded(
                    flex: max(1, item.minutes),
                    child: AnimatedContainer(duration: const Duration(milliseconds: 350), color: i.isEven ? Noc.accent : Noc.accent700),
                  ),
                ],
              ],
            ),
    ),
  );

  /// A plain column rather than a ReorderableListView: nesting a second
  /// scrollable inside the page's list left rows past the first unpainted.
  /// This also matches the handoff's own semantics — the drag records an
  /// index and entering another row splices the item to that position.
  Widget _rows() => Column(
    children: [
      for (final (i, item) in _timeline.indexed)
        DragTarget<int>(
          onWillAcceptWithDetails: (d) {
            if (d.data != i) _reorder(d.data, i);
            return true;
          },
          onAcceptWithDetails: (_) {},
          builder: (context, candidate, _) => _TimelineRow(
            key: ValueKey(item.key),
            index: i,
            item: item,
            dragging: _dragIndex == i,
            onRemove: () => _remove(item.key),
            onDragStart: () => setState(() => _dragIndex = i),
            onDragEnd: () => setState(() => _dragIndex = null),
          ),
        ),
    ],
  );

  // ----------------------------------------------------------- step three
  Widget _buildStep3() {
    final friend = ref.watch(socialProvider).users.values.where((u) => u.id != ref.read(profileProvider)!.id).firstOrNull;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Noc.gutter, 8, Noc.gutter, 40),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('STEP 3 OF 3', style: Noc.kicker),
              const SizedBox(height: 4),
              Text('Name it, then send it', style: Noc.screenTitle),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: Noc.card(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ROUTINE NAME', style: Noc.columnLabel),
              const SizedBox(height: 6),
              TextField(
                controller: _name,
                style: Noc.body,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Noc.rControl),
                    borderSide: const BorderSide(color: Noc.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Noc.rControl),
                    borderSide: const BorderSide(color: Noc.accent),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _Fact(label: 'THEME', value: theme.name),
                  const SizedBox(width: 18),
                  _Fact(label: 'EXERCISES', value: '${_timeline.length}'),
                  const SizedBox(width: 18),
                  _Fact(label: 'DURATION', value: '$totalMinutes min'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: Noc.card(),
          child: Column(
            children: [
              _ToggleRow(
                value: _share,
                onChanged: (v) => setState(() => _share = v),
                title: 'Share to my followers',
                subtitle: 'They can copy it into their own week',
              ),
              const SizedBox(height: 12),
              _ToggleRow(
                value: _invite,
                onChanged: friend == null ? null : (v) => setState(() => _invite = v),
                title: friend == null ? 'Invite a friend to train it' : 'Invite ${friend.name.split(' ').first} to train it with me',
                subtitle: friend == null ? 'Follow someone first' : 'Starts a shared quest with them',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: NocButton(label: 'Back', primary: false, block: true, onTap: () => setState(() => _step = 2)),
            ),
            const SizedBox(width: 9),
            Expanded(
              flex: 2,
              child: NocButton(label: _saving ? 'Saving…' : 'Save routine', block: true, onTap: _saving ? null : _save),
            ),
          ],
        ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Noc.columnLabel),
      const SizedBox(height: 2),
      Text(
        value,
        style: const TextStyle(fontFamily: 'Inter', fontSize: 13.5, color: Noc.text),
      ),
    ],
  );
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({required this.value, required this.onChanged, required this.title, required this.subtitle});
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String title, subtitle;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onChanged == null ? null : () => onChanged!(!value),
    behavior: HitTestBehavior.opaque,
    child: Row(
      children: [
        NocToggle(value: value, onChanged: onChanged),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Noc.rowTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(subtitle, style: Noc.meta, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    ),
  );
}

/// A timeline row: index, media, name, remove, drag handle. Dragging the
/// handle over another row splices this one to that position, and the ring
/// goes accent while it moves.
class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    super.key,
    required this.index,
    required this.item,
    required this.dragging,
    required this.onRemove,
    required this.onDragStart,
    required this.onDragEnd,
  });
  final int index;
  final TimelineItem item;
  final bool dragging;
  final VoidCallback onRemove;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Noc.sunken,
        borderRadius: BorderRadius.circular(Noc.rControl),
        border: Border.all(color: dragging ? Noc.accent : Noc.sunken),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text('${index + 1}', style: Noc.meta, textAlign: TextAlign.center),
          ),
          const SizedBox(width: 9),
          ExerciseMedia(exercise: item.exercise, height: 34, radius: 9),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.exercise.name,
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w500, fontVariations: Noc.w500, color: Noc.text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(item.meta, style: Noc.small, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          GestureDetector(
            onTap: onRemove,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox(width: 24, height: 24, child: Icon(Nx.x, size: 14, color: Noc.dim)),
          ),
          LongPressDraggable<int>(
            data: index,
            delay: const Duration(milliseconds: 120),
            onDragStarted: onDragStart,
            onDraggableCanceled: (_, _) => onDragEnd(),
            onDragEnd: (_) => onDragEnd(),
            feedback: Material(
              color: Colors.transparent,
              child: Container(
                width: 180,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(
                  color: Noc.sunken,
                  borderRadius: BorderRadius.circular(Noc.rControl),
                  border: Border.all(color: Noc.accent),
                ),
                child: Text(item.exercise.name, style: Noc.rowTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
            child: const MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: SizedBox(width: 22, height: 24, child: Icon(Nx.dotsSixVertical, size: 16, color: Noc.neutral700)),
            ),
          ),
        ],
      ),
    );
    return row;
  }
}

/// One grade in the library filter. The athlete's own level keeps an accent
/// dot even when another chip is selected.
class _LevelChip extends StatelessWidget {
  const _LevelChip({required this.label, required this.count, required this.on, required this.onTap, this.mine = false});
  final String label;
  final int count;
  final bool on;
  final bool mine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: on ? Noc.accent900 : Colors.transparent,
        borderRadius: BorderRadius.circular(Noc.rControl),
        border: Border.all(color: on ? Noc.accent : Noc.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (mine) ...[
            Container(
              width: 5,
              height: 5,
              decoration: const BoxDecoration(color: Noc.accent, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: on ? Noc.accent200 : Noc.muted),
          ),
          const SizedBox(width: 6),
          Text('$count', style: Noc.small.copyWith(color: on ? Noc.accent400 : Noc.dim)),
        ],
      ),
    ),
  );
}

class _LibraryTile extends StatelessWidget {
  const _LibraryTile({required this.exercise, required this.theme, required this.onAdd, required this.mine, this.onTimeline = 0});
  final Exercise exercise;
  final SessionTheme theme;
  final VoidCallback onAdd;
  final bool mine;

  /// How many times this exercise is already on the timeline. Tapping a tile
  /// used to do nothing visible up here — the row appeared in a card that can
  /// be scrolled away — so the tile now carries the answer itself.
  final int onTimeline;

  @override
  Widget build(BuildContext context) {
    final added = onTimeline > 0;
    // No entry animation here on purpose: a tween inside this drag-enabled
    // tile is exactly the thing that stuck part-way through in v0.7. The ring,
    // the badge and the changed line are instant and cannot get stranded.
    final card = Stack(
      children: [
        NocCard(
          padding: EdgeInsets.zero,
          radius: Noc.rRow,
          onTap: onAdd,
          border: Border.all(color: added ? Noc.accent : Noc.line),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // fill: true makes this an Expanded, so the badge goes over the
              // whole card rather than inside the media.
              ExerciseMedia(exercise: exercise, chip: true, fill: true),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exercise.name,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        fontVariations: Noc.w500,
                        color: added ? Noc.accent200 : Noc.text,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    // No grade tag on the tile: the shelf it sits under, or the
                    // chip that filtered to it, has already said which one it is.
                    Text(
                      added ? 'On the timeline · tap to add again' : theme.metaFor(exercise),
                      style: Noc.small.copyWith(color: added ? Noc.accent400 : Noc.dim),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (added)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              height: 22,
              padding: EdgeInsets.symmetric(horizontal: onTimeline > 1 ? 8 : 5),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Noc.accent,
                borderRadius: BorderRadius.circular(Noc.rPill),
                border: Border.all(color: Noc.bg, width: 1.5),
              ),
              child: onTimeline > 1
                  ? Text(
                      '×$onTimeline',
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontVariations: Noc.w600, color: Colors.white),
                    )
                  : const Icon(Nx.check, size: 12, color: Colors.white),
            ),
          ),
      ],
    );
    return LongPressDraggable<Exercise>(
      data: exercise,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.9,
          child: Container(
            width: 150,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: Noc.sunken,
              borderRadius: BorderRadius.circular(Noc.rControl),
              border: Border.all(color: Noc.accent),
            ),
            child: Text(exercise.name, style: Noc.rowTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: card),
      child: card,
    );
  }
}
