import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/nocturne.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/social_repository.dart';

/// The + button on the home page (v0.5). Four things a person does with the
/// app on their own terms; nothing here is required to use Ritmo.
// ================================================================ schedule
/// Put a session on the calendar. Returns the session it created, so a caller
/// that needs it next — the training invite on Friends — can pick it up.
Future<ScheduledWorkout?> showScheduleSheet(BuildContext context, {Routine? routine}) => showModalBottomSheet<ScheduledWorkout>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Noc.sheet,
      barrierColor: Noc.scrim,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Noc.rSheet))),
      builder: (_) => _ScheduleSheet(routine: routine),
    );

class _ScheduleSheet extends ConsumerStatefulWidget {
  const _ScheduleSheet({this.routine});
  final Routine? routine;
  @override
  ConsumerState<_ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends ConsumerState<_ScheduleSheet> {
  Routine? _routine;
  int _day = 0;
  late DateTime _at = _nextSlot();
  final _note = TextEditingController();

  /// Tonight if there is still an evening left, otherwise tomorrow morning.
  static DateTime _nextSlot() {
    final now = DateTime.now();
    final h = now.hour < 17 ? 18 : 8;
    final d = now.hour < 17 ? now : now.add(const Duration(days: 1));
    return DateTime(d.year, d.month, d.day, h);
  }

  @override
  void initState() {
    super.initState();
    _routine = widget.routine;
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (d != null) setState(() => _at = DateTime(d.year, d.month, d.day, _at.hour, _at.minute));
  }

  Future<void> _pickTime() async {
    final tm = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_at));
    if (tm != null) setState(() => _at = DateTime(_at.year, _at.month, _at.day, tm.hour, tm.minute));
  }

  @override
  Widget build(BuildContext context) {
    final mine = ref.watch(routinesProvider);
    final all = [...mine, ...SeedData.readyMade.where((c) => mine.every((m) => m.id != c.id))];
    final r = _routine ?? all.firstOrNull;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
          child: NocIn(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: Noc.line, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: Text('Schedule a workout', style: Noc.pageTitle.copyWith(fontSize: 20))),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    behavior: HitTestBehavior.opaque,
                    child: const SizedBox(width: 28, height: 28, child: Icon(Nx.x, size: 17, color: Noc.dim)),
                  ),
                ]),
                if (r == null) ...[
                  const SizedBox(height: 14),
                  const Text('No routines yet. Build one first and it lands here.', style: Noc.bodyMuted),
                  const SizedBox(height: 14),
                  NocButton(
                    label: 'Build a routine',
                    block: true,
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/build');
                    },
                  ),
                ] else ...[
                  const SizedBox(height: 16),
                  Text('ROUTINE', style: Noc.columnLabel),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final x in all)
                      _PickChip(
                        label: x.source == 'me' ? x.name : '${x.name} · ${x.authorName}',
                        selected: x.id == r.id,
                        onTap: () => setState(() {
                          _routine = x;
                          _day = 0;
                        }),
                      ),
                  ]),
                  if (r.days.length > 1) ...[
                    const SizedBox(height: 16),
                    Text('DAY', style: Noc.columnLabel),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final (i, d) in r.days.indexed)
                        _PickChip(label: d.title, selected: _day == i, onTap: () => setState(() => _day = i)),
                    ]),
                  ],
                  const SizedBox(height: 16),
                  Text('WHEN', style: Noc.columnLabel),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: NocButton(label: DateFormat('EEE d MMM').format(_at), icon: Nx.calendarBlank, primary: false, dense: true, block: true, onTap: _pickDate)),
                    const SizedBox(width: 8),
                    Expanded(child: NocButton(label: DateFormat.jm().format(_at), icon: Nx.clock, primary: false, dense: true, block: true, onTap: _pickTime)),
                  ]),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [
                    for (final (label, days) in [('Today', 0), ('Tomorrow', 1), ('In 2 days', 2)])
                      _PickChip(
                        label: label,
                        selected: _at.difference(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)).inDays == days,
                        onTap: () {
                          final d = DateTime.now().add(Duration(days: days));
                          setState(() => _at = DateTime(d.year, d.month, d.day, _at.hour, _at.minute));
                        },
                      ),
                  ]),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _note,
                    style: Noc.body,
                    maxLength: 60,
                    textCapitalization: TextCapitalization.sentences,
                    cursorColor: Noc.accent,
                    decoration: InputDecoration(
                      hintText: 'Note (optional): with Dana, go light…',
                      hintStyle: Noc.metaDim,
                      counterStyle: Noc.tiny,
                      filled: true,
                      fillColor: Noc.sunken,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Noc.rRow), borderSide: const BorderSide(color: Noc.line)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Noc.rRow), borderSide: const BorderSide(color: Noc.line)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Noc.rRow), borderSide: const BorderSide(color: Noc.accent700)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  NocButton(
                    label: 'Add to my schedule',
                    icon: Nx.calendarCheck,
                    block: true,
                    onTap: () async {
                      final s = await ref.read(scheduleProvider.notifier).add(routine: r, dayIndex: _day, at: _at, note: _note.text.trim());
                      if (!context.mounted) return;
                      Navigator.pop(context, s);
                      nocToast(context, '${r.name} on ${DateFormat('EEE d MMM').format(_at)} at ${DateFormat.jm().format(_at)}');
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A one-line choice: routine, day, or a quick date.
class _PickChip extends StatelessWidget {
  const _PickChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? Noc.accent900 : Colors.transparent,
            borderRadius: BorderRadius.circular(Noc.rControl),
            border: Border.all(color: selected ? Noc.accent : Noc.line),
          ),
          child: Text(label, style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: selected ? Noc.accent200 : Noc.muted)),
        ),
      );
}

