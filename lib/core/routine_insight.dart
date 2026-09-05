import 'exercise_repository.dart';
import 'models.dart';

/// What a routine actually asks of you, read out of the catalogue (v0.10).
///
/// A routine arrives from a friend or a coach as a list of exercise ids. This
/// resolves every one of them so the athlete can see what they are agreeing to
/// *before* they accept it: how hard it is, which muscles it hits, what kit it
/// needs and how much of that kit they own.
///
/// Pure and synchronous — it takes the loaded catalogue and gives the same
/// answer twice, so it is testable and safe to build inside a `build`.
class RoutineInsight {
  const RoutineInsight._({
    required this.routine,
    required this.levelCounts,
    required this.ungraded,
    required this.muscles,
    required this.equipment,
    required this.minutes,
    required this.dayMinutes,
  });

  factory RoutineInsight.of(Routine routine, ExerciseRepository repo) {
    final counts = {for (final l in ExerciseLevel.values) l: 0};
    final muscles = <String, int>{};
    final kit = <String>{};
    final dayMinutes = <int>[];
    var ungraded = 0;

    for (final day in routine.days) {
      var sec = 0;
      for (final item in day.items) {
        sec += item.sets * (item.restSec + workSeconds);
        final e = repo.byId(item.exerciseId);
        final level = ExerciseLevel.of(e?.level);
        if (level == null) {
          ungraded++;
        } else {
          counts[level] = counts[level]! + 1;
        }
        if (e == null) continue;
        for (final m in (e.primary.isEmpty ? [e.category] : e.primary)) {
          muscles[m] = (muscles[m] ?? 0) + 1;
        }
        if (!_bare.contains(e.equipment)) kit.add(e.equipment);
      }
      dayMinutes.add((sec / 60).round());
    }

    final ranked = muscles.keys.toList()
      ..sort((a, b) => muscles[b] != muscles[a] ? muscles[b]!.compareTo(muscles[a]!) : a.compareTo(b));

    return RoutineInsight._(
      routine: routine,
      levelCounts: Map.unmodifiable(counts),
      ungraded: ungraded,
      muscles: List.unmodifiable(ranked),
      equipment: List.unmodifiable(kit.toList()..sort()),
      minutes: dayMinutes.fold(0, (a, b) => a + b),
      dayMinutes: List.unmodifiable(dayMinutes),
    );
  }

  final Routine routine;

  /// How the routine's exercises split across the three grades.
  final Map<ExerciseLevel, int> levelCounts;

  /// Exercises we could not resolve in the catalogue (a hand-typed routine, or
  /// one built against a newer asset). They are shown, never hidden.
  final int ungraded;

  /// Primary muscles, most-worked first.
  final List<String> muscles;

  /// Kit the routine needs, bodyweight excluded.
  final List<String> equipment;

  final int minutes;
  final List<int> dayMinutes;

  /// Every set costs its rest plus about forty seconds of work — the same
  /// estimate the plan, the Start card and the coach cards use.
  static const workSeconds = 40;

  static const _bare = {'none', 'other', 'body only'};

  int get graded => levelCounts.values.fold(0, (a, b) => a + b);

  /// The grade the routine reads as: the most common one, and the harder of
  /// the two when it is a tie — a session is as hard as its hardest half.
  ExerciseLevel? get level {
    if (graded == 0) return null;
    ExerciseLevel? best;
    for (final l in ExerciseLevel.values) {
      if (best == null || levelCounts[l]! >= levelCounts[best]!) best = l;
    }
    return best;
  }

  /// Share of the graded exercises at [l], 0-1. Drives the level bar.
  double share(ExerciseLevel l) => graded == 0 ? 0 : levelCounts[l]! / graded;

  /// Kit the routine needs that the athlete has not said they own.
  List<String> missingEquipment(UserProfile me) => [
    for (final e in equipment)
      if (!me.equipment.contains(e)) e,
  ];

  /// One line on whether this routine sits where the athlete trains. Null when
  /// nothing in it resolved, so the UI can stay quiet rather than guess.
  String? verdict(UserProfile me) {
    final l = level;
    if (l == null) return null;
    final steps = l.index - me.experience.exerciseLevel.index;
    return switch (steps) {
      0 => 'Sits where you train',
      1 => 'A step above your level',
      >= 2 => 'Well above your level',
      -1 => 'A step below your level',
      _ => 'Well below your level',
    };
  }
}

/// What happened to one exercise when a routine was re-levelled.
enum SwapKind {
  /// Already at the target grade; only the sets and rest moved.
  kept,

