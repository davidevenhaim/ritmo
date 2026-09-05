import 'exercise_repository.dart';
import 'models.dart';
import 'session_theme.dart';

/// What the Start button offers: a session picked for this athlete, right now.
///
/// Nothing here is generated text. Every exercise comes out of the bundled
/// catalogue after four hard filters — the gear they own, the level they train
/// at, what their goal actually asks for, and what they trained in the last
/// two days — and the sets, reps and rest come from the theme adjusted for the
/// goal and the experience level. [reasons] is the short list the card shows,
/// so the suggestion can always explain itself.
class SessionSuggestion {
  const SessionSuggestion({
    required this.theme,
    required this.name,
    required this.focus,
    required this.exercises,
    required this.items,
    required this.reasons,
  });

  final SessionTheme theme;
  final String name;

  /// "chest · shoulders" — the muscles the picks actually cover.
  final String focus;
  final List<Exercise> exercises;
  final List<RoutineItem> items;
  final List<String> reasons;

  bool get isEmpty => items.isEmpty;

  /// Same estimate the plan uses: every set costs its rest plus about forty
  /// seconds of work (a held exercise costs its hold instead).
  int get minutes {
    var sec = 0;
    for (final i in items) {
      final work = i.notes.startsWith('Hold ') ? theme.reps : 40;
      sec += i.sets * (i.restSec + work);
    }
    return (sec / 60).round();
  }

  /// A routine the player can run. Not saved to the library until the athlete
  /// keeps it, so a suggestion never clutters their routines.
  Routine toRoutine(UserProfile me) => Routine(
        id: 'suggested_${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        description: 'Picked for you: ${reasons.join(' · ')}.',
        authorId: me.id,
        authorName: me.name,
        createdAt: DateTime.now(),
        tags: [theme.name.toLowerCase(), 'suggested'],
        days: [RoutineDay(title: theme.name, focus: focus, items: items)],
      );
}

