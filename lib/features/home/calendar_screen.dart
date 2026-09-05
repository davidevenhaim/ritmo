import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/nocturne.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import 'add_goal_sheet.dart';
import 'me_screen.dart' show SessionCard;
import 'plus_menu.dart';

/// The whole month behind "This week".
///
/// The week chart on Me answers "how am I doing right now"; this answers
/// "what has this month actually looked like, and what is coming". Three
/// things land on a day: sessions already logged, sessions still planned, and
/// the day a goal is due — which is why goals with a date belong here rather
/// than only on the goals card.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);
  static String _key(DateTime d) => '${d.year}-${d.month}-${d.day}';

  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime _selected = _dayOf(DateTime.now());

  void _shift(int months) => setState(() => _month = DateTime(_month.year, _month.month + months));

  void _jumpTo(DateTime day) => setState(() {
        _month = DateTime(day.year, day.month);
        _selected = _dayOf(day);
      });

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(profileProvider);
    final logs = ref.watch(workoutHistoryProvider).value ?? const <WorkoutLog>[];
    final schedule = ref.watch(scheduleProvider);
    final steps = ref.watch(stepsProvider).value ?? const <StepDay>[];
    final goals = ref.watch(goalsProvider).where((g) => g.deadline != null).toList()
      ..sort((a, b) => a.deadline!.compareTo(b.deadline!));

    final byDayLogs = <String, List<WorkoutLog>>{};
    for (final l in logs) {
      byDayLogs.putIfAbsent(_key(l.completedAt), () => []).add(l);
    }
    final byDayPlan = <String, List<ScheduledWorkout>>{};
    for (final s in schedule) {
      byDayPlan.putIfAbsent(_key(s.at), () => []).add(s);
    }
    final byDayGoals = <String, List<PersonalGoal>>{};
    for (final g in goals) {
      byDayGoals.putIfAbsent(_key(g.deadline!), () => []).add(g);
    }
    final byDaySteps = {for (final d in steps) _key(d.date): d.steps};

    final today = _dayOf(DateTime.now());
    // Monday of the week the 1st falls in, then six full weeks: every month
    // fits, and the grid never changes height as you page through the year.
    final first = DateTime(_month.year, _month.month);
    final gridStart = first.subtract(Duration(days: first.weekday - 1));
    final cells = [for (var i = 0; i < 42; i++) gridStart.add(Duration(days: i))];

    final monthLogs = logs.where((l) => l.completedAt.year == _month.year && l.completedAt.month == _month.month).toList();
    final monthPlanned = schedule.where((s) => s.at.year == _month.year && s.at.month == _month.month && !s.at.isBefore(today) && !s.done).length;
    final trainedDays = {for (final l in monthLogs) _key(l.completedAt)}.length;

    return Scaffold(
      backgroundColor: Noc.bg,
      body: SafeArea(
        bottom: false,
        child: NocIn(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Noc.gutter, 0, Noc.gutter, 32),
            children: [
              _header(context),
              const SizedBox(height: 6),
              _monthBar(),
              const SizedBox(height: 12),
              _summary(monthLogs.length, trainedDays, monthPlanned),
              const SizedBox(height: 14),
              _weekdayRow(),
              const SizedBox(height: 6),
              GridView.count(
                crossAxisCount: 7,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 0.78,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                children: [
                  for (final d in cells)
                    _DayCell(
                      day: d,
                      inMonth: d.month == _month.month,
                      isToday: d == today,
                      selected: d == _selected,
                      done: byDayLogs[_key(d)]?.length ?? 0,
                      planned: (byDayPlan[_key(d)] ?? const <ScheduledWorkout>[]).where((s) => !s.done).length,
                      dueGoals: byDayGoals[_key(d)]?.length ?? 0,
                      stepFraction: me == null || byDaySteps[_key(d)] == null ? null : (byDaySteps[_key(d)]! / me.stepGoal).clamp(0.0, 1.0),
                      onTap: () => setState(() => _selected = d),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              _legend(),
              const SizedBox(height: 20),
              _dayDetail(
                context,
                logs: byDayLogs[_key(_selected)] ?? const [],
                plans: (byDayPlan[_key(_selected)] ?? const <ScheduledWorkout>[]).toList()..sort((a, b) => a.at.compareTo(b.at)),
                due: byDayGoals[_key(_selected)] ?? const [],
                steps: byDaySteps[_key(_selected)],
                stepGoal: me?.stepGoal ?? 0,
              ),
              const SizedBox(height: 24),
              _goalsWithDates(goals),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- chrome
  Widget _header(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 8),
        child: Row(
          children: [
            NocIconButton(
              icon: Nx.arrowLeft,
              tooltip: 'Back',
              // Deep links land here with nothing to pop back to.
              onTap: () => context.canPop() ? context.pop() : context.go('/home'),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text('Your calendar', style: Noc.pageTitle)),
            NocIconButton(icon: Nx.calendarPlus, tooltip: 'Schedule a workout', onTap: () => showScheduleSheet(context)),
          ],
        ),
      );

  Widget _monthBar() {
    final isThisMonth = _month.year == DateTime.now().year && _month.month == DateTime.now().month;
    return Row(
      children: [
        Transform.rotate(
          angle: pi,
          child: NocIconButton(icon: Nx.caretRight, size: 32, outlined: true, tooltip: 'Previous month', onTap: () => _shift(-1)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_month.year == DateTime.now().year ? 'THIS YEAR' : '${_month.year}', style: Noc.kicker),
              const SizedBox(height: 1),
              Text(DateFormat('MMMM y').format(_month), style: Noc.planTitle),
            ],
          ),
        ),
        if (!isThisMonth) ...[
          NocButton(label: 'Today', primary: false, dense: true, onTap: () => _jumpTo(DateTime.now())),
          const SizedBox(width: 8),
        ],
        NocIconButton(icon: Nx.caretRight, size: 32, outlined: true, tooltip: 'Next month', onTap: () => _shift(1)),
      ],
    );
  }

  Widget _summary(int sessions, int trainedDays, int planned) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: Noc.card(),
        child: Row(
          children: [
            _Stat(value: '$sessions', label: sessions == 1 ? 'session' : 'sessions'),
            _divider(),
            _Stat(value: '$trainedDays', label: trainedDays == 1 ? 'day trained' : 'days trained'),
            _divider(),
            _Stat(value: '$planned', label: 'still planned'),
          ],
        ),
      );

  Widget _divider() => Container(width: 1, height: 26, color: Noc.divider);

  Widget _weekdayRow() {
    final monday = DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Center(
              child: Text(DateFormat.E().format(monday.add(Duration(days: i))).substring(0, 1), style: Noc.tiny),
            ),
          ),
      ],
    );
  }

  Widget _legend() => Row(
        children: [
          const _LegendDot(color: Noc.accent, label: 'trained'),
          const SizedBox(width: 14),
          const _LegendDot(color: Noc.line, outlined: true, label: 'planned'),
          const SizedBox(width: 14),
          const _LegendDot(color: Noc.accent300, square: true, label: 'goal due'),
        ],
      );

  // ---------------------------------------------------------- day detail
  Widget _dayDetail(
    BuildContext context, {
    required List<WorkoutLog> logs,
    required List<ScheduledWorkout> plans,
    required List<PersonalGoal> due,
    required int? steps,
    required int stepGoal,
  }) {
    final today = _dayOf(DateTime.now());
    final diff = _selected.difference(today).inDays;
    final when = diff == 0
        ? 'today'
        : diff == 1
            ? 'tomorrow'
            : diff == -1
                ? 'yesterday'
                : diff > 0
                    ? 'in $diff days'
                    : '${-diff} days ago';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NocSectionHead(DateFormat('EEEE d MMMM').format(_selected), note: when),
        const SizedBox(height: 11),
        if (logs.isEmpty && plans.isEmpty && due.isEmpty && steps == null)
          NocCard(
            radius: Noc.rRow,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            onTap: () => showScheduleSheet(context),
            child: Row(children: [
              Icon(Nx.plus, size: 14, color: Noc.dim),
              const SizedBox(width: 9),
              const Expanded(child: Text('Nothing on this day — tap to plan a session', style: TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: Noc.dim))),
            ]),
          ),
        for (final l in logs) ...[
          _DoneRow(log: l),
          const SizedBox(height: 8),
        ],
        for (final s in plans) ...[
          SessionCard(session: s),
          const SizedBox(height: 8),
        ],
        for (final g in due) ...[
          _DueRow(goal: g),
          const SizedBox(height: 8),
        ],
        if (steps != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(color: Noc.sunken, borderRadius: BorderRadius.circular(Noc.rRow)),
            child: Row(children: [
              Icon(Nx.footprints, size: 14, color: Noc.accent400),
              const SizedBox(width: 9),
              Expanded(child: Text('${NumberFormat.decimalPattern().format(steps)} steps', style: Noc.rowTitle)),
              Text(stepGoal == 0 ? '' : '${((steps / stepGoal) * 100).round()}% of goal', style: Noc.meta),
            ]),
          ),
      ],
    );
  }

  // ------------------------------------------------------ goals with dates
  Widget _goalsWithDates(List<PersonalGoal> goals) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NocSectionHead('Goals with a date', note: goals.isEmpty ? null : '${goals.length} running'),
          const SizedBox(height: 11),
          if (goals.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: Text('Nothing due yet. A goal with a date lands on this calendar and counts down.', style: Noc.small),
            ),
          for (final g in goals) ...[
            NocCard(
              color: Noc.sunken,
              border: Border.all(color: Noc.sunken),
              radius: Noc.rRowSm,
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
              onTap: () => _jumpTo(g.deadline!),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(g.name, style: Noc.rowTitle, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 8),
                    Text(g.value, style: Noc.metaMuted),
                  ]),
                  const SizedBox(height: 9),
                  NocBar(pct: g.pct, height: 5, track: Noc.sheet),
                  const SizedBox(height: 7),
                  Text(
                    '${g.dueLabel} · ${DateFormat('EEE d MMM').format(g.deadline!)}',
                    style: Noc.small.copyWith(color: g.overdue ? Noc.accent400 : Noc.dim),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 9),
          ],
          const SizedBox(height: 2),
          NocButton(
            label: 'Set a goal',
            icon: Nx.target,
            primary: false,
            block: true,
            onTap: () => showAddGoalSheet(context, ref),
          ),
        ],
      );
}