  /// Replaced by a different movement at the target grade.
  swapped,

  /// The catalogue has nothing at that grade for this muscle, so the original
  /// stays. Said out loud rather than silently dropped.
  unavailable,
}

class ExerciseSwap {
  const ExerciseSwap({
    required this.day,
    required this.index,
    required this.from,
    required this.to,
    required this.kind,
    required this.reason,
    this.fromExercise,
    this.toExercise,
  });

  final int day;
  final int index;
  final RoutineItem from;
  final RoutineItem to;
  final Exercise? fromExercise;
  final Exercise? toExercise;
  final SwapKind kind;

  /// Short line the preview prints under a swapped row.
  final String reason;

  bool get changed => kind == SwapKind.swapped;
}

/// A routine re-levelled, plus the record of what moved and why.
class LevelledRoutine {
  const LevelledRoutine({required this.routine, required this.source, required this.target, required this.swaps});

  /// The adapted routine. Same shape, same day titles, same order.
  final Routine routine;

  /// The grade the original read as.
  final ExerciseLevel? source;
  final ExerciseLevel target;
  final List<ExerciseSwap> swaps;

  int get swapped => swaps.where((s) => s.kind == SwapKind.swapped).length;
  int get unavailable => swaps.where((s) => s.kind == SwapKind.unavailable).length;

  ExerciseSwap? at(int day, int index) => swaps.where((s) => s.day == day && s.index == index).firstOrNull;

  String get summary {
    if (swapped == 0) {
      return unavailable > 0
          ? 'Nothing at ${target.label.toLowerCase()} level to swap in — the sets and rest are tuned instead'
          : 'Already ${target.label.toLowerCase()} — only the sets and rest change';
    }
    final ex = swapped == 1 ? 'exercise' : 'exercises';
    final tail = unavailable == 0 ? '' : ', $unavailable kept as they are';
    return '$swapped $ex swapped for ${target.label.toLowerCase()} ones$tail';
  }
}

/// Re-levels somebody else's routine (v0.10).
///
/// The shape of the session is the author's and stays untouched — same days,
/// same order, same muscle worked in the same slot. Only the movement in each
/// slot changes, to one the catalogue grades at the level asked for, and then
/// the sets and rest shift with it. That is why this is a swap rather than a
/// fresh recommendation: an athlete accepting a coach's programme at an easier
/// grade should still be doing the coach's programme.
///
/// Pure, like [Recommender], so the same routine always levels the same way.
class RoutineLeveller {
  const RoutineLeveller._();

  static LevelledRoutine to({
    required Routine routine,
    required ExerciseRepository repo,
    required ExerciseLevel target,
    List<String> owned = const [],
  }) {
    final source = RoutineInsight.of(routine, repo).level;
    final steps = source == null ? 0 : target.index - source.index;

    // Nothing in the routine may be used twice, and nothing already in it may
    // be swapped in, so a levelled session does not repeat itself.
    final taken = <String>{
      for (final d in routine.days)
        for (final i in d.items) i.exerciseId,
    };

    final swaps = <ExerciseSwap>[];
    final days = <RoutineDay>[];

    for (var di = 0; di < routine.days.length; di++) {
      final day = routine.days[di];
      final items = <RoutineItem>[];
      for (var ii = 0; ii < day.items.length; ii++) {
        final item = day.items[ii];
        final src = repo.byId(item.exerciseId);
        final level = ExerciseLevel.of(src?.level);

        Exercise? pick;
        if (src != null && level != target) {
          pick = _alternative(src: src, repo: repo, target: target, taken: taken, owned: owned);
        }

        final tuned = _tune(item, steps);
        if (pick != null) {
          taken.add(pick.id);
          final to = RoutineItem(
            exerciseId: pick.id,
            exerciseName: pick.name,
            sets: tuned.sets,
            reps: tuned.reps,
            restSec: tuned.restSec,
            notes: item.notes,
          );
          items.add(to);
          swaps.add(
            ExerciseSwap(
              day: di,
              index: ii,
              from: item,
              to: to,
              fromExercise: src,
              toExercise: pick,
              kind: SwapKind.swapped,
              reason: _reason(src!, pick, owned),
            ),
          );
        } else {
          items.add(tuned);
          swaps.add(
            ExerciseSwap(
              day: di,
              index: ii,
              from: item,
              to: tuned,
              fromExercise: src,
              toExercise: src,
              kind: level == target ? SwapKind.kept : SwapKind.unavailable,
              reason: level == target
                  ? 'Already ${target.label.toLowerCase()}'
                  : 'No ${target.label.toLowerCase()} version of this in the library',
            ),
          );
        }
      }
      days.add(day.copyWith(items: items));
    }

    return LevelledRoutine(
      routine: routine.copyWith(
        name: '${routine.name} · ${target.label}',
        description: routine.description.isEmpty
            ? '${target.label} version of ${routine.authorName}\'s routine.'
            : '${routine.description}\n\n${target.label} version of ${routine.authorName}\'s routine.',
        days: days,
        tags: [...routine.tags, '${target.label.toLowerCase()} version'],
      ),
      source: source,
      target: target,
      swaps: swaps,
    );
  }

