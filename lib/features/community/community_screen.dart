import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/nocturne.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/social_repository.dart';

/// Community (v0.9, Nocturne handoff screens community-1 and community-2).
///
/// The paying side of Ritmo, and the only page where money is mentioned:
/// studios sell their timetable, coaches publish programmes, and the AI coach
/// sits above both because it is the one that is always on.
class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key});
  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends ConsumerState<CommunityScreen> {
  bool _coaches = false;

  @override
  Widget build(BuildContext context) {
    final social = ref.watch(socialProvider);
    final coaches = social.users.values.where((u) => u.creator).toList()..sort((a, b) => b.followers.compareTo(a.followers));

    return Scaffold(
      backgroundColor: Noc.bg,
      body: SafeArea(
        bottom: false,
        child: NocIn(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Noc.gutter, 8, Noc.gutter, 110),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text('Community', style: Noc.screenTitle),
              ),
              Row(
                children: [
                  _Pill(label: 'Studios', selected: !_coaches, onTap: () => setState(() => _coaches = false)),
                  const SizedBox(width: 8),
                  _Pill(label: 'Coaches', selected: _coaches, onTap: () => setState(() => _coaches = true)),
                ],
              ),
              const SizedBox(height: 14),
              const _AiCoachCard(),
              const SizedBox(height: 14),
              // The AI coach publishes like any other coach: its programme is
              // built for this athlete alone, so it leads the list.
              if (_coaches) ...[
                const _AiCoachProgrammeCard(),
                const SizedBox(height: 12),
              ],
              if (!_coaches)
                for (final s in SeedData.studios)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _StudioCard(studio: s),
                  )
              else ...[
                for (final c in coaches)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _CoachCard(coach: c),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('Coaches publish from the creator studio. Anyone can apply from Me → Account.', style: Noc.small),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: selected ? Noc.accent900 : Colors.transparent,
        borderRadius: BorderRadius.circular(Noc.rControl),
        border: Border.all(color: selected ? Noc.accent : Noc.line),
      ),
      child: Text(
        label,
        style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontVariations: Noc.w500, color: selected ? Noc.accent300 : Noc.muted),
      ),
    ),
  );
}

// ================================================================ AI coach
class _AiCoachCard extends StatelessWidget {
  const _AiCoachCard();

  @override
  Widget build(BuildContext context) => NocCard(
    border: Border.all(color: Noc.accent700),
    gradient: const LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [Noc.accent900, Noc.surface]),
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
    onTap: () => context.push('/coach'),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Noc.accent800, borderRadius: BorderRadius.circular(Noc.rControl)),
          child: const Icon(Nx.sparkle, size: 19, color: Noc.accent200),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ALWAYS ON', style: Noc.kickerAccent),
              SizedBox(height: 2),
              Text('Ask the AI coach', style: Noc.cardTitle),
              SizedBox(height: 1),
              Text('Tap a question · free for trainees, always', style: Noc.small),
            ],
          ),
        ),
        const Icon(Nx.caretRight, size: 16, color: Noc.dim),
      ],
    ),
  );
}

// ================================================ the AI coach's programme
/// The AI coach as a coach: it publishes one programme, built for this
/// athlete out of their own profile, and it opens in the preview like any
/// other shared routine — see every exercise before you take it on.
class _AiCoachProgrammeCard extends ConsumerWidget {
  const _AiCoachProgrammeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(profileProvider);
    final plan = ref.watch(aiCoachPlanProvider);
    final mine = ref.watch(routinesProvider);

    return NocCard(
      border: Border.all(color: Noc.accent700),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Noc.accent800, borderRadius: BorderRadius.circular(Noc.rControl)),
                child: const Icon(Nx.sparkle, size: 20, color: Noc.accent200),
              ),
              const SizedBox(width: 11),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ritmo AI Coach', style: Noc.planTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('Writes you a plan from your profile · free, always', style: Noc.small, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              NocTag('Free'),
            ],
          ),
          const SizedBox(height: 11),
          if (plan == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(me == null ? 'Finish your profile and a plan shows up here.' : 'Reading the catalogue…', style: Noc.metaDim),
            )
          else ...[
            _CoachRoutineRow(routine: plan, added: mine.any((x) => x.name == plan.name)),
            const SizedBox(height: 8),
            Text('Your goal and your gear: ${me!.goal.label.toLowerCase()}, ${me.daysPerWeek} days a week.', style: Noc.small),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}

