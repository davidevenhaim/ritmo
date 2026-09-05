import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../app/nocturne.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../feed/feed_screen.dart';
import '../build/build_screen.dart' show ExerciseMedia;
import 'add_goal_sheet.dart';
import 'goal_deadline.dart';
import 'plus_menu.dart';

/// Me — the home screen, built to the Nocturne Fit handoff (section 1).
///
/// Order is deliberate and must not be reshuffled: progress first, then the
/// week, then the plan, then other people. Every number here comes from the
/// app's own data; where the design showed a metric we have no source for the
/// card keeps its shape and carries the closest real one (see the notes on
/// the stat row and the follow feed).
class MeScreen extends ConsumerWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(profileProvider)!;

    return Scaffold(
      backgroundColor: Noc.bg,
      // Start is the raised play button in the tab bar, so the only thing
      // floating here is breathing: two minutes between the day and the
      // session, one tap from the front door (v0.12).
      floatingActionButton: const _BreatheButton(),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: Noc.accent,
          backgroundColor: Noc.surface,
          onRefresh: () async {
            await ref.read(stepsProvider.notifier).refresh();
            ref.invalidate(streaksProvider);
            ref.invalidate(weekTrainingProvider);
          },
          child: NocIn(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Noc.gutter, 0, Noc.gutter, 32),
              children: [
                _Header(me: me),
                const _StreakCard(),
                const SizedBox(height: 10),
                const _StatRow(),
                const SizedBox(height: 14),
                const _GoalsCard(),
                const SizedBox(height: 22),
                const _ThisWeek(),
                const SizedBox(height: 24),
                const _YourPlan(),
                const SizedBox(height: 24),
                const _FollowFeed(),
                const SizedBox(height: 24),
                const _Nutrition(),
                const SizedBox(height: 24),
                Text('Account', style: Noc.sectionTitle),
                const SizedBox(height: 11),
                const _AccountList(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The floating way into breathing. Deliberately small and off to the side:
/// it is an offer, not the thing the app wants you to do.
class _BreatheButton extends StatelessWidget {
  const _BreatheButton();

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Start a breathing exercise',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => context.push('/breathe'),
          child: Container(
            key: const Key('breatheButton'),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
              color: Noc.accent900,
              borderRadius: BorderRadius.circular(Noc.rPill),
              border: Border.all(color: Noc.accent700),
              boxShadow: const [BoxShadow(color: Color(0x8C0F111C), blurRadius: 14, offset: Offset(0, 4))],
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Nx.heartbeat, size: 15, color: Noc.accent300),
              SizedBox(width: 8),
              Text('Breathe', style: TextStyle(fontFamily: 'Inter', fontSize: 12.5, fontVariations: Noc.w500, color: Noc.accent200)),
            ]),
          ),
        ),
      );
}

// ================================================================== header
class _Header extends ConsumerWidget {
  const _Header({required this.me});
  final UserProfile me;

  static String greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return 'Still up';
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.take(2).toString().toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }

  Future<void> _changePhoto(BuildContext context, WidgetRef ref) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Noc.sheet,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Noc.rSheet))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: Icon(Nx.image, color: Noc.neutral400), title: const Text('Choose a photo', style: Noc.rowTitle), onTap: () => Navigator.pop(context, 'gallery')),
          if (!kIsWeb) ListTile(leading: Icon(Nx.camera, color: Noc.neutral400), title: const Text('Take a photo', style: Noc.rowTitle), onTap: () => Navigator.pop(context, 'camera')),
          if (me.photo != null) ListTile(leading: Icon(Nx.arrowCounterClockwise, color: Noc.neutral400), title: const Text('Back to initials', style: Noc.rowTitle), onTap: () => Navigator.pop(context, 'remove')),
        ]),
      ),
    );
    if (choice == null) return;
    if (choice == 'remove') return ref.read(profileProvider.notifier).setPhoto(null);
    try {
      final x = await ImagePicker().pickImage(
        source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 400,
        maxHeight: 400,
        imageQuality: 78,
      );
      if (x == null) return;
      await ref.read(profileProvider.notifier).setPhoto(base64Encode(await x.readAsBytes()));
    } catch (e) {
      if (context.mounted) nocToast(context, 'Could not pick a photo: $e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photo = NocAvatar.decode(me.photo);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 18),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _changePhoto(context, ref),
            child: Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: photo == null
                    ? const LinearGradient(begin: Alignment(-0.6, -1), end: Alignment(0.6, 1), colors: [Noc.accent800, Noc.surface])
                    : null,
                border: Border.all(color: Noc.neutral700),
              ),
              child: photo != null
                  ? Image.memory(photo, width: 42, height: 42, fit: BoxFit.cover, gaplessPlayback: true)
                  : Text(initials(me.name), style: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, fontVariations: Noc.w600, color: Noc.accent300)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(greeting(), style: Noc.metaDim),
                Text(me.name, style: Noc.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const _FriendsPill(),
        ],
      ),
    );
  }
}