  /// The best stand-in for [src] at [target]. Scored rather than filtered, so
  /// a thin corner of the catalogue still returns the nearest thing instead of
  /// nothing — but a candidate that shares no muscle is never returned.
  static Exercise? _alternative({
    required Exercise src,
    required ExerciseRepository repo,
    required ExerciseLevel target,
    required Set<String> taken,
    required List<String> owned,
  }) {
    final srcPrimary = src.primary.toSet();
    final srcSecondary = src.secondary.toSet();
    Exercise? best;
    var bestScore = 0;

    for (final e in repo.all) {
      if (ExerciseLevel.of(e.level) != target) continue;
      if (taken.contains(e.id)) continue;
      // A mobility flow stays a mobility flow. Every other category can trade
      // with its neighbours, but a stretch swapped for a deadlift is not the
      // same routine at another level, it is a different routine.
      if (_isMobility(e.category) != _isMobility(src.category)) continue;

      final primary = e.primary.toSet();
      final shared = primary.intersection(srcPrimary).length;
      var score = 0;
      if (shared > 0) {
        score += 8 + shared * 2;
        if (primary.length == srcPrimary.length && shared == srcPrimary.length) score += 3;
      } else if (srcPrimary.isEmpty && primary.isEmpty && e.category == src.category) {
        score += 6;
      } else if (primary.intersection(srcSecondary).isNotEmpty) {
        // A near miss — the same region worked, not the same prime mover.
        score += 3;
      } else {
        continue;
      }

      if (e.category == src.category) score += 3;
      // Direction matters more than the muscle label: swapping a face pull
      // for a handstand push-up works the same shoulders and trains the
      // opposite thing.
      if (e.force != null && src.force != null) score += e.force == src.force ? 5 : -6;
      if (e.mechanic != null && e.mechanic == src.mechanic) score += 2;
      if (e.equipment == src.equipment) score += 2;
      if (_owns(e.equipment, owned)) {
        score += 2;
      } else {
        score -= 4;
      }
      // "Pushups" -> "Pushups - Close Triceps Position" is the same movement
      // graded differently, which is exactly what a level swap wants.
      if (_family(e.name) == _family(src.name)) score += 4;

      if (score > bestScore || (score == bestScore && best != null && e.name.compareTo(best.name) < 0)) {
        best = e;
        bestScore = score;
      }
    }
    return best;
  }

  static const _mobility = {'stretching', 'yoga'};

  static bool _isMobility(String category) => _mobility.contains(category);

  static bool _owns(String equipment, List<String> owned) =>
      RoutineInsight._bare.contains(equipment) || owned.contains(equipment);

  static String _family(String name) {
    final words = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    return words.take(2).join(' ');
  }

  /// Sets and rest carry the difficulty the movement cannot. Reps are left
  /// alone on purpose: they are the author's prescription, and rewriting them
  /// as well turns "the same programme, easier" into a different programme.
  static RoutineItem _tune(RoutineItem item, int steps) {
    if (steps == 0) return item;
    final sets = (item.sets + steps).clamp(2, 6);
    final rest = (item.restSec - steps * 15).clamp(item.restSec == 0 ? 0 : 20, 240);
    return item.copyWith(sets: sets, restSec: rest);
  }

  static String _reason(Exercise from, Exercise to, List<String> owned) {
    final parts = <String>[];
    final shared = to.primary.toSet().intersection(from.primary.toSet());
    if (shared.isNotEmpty) {
      parts.add('same ${shared.first}');
    } else if (to.category == from.category) {
      parts.add('same ${to.category}');
    }
    if (to.equipment != from.equipment) {
      parts.add(
        RoutineInsight._bare.contains(to.equipment)
            ? 'no kit needed'
            : _owns(to.equipment, owned)
            ? 'uses your ${to.equipment}'
            : 'uses ${to.equipment}',
      );
    }
    return parts.isEmpty ? 'closest match in the library' : parts.join(' · ');
  }
}
