import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/nocturne.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../feed/comments_sheet.dart';
import '../home/me_screen.dart' show compactSteps;
import '../home/plus_menu.dart';

/// Friends (v0.8). Reached from the top of Me, not from a tab: it is a place
/// you visit when you want somebody with you.
///
/// The order is the point. Inviting a friend to a training comes first —
/// that is the thing worth doing here — and the feed of what everyone has
/// been up to sits underneath it.
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});
  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  bool _routines = false;

  @override
  Widget build(BuildContext context) {
    final social = ref.watch(socialProvider);
    final invites = ref.watch(trainingInvitesProvider);
    final posts = social.posts.where((p) => social.following.contains(p.authorId)).toList();
    final theirRoutines = [
      for (final p in social.posts)
        if (p.routine != null && social.following.contains(p.authorId)) (p.routine!, p.authorId),
    ];

    return Scaffold(
      backgroundColor: Noc.bg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: Noc.accent,
          backgroundColor: Noc.surface,
          onRefresh: () => ref.read(socialProvider.notifier).refresh(),
          child: NocIn(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Noc.gutter, 0, Noc.gutter, 32),
              children: [
                const _Header(),
                const _InviteCard(),
                if (invites.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  NocSectionHead('Training together', note: '${invites.length}'),
                  for (final s in invites)
                    Padding(padding: const EdgeInsets.only(top: 10), child: _InviteRow(session: s)),
                ],
                const SizedBox(height: 24),
                Row(children: [
                  Expanded(child: Text('Their week', style: Noc.sectionTitle)),
                  _Segmented(
                    routines: _routines,
                    onChanged: (v) => setState(() => _routines = v),
                  ),
                ]),
                const SizedBox(height: 12),
                if (social.following.isEmpty)
                  _Empty(
                    title: 'Nobody here yet',
                    body: 'Follow a few people and their sessions and routines land here.',
                    action: 'Find people',
                    onAction: () => context.push('/discover'),
                  )
                else if (!_routines) ...[
                  if (posts.isEmpty)
                    const _Empty(title: 'Quiet in here', body: 'Nothing new from the people you follow.')
                  else
                    for (final p in posts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _FeedPost(post: p, author: social.users[p.authorId]),
                      ),
                ] else ...[
                  if (theirRoutines.isEmpty)
                    const _Empty(title: 'No routines shared yet', body: 'When a friend shares a routine you can copy it in one tap.')
                  else
                    for (final (r, authorId) in theirRoutines)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _SharedRoutine(routine: r, author: social.users[authorId]),
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

// ================================================================== header
class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(socialProvider).unread;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 18),
      child: Row(
        children: [
          NocIconButton(
            icon: Nx.arrowLeft,
            tooltip: 'Back',
            // Deep links land here with nothing to pop back to.
            onTap: () => context.canPop() ? context.pop() : context.go('/home'),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text('Friends', style: Noc.pageTitle)),
          Stack(
            clipBehavior: Clip.none,
            children: [
              NocIconButton(icon: Nx.bell, tooltip: 'Activity', onTap: () => context.push('/notifications')),
              if (unread > 0)
                Positioned(
                  right: 7,
                  top: 7,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(color: Noc.accent, shape: BoxShape.circle, border: Border.all(color: Noc.bg)),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),
          NocIconButton(icon: Nx.magnifyingGlass, tooltip: 'Find people', onTap: () => context.push('/discover')),
        ],
      ),
    );
  }
}

// ================================================================== invite
/// Invite to a training: who, then which session, then send. The session is
/// one that already sits on my plan — an invite is never a second calendar.
class _InviteCard extends ConsumerStatefulWidget {
  const _InviteCard();
  @override
  ConsumerState<_InviteCard> createState() => _InviteCardState();
}

class _InviteCardState extends ConsumerState<_InviteCard> {
  final _picked = <String>{};
  String? _sessionId;
  bool _busy = false;

  /// Everyone I follow first, then the rest of the people the app knows.
  List<SocialUser> _people(SocialState social, String meId) {
    final list = social.users.values.where((u) => u.id != meId).toList()
      ..sort((a, b) {
        final fa = social.following.contains(a.id) ? 0 : 1;
        final fb = social.following.contains(b.id) ? 0 : 1;
        return fa != fb ? fa - fb : a.name.compareTo(b.name);
      });
    return list;
  }

  /// Whatever the schedule sheet just added becomes the selected session.
  Future<void> _newSession() async {
    final added = await showScheduleSheet(context);
    if (!mounted || added == null) return;
    setState(() => _sessionId = added.id);
  }

  Future<void> _send(ScheduledWorkout session, List<SocialUser> friends) async {
    setState(() => _busy = true);
    final me = ref.read(profileProvider)!;
    final updated = await ref.read(scheduleProvider.notifier).invite(sessionId: session.id, friends: friends);
    final text = ref.read(scheduleProvider.notifier).inviteText(updated, me);
    try {
      await Clipboard.setData(ClipboardData(text: text)).timeout(const Duration(seconds: 2));
    } catch (_) {
      // An unfocused web tab can refuse the clipboard; the invite still stands.
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _picked.clear();
    });
    final names = friends.map((f) => f.name.split(' ').first).join(', ');
    nocToast(context, updated.guests.every((g) => g.accepted) ? '$names is in. Invite copied.' : 'Invite copied. Send it to $names.');
  }

  @override
  Widget build(BuildContext context) {
    final social = ref.watch(socialProvider);
    final me = ref.watch(profileProvider)!;
    final people = _people(social, me.id);
    final sessions = ref.watch(upcomingWorkoutsProvider);
    final session = sessions.where((s) => s.id == _sessionId).firstOrNull ?? sessions.firstOrNull;
    final friends = [for (final id in _picked) ?social.users[id]];
    final ready = friends.isNotEmpty && session != null && !_busy;

    return NocCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Noc.accent900, borderRadius: BorderRadius.circular(Noc.rIcon)),
              child: const Icon(Nx.calendarPlus, size: 16, color: Noc.accent300),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Invite to a training', style: Noc.cardTitle),
                Text('Pick who, pick when. They get the session and the time.', style: Noc.small),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          Text('WHO', style: Noc.columnLabel),
          const SizedBox(height: 8),
          if (people.isEmpty)
            Text('No people yet. Find somebody on Discover first.', style: Noc.metaDim)
          else
            SizedBox(
              height: 68,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.zero,
                children: [
                  for (final u in people)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _picked.contains(u.id) ? _picked.remove(u.id) : _picked.add(u.id)),
                        child: SizedBox(
                          width: 52,
                          child: Column(children: [
                            NocFace(u.emoji, size: 42, selected: _picked.contains(u.id)),
                            const SizedBox(height: 5),
                            Text(
                              u.name.split(' ').first,
                              style: Noc.small.copyWith(color: _picked.contains(u.id) ? Noc.accent300 : Noc.dim),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ]),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          Text('WHEN', style: Noc.columnLabel),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in sessions.take(6))
                _WhenChip(
                  label: '${s.dayTitle.isEmpty ? s.routineName : s.dayTitle} · ${DateFormat('EEE').format(s.at)} ${DateFormat.jm().format(s.at)}',
                  selected: s.id == session?.id,
                  onTap: () => setState(() => _sessionId = s.id),
                ),
              _WhenChip(
                label: 'New session',
                icon: Nx.plus,
                onTap: _newSession,
              ),
            ],
          ),
          const SizedBox(height: 14),
          NocButton(
            block: true,
            icon: Nx.paperPlaneTilt,
            label: friends.isEmpty
                ? 'Pick a friend'
                : session == null
                    ? 'Pick a session'
                    : 'Invite ${friends.map((f) => f.name.split(' ').first).join(', ')}',
            onTap: !ready ? null : () => _send(session, friends),
          ),
        ],
      ),
    );
  }
}