/// Decodes the profile photo once and caches it, so the header does not
/// re-decode base64 on every rebuild.
class NocAvatar {
  static final _cache = <String, Uint8List>{};
  static Uint8List? decode(String? b64) {
    if (b64 == null || b64.isEmpty) return null;
    return _cache.putIfAbsent('${b64.length}:${b64.substring(0, 24)}', () => base64Decode(b64));
  }
}

/// The way into Friends, sitting where the design put the invite button:
/// the faces of the people you follow, then a +. Tapping either opens the
/// Friends page — invite somebody to train, then read their week.
class _FriendsPill extends ConsumerWidget {
  const _FriendsPill();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final social = ref.watch(socialProvider);
    final faces = [for (final id in social.following.take(3)) ?social.users[id]];
    final invites = ref.watch(trainingInvitesProvider).length;

    return Semantics(
      button: true,
      label: 'Friends',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.push('/friends'),
        child: Container(
          height: 36,
          padding: EdgeInsets.fromLTRB(faces.isEmpty ? 9 : 7, 0, 9, 0),
          decoration: BoxDecoration(
            color: Noc.surface,
            borderRadius: BorderRadius.circular(Noc.rPill),
            border: Border.all(color: invites > 0 ? Noc.accent700 : Noc.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (faces.isNotEmpty) ...[
                SizedBox(
                  width: 24 + (faces.length - 1) * 15,
                  height: 24,
                  child: Stack(
                    children: [
                      for (final (i, u) in faces.indexed)
                        Positioned(left: i * 15, child: NocFace(u.emoji, size: 24, border: Noc.surface)),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Icon(Nx.userPlus, size: 16, color: invites > 0 ? Noc.accent300 : Noc.neutral400),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================ streak card
class _StreakCard extends ConsumerWidget {
  const _StreakCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streaks = ref.watch(streaksProvider).value ?? const Streaks();
    final done = ref.watch(weekTrainingProvider).value?.days ?? const <int>{};
    final today = DateTime.now().weekday;
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Noc.rCardLg),
        gradient: Noc.streakGradient,
        border: Noc.hairlineAccent,
      ),
      child: Stack(
        children: [
          Positioned(
            right: -40,
            top: -50,
            child: Container(
              width: 170,
              height: 170,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [Color(0x479184D9), Color(0x009184D9)], stops: [0.0, 0.68]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('WEEKLY STREAK', style: Noc.kickerAccent),
                          const SizedBox(height: 6),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text('${streaks.workoutStreak}', style: Noc.hero),
                              const SizedBox(width: 7),
                              Text(streaks.workoutStreak == 1 ? 'week unbroken' : 'weeks unbroken', style: Noc.bodyMuted),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(Nx.fire, size: 30, color: Noc.accent),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    for (var i = 0; i < 7; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      Expanded(child: _DayCell(letter: letters[i], done: done.contains(i + 1), isToday: today == i + 1)),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.letter, required this.done, required this.isToday});
  final String letter;
  final bool done;
  final bool isToday;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Container(
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: done ? Noc.accent800 : (isToday ? Colors.transparent : Noc.sunken),
              borderRadius: BorderRadius.circular(9),
              border: isToday && !done ? Border.all(color: Noc.accent, width: 1.5) : null,
            ),
            child: done
                ? Icon(Nx.check, size: 13, color: Noc.accent200)
                : isToday
                    ? const NocPulse(child: SizedBox(width: 6, height: 6, child: DecoratedBox(decoration: BoxDecoration(color: Noc.accent, shape: BoxShape.circle))))
                    : null,
          ),
          const SizedBox(height: 5),
          Text(letter, style: Noc.tiny.copyWith(color: isToday ? Noc.accent300 : Noc.dim)),
        ],
      );
}

// ================================================================ stat row
/// The handoff's row is Volume / Steps / Resting HR. Steps are real. We do
/// not record load per set, and reading heart rate would widen the Health
/// permission past the steps-only promise in Settings, so the ring shows the
/// week against the user's own session target and the third card shows the
/// sets behind it. Same shapes, numbers we can actually stand behind.
class _StatRow extends ConsumerWidget {
  const _StatRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(profileProvider)!;
    final week = ref.watch(weekTrainingProvider).value;
    final workouts = week?.workouts ?? 0;
    final pct = me.daysPerWeek == 0 ? 0.0 : workouts / me.daysPerWeek;
    final steps = ref.watch(todayStepsProvider);
    final fmt = NumberFormat.decimalPattern();

    // IntrinsicHeight so the ring card matches the two stacked cards beside
    // it, the way the handoff draws them.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: NocCard(
              onTap: () => context.push('/schedule'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('This week', style: Noc.metaMuted)),
                      Icon(Nx.arrowsOutSimple, size: 14, color: Noc.dim),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      NocRing(pct: pct),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${(pct * 100).round()}%', style: Noc.stat),
                            Text('of ${me.daysPerWeek} sessions', style: Noc.small, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: _MiniStat(
                    label: 'Steps',
                    value: fmt.format(steps),
                    icon: Nx.footprints,
                    onTap: () => context.push('/steps'),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: _MiniStat(
                    label: 'Sets logged',
                    value: '${week?.sets ?? 0}',
                    suffix: 'this week',
                    icon: Nx.barbell,
                    onTap: () => context.push('/schedule'),
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

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, required this.icon, this.suffix, this.onTap});
  final String label;
  final String value;
  final String? suffix;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => NocCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Noc.metaMuted),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(child: Text(value, style: Noc.statSm, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      if (suffix != null) ...[
                        const SizedBox(width: 4),
                        Flexible(child: Text(suffix!, style: Noc.tiny, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ],
                    ],
                  ),
                ),
                Icon(icon, size: 18, color: Noc.accent700),
              ],
            ),
          ],
        ),
      );
}

// ============================================================== goals card
class _GoalsCard extends ConsumerStatefulWidget {
  const _GoalsCard();
  @override
  ConsumerState<_GoalsCard> createState() => _GoalsCardState();
}

class _GoalsCardState extends ConsumerState<_GoalsCard> {
  bool _open = false;

  Future<void> _setGoal() async {
    final added = await showAddGoalSheet(context, ref);
    if (added && mounted) nocToast(context, 'Goal set. Track it from here as you train.');
  }

  Future<void> _editProgress(PersonalGoal g) async {
    var value = g.current;
    var deadline = g.deadline;
    final saved = await showDialog<bool>(
      context: context,
      barrierColor: Noc.scrim,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          backgroundColor: Noc.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Noc.muted)),
          // The deadline chips make this dialog tall on a small phone.
          content: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(g.name, style: Noc.cardTitle),
              const SizedBox(height: 14),
              Text(PersonalGoal(id: '', name: '', current: value, target: g.target, unit: g.unit).value, style: Noc.stat),
              Slider(
                value: value.clamp(0, g.target),
                max: g.target,
                divisions: g.target >= 20 ? g.target.round() : (g.target * 4).round(),
                activeColor: Noc.accent,
                inactiveColor: Noc.sunken,
                onChanged: (v) => setLocal(() => value = v),
              ),
              const SizedBox(height: 6),
              Text('BY WHEN', style: Noc.columnLabel),
              const SizedBox(height: 9),
              // The date can be added or moved after the fact: a goal set
              // open-ended is exactly the one that needs a date later.
              DeadlinePicker(
                value: deadline,
                onChanged: (d) => setLocal(() => deadline = d),
              ),
            ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await ref.read(customGoalsProvider.notifier).remove(g.id);
                if (context.mounted) Navigator.pop(context, false);
              },
              child: const Text('Remove', style: TextStyle(fontFamily: 'Inter', color: Noc.dim)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save', style: TextStyle(fontFamily: 'Inter', color: Noc.accent)),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    await ref.read(customGoalsProvider.notifier).setProgress(g.id, value);
    if (deadline != g.deadline) {
      await ref.read(customGoalsProvider.notifier).setDeadline(g.id, deadline, clear: deadline == null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final goals = ref.watch(goalsProvider);
    if (goals.isEmpty) return const SizedBox.shrink();
    final avg = goals.map((g) => g.pct).reduce((a, b) => a + b) / goals.length;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: Noc.card(),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Goals', style: Noc.cardTitle),
                            const SizedBox(height: 2),
                            Text('${goals.length} active · ${_open ? 'tap to collapse' : 'tap to see all'}', style: Noc.meta),
                          ],
                        ),
                      ),
                      const SizedBox(width: 9),
                      Text('${(avg * 100).round()}%', style: Noc.statSm.copyWith(color: Noc.accent400)),
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: AnimatedRotation(
                          turns: _open ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(Nx.caretDown, size: 14, color: Noc.dim),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      for (final (i, g) in goals.indexed) ...[
                        if (i > 0) const SizedBox(width: 5),
                        Expanded(child: NocBar(pct: g.pct)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            NocIn(
              duration: const Duration(milliseconds: 260),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Column(
                  children: [
                    Container(height: 1, color: Noc.divider),
                    const SizedBox(height: 9),
                    for (final g in goals) ...[
                      NocCard(
                        color: Noc.sunken,
                        border: Border.all(color: Noc.sunken),
                        radius: Noc.rRowSm,
                        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                        onTap: g.derived ? null : () => _editProgress(g),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                // A goal on a specific exercise carries the
                                // movement, so the row is the thing itself.
                                if (g.exerciseId != null) ...[
                                  if (ref.watch(exerciseRepoProvider).value?.byId(g.exerciseId!) case final ex?)
                                    ExerciseMedia(exercise: ex, height: 26, radius: 7, dot: false)
                                  else
                                    const Icon(Nx.target, size: 15, color: Noc.accent400),
                                  const SizedBox(width: 9),
                                ],
                                Expanded(child: Text(g.name, style: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w500, fontVariations: Noc.w500, color: Noc.text))),
                                const SizedBox(width: 8),
                                Text(g.value, style: Noc.metaMuted),
                              ],
                            ),
                            const SizedBox(height: 9),
                            NocBar(pct: g.pct, height: 5, track: Noc.sheet),
                            const SizedBox(height: 7),
                            Row(children: [
                              Expanded(child: Text(g.note, style: Noc.small, maxLines: 1, overflow: TextOverflow.ellipsis)),
                              // A goal with a date says how long is left; one
                              // without says nothing, so the row stays quiet.
                              if (g.dueLabel case final due?) ...[
                                const SizedBox(width: 8),
                                Text(due, style: Noc.small.copyWith(color: g.overdue ? Noc.accent400 : Noc.accent300)),
                              ],
                            ]),
                          ],
                        ),
                      ),
                      const SizedBox(height: 9),
                    ],
                    GestureDetector(
                      onTap: _setGoal,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(Noc.rControl),
                          border: Border.all(color: Noc.accent700, style: BorderStyle.solid),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Nx.plus, size: 14, color: Noc.accent300),
                            const SizedBox(width: 7),
                            const Text('Set a goal', style: TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: Noc.accent300)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// =============================================================== this week
/// The week's shape. The handoff charts training volume; we chart the seven
/// step days, which is the one daily series the app actually holds.
class _ThisWeek extends ConsumerWidget {
  const _ThisWeek();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = ref.watch(weekStepsProvider);
    final peak = days.fold(0, (m, d) => d.steps > m ? d.steps : m);
    final today = DateTime.now().weekday;
    final fmt = DateFormat('MMM d');
    final range = '${fmt.format(days.first.date)} – ${fmt.format(days.last.date)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NocSectionHead(
          'This week',
          note: range,
          trailing: Padding(
            padding: const EdgeInsets.only(left: 10),
            child: NocIconButton(
              icon: Nx.arrowsOutSimple,
              size: 30,
              outlined: true,
              tooltip: 'Full calendar',
              onTap: () => context.push('/calendar'),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // The seven bars are the week; the whole card opens the month behind
        // them, where the sessions, the plan and the goal dates live.
        NocCard(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
          onTap: () => context.push('/calendar'),
          child: Column(
            children: [
              SizedBox(
                height: 112,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < days.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: _WeekBar(
                          day: days[i],
                          peak: peak,
                          isPeak: peak > 0 && days[i].steps == peak,
                          isToday: today == i + 1,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(height: 1, color: Noc.divider),
              const SizedBox(height: 9),
              Row(children: [
                Icon(Nx.calendarBlank, size: 13, color: Noc.accent400),
                const SizedBox(width: 8),
                const Expanded(child: Text('Open the full calendar', style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: Noc.accent300))),
                const Icon(Nx.caretRight, size: 12, color: Noc.accent400),
              ]),
            ],
          ),
        ),
      ],
    );
  }
}

class _WeekBar extends StatelessWidget {
  const _WeekBar({required this.day, required this.peak, required this.isPeak, required this.isToday});
  final StepDay day;
  final int peak;
  final bool isPeak;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final frac = peak == 0 ? 0.0 : day.steps / peak;
    final color = isPeak
        ? Noc.accent
        : frac > 0.5
            ? Noc.accent700
            : frac > 0.08
                ? Noc.line
                : Noc.sunken;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (isPeak && day.steps > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: Noc.accent800, borderRadius: BorderRadius.circular(6)),
            child: Text(compactSteps(day.steps), style: const TextStyle(fontFamily: 'Inter', fontSize: 9.5, color: Noc.accent200)),
          ),
        const SizedBox(height: 7),
        Flexible(
          child: FractionallySizedBox(
            heightFactor: frac.clamp(0.06, 1.0),
            child: Container(
              width: 9,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(5)),
            ),
          ),
        ),
        const SizedBox(height: 7),
        Text(DateFormat.E().format(day.date), style: Noc.tiny.copyWith(color: isToday ? Noc.accent300 : Noc.dim)),
      ],
    );
  }
}