// ================================================================== cells
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.selected,
    required this.done,
    required this.planned,
    required this.dueGoals,
    required this.stepFraction,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final bool selected;
  final int done;
  final int planned;
  final int dueGoals;

  /// How far the day's steps got towards the goal, where the app has the day.
  /// Only the last week is ever known, so most cells carry null.
  final double? stepFraction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Days in the month always carry a ground so the grid reads as one; where
    // the app has the step count, that ground warms towards the goal.
    final base = inMonth ? Noc.surface : Colors.transparent;
    final ground = selected
        ? Noc.accent900
        : stepFraction == null
            ? base
            : Color.lerp(base, Noc.accent800, stepFraction!)!;
    final numberColor = !inMonth
        ? Noc.neutral700
        : selected || isToday
            ? Noc.accent200
            : Noc.text;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: ground,
          borderRadius: BorderRadius.circular(Noc.rControl),
          border: Border.all(color: selected ? Noc.accent : (isToday ? Noc.accent700 : Colors.transparent)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w500, fontVariations: Noc.w500, color: numberColor),
            ),
            const SizedBox(height: 5),
            SizedBox(
              height: 6,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < done.clamp(0, 3); i++) ...[
                    if (i > 0) const SizedBox(width: 3),
                    Container(width: 5, height: 5, decoration: const BoxDecoration(color: Noc.accent, shape: BoxShape.circle)),
                  ],
                  for (var i = 0; i < planned.clamp(0, 2); i++) ...[
                    if (done > 0 || i > 0) const SizedBox(width: 3),
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: inMonth ? Noc.line : Noc.divider)),
                    ),
                  ],
                  if (dueGoals > 0) ...[
                    if (done > 0 || planned > 0) const SizedBox(width: 3),
                    Container(width: 5, height: 5, decoration: BoxDecoration(color: Noc.accent300, borderRadius: BorderRadius.circular(1.5))),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label, this.outlined = false, this.square = false});
  final Color color;
  final String label;
  final bool outlined;
  final bool square;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: outlined ? Colors.transparent : color,
              shape: square ? BoxShape.rectangle : BoxShape.circle,
              borderRadius: square ? BorderRadius.circular(1.5) : null,
              border: outlined ? Border.all(color: color) : null,
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: Noc.tiny),
        ],
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            Text(value, style: Noc.statSm),
            const SizedBox(height: 2),
            Text(label, style: Noc.small, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      );
}

