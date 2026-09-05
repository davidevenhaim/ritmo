import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/models.dart';
import '../../core/providers.dart';

const _emojis = ['🙂', '😎', '🦁', '🐺', '🦊', '🐯', '🦄', '🐉', '🤖', '👽', '🔥', '⚡'];

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.initial});
  final UserProfile? initial;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _page = PageController();
  int _index = 0;

  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _handle = TextEditingController(text: widget.initial?.handle ?? '');
  late final _bio = TextEditingController(text: widget.initial?.bio ?? '');
  late String _emoji = widget.initial?.emoji ?? '🙂';
  late double _height = widget.initial?.heightCm ?? 172;
  late double _weight = widget.initial?.weightKg ?? 72;
  late double _target = widget.initial?.targetWeightKg ?? (widget.initial?.weightKg ?? 72);
  late int _age = widget.initial?.age ?? 28;
  late Goal _goal = widget.initial?.goal ?? Goal.buildMuscle;
  late int _days = widget.initial?.daysPerWeek ?? 3;
  late ExperienceLevel _experience = widget.initial?.experience ?? ExperienceLevel.beginner;
  late int _stepGoal = widget.initial?.stepGoal ?? 8000;
  late final Set<String> _equipment = {...(widget.initial?.equipment ?? const ['body only', 'dumbbell'])};
  late final Set<String> _diet = {...(widget.initial?.diet ?? const [])};

  bool get _editing => widget.initial != null;

  void _next() {
    if (_index == 0 && _name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tell us your name first')));
      return;
    }
    if (_index < 3) {
      _page.animateToPage(++_index, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    final handle = _handle.text.trim().isEmpty
        ? _name.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '.')
        : _handle.text.trim().replaceAll('@', '');
    final profile = UserProfile(
      id: widget.initial?.id ?? 'me',
      name: _name.text.trim(),
      handle: handle,
      emoji: _emoji,
      heightCm: _height,
      weightKg: _weight,
      targetWeightKg: _target,
      age: _age,
      goal: _goal,
      diet: _diet.toList(),
      equipment: _equipment.toList(),
      daysPerWeek: _days,
      experience: _experience,
      bio: _bio.text.trim(),
      stepGoal: _stepGoal,
      creator: widget.initial?.creator ?? false,
      moderator: widget.initial?.moderator ?? false,
    );
    await ref.read(profileProvider.notifier).save(profile);
    if (_editing && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  if (_editing)
                    IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close))
                  else
                    const _Logo(),
                  const Spacer(),
                  for (var i = 0; i < 4; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.only(left: 6),
                      width: i == _index ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i <= _index ? SoColors.coral : SoColors.line,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _page,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _Step(
                    title: _editing ? 'Edit profile' : 'Train together,\neverywhere.',
                    subtitle: _editing ? null : 'Ritmo is the social gym. Share workouts, steps, routines and diet wins with people who get it.',
                    children: [
                      // The promise the app is built on, said before anything
                      // is asked of the person reading it.
                      if (!_editing) ...[const _FreeBanner(), const SizedBox(height: 18)],
                      TextField(controller: _name, decoration: const InputDecoration(hintText: 'Your name'), textCapitalization: TextCapitalization.words),
                      const SizedBox(height: 10),
                      TextField(controller: _handle, decoration: const InputDecoration(hintText: '@handle (optional)')),
                      const SizedBox(height: 10),
                      TextField(controller: _bio, decoration: const InputDecoration(hintText: 'One line about you (optional)')),
                      const SizedBox(height: 18),
                      Text('PICK AN AVATAR', style: t.labelSmall),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final e in _emojis)
                            GestureDetector(
                              onTap: () => setState(() => _emoji = e),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: 48,
                                height: 48,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: e == _emoji ? SoColors.coralSoft : SoColors.surface2,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: e == _emoji ? SoColors.coral : Colors.transparent, width: 2),
                                ),
                                child: Text(e, style: const TextStyle(fontSize: 22)),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  _Step(
                    title: 'Your numbers.',
                    subtitle: 'The coach uses these to size your plan. Only you and the coach see them.',
                    children: [
                      _SliderRow(label: 'Height', value: _height, min: 140, max: 210, unit: 'cm', onChanged: (v) => setState(() => _height = v)),
                      _SliderRow(label: 'Weight', value: _weight, min: 40, max: 160, unit: 'kg', decimals: 1, onChanged: (v) => setState(() => _weight = v)),
                      _SliderRow(label: 'Target weight', value: _target, min: 40, max: 160, unit: 'kg', decimals: 1, onChanged: (v) => setState(() => _target = v)),
                      _SliderRow(label: 'Age', value: _age.toDouble(), min: 14, max: 90, unit: 'yrs', onChanged: (v) => setState(() => _age = v.round())),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: SoColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: SoColors.line)),
                        child: Row(
                          children: [
                            const Icon(Icons.monitor_weight_outlined, color: SoColors.mint),
                            const SizedBox(width: 10),
                            Text('BMI ${(_weight / ((_height / 100) * (_height / 100))).toStringAsFixed(1)}', style: t.titleMedium),
                            const Spacer(),
                            Text(_target < _weight ? '${(_weight - _target).toStringAsFixed(1)} kg to lose' : _target > _weight ? '${(_target - _weight).toStringAsFixed(1)} kg to gain' : 'maintain', style: t.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                  _Step(
                    title: 'What are we chasing?',
                    subtitle: 'Pick one main goal. You can change it any time.',
                    children: [
                      for (final g in Goal.values)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _GoalTile(goal: g, selected: g == _goal, onTap: () => setState(() => _goal = g)),
                        ),
                      const SizedBox(height: 12),
                      Text('TRAINING DAYS PER WEEK', style: t.labelSmall),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (var d = 1; d <= 6; d++)
                            ChoiceChip(label: Text('$d'), selected: d == _days, onSelected: (_) => setState(() => _days = d)),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text('HOW LONG HAVE YOU BEEN TRAINING', style: t.labelSmall),
                      const SizedBox(height: 4),
                      Text('Start only suggests exercises graded for this level.', style: t.bodySmall),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final e in ExperienceLevel.values)
                            ChoiceChip(
                              label: Text(e.label),
                              selected: e == _experience,
                              onSelected: (_) => setState(() => _experience = e),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _SliderRow(label: 'Daily step goal', value: _stepGoal.toDouble(), min: 3000, max: 20000, unit: '', onChanged: (v) => setState(() => _stepGoal = (v / 500).round() * 500)),
                    ],
                  ),
                  _Step(
                    title: 'Gear and food.',
                    subtitle: 'The coach only suggests exercises you can actually do and food you can actually eat.',
                    children: [
                      Text('EQUIPMENT I HAVE', style: t.labelSmall),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final e in equipmentOptions)
                            FilterChip(
                              label: Text(e),
                              selected: _equipment.contains(e),
                              onSelected: (s) => setState(() => s ? _equipment.add(e) : _equipment.remove(e)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text('DIET RESTRICTIONS', style: t.labelSmall),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final d in dietOptions)
                            FilterChip(
                              label: Text(d),
                              selected: _diet.contains(d),
                              selectedColor: SoColors.mint,
                              labelStyle: TextStyle(color: _diet.contains(d) ? SoColors.ink : SoColors.text, fontWeight: FontWeight.w600, fontSize: 13),
                              onSelected: (s) => setState(() => s ? _diet.add(d) : _diet.remove(d)),
                            ),
                        ],
                      ),
                      // Said again on the last step, so nobody reaches the end
                      // of setup wondering when the bill arrives.
                      if (!_editing) ...[const SizedBox(height: 22), const _FreeBanner()],
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Row(
                children: [
                  if (_index > 0)
                    OutlinedButton(
                      onPressed: () => _page.animateToPage(--_index, duration: const Duration(milliseconds: 280), curve: Curves.easeOut),
                      child: const Text('Back'),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _next,
                    child: Text(_index == 3 ? (_editing ? 'Save' : "Let's go") : 'Continue'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Free to use for trainees. Always." — the app's own promise, on the way in.
///
/// It is not marketing copy: individuals never pay in Ritmo, and the paying
/// side is studios, clubs and personal trainers. Somebody handing over their
/// height, weight and goals deserves to know that before they type them.
class _FreeBanner extends StatelessWidget {
  const _FreeBanner();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: SoColors.mintSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SoColors.mint),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.volunteer_activism_outlined, color: SoColors.mint, size: 20),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Free to use for trainees. Always.', style: t.titleMedium?.copyWith(color: SoColors.mint)),
                const SizedBox(height: 3),
                Text(
                  'No subscription, no paywall, no ads. Every workout, routine, goal and the AI coach cost you nothing — '
                  'studios, clubs and personal trainers are the paying side of Ritmo.',
                  style: t.bodySmall?.copyWith(color: SoColors.text, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: SoColors.coral, borderRadius: BorderRadius.circular(9)),
            child: const Icon(Icons.local_fire_department, size: 20, color: Colors.white),
          ),
          const SizedBox(width: 8),
          const Text('Ritmo', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: -0.5)),
        ],
      );
}

class _Step extends StatelessWidget {
  const _Step({required this.title, this.subtitle, required this.children});
  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      children: [
        Text(title, style: t.headlineMedium),
        if (subtitle != null) ...[const SizedBox(height: 8), Text(subtitle!, style: t.bodyMedium?.copyWith(color: SoColors.muted))],
        const SizedBox(height: 22),
        ...children,
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({required this.label, required this.value, required this.min, required this.max, required this.unit, required this.onChanged, this.decimals = 0});
  final String label;
  final double value, min, max;
  final String unit;
  final int decimals;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(label, style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text('${value.toStringAsFixed(decimals)} $unit', style: const TextStyle(fontWeight: FontWeight.w700, color: SoColors.mint, fontFeatures: [FontFeature.tabularFigures()])),
              ],
            ),
            Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
          ],
        ),
      );
}

class _GoalTile extends StatelessWidget {
  const _GoalTile({required this.goal, required this.selected, required this.onTap});
  final Goal goal;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? SoColors.coralSoft : SoColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? SoColors.coral : SoColors.line),
          ),
          child: Row(
            children: [
              Text(goal.emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Text(goal.label, style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              if (selected) const Icon(Icons.check_circle, color: SoColors.coral),
            ],
          ),
        ),
      );
}