String compactSteps(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';

// =============================================================== your plan
class _YourPlan extends ConsumerWidget {
  const _YourPlan();

  static int weekOfYear(DateTime d) {
    final firstDay = DateTime(d.year, 1, 1);
    return ((d.difference(firstDay).inDays + firstDay.weekday) / 7).ceil();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedule = ref.watch(scheduleProvider);
    final routines = ref.watch(routinesProvider);
    final monday = weekStart(DateTime.now());
    final today = DateTime.now();
    final week = [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))];
    final sessions = schedule.where((s) => !s.at.isBefore(monday) && s.at.isBefore(monday.add(const Duration(days: 7)))).toList();

    // Duration is estimated from the routine: every set costs its rest plus
    // about forty seconds of work. Labelled with a tilde, never as a fact.
    var minutes = 0;
    for (final s in sessions) {
      final r = routines.where((x) => x.id == s.routineId).firstOrNull;
      if (r == null || r.days.isEmpty) {
        minutes += 40;
        continue;
      }
      final day = r.days[s.dayIndex.clamp(0, r.days.length - 1)];
      minutes += day.items.fold(0, (n, i) => n + (i.sets * (i.restSec + 40) / 60).round());
    }
    final themes = {for (final s in sessions) s.dayTitle.isEmpty ? s.routineName : s.dayTitle}.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('WEEK ${weekOfYear(today)}', style: Noc.kicker),
                  const SizedBox(height: 3),
                  Text('Your plan', style: Noc.planTitle),
                ],
              ),
            ),
            NocIconButton(
              icon: Nx.plus,
              size: 32,
              outlined: true,
              tooltip: 'Schedule a workout',
              onTap: () => showScheduleSheet(context),
            ),
            const SizedBox(width: 8),
            NocButton(
              label: 'Share',
              primary: false,
              dense: true,
              onTap: () {
                if (sessions.isEmpty) {
                  nocToast(context, 'Nothing scheduled yet. Add a session first.');
                  return;
                }
                final themes = {for (final s in sessions) s.dayTitle.isEmpty ? s.routineName : s.dayTitle};
                showModalBottomSheet<void>(
                  context: context,
                  useRootNavigator: true,
                  isScrollControlled: true,
                  builder: (_) => ComposeSheet(
                    title: 'Week ${weekOfYear(today)}: ${sessions.length} session${sessions.length == 1 ? '' : 's'} · ${themes.join(', ')}',
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          sessions.isEmpty
              ? 'No sessions yet · tap + to plan one'
              : '${sessions.length} session${sessions.length == 1 ? '' : 's'} · ~${minutes ~/ 60}h ${minutes % 60}m · $themes theme${themes == 1 ? '' : 's'}',
          style: Noc.metaDim,
        ),
        const SizedBox(height: 8),
        for (final date in week)
          _PlanDay(
            date: date,
            isToday: date.year == today.year && date.month == today.month && date.day == today.day,
            sessions: sessions.where((s) => s.isOn(date)).toList(),
          ),
      ],
    );
  }
}

