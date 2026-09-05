import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/nocturne.dart';
import '../../core/ai_coach.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import 'open_chat_soon.dart';

/// The AI coach (v0.12: presets in, free typing closed).
///
/// The coach is on and free — it answers from the profile and the bundled
/// catalogue, and every plan it writes opens in the routine preview like any
/// other shared routine. What is closed is the open text box: an open chat is
/// what costs money per athlete, and until we know how to give that away to
/// everyone the app does not sell it. So the input is [CoachPrompt] buttons,
/// each of which the offline coach answers properly, and the box under them
/// says when the rest is coming.
class CoachScreen extends ConsumerStatefulWidget {
  const CoachScreen({super.key});
  @override
  ConsumerState<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends ConsumerState<CoachScreen> {
  final _scroll = ScrollController();

  Future<void> _ask(CoachPrompt p) async {
    await ref.read(coachProvider.notifier).send(p.label);
    if (_scroll.hasClients) {
      _scroll.animateTo(_scroll.position.maxScrollExtent + 400, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(coachProvider);
    final settings = ref.watch(settingsProvider);
    final mode = ref.watch(coachModeProvider);
    final me = ref.watch(profileProvider)!;

    return Scaffold(
      backgroundColor: Noc.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Noc.gutter, 6, Noc.gutter, 10),
              child: Row(children: [
                NocIconButton(
                  icon: Nx.arrowLeft,
                  tooltip: 'Back',
                  onTap: () => context.canPop() ? context.pop() : context.go('/community'),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text('AI coach', style: Noc.pageTitle)),
                if (state.messages.isNotEmpty)
                  NocIconButton(
                    icon: Nx.arrowCounterClockwise,
                    size: 32,
                    tooltip: 'Start over',
                    onTap: () => ref.read(coachProvider.notifier).clear(),
                  ),
              ]),
            ),
            Expanded(
              child: NocIn(
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(Noc.gutter, 0, Noc.gutter, 16),
                  children: [
                    if (state.messages.isEmpty) _Intro(me: me, mode: mode, model: settings.model),
                    for (final m in state.messages) _Bubble(message: m),
                    if (state.streaming case final partial? when partial.isNotEmpty)
                      _Bubble(message: ChatMessage(role: 'coach', text: partial)),
                    if (state.busy && (state.streaming == null || state.streaming!.isEmpty))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(children: [
                          const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Noc.accent)),
                          const SizedBox(width: 10),
                          Text('Reading your profile…', style: Noc.metaMuted),
                        ]),
                      ),
                  ],
                ),
              ),
            ),
            _AskBar(busy: state.busy, onAsk: _ask),
          ],
        ),
      ),
    );
  }
}

// =================================================================== intro
class _Intro extends StatelessWidget {
  const _Intro({required this.me, required this.mode, required this.model});
  final UserProfile me;
  final CoachMode mode;
  final String model;

  @override
  Widget build(BuildContext context) => NocCard(
        border: Border.all(color: Noc.accent700),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Noc.accent900, Noc.surface]),
        padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Nx.sparkle, size: 17, color: Noc.accent300),
              const SizedBox(width: 8),
              Expanded(child: Text('FREE FOR TRAINEES, ALWAYS', style: Noc.kickerAccent)),
              NocTag(switch (mode) {
                CoachMode.cloud => 'Hosted',
                CoachMode.device => model,
                CoachMode.offline => 'On device',
              }, style: NocTagStyle.outline, fontSize: 9.5),
            ]),
            const SizedBox(height: 10),
            Text('Hey ${me.name.split(' ').first}. I know your numbers.', style: Noc.name),
            const SizedBox(height: 6),
            Text(
              '${me.heightCm.toStringAsFixed(0)} cm · ${me.weightKg.toStringAsFixed(1)} kg · ${me.goal.label} · ${me.daysPerWeek} days a week'
              '${me.diet.isEmpty ? '' : ' · ${me.diet.join(', ')}'}',
              style: Noc.small,
            ),
            const SizedBox(height: 10),
            Text(
              'Pick a question below. Anything I write comes out of the 1,443-exercise library using only the gear you own, '
              'and you see the whole routine before you take it on.',
              style: Noc.body.copyWith(color: Noc.muted),
            ),
          ],
        ),
      );
}

