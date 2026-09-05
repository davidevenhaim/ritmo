import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ritmo/core/ai_coach.dart';
import 'package:ritmo/core/exercise_repository.dart';
import 'package:ritmo/core/models.dart';
import 'package:ritmo/core/session_theme.dart';

ExerciseRepository loadRepo() {
  final raw = File('assets/data/exercises.json').readAsStringSync();
  final list = (jsonDecode(raw) as List).map((e) => Exercise.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  return ExerciseRepository(list);
}

const profile = UserProfile(
  id: 'me', name: 'Test Athlete', handle: 'test', emoji: '🙂',
  heightCm: 175, weightKg: 70, age: 30, goal: Goal.buildMuscle,
  diet: ['Vegan', 'Nut allergy'], equipment: ['body only', 'dumbbell'], daysPerWeek: 3,
);

void main() {
  final repo = loadRepo();

  test('bundled catalogue merges four sources with unique ids', () {
    expect(repo.all.length, greaterThan(1400));
    expect(repo.all.map((e) => e.id).toSet().length, repo.all.length);
    expect(repo.all.where((e) => e.source == 'free-exercise-db').length, 876);
    expect(repo.all.where((e) => e.source == 'repdb').length, 484);
    expect(repo.all.where((e) => e.source == 'yoga-api').length, 47);
    expect(repo.all.where((e) => e.source == 'sogym-editorial').length, 36);
    expect(repo.byId('Barbell_Squat')?.primary, contains('quadriceps'));
    // Every record the UI renders needs a name and a category at minimum.
    expect(repo.all.every((e) => e.name.isNotEmpty && e.category.isNotEmpty), isTrue);
  });

  test('every exercise is graded beginner, intermediate or advanced', () {
    // The app filters, groups and recommends by grade, so an ungraded row —
    // or one carrying a source's own vocabulary like "expert" — is a bug.
    final levels = repo.all.map((e) => e.level).toSet();
    expect(levels, unorderedEquals(ExerciseLevel.catalogue));
    for (final e in repo.all) {
      expect(ExerciseLevel.of(e.level), isNotNull, reason: '${e.name} is graded "${e.level}"');
    }
    // Each grade is worth showing: none of the three is a rounding error.
    for (final l in ExerciseLevel.values) {
      final n = repo.all.where((e) => ExerciseLevel.of(e.level) == l).length;
      expect(n, greaterThan(50), reason: '${l.label} has only $n exercises');
    }
  });

  test('the in-house rows fill the ends of the ladder', () {
    final ours = repo.all.where((e) => e.source == 'sogym-editorial').toList();
    expect(ours.length, 36);
    for (final e in ours) {
      expect(e.id, startsWith('sogym_'));
      expect(e.instructions, isNotEmpty, reason: '${e.name} has no cues');
      expect(e.primary, isNotEmpty, reason: '${e.name} works nothing');
      expect(ExerciseLevel.of(e.level), isNotNull);
    }
    expect(ours.where((e) => e.level == 'beginner'), isNotEmpty);
    expect(ours.where((e) => e.level == 'advanced'), isNotEmpty);
  });

  test('experience maps onto the catalogue grades', () {
    expect(ExperienceLevel.beginner.allows('beginner'), isTrue);
    expect(ExperienceLevel.beginner.allows('intermediate'), isFalse);
    expect(ExperienceLevel.beginner.allows('advanced'), isFalse);
    expect(ExperienceLevel.intermediate.allows('advanced'), isFalse);
    expect(ExperienceLevel.advanced.allows('advanced'), isTrue);
    // The old vocabulary still resolves, so a stale asset is not a lockout.
    expect(ExperienceLevel.advanced.allows('expert'), isTrue);
    expect(ExperienceLevel.advanced.exerciseLevel, ExerciseLevel.advanced);
  });

  test('a theme library can be split by grade', () {
    for (final theme in SessionTheme.values) {
      final counts = repo.levelCounts(theme);
      expect(counts.values.fold(0, (a, b) => a + b), repo.countFor(theme), reason: theme.name);
      for (final l in ExerciseLevel.values) {
        final only = repo.forTheme(theme, level: l);
        expect(only.length, counts[l], reason: '${theme.name}/${l.label}');
        expect(only.every((e) => ExerciseLevel.of(e.level) == l), isTrue);
      }
    }
  });

  test('search filters by muscle, equipment and allowed equipment', () {
    final chest = repo.search(muscle: 'chest', equipment: 'dumbbell');
    expect(chest, isNotEmpty);
    expect(chest.every((e) => e.equipment == 'dumbbell'), isTrue);
    final restricted = repo.search(muscle: 'chest', allowedEquipment: ['body only']);
    expect(restricted.every((e) => ['body only', 'none', 'other'].contains(e.equipment)), isTrue);
    expect(repo.search(query: 'squat').first.name.toLowerCase(), startsWith('squat'));
  });

  test('offline coach builds a plan matching days per week and equipment', () async {
    final reply = await LocalCoach().reply(
      history: const [ChatMessage(role: 'user', text: 'Build me a plan')],
      profile: profile,
      repo: repo,
    );
    final r = reply.routine!;
    expect(r.days.length, 3);
    expect(r.exerciseCount, greaterThan(6));
    for (final it in r.days.expand((d) => d.items)) {
      final e = repo.byId(it.exerciseId)!;
      expect(['body only', 'dumbbell', 'none', 'other'], contains(e.equipment));
    }
    expect(r.source, 'ai');
  });

  test('offline coach diet advice respects vegan and nut allergy', () async {
    final reply = await LocalCoach().reply(
      history: const [ChatMessage(role: 'user', text: 'What should I eat?')],
      profile: profile,
      repo: repo,
    );
    final text = reply.text.toLowerCase();
    expect(text, isNot(contains('chicken')));
    expect(text, isNot(contains('peanut')));
    expect(text, contains('tofu'));
  });

  test('save_plan tool payload converts to a routine and drops unknown ids', () {
    final routine = planToRoutine({
      'name': 'Test plan',
      'description': 'desc',
      'days': [
        {
          'title': 'Day 1',
          'focus': 'Legs',
          'exercises': [
            {'exercise_id': 'Barbell_Squat', 'sets': 5, 'reps': 5, 'rest_sec': 120, 'notes': ''},
            {'exercise_id': 'does_not_exist', 'sets': 3, 'reps': 10, 'rest_sec': 60, 'notes': ''},
          ]
        }
      ],
      'nutrition_notes': 'Eat well',
      'weekly_step_goal': 9000,
    }, repo, profile);
    expect(routine.days.single.items.length, 1);
    expect(routine.days.single.items.single.sets, 5);
    expect(routine.description, contains('Nutrition: Eat well'));
  });

  test('models round-trip through JSON', () {
    final r = planToRoutine({
      'name': 'RT', 'description': '', 'nutrition_notes': '', 'weekly_step_goal': 1,
      'days': [{'title': 'D', 'focus': 'F', 'exercises': [{'exercise_id': 'Pushups', 'sets': 3, 'reps': 12, 'rest_sec': 45, 'notes': 'slow'}]}],
    }, repo, profile);
    final back = Routine.fromJson(jsonDecode(jsonEncode(r.toJson())));
    expect(back.days.single.items.single.notes, 'slow');
    final p = UserProfile.fromJson(jsonDecode(jsonEncode(profile.toJson())));
    expect(p.diet, ['Vegan', 'Nut allergy']);
    expect(p.goal, Goal.buildMuscle);
  });
}