class _WhenChip extends StatelessWidget {
  const _WhenChip({required this.label, required this.onTap, this.selected = false, this.icon});
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Noc.accent900 : Colors.transparent,
            borderRadius: BorderRadius.circular(Noc.rControl),
            border: Border.all(color: selected ? Noc.accent : Noc.line),
          ),
          constraints: const BoxConstraints(maxWidth: 240),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 13, color: Noc.dim), const SizedBox(width: 6)],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: 'Inter', fontSize: 11.5, color: selected ? Noc.accent200 : Noc.muted),
              ),
            ),
          ]),
        ),
      );
}

/// A session somebody else is coming to.
class _InviteRow extends ConsumerWidget {
  const _InviteRow({required this.session});
  final ScheduledWorkout session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waiting = session.guests.where((g) => !g.accepted).length;
    return NocCard(
      radius: Noc.rRow,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      // Tapping an invite shows the session, it does not start it. A booked
      // class has no routine behind it, so it goes back to Community.
      onTap: () => session.isClass
          ? context.push('/community')
          : context.push('/routine/${session.routineId}?day=${session.dayIndex}'),
      child: Row(
        children: [
          Container(width: 3, height: 32, decoration: BoxDecoration(color: Noc.accent, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(session.routineName, style: Noc.cardTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  '${DateFormat('EEE d MMM').format(session.at)} · ${DateFormat.jm().format(session.at)} · '
                  '${session.guests.map((g) => g.firstName).join(', ')}'
                  '${waiting == 0 ? ' · coming' : ' · $waiting waiting'}',
                  style: Noc.meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          NocIconButton(
            icon: Nx.copySimple,
            size: 30,
            tooltip: 'Copy the invite again',
            onTap: () async {
              final me = ref.read(profileProvider)!;
              final text = ref.read(scheduleProvider.notifier).inviteText(session, me);
              try {
                await Clipboard.setData(ClipboardData(text: text)).timeout(const Duration(seconds: 2));
              } catch (_) {}
              if (context.mounted) nocToast(context, 'Invite copied.');
            },
          ),
        ],
      ),
    );
  }
}

// ==================================================================== feed
class _Segmented extends StatelessWidget {
  const _Segmented({required this.routines, required this.onChanged});
  final bool routines;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: Noc.sunken, borderRadius: BorderRadius.circular(Noc.rControl)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final (on, label) in [(false, 'Activity'), (true, 'Routines')])
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(on),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: routines == on ? Noc.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: routines == on ? Noc.line : Colors.transparent),
                ),
                child: Text(
                  label,
                  style: TextStyle(fontFamily: 'Inter', fontSize: 11.5, fontVariations: Noc.w500, color: routines == on ? Noc.text : Noc.dim),
                ),
              ),
            ),
        ]),
      );
}