/// A session that already happened. There is nothing to open — it is done —
/// so the row is a record, not a button.
class _DoneRow extends StatelessWidget {
  const _DoneRow({required this.log});
  final WorkoutLog log;

  @override
  Widget build(BuildContext context) {
    final minutes = (log.durationSec / 60).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: Noc.card(radius: Noc.rRow),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Noc.accent900, borderRadius: BorderRadius.circular(Noc.rIcon)),
            child: const Icon(Nx.check, size: 13, color: Noc.accent300),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(log.routineName.isEmpty ? 'Session' : log.routineName, style: Noc.cardTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 1),
                Text(
                  [
                    if (log.dayTitle.isNotEmpty) log.dayTitle,
                    if (log.sets > 0) '${log.sets} sets',
                    if (minutes > 0) '${minutes}m',
                    DateFormat.jm().format(log.completedAt),
                  ].join(' · '),
                  style: Noc.meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A goal falling due on the selected day.
class _DueRow extends StatelessWidget {
  const _DueRow({required this.goal});
  final PersonalGoal goal;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: Noc.card(radius: Noc.rRow, border: Noc.hairlineAccentLift),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Noc.accent900, borderRadius: BorderRadius.circular(Noc.rIcon)),
              child: const Icon(Nx.target, size: 13, color: Noc.accent300),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(goal.name, style: Noc.cardTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 1),
                  Text('Goal due · ${goal.value}', style: Noc.meta),
                ],
              ),
            ),
            NocBarSmall(pct: goal.pct),
          ],
        ),
      );
}

/// The goal's progress as a short bar, sized for a row's trailing edge.
class NocBarSmall extends StatelessWidget {
  const NocBarSmall({super.key, required this.pct});
  final double pct;

  @override
  Widget build(BuildContext context) => SizedBox(width: 46, child: NocBar(pct: pct, height: 5, track: Noc.sunken));
}
