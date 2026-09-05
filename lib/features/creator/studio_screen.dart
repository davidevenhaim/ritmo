import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../video/video_card.dart';

/// Creator studio (v0.3): apply to upload, then watch the numbers.
class StudioScreen extends ConsumerStatefulWidget {
  const StudioScreen({super.key});
  @override
  ConsumerState<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends ConsumerState<StudioScreen> {
  late Future<CreatorStats> _stats;

  @override
  void initState() {
    super.initState();
    _stats = _load();
  }

  Future<CreatorStats> _load() {
    final me = ref.read(profileProvider)!;
    return ref.read(socialProvider.notifier).creatorStats(me.id);
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(profileProvider)!;
    final status = ref.watch(creatorStatusProvider);
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Creator studio'),
        actions: [IconButton(onPressed: () => setState(() => _stats = _load()), icon: const Icon(Icons.refresh))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          _CreatorCard(me: me, status: status.value ?? CreatorStatus.none),
          const SizedBox(height: 16),
          FutureBuilder<CreatorStats>(
            future: _stats,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
              }
              if (snap.hasError) return Text('Could not load stats: ${snap.error}', style: const TextStyle(color: SoColors.amber));
              final s = snap.data!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    _Tile(label: 'Views', value: compact(s.views), color: SoColors.coral),
                    const SizedBox(width: 8),
                    _Tile(label: 'Followers', value: compact(s.followers), color: SoColors.mint),
                    const SizedBox(width: 8),
                    _Tile(label: 'Tries', value: compact(s.tries), color: SoColors.amber),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    _Tile(label: 'Likes', value: compact(s.likes)),
                    const SizedBox(width: 8),
                    _Tile(label: 'Comments', value: compact(s.comments)),
                    const SizedBox(width: 8),
                    _Tile(label: 'Engagement', value: '${s.engagementPct.toStringAsFixed(1)}%', hint: 'likes + comments + recs per 100 views'),
                  ]),
                  const SizedBox(height: 20),
                  const SectionTitle('Views, last 7 days'),
                  _ViewsChart(values: s.viewsByDay),
                  const SizedBox(height: 20),
                  const SectionTitle('Posts by views'),
                  if (s.topPosts.isEmpty)
                    Text('Nothing posted yet. Your first share shows up here with its numbers.', style: t.bodySmall)
                  else
                    _PostTable(rows: s.topPosts),
                  const SizedBox(height: 20),
                  const SectionTitle('What moves the numbers'),
                  const _Tip(icon: Icons.play_arrow, text: 'Attach a routine to a clip. Posts with a routine get the Try it button, and tries are the metric that matters.'),
                  const _Tip(icon: Icons.fitness_center, text: 'Tag the exercises in the clip. Each tag links to the catalogue page and shows up in searches.'),
                  const _Tip(icon: Icons.timer_outlined, text: 'Sixty seconds, one idea. The cap is deliberate; the hot burners are all under a minute.'),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CreatorCard extends ConsumerStatefulWidget {
  const _CreatorCard({required this.me, required this.status});
  final UserProfile me;
  final CreatorStatus status;
  @override
  ConsumerState<_CreatorCard> createState() => _CreatorCardState();
}

class _CreatorCardState extends ConsumerState<_CreatorCard> {
  final _statement = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _statement.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    if (_statement.text.trim().length < 10) {
      toast(context, 'Tell us a little more (at least 10 characters).');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(socialProvider.notifier).applyAsCreator(_statement.text);
      if (mounted) toast(context, ref.read(socialBackendProvider).isRemote ? 'Application sent. A moderator will review it.' : 'Approved. Demo build: uploads are open now.');
    } catch (e) {
      if (mounted) toast(context, 'Could not apply: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final me = widget.me;
    final remote = ref.watch(socialBackendProvider).isRemote;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: SoColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: me.creator ? SoColors.mint : SoColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Avatar(me.emoji, size: 44, ring: me.creator),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Flexible(child: Text(me.name, style: t.titleMedium, overflow: TextOverflow.ellipsis)), if (me.creator) const CreatorBadge()]),
                Text(me.creator ? 'Creator · uploads open' : switch (widget.status) {
                  CreatorStatus.pending => 'Application pending review',
                  CreatorStatus.rejected => 'Application not approved',
                  _ => 'Member',
                }, style: t.bodySmall),
              ]),
            ),
            TextButton(onPressed: () => context.push('/u/${me.id}'), child: const Text('Public profile')),
          ]),
          if (!me.creator && widget.status != CreatorStatus.pending) ...[
            const Divider(height: 22),
            Text('Video uploads are open to creators first: trainers, athletes and people who post regularly. Say what you would post and a moderator approves you. Clips are capped at 60 seconds, screened automatically, and streamed via Cloudflare Stream or Mux.', style: t.bodySmall),
            const SizedBox(height: 10),
            TextField(controller: _statement, minLines: 2, maxLines: 4, maxLength: 500, decoration: const InputDecoration(hintText: 'What will you post? Links welcome.', counterText: '')),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: _busy ? null : _apply, child: Text(_busy ? 'Sending…' : remote ? 'Apply to be a creator' : 'Apply (instant in the demo)')),
            ),
          ],
          if (widget.status == CreatorStatus.pending && !me.creator) ...[
            const Divider(height: 22),
            Row(children: [
              const Icon(Icons.hourglass_top, color: SoColors.amber, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text('A moderator is reviewing your application. You get a notification either way.', style: t.bodySmall)),
            ]),
          ],
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, this.color, this.hint});
  final String label, value;
  final Color? color;
  final String? hint;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Tooltip(
          message: hint ?? label,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(color: SoColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: SoColors.line)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  if (color != null) Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 6), decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  Text(label.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
                ]),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5, fontFeatures: [FontFeature.tabularFigures()])),
              ],
            ),
          ),
        ),
      );
}