class _PlanDay extends ConsumerWidget {
  const _PlanDay({required this.date, required this.isToday, required this.sessions});
  final DateTime date;
  final bool isToday;
  final List<ScheduledWorkout> sessions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dayColor = isToday ? Noc.accent300 : Noc.dim;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Noc.divider))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(DateFormat.E().format(date), style: Noc.meta.copyWith(color: dayColor)),
                  Text('${date.day}', style: TextStyle(fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w500, fontVariations: Noc.w500, color: dayColor)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: sessions.isEmpty
                ? GestureDetector(
                    onTap: () => showScheduleSheet(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(Noc.rRow), border: Border.all(color: Noc.line)),
                      child: Row(children: [
                        Icon(Nx.plus, size: 13, color: Noc.dim),
                        const SizedBox(width: 7),
                        const Text('Rest — add a session', style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: Noc.dim)),
                      ]),
                    ),
                  )
                : Column(
                    children: [
                      for (final s in sessions) ...[
                        SessionCard(session: s),
                        if (s != sessions.last) const SizedBox(height: 8),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// One scheduled session, as it appears on the plan and on the calendar.
class SessionCard extends ConsumerWidget {
  const SessionCard({super.key, required this.session});
  final ScheduledWorkout session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routine = ref.watch(routinesProvider).where((r) => r.id == session.routineId).firstOrNull;
    final count = routine == null || routine.days.isEmpty
        ? null
        : routine.days[session.dayIndex.clamp(0, routine.days.length - 1)].items.length;
    return NocCard(
      radius: Noc.rRow,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      // A booked class has no routine behind it — the studio runs the hour —
      // so its row opens the booking instead of the player.
      onTap: () => session.isClass
          ? showBookingSheet(context, ref, session)
          : context.push('/workout/${session.routineId}?day=${session.dayIndex}'),
      child: Row(
        children: [
          Container(width: 3, height: 26, decoration: BoxDecoration(color: session.done ? Noc.accent700 : Noc.accent, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(session.routineName, style: Noc.cardTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 1),
                Text(
                  [
                    if (count != null) '$count exercises',
                    DateFormat.jm().format(session.at),
                    if (session.done) 'done' else if (session.isPast) 'missed',
                    if (session.note.isNotEmpty) session.note,
                  ].join(' · '),
                  style: Noc.meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (session.guests.isNotEmpty) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 20 + (session.guests.length.clamp(1, 3) - 1) * 12,
              height: 20,
              child: Stack(
                children: [
                  for (final (i, g) in session.guests.take(3).indexed)
                    Positioned(left: i * 12, child: NocFace(g.emoji, size: 20, border: Noc.surface)),
                ],
              ),
            ),
          ],
          if (session.dayTitle.isNotEmpty) ...[const SizedBox(width: 8), NocTag(session.dayTitle)],
        ],
      ),
    );
  }
}

/// What a booked studio class opens: where, when, and the way out of it.
void showBookingSheet(BuildContext context, WidgetRef ref, ScheduledWorkout session) {
  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    backgroundColor: Noc.sheet,
    barrierColor: Noc.scrim,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Noc.rSheet))),
    builder: (sheet) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('BOOKED', style: Noc.kickerAccent),
            const SizedBox(height: 4),
            Text(session.routineName, style: Noc.pageTitle.copyWith(fontSize: 20)),
            const SizedBox(height: 4),
            Text('${session.dayTitle} · ${DateFormat('EEE d MMM, HH:mm').format(session.at)}', style: Noc.bodyMuted),
            if (session.note.isNotEmpty) Text(session.note, style: Noc.metaDim),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: NocButton(
                  label: 'Cancel booking',
                  primary: false,
                  block: true,
                  onTap: () async {
                    Navigator.pop(sheet);
                    await ref.read(scheduleProvider.notifier).cancelClass(session.classId!);
                    if (context.mounted) nocToast(context, 'Booking cancelled.');
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: NocButton(label: 'Keep it', block: true, onTap: () => Navigator.pop(sheet))),
            ]),
          ],
        ),
      ),
    ),
  );
}