/// Picks a session from the profile. Pure, so it is testable and gives the
/// same answer twice for the same inputs; [nudge] is what the shuffle control
/// turns to walk further down the ranked pool.
class Recommender {
  static SessionSuggestion? suggest({
    required UserProfile me,
    required ExerciseRepository repo,
    List<WorkoutLog> recent = const [],
    List<Routine> library = const [],
    int nudge = 0,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final tired = _recentMuscles(recent, library, repo, today);
    final lowImpact = me.age >= 55 || me.bmi >= 30;

    for (final theme in _themesFor(me.goal, nudge)) {
      final picks = _pick(me: me, repo: repo, theme: theme, tired: tired, lowImpact: lowImpact, nudge: nudge);
      if (picks.exercises.length < 3) continue;

      final sets = _sets(theme, me);
      final reps = _reps(theme, me);
      final rest = _rest(theme, me);
      final items = [
        for (final e in picks.exercises)
          RoutineItem(
            exerciseId: e.id,
            exerciseName: e.name,
            sets: sets,
            reps: theme.hold ? 1 : reps,
            restSec: rest,
            notes: theme.hold ? 'Hold ${reps}s' : '',
          ),
      ];
      final focus = _focus(picks.exercises);

      return SessionSuggestion(
        theme: theme,
        name: '${theme.name} · ${focus.split(' · ').first}',
        focus: focus,
        exercises: picks.exercises,
        items: items,
        reasons: [
          me.goal.label,
          picks.kitLabel,
          _experienceLabel(me.experience, picks.levelHeld),
          if (lowImpact) 'Low-impact',
          if (picks.rested.isNotEmpty) '${picks.rested.first} is resting',
        ],
      );
    }
    return null;
  }

  // ------------------------------------------------------------- themes
  /// Which themes serve a goal, best first. The nudge rotates the list so the
  /// shuffle can move the athlete to the next reasonable theme rather than
  /// re-drawing the same one.
  static List<SessionTheme> _themesFor(Goal goal, int nudge) {
    final order = switch (goal) {
      Goal.buildMuscle => [SessionTheme.gym, SessionTheme.calisthenics, SessionTheme.bodyweight, SessionTheme.core],
      Goal.getStronger => [SessionTheme.gym, SessionTheme.calisthenics, SessionTheme.core, SessionTheme.bodyweight],
      Goal.loseFat => [SessionTheme.bodyweight, SessionTheme.gym, SessionTheme.core, SessionTheme.calisthenics],
      Goal.endurance => [SessionTheme.bodyweight, SessionTheme.core, SessionTheme.calisthenics, SessionTheme.gym],
      Goal.mobility => [SessionTheme.flexibility, SessionTheme.core, SessionTheme.bodyweight, SessionTheme.handstand],
      Goal.generalHealth => [SessionTheme.bodyweight, SessionTheme.flexibility, SessionTheme.core, SessionTheme.gym],
    };
    if (nudge <= 0) return order;
    final at = nudge % order.length;
    return [...order.skip(at), ...order.take(at)];
  }

  // -------------------------------------------------------------- picks
  static ({List<Exercise> exercises, String kitLabel, List<String> rested, bool levelHeld}) _pick({
    required UserProfile me,
    required ExerciseRepository repo,
    required SessionTheme theme,
    required Set<String> tired,
    required bool lowImpact,
    required int nudge,
  }) {
    final pool = repo.forTheme(theme, allowedEquipment: me.equipment);

    bool impactOk(Exercise e) {
      if (!lowImpact) return true;
      final n = e.name.toLowerCase();
      return e.category != 'plyometrics' && !n.contains('jump') && !n.contains('burpee') && !n.contains('hop');
    }

    var levelHeld = true;
    var candidates = pool.where((e) => me.experience.allows(e.level) && impactOk(e)).toList();
    if (candidates.length < 4) {
      // The athlete's gear plus their level left too little to program with;
      // the level is the softer of the two constraints, so it gives first.
      levelHeld = false;
      candidates = pool.where(impactOk).toList();
    }
    if (candidates.length < 4) candidates = pool;

    final want = _size(me);
    final used = <String, int>{};
    final families = <String>{};
    final rested = <String>{};
    final out = <Exercise>[];

    // Four passes over the ranked pool. One exercise per muscle group first,
    // so a session reads as a session rather than five variations of a row;
    // then a second per group to fill it out. Muscles trained in the last two
    // days are skipped until the pool has nothing else left to offer.
    for (final skipTired in [true, false]) {
      for (final cap in [1, 2]) {
        for (var i = 0; i < candidates.length && out.length < want; i++) {
          final e = candidates[(i + nudge * 3) % candidates.length];
          if (out.contains(e)) continue;
          final primary = e.primary.isEmpty ? [e.category] : e.primary;
          if (skipTired && primary.any(tired.contains)) {
            rested.addAll(primary.where(tired.contains));
            continue;
          }
          if (primary.any((m) => (used[m] ?? 0) >= cap)) continue;
          if (!families.add(_family(e.name))) continue;
          for (final m in primary) {
            used[m] = (used[m] ?? 0) + 1;
          }
          out.add(e);
        }
      }
      if (out.length >= want) break;
    }

    final kit = {for (final e in out) e.equipment}..removeWhere((k) => k == 'none' || k == 'other');
    return (
      exercises: out,
      kitLabel: kit.isEmpty ? 'No kit needed' : kit.take(2).join(' · '),
      rested: rested.toList()..sort(),
      levelHeld: levelHeld,
    );
  }

  /// The catalogue carries a lot of near-twins — "Bent Over Two-Dumbbell Row"
  /// and "…With Palms In" — and stacking them makes a session look picked by
  /// a machine. Two exercises sharing their first two words are the same
  /// movement as far as one session is concerned.
  static String _family(String name) {
    final words = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    return words.take(2).join(' ');
  }

  /// Fewer, longer sessions for someone who trains three days a week; shorter
  /// ones for someone in the gym six times. Beginners get one exercise less.
  static int _size(UserProfile me) {
    final base = switch (me.daysPerWeek) { <= 3 => 6, <= 5 => 5, _ => 4 };
    return me.experience == ExperienceLevel.beginner ? (base - 1).clamp(4, 6) : base;
  }

  static int _sets(SessionTheme theme, UserProfile me) => switch (me.experience) {
        ExperienceLevel.beginner => (theme.sets - 1).clamp(2, 5),
        ExperienceLevel.intermediate => theme.sets,
        ExperienceLevel.advanced => theme.hold ? theme.sets : theme.sets + 1,
      };

  static int _reps(SessionTheme theme, UserProfile me) {
    if (theme.hold) return theme.reps;
    return switch (me.goal) {
      Goal.getStronger => (theme.reps - 3).clamp(4, 20),
      Goal.loseFat || Goal.endurance => theme.reps + 2,
      _ => theme.reps,
    };
  }

  static int _rest(SessionTheme theme, UserProfile me) => switch (me.goal) {
        Goal.getStronger => theme.restSec + 30,
        Goal.loseFat || Goal.endurance => (theme.restSec - 15).clamp(15, 240),
        _ => theme.restSec,
      };

  /// "chest · shoulders · triceps" from what the picks actually work.
  static String _focus(List<Exercise> picks) {
    final count = <String, int>{};
    for (final e in picks) {
      for (final m in (e.primary.isEmpty ? [e.category] : e.primary)) {
        count[m] = (count[m] ?? 0) + 1;
      }
    }
    final top = count.keys.toList()..sort((a, b) => count[b]!.compareTo(count[a]!));
    return top.take(3).join(' · ');
  }

  static String _experienceLabel(ExperienceLevel level, bool held) {
    if (!held) return 'Everything you own';
    return switch (level) {
      ExperienceLevel.beginner => 'Beginner-friendly',
      ExperienceLevel.intermediate => 'Intermediate',
      ExperienceLevel.advanced => 'Advanced',
    };
  }

  /// Muscles trained in the last 48 hours, resolved from the logged sessions
  /// back through the routine that was run — the day that was actually done
  /// where the log names it, so finishing push day does not retire the whole
  /// split. Sessions we cannot resolve simply do not constrain the pick.
  static Set<String> _recentMuscles(List<WorkoutLog> logs, List<Routine> library, ExerciseRepository repo, DateTime now) {
    final out = <String>{};
    for (final log in logs) {
      if (now.difference(log.completedAt) > const Duration(hours: 48)) continue;
      final r = library.where((x) => x.id == log.routineId).firstOrNull;
      if (r == null) continue;
      final done = r.days.where((d) => d.title == log.dayTitle);
      for (final day in done.isEmpty ? r.days : done) {
        for (final item in day.items) {
          out.addAll(repo.byId(item.exerciseId)?.primary ?? const []);
        }
      }
    }
    return out;
  }
}