/// Single-series bar chart: one hue, thin bars with rounded data-ends on the
/// baseline, the peak labeled directly, every bar carrying a hover tooltip.
class _ViewsChart extends StatelessWidget {
  const _ViewsChart({required this.values});
  final List<int> values;

  static const _days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final vals = values.length == 7 ? values : List<int>.filled(7, 0);
    final maxV = vals.fold(0, (m, v) => v > m ? v : m);
    final today = DateTime.now();
    final labels = List<String>.generate(7, (i) => _days[today.subtract(Duration(days: 6 - i)).weekday - 1]);
    final peak = maxV == 0 ? -1 : vals.lastIndexOf(maxV);
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(color: SoColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: SoColors.line)),
      child: Column(
        children: [
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Tooltip(
                      message: '${labels[i]}: ${vals[i]} views',
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (i == peak) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(compact(vals[i]), style: t.bodySmall?.copyWith(color: SoColors.text, fontWeight: FontWeight.w700))),
                          Container(
                            width: 14,
                            height: maxV == 0 ? 2 : (4 + 96 * vals[i] / maxV),
                            decoration: BoxDecoration(
                              color: maxV == 0 ? SoColors.line : SoColors.coral.withValues(alpha: i == peak ? 1 : 0.75),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 10, color: SoColors.line),
          Row(children: [for (final l in labels) Expanded(child: Text(l, textAlign: TextAlign.center, style: t.bodySmall))]),
          if (maxV == 0) Padding(padding: const EdgeInsets.only(top: 6), child: Text('No views yet this week.', style: t.bodySmall)),
        ],
      ),
    );
  }
}

class _PostTable extends StatelessWidget {
  const _PostTable({required this.rows});
  final List<PostStat> rows;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget cell(String s, {bool head = false, TextAlign align = TextAlign.right, int flex = 1}) => Expanded(
          flex: flex,
          child: Text(s, textAlign: align, maxLines: 1, overflow: TextOverflow.ellipsis, style: head ? t.labelSmall : TextStyle(fontSize: 13, fontWeight: head ? FontWeight.w600 : FontWeight.w500, fontFeatures: const [FontFeature.tabularFigures()])),
        );
    return Container(
      decoration: BoxDecoration(color: SoColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: SoColors.line)),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(children: [cell('POST', head: true, align: TextAlign.left, flex: 4), cell('VIEWS', head: true), cell('LIKES', head: true), cell('TRIES', head: true)]),
          ),
          const Divider(height: 1),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(children: [
                Expanded(
                  flex: 4,
                  child: Row(children: [
                    TagChip(kindLabel(r.kind), color: r.kind == PostKind.video ? SoColors.coral : null),
                    const SizedBox(width: 6),
                    Expanded(child: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                  ]),
                ),
                cell(compact(r.views)),
                cell(compact(r.likes)),
                cell(r.tries == 0 ? '—' : compact(r.tries)),
              ]),
            ),
        ],
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: SoColors.mint),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ]),
      );
}