// ================================================================= bubbles
class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 460),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: message.error
                  ? Noc.accent900
                  : isUser
                      ? Noc.accent800
                      : Noc.surface,
              border: Border.all(color: message.error ? Noc.accent : (isUser ? Noc.accent700 : Noc.line)),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(Noc.rRow),
                topRight: const Radius.circular(Noc.rRow),
                bottomLeft: Radius.circular(isUser ? Noc.rRow : 4),
                bottomRight: Radius.circular(isUser ? 4 : Noc.rRow),
              ),
            ),
            child: SelectableText(
              message.text,
              style: Noc.body.copyWith(color: isUser ? Noc.accent100 : Noc.text),
            ),
          ),
          if (message.routine case final routine?) ...[
            const SizedBox(height: 9),
            _PlanCard(routine: routine),
          ],
        ],
      ),
    );
  }
}

/// What the coach built, as a card you look inside rather than take on trust.
class _PlanCard extends ConsumerWidget {
  const _PlanCard({required this.routine});
  final Routine routine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(routinesProvider).any((r) => r.id == routine.id || r.name == routine.name);
    return Container(
      constraints: const BoxConstraints(maxWidth: 460),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
      decoration: Noc.card(border: Border.all(color: Noc.accent700)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Nx.sparkle, size: 15, color: Noc.accent400),
            const SizedBox(width: 8),
            Expanded(child: Text(routine.name, style: Noc.cardTitle, maxLines: 2, overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 4),
          Text('${routine.days.length} day${routine.days.length == 1 ? '' : 's'} · ${routine.exerciseCount} exercises', style: Noc.meta),
          const SizedBox(height: 10),
          for (final d in routine.days.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.title, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontVariations: Noc.w500, color: Noc.accent300)),
                  const SizedBox(height: 2),
                  Text(
                    d.items.map((i) => i.exerciseName).join(' · '),
                    style: Noc.small,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          if (routine.days.length > 3) Text('+${routine.days.length - 3} more days', style: Noc.small),
          const SizedBox(height: 8),
          // Everything the coach writes opens in the preview first: every
          // exercise, its grade, the kit it needs, and the level switcher.
          NocButton(
            label: 'See the routine',
            icon: Nx.listBullets,
            block: true,
            onTap: () => context.push('/routine/${routine.id}', extra: routine),
          ),
          if (saved) ...[
            const SizedBox(height: 7),
            // The coach keeps what it writes, so nothing it says is lost when
            // the chat is cleared.
            Row(children: [
              const Icon(Nx.check, size: 12, color: Noc.accent400),
              const SizedBox(width: 6),
              Text('Kept in your routines', style: Noc.small),
            ]),
          ],
        ],
      ),
    );
  }
}

// ================================================================= the ask
/// The only input the coach has for now: five questions and an honest note
/// about the sixth.
class _AskBar extends StatelessWidget {
  const _AskBar({required this.busy, required this.onAsk});
  final bool busy;
  final ValueChanged<CoachPrompt> onAsk;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: Noc.bg,
          border: Border(top: BorderSide(color: Noc.divider)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Noc.gutter, 12, Noc.gutter, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ASK THE COACH', style: Noc.columnLabel),
                const SizedBox(height: 9),
                SizedBox(
                  height: 62,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: CoachPrompt.values.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final p = CoachPrompt.values[i];
                      return Opacity(
                        opacity: busy ? 0.45 : 1,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: busy ? null : () => onAsk(p),
                          child: Container(
                            width: 200,
                            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                            decoration: BoxDecoration(
                              color: Noc.sunken,
                              borderRadius: BorderRadius.circular(Noc.rControl),
                              border: Border.all(color: Noc.line),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.label, style: Noc.rowTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 2),
                                Text(p.note, style: Noc.small, maxLines: 1, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => showOpenChatSoonSheet(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Noc.rControl),
                      border: Border.all(color: Noc.line),
                    ),
                    child: Row(children: [
                      const Icon(Nx.chatCircle, size: 15, color: Noc.dim),
                      const SizedBox(width: 10),
                      Expanded(child: Text('Ask it anything, in your own words', style: Noc.metaDim)),
                      const NocTag('Soon', style: NocTagStyle.outline, fontSize: 9.5),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
