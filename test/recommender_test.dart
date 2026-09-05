import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ritmo/core/exercise_repository.dart';
import 'package:ritmo/core/models.dart';
import 'package:ritmo/core/recommender.dart';
import 'package:ritmo/core/session_theme.dart';
import 'package:ritmo/core/social_repository.dart';

const base = UserProfile(
  id: 'me', name: 'Test Athlete', handle: 'test', emoji: '🙂',
  heightCm: 178, weightKg: 74, age: 30, goal: Goal.buildMuscle,
  diet: [], equipment: ['body only', 'dumbbell'], daysPerWeek: 3,
  experience: ExperienceLevel.intermediate,
);

ExerciseRepository loadCatalogue() {
  final raw = File('assets/data/exercises.json').readAsStringSync();
  return ExerciseRepository((jsonDecode(raw) as List).map((e) => Exercise.fromJson(Map<String, dynamic>.from(e as Map))).toList());
}

void main() {
  late ExerciseRepository repo;
  setUpAll(() => repo = loadCatalogue());

  SessionSuggestion suggest(UserProfile me, {List<WorkoutLog> recent = const [], int nudge = 0}) {
    final s = Recommender.suggest(
      me: me,
      repo: repo,
      recent: recent,
      library: [...SeedData.readyMade, ...SeedData.coachProgrammes],
      nudge: nudge,
    );
    expect(s, isNotNull, reason: 'every profile gets a session');
    return s!;
  }

  test('only offers exercises the athlete owns the gear for', () {
    final s = suggest(base);
    for (final e in s.exercises) {
      expect(
        ['body only', 'dumbbell', 'none', 'other'],
        contains(e.equipment),
        reason: '${e.name} needs ${e.equipment}',
      );
    }
    expect(s.items.length, s.exercises.length);
    expect(s.minutes, greaterThan(0));
  });

  test('a beginner is only offered beginner-graded work', () {
    final s = suggest(base.copyWith(experience: ExperienceLevel.beginner));
    for (final e in s.exercises) {
      expect(e.level, anyOf(isNull, 'beginner'), reason: e.name);
    }
    expect(s.reasons, contains('Beginner-friendly'));
    // One exercise fewer and one set fewer than the same athlete a level up.
    final up = suggest(base.copyWith(experience: ExperienceLevel.intermediate));
    expect(s.exercises.length, lessThan(up.exercises.length));
    expect(s.items.first.sets, lessThan(up.items.first.sets));
  });

  test('a session is spread across muscles, with no near-twin exercises', () {
    final s = suggest(base.copyWith(equipment: [...equipmentOptions]));
    final muscles = {for (final e in s.exercises) ...e.primary};
    expect(muscles.length, greaterThanOrEqualTo(3), reason: 'not five variations of one movement');

    final families = <String>{};
    for (final e in s.exercises) {
      final key = e.name.toLowerCase().split(' ').take(2).join(' ');
      expect(families.add(key), isTrue, reason: 'two of the same movement: ${e.name}');
    }
    // Nothing is offered twice.
    expect(s.exercises.map((e) => e.id).toSet(), hasLength(s.exercises.length));
  });

  test('the goal moves the reps and the rest, not just the label', () {
    final strong = suggest(base.copyWith(goal: Goal.getStronger));
    final muscle = suggest(base.copyWith(goal: Goal.buildMuscle));
    final fat = suggest(base.copyWith(goal: Goal.loseFat));

    expect(strong.items.first.reps, lessThan(muscle.items.first.reps));
    expect(strong.items.first.restSec, greaterThan(muscle.items.first.restSec));
    expect(fat.items.first.restSec, lessThan(muscle.items.first.restSec));
    expect(strong.reasons.first, 'Get stronger');
  });

  test('mobility goals come back held, not repeated', () {
    final s = suggest(base.copyWith(goal: Goal.mobility));
    expect(s.theme, SessionTheme.flexibility);
    expect(s.items.first.notes, startsWith('Hold '));
  });

  test('age and body stats keep the impact down', () {
    final older = suggest(base.copyWith(age: 62, goal: Goal.loseFat));
    expect(older.reasons, contains('Low-impact'));
    for (final e in older.exercises) {
      expect(e.category, isNot('plyometrics'));
      expect(e.name.toLowerCase(), isNot(contains('jump')));
    }
    // The same athlete at 30 is allowed the jumping work.
    expect(suggest(base.copyWith(goal: Goal.loseFat)).reasons, isNot(contains('Low-impact')));
  });

  test('what was trained yesterday gets a rest', () {
    final log = WorkoutLog(
      id: 'l1',
      userId: 'me',
      routineId: SeedData.pushPullLegs.id,
      routineName: SeedData.pushPullLegs.name,
      dayTitle: 'Push',
      completedAt: DateTime.now().subtract(const Duration(hours: 14)),
    );
    final fresh = suggest(base.copyWith(equipment: [...equipmentOptions]));
    final after = suggest(base.copyWith(equipment: [...equipmentOptions]), recent: [log]);

    expect(after.exercises.any((e) => e.primary.contains('chest')), isFalse);
    expect(after.reasons.any((r) => r.endsWith('is resting')), isTrue);
    expect(fresh.exercises, isNotEmpty);
  });

  test('the shuffle moves to another theme instead of redrawing the same one', () {
    final a = suggest(base);
    final b = suggest(base, nudge: 1);
    expect(b.theme, isNot(a.theme));
  });

  test('the suggestion becomes a runnable routine', () {
    final s = suggest(base);
    final r = s.toRoutine(base);
    expect(r.days, hasLength(1));
    expect(r.exerciseCount, s.items.length);
    expect(r.days.first.items.first.exerciseId, s.exercises.first.id);
    expect(r.description, contains(base.goal.label));
  });

  test('every seeded routine points at exercises that exist', () {
    for (final r in [...SeedData.readyMade, ...SeedData.coachProgrammes]) {
      for (final item in r.days.expand((d) => d.items)) {
        expect(repo.byId(item.exerciseId), isNotNull, reason: '${r.name}: ${item.exerciseId}');
      }
    }
  });

  test('studio classes land on the next occurrence of their weekday', () {
    for (final studio in SeedData.studios) {
      expect(studio.classes, isNotEmpty);
      for (final k in studio.classes) {
        final at = k.nextAt(DateTime(2026, 9, 5, 12));
        expect(at.weekday, k.weekday);
        expect(at.hour, k.hour);
        expect(at.isAfter(DateTime(2026, 9, 5, 12)), isTrue);
        expect(at.difference(DateTime(2026, 9, 5, 12)).inDays, lessThan(8));
      }
    }
  });
}