// ======================================================= from people I follow
/// The handoff's receipt strip is Volume / Time / PR. We do not record load,
/// so each post shows the three numbers it actually carries, with the
/// standout one in accent, exactly where PR sat.
class _FollowFeed extends ConsumerWidget {
  const _FollowFeed();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final social = ref.watch(socialProvider);
    final posts = social.posts.where((p) => social.following.contains(p.authorId)).take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NocSectionHead('From people you follow', note: 'See all', onNote: () => context.push('/friends')),
        if (posts.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: NocCard(
              onTap: () => context.push('/discover'),
              child: Row(children: [
                Icon(Nx.usersThree, size: 18, color: Noc.dim),
                const SizedBox(width: 10),
                const Expanded(child: Text('Follow a few people and their sessions land here.', style: Noc.bodyMuted)),
              ]),
            ),
          )
        else
          for (final p in posts)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _PostCard(post: p, author: social.users[p.authorId]),
            ),
      ],
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post, this.author});
  final Post post;
  final SocialUser? author;

  @override
  Widget build(BuildContext context) {
    final stats = _stats(post);
    return NocCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      onTap: () => context.push('/u/${post.authorId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: Noc.line, shape: BoxShape.circle),
              child: Text(
                _Header.initials(author?.name ?? '?'),
                style: const TextStyle(fontFamily: 'Inter', fontSize: 10.5, fontWeight: FontWeight.w600, fontVariations: Noc.w600, color: Noc.neutral300),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(child: Text(author?.name ?? 'Someone', style: const TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: Noc.text))),
            Text(_ago(post.createdAt), style: Noc.small),
          ]),
          const SizedBox(height: 9),
          Text(post.title, style: Noc.cardTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 9),
          Container(
            padding: const EdgeInsets.only(top: 10),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Noc.divider))),
            child: Row(
              children: [
                for (final (i, s) in stats.indexed) ...[
                  if (i > 0) const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.$1, style: Noc.columnLabel),
                      const SizedBox(height: 2),
                      Text(s.$2, style: TextStyle(fontFamily: 'Inter', fontSize: 13.5, color: i == 2 ? Noc.accent400 : Noc.text)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static List<(String, String)> _stats(Post p) {
    if (p.routine != null) {
      return [
        ('EXERCISES', '${p.routine!.exerciseCount}'),
        ('DAYS', '${p.routine!.days.length}'),
        ('TRIES', '${p.recommends}'),
      ];
    }
    if (p.steps != null) {
      return [
        ('STEPS', compactSteps(p.steps!)),
        ('LIKES', '${p.likes}'),
        ('RECS', '${p.recommends}'),
      ];
    }
    return [
      ('LIKES', '${p.likes}'),
      ('COMMENTS', '${p.comments}'),
      ('RECS', '${p.recommends}'),
    ];
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}

// =============================================================== nutrition
class _Nutrition extends ConsumerWidget {
  const _Nutrition();

  Future<void> _logMeal(BuildContext context, WidgetRef ref) async {
    final kcal = TextEditingController();
    final protein = TextEditingController();
    final carbs = TextEditingController();
    final fat = TextEditingController();
    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          labelStyle: Noc.small,
          isDense: true,
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Noc.rControl), borderSide: const BorderSide(color: Noc.line)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Noc.rControl), borderSide: const BorderSide(color: Noc.accent)),
        );

    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Noc.scrim,
      builder: (_) => AlertDialog(
        backgroundColor: Noc.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Noc.muted)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Log a meal', style: Noc.name),
            const SizedBox(height: 4),
            const Text('Stays on this device.', style: Noc.small),
            const SizedBox(height: 14),
            TextField(controller: kcal, keyboardType: TextInputType.number, autofocus: true, style: Noc.body, decoration: deco('Calories')),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: protein, keyboardType: TextInputType.number, style: Noc.body, decoration: deco('Protein g'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: carbs, keyboardType: TextInputType.number, style: Noc.body, decoration: deco('Carbs g'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: fat, keyboardType: TextInputType.number, style: Noc.body, decoration: deco('Fat g'))),
            ]),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(fontFamily: 'Inter', color: Noc.dim))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add', style: TextStyle(fontFamily: 'Inter', color: Noc.accent))),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(nutritionProvider.notifier).log(
          kcal: int.tryParse(kcal.text) ?? 0,
          protein: int.tryParse(protein.text) ?? 0,
          carbs: int.tryParse(carbs.text) ?? 0,
          fat: int.tryParse(fat.text) ?? 0,
        );
    if (context.mounted) nocToast(context, 'Logged.');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(nutritionProvider);
    final target = ref.watch(calorieTargetProvider);
    final fmt = NumberFormat.decimalPattern();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NocSectionHead('Nutrition', note: 'Log a meal', onNote: () => _logMeal(context, ref)),
        const SizedBox(height: 11),
        NocCard(
          onTap: () => _logMeal(context, ref),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  const Expanded(child: Text('Calories today', style: Noc.metaMuted)),
                  Text('${fmt.format(day.kcal)} / ${fmt.format(target)}', style: Noc.metaDim),
                ],
              ),
              const SizedBox(height: 9),
              NocBar(pct: target == 0 ? 0 : day.kcal / target),
              const SizedBox(height: 12),
              Row(
                children: [
                  _Macro(value: '${day.protein}g', label: 'Protein'),
                  const SizedBox(width: 8),
                  _Macro(value: '${day.carbs}g', label: 'Carbs'),
                  const SizedBox(width: 8),
                  _Macro(value: '${day.fat}g', label: 'Fat'),
                ],
              ),
              const SizedBox(height: 8),
              Text('Target estimated from your height, weight, age, goal and training days.', style: Noc.small),
            ],
          ),
        ),
      ],
    );
  }
}