// ================================================================= studios
class _StudioCard extends ConsumerWidget {
  const _StudioCard({required this.studio});
  final Studio studio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booked = ref.watch(bookedClassesProvider);
    return NocCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(Noc.rCard - 1)),
            child: SizedBox(
              height: 96,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const NocStripes(bloom: true),
                  Positioned(top: 10, right: 10, child: NocTag(studio.kind, style: NocTagStyle.outline)),
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 10,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(studio.name, style: Noc.planTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(studio.where, style: Noc.metaDim),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Column(
              children: [for (final k in studio.classes) _ClassRow(studio: studio, klass: k, booked: booked.contains(k.id))],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClassRow extends ConsumerWidget {
  const _ClassRow({required this.studio, required this.klass, required this.booked});
  final Studio studio;
  final StudioClass klass;
  final bool booked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final at = klass.nextAt();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(DateFormat.Hm().format(at), style: Noc.cardTitle),
                Text(DateFormat.E().format(at), style: Noc.small),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(klass.name, style: Noc.rowTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(klass.meta, style: Noc.small, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          NocButton(
            label: booked ? 'Booked' : 'Join',
            dense: true,
            primary: !booked,
            onTap: () => booked ? _cancel(context, ref) : _join(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _join(BuildContext context, WidgetRef ref) async {
    final ok = await showBookingSheet(context, studio: studio, klass: klass);
    if (ok != true || !context.mounted) return;
    final s = await ref.read(scheduleProvider.notifier).book(studio: studio, klass: klass);
    if (!context.mounted) return;
    nocToast(context, 'Booked ${klass.name} · ${DateFormat('EEE d MMM, HH:mm').format(s.at)}. It is on your plan.');
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    await ref.read(scheduleProvider.notifier).cancelClass(klass.id);
    if (!context.mounted) return;
    nocToast(context, 'Booking cancelled.');
  }
}

/// Confirm a class before it lands on the plan. The studio takes the money at
/// the door: Ritmo shows the price and never asks for a card.
Future<bool?> showBookingSheet(BuildContext context, {required Studio studio, required StudioClass klass}) {
  final at = klass.nextAt();
  return showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    backgroundColor: Noc.sheet,
    barrierColor: Noc.scrim,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Noc.rSheet))),
    builder: (sheet) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(color: Noc.line, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text(klass.name, style: Noc.pageTitle.copyWith(fontSize: 20)),
            const SizedBox(height: 4),
            Text('${studio.name} · ${DateFormat('EEE d MMM, HH:mm').format(at)}', style: Noc.bodyMuted),
            Text(klass.meta, style: Noc.metaDim),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: Noc.sunken,
                borderRadius: BorderRadius.circular(Noc.rRow),
                border: Border.all(color: Noc.line),
              ),
              child: Row(
                children: [
                  const Expanded(child: Text('Drop-in price', style: Noc.rowTitle)),
                  Text(klass.price, style: Noc.statSm),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text('Paid at the studio. Ritmo never asks for card details.', style: Noc.small),
            const SizedBox(height: 14),
            NocButton(label: 'Book the spot', icon: Nx.calendarCheck, block: true, onTap: () => Navigator.pop(sheet, true)),
          ],
        ),
      ),
    ),
  );
}

// ================================================================= coaches
class _CoachCard extends ConsumerWidget {
  const _CoachCard({required this.coach});
  final SocialUser coach;

  /// What this coach publishes: their programmes plus anything they have
  /// shared to the feed, de-duplicated.
  List<Routine> _routines(SocialState social) {
    final out = <String, Routine>{
      for (final r in SeedData.coachProgrammes)
        if (r.authorId == coach.id) r.id: r,
    };
    for (final p in social.posts) {
      if (p.routine != null && p.authorId == coach.id) out[p.routine!.id] = p.routine!;
    }
    return out.values.toList();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final social = ref.watch(socialProvider);
    final following = social.following.contains(coach.id);
    final routines = _routines(social);
    final mine = ref.watch(routinesProvider);

    return NocCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(onTap: () => context.push('/u/${coach.id}'), child: NocFace(coach.emoji, size: 42)),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(coach.name, style: Noc.planTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      '${coach.bio.split('.').first} · ${compactCount(coach.followers)} athletes',
                      style: Noc.small,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              NocButton(
                label: following ? 'Following' : 'Follow',
                dense: true,
                primary: !following,
                onTap: () => ref.read(socialProvider.notifier).toggleFollow(coach.id),
              ),
            ],
          ),
          const SizedBox(height: 11),
          for (final r in routines)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _CoachRoutineRow(routine: r, added: mine.any((x) => x.name == r.name)),
            ),
          if (routines.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('Nothing published yet.', style: Noc.metaDim),
            ),
        ],
      ),
    );
  }
}

class _CoachRoutineRow extends ConsumerWidget {
  const _CoachRoutineRow({required this.routine, required this.added});
  final Routine routine;
  final bool added;

  /// Rough length of the routine, the same estimate the plan uses.
  int get minutes {
    var sec = 0;
    for (final d in routine.days) {
      for (final i in d.items) {
        sec += i.sets * (i.restSec + 40);
      }
    }
    return (sec / 60).round();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    // The row is the session: tapping it starts the workout. Looking inside
    // first — every exercise, the level switcher, saving it — is what "View
    // more" opens.
    onTap: () => context.push('/workout/${routine.id}', extra: routine),
    child: Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 9, 9),
      decoration: BoxDecoration(color: Noc.sunken, borderRadius: BorderRadius.circular(Noc.rRow)),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Noc.accent800, borderRadius: BorderRadius.circular(Noc.rIcon)),
            child: const Icon(Nx.play, size: 14, color: Noc.accent200),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(routine.name, style: Noc.rowTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 1),
                Text(
                  '${routine.exerciseCount} exercises · $minutes min${added ? ' · saved' : ''}',
                  style: Noc.small,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          NocButton(
            label: 'View more',
            primary: false,
            dense: true,
            onTap: () => context.push('/routine/${routine.id}', extra: routine),
          ),
        ],
      ),
    ),
  );
}

String compactCount(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}k' : '$n';
