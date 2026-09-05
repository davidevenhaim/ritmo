import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/nocturne.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/session_theme.dart';

/// The three prompts the sheet offers, and how each one shapes the draft.
enum AiPrompt {
  short('Keep it short — 25 minutes', 'Fewer exercises, less rest'),
  heavy('Go heavy on the compounds', 'Big movements first'),
  gentle('Easy on my joints today', 'Bodyweight and low-impact only');

  const AiPrompt(this.label, this.note);
  final String label;
  final String note;
}

/// AI assist (Nocturne handoff, step 2). Tell it what today should be; it
/// drafts onto the timeline and you keep editing.
///
/// The draft is currently chosen from the theme's own library against the
/// user's equipment and the selected prompt. Swapping in the hosted coach is
/// a change to [draftBlock] alone: it returns the exercises, the sheet does
/// not care where they came from.
Future<List<Exercise>?> showAiAssistSheet(BuildContext context, {required SessionTheme theme, required WidgetRef ref}) =>
    showModalBottomSheet<List<Exercise>>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Noc.sheet,
      barrierColor: Noc.scrim,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Noc.rSheet))),
      builder: (_) => _AiAssistSheet(theme: theme),
    );

/// Picks the block. Deterministic, grounded in the bundled catalogue.
List<Exercise> draftBlock({
  required List<Exercise> library,
  required AiPrompt? prompt,
  required List<String> equipment,
  String freeText = '',
}) {
  var pool = library;
  if (prompt == AiPrompt.gentle) {
    pool = pool.where((e) => e.equipment == 'body only' || e.equipment == 'none' || e.category == 'stretching' || e.category == 'yoga').toList();
  }
  if (prompt == AiPrompt.heavy) {
    pool = pool.where((e) => e.mechanic == 'compound').toList();
  }
  final q = freeText.trim().toLowerCase();
  if (q.isNotEmpty) {
    final hits = pool.where((e) => '${e.name} ${e.primary.join(' ')}'.toLowerCase().contains(q)).toList();
    if (hits.length >= 3) pool = hits;
  }
  // Prefer what the athlete owns, then spread across muscle groups so the
  // block is not five variations of the same movement.
  final mine = pool.where((e) => equipment.contains(e.equipment) || e.equipment == 'body only' || e.equipment == 'none').toList();
  final source = mine.length >= 5 ? mine : pool;
  final out = <Exercise>[];
  final used = <String>{};
  for (final e in source) {
    final part = e.primary.isEmpty ? e.category : e.primary.first;
    if (used.contains(part)) continue;
    used.add(part);
    out.add(e);
    if (out.length == (prompt == AiPrompt.short ? 4 : 5)) return out;
  }
  for (final e in source) {
    if (out.length == 5) break;
    if (!out.contains(e)) out.add(e);
  }
  return out;
}

class _AiAssistSheet extends ConsumerStatefulWidget {
  const _AiAssistSheet({required this.theme});
  final SessionTheme theme;
  @override
  ConsumerState<_AiAssistSheet> createState() => _AiAssistSheetState();
}

class _AiAssistSheetState extends ConsumerState<_AiAssistSheet> {
  AiPrompt? _picked;
  final _text = TextEditingController();
  bool _drafting = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() => _drafting = true);
    final repo = await ref.read(exerciseRepoProvider.future);
    final me = ref.read(profileProvider)!;
    final picks = draftBlock(
      library: repo.forTheme(widget.theme),
      prompt: _picked,
      equipment: me.equipment,
      freeText: _text.text,
    );
    // The handoff holds the drafting state for about a second so the sweep
    // reads as work rather than a flash.
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    if (mounted) Navigator.pop(context, picks);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(width: 38, height: 4, decoration: BoxDecoration(color: Noc.line, borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 16),
              Row(children: [
                const Icon(Nx.sparkle, size: 18, color: Noc.accent),
                const SizedBox(width: 8),
                Text('AI assist', style: Noc.name),
              ]),
              const SizedBox(height: 6),
              Text(
                'Tell it what today should be. It drafts onto your timeline — you keep editing.',
                style: Noc.metaDim.copyWith(height: 1.4),
              ),
              const SizedBox(height: 14),
              for (final p in AiPrompt.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: NocCard(
                    color: _picked == p ? Noc.accent900 : Noc.sunken,
                    border: Border.all(color: _picked == p ? Noc.accent : Noc.sunken),
                    radius: Noc.rControl,
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                    onTap: _drafting ? null : () => setState(() => _picked = _picked == p ? null : p),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.label, style: Noc.rowTitle),
                        const SizedBox(height: 2),
                        Text(p.note, style: Noc.small),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              TextField(
                controller: _text,
                enabled: !_drafting,
                style: Noc.body,
                decoration: InputDecoration(
                  hintText: 'Or say it in your own words',
                  hintStyle: Noc.metaDim,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Noc.rControl), borderSide: const BorderSide(color: Noc.line)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Noc.rControl), borderSide: const BorderSide(color: Noc.accent)),
                ),
              ),
              const SizedBox(height: 12),
              if (_drafting) ...[
                const NocSweep(),
                const SizedBox(height: 10),
                Center(child: Text('Drafting…', style: Noc.metaMuted)),
              ] else
                NocButton(label: 'Build it', icon: Nx.sparkle, block: true, onTap: _run),
            ],
          ),
        ),
      );
}