class _Macro extends StatelessWidget {
  const _Macro({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(color: Noc.sunken, borderRadius: BorderRadius.circular(Noc.rIcon)),
          child: Column(children: [
            Text(value, style: const TextStyle(fontFamily: 'Inter', fontSize: 13.5, color: Noc.text)),
            const SizedBox(height: 1),
            Text(label, style: Noc.tiny),
          ]),
        ),
      );
}

// ============================================================ account list
class _AccountList extends ConsumerWidget {
  const _AccountList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final steps = ref.watch(stepsProvider);
    final connected = (steps.value ?? const []).isNotEmpty;
    final me = ref.watch(profileProvider)!;
    final isMod = ref.watch(isModeratorProvider);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: Noc.card(),
      child: Column(
        children: [
          _AccountRow(
            icon: Nx.heart,
            iconColor: Noc.accent,
            title: defaultTargetPlatform == TargetPlatform.iOS ? 'Apple Health' : 'Health Connect',
            subtitle: connected ? 'Steps only — nothing else is read' : 'Not connected',
            trailing: NocToggle(
              value: connected,
              onChanged: (v) {
                if (v) {
                  ref.read(stepsProvider.notifier).connect();
                } else {
                  nocToast(context, 'Turn steps off in your phone’s health settings.');
                }
              },
            ),
          ),
          const _AccountDivider(),
          _AccountRow(
            icon: Nx.usersThree,
            title: 'Chase a goal together',
            subtitle: 'A shared CoG quest with one friend',
            onTap: () => showCogSheet(context),
          ),
          const _AccountDivider(),
          _AccountRow(
            icon: Nx.listBullets,
            title: 'Exercise library',
            subtitle: '1,443 exercises, graded and searchable',
            onTap: () => context.push('/explore'),
          ),
          const _AccountDivider(),
          _AccountRow(
            icon: Nx.clipboardText,
            iconColor: Noc.accent,
            title: 'Coach dashboard',
            subtitle: me.creator ? 'Views, tries and your published work' : 'For trainers, studios and clubs',
            onTap: () => context.push('/studio'),
          ),
          if (isMod) ...[
            const _AccountDivider(),
            _AccountRow(
              icon: Nx.shieldCheck,
              title: 'Moderation queue',
              subtitle: 'Reports and automated flags',
              onTap: () => context.push('/moderation'),
            ),
          ],
          const _AccountDivider(),
          _AccountRow(
            icon: Nx.gear,
            title: 'Profile & settings',
            subtitle: 'Body stats, equipment, AI trainer, account',
            onTap: () => context.push('/settings'),
          ),
        ],
      ),
    );
  }
}

class _AccountDivider extends StatelessWidget {
  const _AccountDivider();
  @override
  Widget build(BuildContext context) => Container(height: 1, color: Noc.divider);
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.icon, required this.title, required this.subtitle, this.trailing, this.onTap, this.iconColor});
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        hoverColor: const Color(0xFF282B38),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(icon, size: 17, color: iconColor ?? Noc.neutral400),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Noc.rowTitle),
                    Text(subtitle, style: Noc.meta, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              trailing ?? Icon(Nx.caretRight, size: 16, color: Noc.neutral700),
            ],
          ),
        ),
      );
}
