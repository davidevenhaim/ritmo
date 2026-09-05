import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/models.dart';
import '../../core/providers.dart';

/// One league's table for the current week (v0.4). Single-series bars in the
/// mint step colour, my row highlighted, a seven-day strip per member.
class LeagueDetailScreen extends ConsumerWidget {
  const LeagueDetailScreen({super.key, required this.leagueId, this.league});
  final String leagueId;
  final League? league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(profileProvider)!;
    final l = league ?? ref.watch(leaguesProvider).value?.where((x) => x.id == leagueId).firstOrNull;
    final standings = ref.watch(standingsProvider(leagueId));
    final t = Theme.of(context).textTheme;
    final daysLeft = 8 - DateTime.now().weekday;

    return Scaffold(
      appBar: AppBar(
        title: Text(l == null ? 'League' : '${l.emoji} ${l.name}'),
        actions: [
          IconButton(onPressed: () => ref.invalidate(standingsProvider(leagueId)), icon: const Icon(Icons.refresh)),
          PopupMenuButton<String>(
            color: SoColors.surface2,
            onSelected: (v) async {
              if (v == 'leave') {
                await ref.read(leaguesProvider.notifier).leave(leagueId);
                if (context.mounted) {
                  context.pop();
                  toast(context, 'Left ${l?.name ?? 'the league'}');
                }
              }
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'leave', child: Text('Leave league'))],
          ),
        ],
      ),
      body: standings.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => EmptyState(emoji: '🔒', title: 'Members only', body: '$e'),
        data: (rows) {
          final leader = rows.isEmpty ? 0 : rows.first.steps;
          final mine = rows.where((r) => r.userId == me.id).firstOrNull;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              if (l != null)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: SoColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: SoColors.line)),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('INVITE CODE', style: t.labelSmall),
                        Text(l.inviteCode, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 2, fontFeatures: [FontFeature.tabularFigures()])),
                        Text('${rows.length} of ${l.maxMembers} members · $daysLeft day${daysLeft == 1 ? '' : 's'} left', style: t.bodySmall),
                      ]),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: 'Join my Ritmo step league "${l.name}" with code ${l.inviteCode}'));
                        if (context.mounted) toast(context, 'Invite copied');
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Share'),
                    ),
                  ]),
                ),
              const SizedBox(height: 12),
              if (mine != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    mine.rank == 1
                        ? 'You are leading. Keep walking.'
                        : 'You are #${mine.rank}, ${compact(leader - mine.steps)} steps behind the leader.',
                    style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              const SectionTitle('This week'),
              for (final r in rows) _StandingRow(row: r, leader: leader, isMe: r.userId == me.id),
              const SizedBox(height: 16),
              Text('Steps come from your health app each time Ritmo opens. Only league members see each other\'s daily counts.', style: t.bodySmall, textAlign: TextAlign.center),
            ],
          );
        },
      ),
    );
  }
}

class _StandingRow extends StatelessWidget {
  const _StandingRow({required this.row, required this.leader, required this.isMe});
  final Standing row;
  final int leader;
  final bool isMe;

  static const _dow = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final pct = leader == 0 ? 0.0 : (row.steps / leader).clamp(0.0, 1.0);
    final rankColor = switch (row.rank) { 1 => SoColors.amber, 2 => SoColors.mint, 3 => SoColors.violet, _ => SoColors.muted };
    final maxDay = row.days.fold(0, (m, v) => v > m ? v : m);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isMe ? SoColors.mintSoft : SoColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isMe ? SoColors.mint : SoColors.line),
      ),
      child: InkWell(
        onTap: () => context.push('/u/${row.userId}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              SizedBox(width: 26, child: Text('${row.rank}', style: TextStyle(fontWeight: FontWeight.w800, color: rankColor, fontSize: 16, fontFeatures: const [FontFeature.tabularFigures()]))),
              Avatar(row.emoji, size: 34, ring: row.rank == 1),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(isMe ? '${row.name} (you)' : row.name, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('@${row.handle}', style: t.bodySmall),
                ]),
              ),
              Text(compact(row.steps), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: pct, minHeight: 6, backgroundColor: SoColors.line, color: SoColors.mint),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Tooltip(
                      message: '${_dow[i]}: ${row.days.length > i ? row.days[i] : 0} steps',
                      child: Column(children: [
                        Container(
                          height: 4 + 18 * (maxDay == 0 || row.days.length <= i ? 0 : row.days[i] / maxDay),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(color: SoColors.mint.withValues(alpha: 0.7), borderRadius: const BorderRadius.vertical(top: Radius.circular(2))),
                        ),
                        Text(_dow[i], style: t.bodySmall?.copyWith(fontSize: 10)),
                      ]),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
