import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/models.dart';
import '../../core/providers.dart';

/// Report a post, comment or member (v0.3). One report per member per
/// target; three open reports hide a post until a moderator looks.
class ReportSheet extends ConsumerStatefulWidget {
  const ReportSheet({super.key, required this.target, required this.targetId, required this.title});
  final ReportTarget target;
  final String targetId;
  final String title;

  static Future<void> show(BuildContext context, {required ReportTarget target, required String targetId, required String title}) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => ReportSheet(target: target, targetId: targetId, title: title),
      );

  @override
  ConsumerState<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<ReportSheet> {
  ReportReason? _reason;
  final _details = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final reason = _reason;
    if (reason == null || _sending) return;
    setState(() => _sending = true);
    final ok = await ref.read(socialProvider.notifier).report(target: widget.target, targetId: widget.targetId, reason: reason, details: _details.text);
    if (!mounted) return;
    Navigator.of(context).pop();
    toast(context, ok ? 'Thanks. A moderator will take a look.' : 'You already reported this.');
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
            Text('Report ${widget.target.name}', style: t.titleLarge),
            const SizedBox(height: 4),
            Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall),
            const SizedBox(height: 14),
            for (final r in ReportReason.selectable)
              RadioListTile<ReportReason>(
                value: r,
                // ignore: deprecated_member_use
                groupValue: _reason,
                // ignore: deprecated_member_use
                onChanged: (v) => setState(() => _reason = v),
                dense: true,
                contentPadding: EdgeInsets.zero,
                activeColor: SoColors.coral,
                title: Text(r.label),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _details,
              minLines: 1,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(hintText: 'Anything the moderator should know (optional)', counterText: ''),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _reason == null || _sending ? null : _send,
                child: Text(_sending ? 'Sending…' : 'Send report'),
              ),
            ),
            const SizedBox(height: 6),
            Text('Reports are private. Repeated false reports count against your account.', style: t.bodySmall, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