// ===================================================================== CoG
Future<void> showCogSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => const _CogSheet(),
    );

/// "CoG together": pick one friend, pick a shared quest, send the invite.
class _CogSheet extends ConsumerStatefulWidget {
  const _CogSheet();
  @override
  ConsumerState<_CogSheet> createState() => _CogSheetState();
}

class _CogSheetState extends ConsumerState<_CogSheet> {
  String? _friend;
  int _preset = 0;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final social = ref.watch(socialProvider);
    final me = ref.watch(profileProvider)!;
    final people = social.users.values.where((u) => u.id != me.id).toList()
      ..sort((a, b) {
        final fa = social.following.contains(a.id) ? 0 : 1;
        final fb = social.following.contains(b.id) ? 0 : 1;
        return fa != fb ? fa - fb : a.name.compareTo(b.name);
      });
    final preset = questPresets[_preset];
    final canSend = _friend != null && !_busy;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          Text('CoG together', style: t.titleLarge),
          Text('A Common Goal you and one friend chase as a team. Both counters add up; nobody is ranked.', style: t.bodySmall),
          const SizedBox(height: 14),
          Text('WHO', style: t.labelSmall),
          const SizedBox(height: 6),
          if (people.isEmpty)
            Text('Follow someone on the feed first, or wait for the demo people to load.', style: t.bodySmall)
          else
            SizedBox(
              height: 92,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final u in people)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setState(() => _friend = u.id),
                        child: Container(
                          width: 76,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: _friend == u.id ? SoColors.coralSoft : SoColors.surface,
                            border: Border.all(color: _friend == u.id ? SoColors.coral : SoColors.line),
                          ),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Avatar(u.emoji, size: 44, ring: _friend == u.id),
                            const SizedBox(height: 4),
                            Text(u.name.split(' ').first, style: t.bodySmall?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ]),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          Text('QUEST', style: t.labelSmall),
          const SizedBox(height: 6),
          for (final (i, p) in questPresets.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() => _preset = i),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: _preset == i ? SoColors.mintSoft : SoColors.surface,
                    border: Border.all(color: _preset == i ? SoColors.mint : SoColors.line),
                  ),
                  child: Row(children: [
                    Text(p.kind.emoji, style: const TextStyle(fontSize: 24)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text('${p.blurb} ${p.days} days.', style: t.bodySmall),
                      ]),
                    ),
                    if (_preset == i) const Icon(Icons.check_circle, color: SoColors.mint),
                  ]),
                ),
              ),
            ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: !canSend
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      final friend = social.users[_friend]!;
                      final q = await ref.read(questsProvider.notifier).invite(friend: friend, preset: preset);
                      final text = ref.read(questsProvider.notifier).inviteText(q, me);
                      try {
                        await Clipboard.setData(ClipboardData(text: text)).timeout(const Duration(seconds: 2));
                      } catch (_) {
                        // Clipboard can be unavailable (unfocused web tab); the quest is still saved.
                      }
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      toast(context, q.accepted ? '${friend.name.split(' ').first} is in. Quest started.' : 'Invite copied. Send it to ${friend.name.split(' ').first}.');
                    },
              icon: const Icon(Icons.handshake_outlined),
              label: Text(_friend == null ? 'Pick a friend' : 'Start with ${social.users[_friend]?.name.split(' ').first}'),
            ),
          ),
        ],
      ),
    );
  }
}
