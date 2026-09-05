import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/social_backend.dart';

/// My weekly step leagues (v0.4): rank pill per league, create or join.
class LeaguesScreen extends ConsumerWidget {
  const LeaguesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leagues = ref.watch(leaguesProvider);
    final ranks = ref.watch(leagueRanksProvider).value ?? const <LeagueRank>[];
    final remote = ref.watch(socialBackendProvider).isRemote;
    final t = Theme.of(context).textTheme;
    final daysLeft = 8 - DateTime.now().weekday;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Leagues'),
        actions: [IconButton(onPressed: () => ref.invalidate(leaguesProvider), icon: const Icon(Icons.refresh))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createOrJoin(context, ref),
        backgroundColor: SoColors.coral,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New or join'),
      ),
      body: leagues.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => EmptyState(emoji: '⚠️', title: 'Could not load leagues', body: '$e'),
        data: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: SoColors.mintSoft, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                const Icon(Icons.emoji_events_outlined, color: SoColors.mint),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Weekly step leagues, Monday to Sunday. $daysLeft day${daysLeft == 1 ? '' : 's'} left this week. '
                    '${remote ? 'Results land Monday morning with a badge for the podium.' : 'Demo: join Deadlift Club with code ${LocalSocialBackend.seedJoinCode}.'}',
                    style: t.bodySmall?.copyWith(color: SoColors.text),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            if (list.isEmpty)
              const EmptyState(emoji: '🏆', title: 'No leagues yet', body: 'Start one and share the code, or join a friend\'s.')
            else
              for (final l in list) ...[
                _LeagueCard(league: l, rank: ranks.where((r) => r.leagueId == l.id).firstOrNull),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }

  Future<void> _createOrJoin(BuildContext context, WidgetRef ref) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const _CreateJoinSheet(),
      );
}

class _LeagueCard extends ConsumerWidget {
  const _LeagueCard({required this.league, this.rank});
  final League league;
  final LeagueRank? rank;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final r = rank;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push('/leagues/${league.id}', extra: league),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Text(league.emoji, style: const TextStyle(fontSize: 30)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(league.name, style: t.titleMedium),
                    Text(
                      r == null
                          ? '${league.memberCount} member${league.memberCount == 1 ? '' : 's'}'
                          : '${compact(r.steps)} steps · ${r.rank == 1 ? 'leading' : '${compact(r.gapToLeader)} behind'} · ${r.of} members',
                      style: t.bodySmall,
                    ),
                  ],
                ),
              ),
              if (r != null && r.rank > 0) _RankPill(rank: r.rank),
              const Icon(Icons.chevron_right, color: SoColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _RankPill extends StatelessWidget {
  const _RankPill({required this.rank});
  final int rank;
  @override
  Widget build(BuildContext context) {
    final color = switch (rank) { 1 => SoColors.amber, 2 => SoColors.mint, 3 => SoColors.violet, _ => SoColors.muted };
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(999)),
      child: Text('#$rank', style: TextStyle(fontWeight: FontWeight.w800, color: color, fontFeatures: const [FontFeature.tabularFigures()])),
    );
  }
}

class _CreateJoinSheet extends ConsumerStatefulWidget {
  const _CreateJoinSheet();
  @override
  ConsumerState<_CreateJoinSheet> createState() => _CreateJoinSheetState();
}

class _CreateJoinSheetState extends ConsumerState<_CreateJoinSheet> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  String _emoji = '🏆';
  bool _busy = false;

  static const _emojis = ['🏆', '🥪', '🏋️', '🐢', '🚶', '⚡', '🌄', '🐕', '🏢', '🎯'];

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<League> Function() action, String verb) async {
    setState(() => _busy = true);
    try {
      final l = await action();
      if (!mounted) return;
      Navigator.of(context).pop();
      toast(context, '$verb ${l.name}. Code ${l.inviteCode}');
      context.push('/leagues/${l.id}', extra: l);
    } catch (e) {
      if (mounted) toast(context, e.toString().replaceFirst('Bad state: ', '').replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Start a league', style: t.titleLarge),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: [for (final e in _emojis) ChoiceChip(label: Text(e), selected: _emoji == e, onSelected: (_) => setState(() => _emoji = e))],
            ),
            const SizedBox(height: 8),
            TextField(controller: _name, maxLength: 40, decoration: const InputDecoration(hintText: 'League name, e.g. Office walkers', counterText: ''), textCapitalization: TextCapitalization.sentences),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy || _name.text.trim().isEmpty ? null : () => _run(() => ref.read(leaguesProvider.notifier).create(_name.text, _emoji), 'Created'),
                child: const Text('Create and get a code'),
              ),
            ),
            const Divider(height: 28),
            Text('Join with a code', style: t.titleLarge),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 6,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(hintText: '6-letter code', counterText: ''),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _busy || _code.text.trim().length < 6 ? null : () => _run(() => ref.read(leaguesProvider.notifier).join(_code.text), 'Joined'),
                style: FilledButton.styleFrom(backgroundColor: SoColors.mint, foregroundColor: SoColors.ink),
                child: const Text('Join'),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
