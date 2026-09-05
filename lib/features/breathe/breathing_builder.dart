import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/nocturne.dart';
import '../../core/models.dart';
import '../../core/providers.dart';

/// Build your own pattern (v0.13): in for x, hold for y, out for z, hold for
/// w, that many times.
///
/// Four steppers and a cycle count, with the clock underneath doing the sum —
/// the whole point of building one is knowing how long you are committing to,
/// so the total is never more than a glance away.
Future<BreathingPattern?> showBreathingBuilder(BuildContext context, WidgetRef ref) => showModalBottomSheet<BreathingPattern>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      // The sheet draws the handoff's own handle, not the theme's Material one.
      showDragHandle: false,
      backgroundColor: Noc.sheet,
      barrierColor: Noc.scrim,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Noc.rSheet))),
      builder: (_) => const _BreathingBuilder(),
    );

class _BreathingBuilder extends ConsumerStatefulWidget {
  const _BreathingBuilder();
  @override
  ConsumerState<_BreathingBuilder> createState() => _BreathingBuilderState();
}

class _BreathingBuilderState extends ConsumerState<_BreathingBuilder> {
  // Opens on a long exhale, which is the pattern that works for most people
  // most of the time.
  int _inhale = 4;
  int _holdIn = 0;
  int _exhale = 6;
  int _holdOut = 0;
  int _cycles = 12;
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  BreathingPattern get _preview => BreathingPattern(
        id: 'preview',
        name: _name.text.trim().isEmpty ? _autoName : _name.text.trim(),
        tagline: '',
        inhale: _inhale,
        holdIn: _holdIn,
        exhale: _exhale,
        holdOut: _holdOut,
        cycles: _cycles,
        emoji: '🌬',
        purpose: BreathePurpose.mine,
        custom: true,
      );

  String get _autoName => 'My $_inhale-$_holdIn-$_exhale${_holdOut > 0 ? '-$_holdOut' : ''}';

  Future<void> _save() async {
    final p = await ref.read(customBreathingProvider.notifier).add(
          name: _name.text.trim().isEmpty ? _autoName : _name.text.trim(),
          inhale: _inhale,
          holdIn: _holdIn,
          exhale: _exhale,
          holdOut: _holdOut,
          cycles: _cycles,
        );
    if (mounted) Navigator.pop(context, p);
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    // A breath has to have air in it: everything else can be zero.
    final valid = _inhale > 0 && _exhale > 0;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(18, 10, 18, 22 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: Noc.line, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Text('Build a pattern', style: Noc.pageTitle),
              const SizedBox(height: 4),
              Text('In for x, hold for y, out for z. Say how many rounds and the clock does the rest.', style: Noc.bodyMuted),
              const SizedBox(height: 16),
              _Step(label: 'INHALE', value: _inhale, min: 1, max: 20, onChanged: (v) => setState(() => _inhale = v)),
              _Step(label: 'HOLD', value: _holdIn, min: 0, max: 20, onChanged: (v) => setState(() => _holdIn = v)),
              _Step(label: 'EXHALE', value: _exhale, min: 1, max: 20, onChanged: (v) => setState(() => _exhale = v)),
              _Step(label: 'HOLD AFTER', value: _holdOut, min: 0, max: 20, onChanged: (v) => setState(() => _holdOut = v)),
              const SizedBox(height: 6),
              _Step(label: 'ROUNDS', value: _cycles, min: 1, max: 60, unit: '', step: 1, onChanged: (v) => setState(() => _cycles = v)),
              const SizedBox(height: 14),
              // The sum, which is the reason to build one at all.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                decoration: BoxDecoration(
                  color: Noc.accent900,
                  borderRadius: BorderRadius.circular(Noc.rControl),
                  border: Border.all(color: Noc.accent700),
                ),
                child: Row(children: [
                  const Icon(Nx.clock, size: 15, color: Noc.accent300),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        preview.rhythm,
                        key: const Key('builderRhythm'),
                        style: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontVariations: Noc.w500, color: Noc.accent200),
                      ),
                      const SizedBox(height: 1),
                      Text('$_cycles rounds of ${preview.cycleSeconds}s', style: Noc.small),
                    ]),
                  ),
                  Text(preview.clock, key: const Key('builderClock'), style: Noc.statSm.copyWith(color: Noc.accent200)),
                ]),
              ),
              const SizedBox(height: 14),
              Text('NAME', style: Noc.columnLabel),
              const SizedBox(height: 8),
              TextField(
                controller: _name,
                style: Noc.body,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: _autoName,
                  hintStyle: Noc.metaDim,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Noc.rControl), borderSide: const BorderSide(color: Noc.line)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Noc.rControl), borderSide: const BorderSide(color: Noc.accent)),
                ),
              ),
              const SizedBox(height: 16),
              NocButton(
                label: 'Save and breathe',
                icon: Nx.play,
                block: true,
                onTap: valid ? _save : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One row of the pattern: a label, a big number, and a second either way.
class _Step extends StatelessWidget {
  const _Step({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.unit = 's',
    this.step = 1,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final String unit;
  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(child: Text(label, style: Noc.columnLabel)),
            NocIconButton(
              icon: Nx.minus,
              size: 32,
              outlined: true,
              tooltip: 'Less',
              onTap: value <= min ? null : () => onChanged((value - step).clamp(min, max)),
            ),
            SizedBox(
              width: 62,
              child: Text(
                '$value$unit',
                textAlign: TextAlign.center,
                style: Noc.statSm,
              ),
            ),
            NocIconButton(
              icon: Nx.plus,
              size: 32,
              outlined: true,
              tooltip: 'More',
              onTap: value >= max ? null : () => onChanged((value + step).clamp(min, max)),
            ),
          ],
        ),
      );
}