class _FeedPost extends ConsumerWidget {
  const _FeedPost({required this.post, this.author});
  final Post post;
  final SocialUser? author;

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final social = ref.watch(socialProvider);
    final liked = social.liked.contains(post.id);
    return NocCard(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            GestureDetector(
              onTap: () => context.push('/u/${post.authorId}'),
              child: NocFace(author?.emoji ?? '🙂', size: 28),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(author?.name ?? 'Someone', style: const TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: Noc.text)),
            ),
            Text(_ago(post.createdAt), style: Noc.small),
          ]),
          const SizedBox(height: 9),
          Text(post.title, style: Noc.cardTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
          if (post.body.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(post.body, style: Noc.bodyMuted, maxLines: 3, overflow: TextOverflow.ellipsis),
          ],
          if (post.steps != null) ...[
            const SizedBox(height: 6),
            Text('${compactSteps(post.steps!)} steps', style: Noc.metaDim.copyWith(color: Noc.accent300)),
          ],
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.only(top: 4),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Noc.divider))),
            child: Row(children: [
              _Action(
                icon: Nx.heart,
                label: '${post.likes}',
                on: liked,
                onTap: () => ref.read(socialProvider.notifier).toggleLike(post.id),
              ),
              _Action(
                icon: Nx.chatCircle,
                label: '${post.comments}',
                onTap: () => CommentsSheet.show(context, post),
              ),
              const Spacer(),
              if (post.routine != null)
                _Action(
                  icon: Nx.listBullets,
                  label: 'See routine',
                  // Every exercise, its grade and the kit it needs, before
                  // anyone takes somebody else's programme on.
                  onTap: () => context.push('/routine/${post.routine!.id}', extra: post.routine),
                ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap, this.on = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool on;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: on ? Noc.accent : Noc.dim),
            const SizedBox(width: 6),
            Text(label, style: Noc.meta.copyWith(color: on ? Noc.accent300 : Noc.dim)),
          ]),
        ),
      );
}

/// A friend's routine. Looking inside comes first — the preview is where the
/// exercises, their grades and the level switcher live — with the one-tap copy
/// kept for a routine they already know.
class _SharedRoutine extends ConsumerWidget {
  const _SharedRoutine({required this.routine, this.author});
  final Routine routine;
  final SocialUser? author;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(profileProvider)!;
    final mine = ref.watch(routinesProvider).any((x) => x.name == routine.name && x.authorId == me.id);
    return NocCard(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
      onTap: () => context.push('/routine/${routine.id}', extra: routine),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            NocFace(author?.emoji ?? '🙂', size: 28),
            const SizedBox(width: 9),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(routine.name, style: Noc.cardTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  '${author?.name ?? routine.authorName} · ${routine.days.length} day${routine.days.length == 1 ? '' : 's'} · ${routine.exerciseCount} exercises',
                  style: Noc.small,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 11),
          Row(children: [
            Expanded(
              child: NocButton(
                label: 'Look inside',
                primary: false,
                dense: true,
                block: true,
                onTap: () => context.push('/routine/${routine.id}', extra: routine),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: NocButton(
                label: mine ? 'Copied' : 'Copy to mine',
                dense: true,
                block: true,
                icon: mine ? Nx.check : Nx.copySimple,
                onTap: mine ? null : () => copyRoutine(context, ref, routine),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

/// Copy a friend's routine into mine and open it.
Future<void> copyRoutine(BuildContext context, WidgetRef ref, Routine routine) async {
  final me = ref.read(profileProvider)!;
  final copy = await ref.read(routinesProvider.notifier).clone(routine, me);
  if (!context.mounted) return;
  nocToast(context, 'Copied to my routines');
  context.push('/workout/${copy.id}', extra: copy);
}

class _Empty extends StatelessWidget {
  const _Empty({required this.title, required this.body, this.action, this.onAction});
  final String title;
  final String body;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => NocCard(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Noc.cardTitle),
            const SizedBox(height: 4),
            Text(body, style: Noc.bodyMuted),
            if (action != null) ...[
              const SizedBox(height: 12),
              NocButton(label: action!, dense: true, onTap: onAction),
            ],
          ],
        ),
      );
}
