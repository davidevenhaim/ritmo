import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/models.dart';
import '../../core/providers.dart';

/// Report queue for moderators (v0.3). Oldest first; one decision resolves
/// every open report on the same target.
class ModerationScreen extends ConsumerStatefulWidget {
  const ModerationScreen({super.key});
  @override
  ConsumerState<ModerationScreen> createState() => _ModerationScreenState();
}

class _ModerationScreenState extends ConsumerState<ModerationScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await ref.read(socialProvider.notifier).loadReports();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final social = ref.watch(socialProvider);
    final isMod = ref.watch(isModeratorProvider);
    final remote = ref.watch(socialBackendProvider).isRemote;
    final t = Theme.of(context).textTheme;

    // Group by target so a pile-on shows as one card.
    final groups = <String, List<Report>>{};
    for (final r in social.reports) {
      groups.putIfAbsent('${r.target.name}:${r.targetId}', () => []).add(r);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Moderation'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: !isMod
          ? const EmptyState(emoji: '🔒', title: 'Moderators only', body: 'Ask an operator to flag your account.')
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              children: [
                if (!remote)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text('Demo build: everyone is a moderator here. On the hosted graph this needs the moderator flag.', style: t.bodySmall),
                  ),
                if (social.error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(social.error!, style: const TextStyle(color: SoColors.amber))),
                if (_loading)
                  const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                else if (groups.isEmpty)
                  const EmptyState(emoji: '🧹', title: 'Queue is empty', body: 'Nothing waiting for a decision.')
                else
                  for (final entry in groups.entries) ...[
                    _ReportCard(reports: entry.value),
                    const SizedBox(height: 12),
                  ],
              ],
            ),
    );
  }
}

class _ReportCard extends ConsumerWidget {
  const _ReportCard({required this.reports});
  final List<Report> reports;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final first = reports.first;
    final t = Theme.of(context).textTheme;
    final notifier = ref.read(socialProvider.notifier);
    final author = first.targetAuthorId == null ? null : notifier.userOf(first.targetAuthorId!);
    final automated = reports.any((r) => r.automated);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TagChip(first.target.name.toUpperCase(), color: SoColors.violet),
                const SizedBox(width: 6),
                if (first.targetHidden) const TagChip('HIDDEN', color: SoColors.amber),
                if (automated) ...[const SizedBox(width: 6), const TagChip('AUTO-SCREENED', color: SoColors.coral)],
                const Spacer(),
                Text('${reports.length} report${reports.length == 1 ? '' : 's'} · ${timeAgo(first.createdAt)}', style: t.bodySmall),
              ],
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: first.target == ReportTarget.profile || first.targetAuthorId == null ? null : () => context.push('/u/${first.targetAuthorId}'),
              child: Text(first.targetTitle, style: t.titleMedium),
            ),
            if (author != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('by ${author.name} · @${author.handle}', style: t.bodySmall),
              ),
            const Divider(height: 18),
            for (final r in reports)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(r.automated ? Icons.auto_awesome : Icons.flag_outlined, size: 16, color: r.automated ? SoColors.coral : SoColors.amber),
                    const SizedBox(width: 6),
                    Expanded(
                      child: RichText(
                        text: TextSpan(style: t.bodyMedium, children: [
                          TextSpan(text: r.reason.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                          TextSpan(text: r.automated ? ' · screener' : ' · @${notifier.userOf(r.reporterId!).handle}', style: t.bodySmall),
                          if (r.details.isNotEmpty) TextSpan(text: '\n${r.details}'),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in _actionsFor(first))
                  OutlinedButton(
                    onPressed: () => _decide(context, ref, first, a),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      foregroundColor: switch (a) {
                        ModerationAction.remove || ModerationAction.ban => SoColors.coral,
                        ModerationAction.dismiss || ModerationAction.restore => SoColors.mint,
                        _ => SoColors.text,
                      },
                    ),
                    child: Text(a.label),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<ModerationAction> _actionsFor(Report r) => switch (r.target) {
        ReportTarget.post => [
            ModerationAction.dismiss,
            if (r.targetHidden) ModerationAction.restore else ModerationAction.hide,
            ModerationAction.warn,
            ModerationAction.remove,
            ModerationAction.ban,
          ],
        ReportTarget.comment => [ModerationAction.dismiss, ModerationAction.warn, ModerationAction.remove, ModerationAction.ban],
        ReportTarget.profile => [ModerationAction.dismiss, ModerationAction.warn, ModerationAction.ban],
      };

  Future<void> _decide(BuildContext context, WidgetRef ref, Report r, ModerationAction a) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${a.label}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(a.hint, style: Theme.of(ctx).textTheme.bodySmall),
            if (a != ModerationAction.dismiss) ...[
              const SizedBox(height: 12),
              TextField(controller: note, decoration: const InputDecoration(hintText: 'Note for the log (and the author, if told)'), maxLength: 200),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(a.label)),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(socialProvider.notifier).moderate(r, a, note: note.text);
    if (context.mounted) toast(context, '${a.label}: done');
  }
}
