import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'exercise_repository.dart';
import 'models.dart';
import 'social_backend.dart';

class CoachReply {
  const CoachReply({required this.text, this.routine});
  final String text;
  final Routine? routine;
}

abstract class Coach {
  /// [onText] receives streamed text deltas when the implementation streams
  /// (the hosted coach does); the full text is still returned in the reply.
  Future<CoachReply> reply({
    required List<ChatMessage> history,
    required UserProfile profile,
    required ExerciseRepository repo,
    List<StepDay> recentSteps = const [],
    void Function(String delta)? onText,
  });
}

String _profileSummary(UserProfile p, List<StepDay> steps) {
  final avg = steps.isEmpty ? null : steps.map((s) => s.steps).reduce((a, b) => a + b) ~/ steps.length;
  return '''
Name: ${p.name} (@${p.handle}), age ${p.age}
Height: ${p.heightCm.toStringAsFixed(0)} cm, weight: ${p.weightKg.toStringAsFixed(1)} kg, BMI ${p.bmi.toStringAsFixed(1)}${p.targetWeightKg != null ? ', target weight ${p.targetWeightKg} kg' : ''}
Goal: ${p.goal.label}
Training days per week: ${p.daysPerWeek}
Available equipment: ${p.equipment.isEmpty ? 'body only' : p.equipment.join(', ')}
Diet restrictions: ${p.diet.isEmpty ? 'none' : p.diet.join(', ')}
Daily step goal: ${p.stepGoal}${avg != null ? ', 7-day average $avg steps' : ''}
''';
}

// ---------------------------------------------------------------------------
// Claude-powered coach (Anthropic Messages API over raw HTTP; there is no
// official Dart SDK). Tools: search_exercises (grounds the plan in the real
// catalogue) and save_plan (structured output the app turns into a Routine).
// ---------------------------------------------------------------------------
class ClaudeCoach implements Coach {
  ClaudeCoach({required this.apiKey, this.model = 'claude-opus-5', http.Client? client})
      : _client = client ?? http.Client();

  final String apiKey;
  final String model;
  final http.Client _client;

  static const _endpoint = 'https://api.anthropic.com/v1/messages';

  static const _systemPrompt = '''
You are the Ritmo Coach: a friendly, precise personal trainer and nutrition guide living inside a social workout app.

How you work:
- Ground every exercise recommendation in the app catalogue. Use the search_exercises tool to find exercises by muscle, equipment, or name, and only reference exercise_ids that came back from that tool.
- Respect the athlete's equipment list, training days, and diet restrictions exactly. Never suggest food that violates a listed restriction.
- When the athlete asks for a plan, program, routine, or schedule, build it and call save_plan once with the complete plan. Keep the number of days equal to their training days per week. After saving, summarise the plan in a few short lines.
- For medical issues, pain, injuries, or eating disorders, give conservative advice and tell them to see a professional.
- Be concise and motivating. Use plain language, short paragraphs, no markdown headers. Metric units.
''';

  static final _tools = [
    {
      'name': 'search_exercises',
      'description':
          'Search the Ritmo exercise catalogue (1,443 exercises, each graded beginner, intermediate or advanced). Returns up to 12 matches with ids, primary muscles, equipment and level. Call it with a muscle group, an equipment type, or a free-text name.',
      'input_schema': {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'Free text, e.g. "squat", "chest press". Empty string allowed.'},
          'muscle': {
            'type': 'string',
            'description':
                'One of: abdominals, abductors, adductors, biceps, calves, chest, forearms, glutes, hamstrings, lats, lower back, middle back, neck, quadriceps, shoulders, traps, triceps. Empty string for any.'
          },
          'equipment': {
            'type': 'string',
            'description': 'One of: body only, dumbbell, barbell, kettlebells, bands, cable, machine, medicine ball, exercise ball, foam roll, other. Empty string for any.'
          },
          'category': {
            'type': 'string',
            'description': 'strength, stretching, cardio, plyometrics, powerlifting, olympic weightlifting, strongman. Empty string for any.'
          },
        },
        'required': ['query', 'muscle', 'equipment', 'category'],
        'additionalProperties': false,
      },
      'strict': true,
    },
    {
      'name': 'save_plan',
      'description': 'Save a complete training plan into the athlete\'s routines. Call exactly once per plan, only with exercise_ids returned by search_exercises.',
      'input_schema': {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'description': {'type': 'string', 'description': 'One or two sentences on who this plan is for and why.'},
          'days': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'title': {'type': 'string', 'description': 'e.g. "Day 1 - Push"'},
                'focus': {'type': 'string', 'description': 'e.g. "Chest, shoulders, triceps"'},
                'exercises': {
                  'type': 'array',
                  'items': {
                    'type': 'object',
                    'properties': {
                      'exercise_id': {'type': 'string'},
                      'sets': {'type': 'integer'},
                      'reps': {'type': 'integer'},
                      'rest_sec': {'type': 'integer'},
                      'notes': {'type': 'string'},
                    },
                    'required': ['exercise_id', 'sets', 'reps', 'rest_sec', 'notes'],
                    'additionalProperties': false,
                  }
                },
              },
              'required': ['title', 'focus', 'exercises'],
              'additionalProperties': false,
            }
          },
          'nutrition_notes': {'type': 'string', 'description': 'Short diet guidance respecting the restrictions.'},
          'weekly_step_goal': {'type': 'integer', 'description': 'Suggested daily steps target.'},
        },
        'required': ['name', 'description', 'days', 'nutrition_notes', 'weekly_step_goal'],
        'additionalProperties': false,
      },
      'strict': true,
    },
  ];

  @override
  Future<CoachReply> reply({
    required List<ChatMessage> history,
    required UserProfile profile,
    required ExerciseRepository repo,
    List<StepDay> recentSteps = const [],
    void Function(String delta)? onText,
  }) async {
    final messages = <Map<String, dynamic>>[
      for (final m in history)
        {'role': m.role == 'user' ? 'user' : 'assistant', 'content': m.text},
    ];
    if (messages.isEmpty || messages.last['role'] != 'user') {
      throw StateError('History must end with a user message');
    }

    final system = [
      {
        'type': 'text',
        'text': _systemPrompt,
        'cache_control': {'type': 'ephemeral'},
      },
      {'type': 'text', 'text': 'Athlete profile:\n${_profileSummary(profile, recentSteps)}'},
    ];

    Routine? savedRoutine;
    final textOut = StringBuffer();

    for (var turn = 0; turn < 8; turn++) {
      final body = {
        'model': model,
        'max_tokens': 8000,
        'output_config': {'effort': 'medium'},
        'system': system,
        'tools': _tools,
        'messages': messages,
      };
      final res = await _client
          .post(
            Uri.parse(_endpoint),
            headers: {
              'content-type': 'application/json',
              'x-api-key': apiKey,
              'anthropic-version': '2023-06-01',
              // The demo can run in a browser; production routes through our backend.
              if (kIsWeb) 'anthropic-dangerous-direct-browser-access': 'true',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(minutes: 3));

      if (res.statusCode != 200) {
        String detail = res.body;
        try {
          detail = (jsonDecode(res.body)['error']?['message'] ?? res.body).toString();
        } catch (_) {}
        throw CoachException('Claude API ${res.statusCode}: $detail');
      }

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final stopReason = json['stop_reason'] as String?;
      if (stopReason == 'refusal') {
        return CoachReply(text: textOut.isEmpty ? "I can't help with that one, but I'm happy to work on your training or nutrition." : textOut.toString());
      }
      final content = (json['content'] as List).cast<Map<String, dynamic>>();
      final toolUses = <Map<String, dynamic>>[];
      for (final block in content) {
        if (block['type'] == 'text') {
          textOut.write(block['text']);
        } else if (block['type'] == 'tool_use') {
          toolUses.add(block);
        }
      }
      if (toolUses.isEmpty || stopReason != 'tool_use') break;

      messages.add({'role': 'assistant', 'content': content});
      final results = <Map<String, dynamic>>[];
      for (final tu in toolUses) {
        final input = Map<String, dynamic>.from(tu['input'] as Map);
        String result;
        if (tu['name'] == 'search_exercises') {
          result = _runSearch(repo, profile, input);
        } else if (tu['name'] == 'save_plan') {
          final routine = planToRoutine(input, repo, profile);
          savedRoutine = routine;
          result = 'Saved routine "${routine.name}" with ${routine.days.length} days and ${routine.exerciseCount} exercises.';
        } else {
          result = 'Unknown tool';
        }
        results.add({'type': 'tool_result', 'tool_use_id': tu['id'], 'content': result});
      }
      messages.add({'role': 'user', 'content': results});
    }

    return CoachReply(text: textOut.toString().trim(), routine: savedRoutine);
  }

  String _runSearch(ExerciseRepository repo, UserProfile profile, Map<String, dynamic> input) {
    String? nz(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim().toLowerCase();
    final hits = repo.search(
      query: input['query'] as String? ?? '',
      muscle: nz(input['muscle'] as String?),
      equipment: nz(input['equipment'] as String?),
      category: nz(input['category'] as String?),
      allowedEquipment: profile.equipment,
      limit: 12,
    );
    if (hits.isEmpty) return 'No matches. Try a broader query or different equipment.';
    return hits
        .map((e) => '${e.id} | ${e.name} | ${e.primary.join('/')} | ${e.equipment} | ${e.level ?? ''}')
        .join('\n');
  }
}

class CoachException implements Exception {
  CoachException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Turn the save_plan tool input into a Routine, dropping unknown ids.
Routine planToRoutine(Map<String, dynamic> plan, ExerciseRepository repo, UserProfile profile) {
  final days = <RoutineDay>[];
  for (final d in (plan['days'] as List? ?? const [])) {
    final dm = Map<String, dynamic>.from(d as Map);
    final items = <RoutineItem>[];
    for (final ex in (dm['exercises'] as List? ?? const [])) {
      final em = Map<String, dynamic>.from(ex as Map);
      final e = repo.byId(em['exercise_id'] as String? ?? '');
      if (e == null) continue;
      items.add(RoutineItem(
        exerciseId: e.id,
        exerciseName: e.name,
        sets: (em['sets'] as num?)?.toInt() ?? 3,
        reps: (em['reps'] as num?)?.toInt() ?? 10,
        restSec: (em['rest_sec'] as num?)?.toInt() ?? 60,
        notes: em['notes'] as String? ?? '',
      ));
    }
    if (items.isNotEmpty) {
      days.add(RoutineDay(title: dm['title'] ?? 'Day ${days.length + 1}', focus: dm['focus'] ?? '', items: items));
    }
  }
  final nutrition = plan['nutrition_notes'] as String? ?? '';
  return Routine(
    id: newUuid(),
    name: plan['name'] as String? ?? 'AI plan',
    description: [plan['description'] as String? ?? '', if (nutrition.isNotEmpty) 'Nutrition: $nutrition'].join('\n'),
    authorId: profile.id,
    authorName: 'Ritmo Coach for ${profile.name}',
    days: days,
    createdAt: DateTime.now(),
    tags: ['ai', profile.goal.name],
    source: 'ai',
  );
}

// ---------------------------------------------------------------------------
// Offline rule-based coach. Used when no API key is set so the app is fully
// demoable, and as a fallback if the network call fails.
// ---------------------------------------------------------------------------
/// The questions the coach can be asked (v0.12).
///
/// The free-text box is closed while we work out how to give the coach away
/// to everyone, so these presets are the whole input surface — which means
/// every one of them has to land. [LocalCoach] answers each explicitly rather
/// than falling through to "I can build you a plan".
enum CoachPrompt {
  plan('Build me a plan', 'A week shaped around your goal and your gear'),
  short('I only have 25 minutes today', 'One session, trimmed to fit'),
  food('What should I eat around training?', 'Protein, timing, your restrictions'),
  joints('Make it easier on my knees', 'Low-impact swaps that keep the work'),
  swap('Swap barbell moves for dumbbells', 'The same plan with the kit you have');

  const CoachPrompt(this.label, this.note);
  final String label;
  final String note;
}

class LocalCoach implements Coach {
  @override
  Future<CoachReply> reply({
    required List<ChatMessage> history,
    required UserProfile profile,
    required ExerciseRepository repo,
    List<StepDay> recentSteps = const [],
    void Function(String delta)? onText,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final last = history.isEmpty ? '' : history.last.text.toLowerCase();
    final wantsPlan = RegExp(r'plan|routine|program|schedule|build|workout|week').hasMatch(last);
    final wantsDiet = RegExp(r'diet|eat|food|meal|protein|calorie|nutrition').hasMatch(last);

    // The narrower asks are checked first: "I only have 25 minutes" is about
    // a plan, but answering it with a full week would be missing the point.
    if (RegExp(r'\d+ ?min|short|quick|no time').hasMatch(last)) {
      final session = _shortSession(profile, repo);
      return CoachReply(
        text: 'Twenty-five minutes is a session, not a write-off. Here is one: '
            '${session.days.first.items.length} movements, straight through, short rests. '
            'Do the first two properly and let the rest be a bonus.',
        routine: session,
      );
    }
    if (RegExp(r'knee|joint|impact|hurt|sore|gentle|easier').hasMatch(last)) {
      return CoachReply(text: _jointAdvice(profile));
    }
    if (RegExp(r'swap|instead of|dumbbell|no barbell|home').hasMatch(last)) {
      final dumbbell = buildCoachPlan(
        profile.copyWith(equipment: const ['dumbbell', 'body only']),
        repo,
      );
      return CoachReply(
        text: 'Same shape, no barbell. Every lift below is a dumbbell or bodyweight version of what you were doing — '
            'go a little lighter than you think for the first session while the stabilisers catch up.',
        routine: dumbbell,
      );
    }
    if (wantsDiet) {
      return CoachReply(text: _dietAdvice(profile));
    }
    // An opening message with nothing recognisable in it still gets a plan:
    // that is what somebody who has just arrived is here for.
    if (wantsPlan || history.length <= 1) {
      final routine = _buildRoutine(profile, repo);
      return CoachReply(
        text: 'Here is a ${profile.daysPerWeek}-day plan built for "${profile.goal.label}" with the equipment you have. '
            'Each day mixes a main lift, accessories and a finisher. '
            '${_dietAdvice(profile, short: true)}\n\n'
            'Open it below to see every exercise, what it is graded at and the kit it needs — and to run it at another level '
            'if it looks like too much. It is already saved to your routines either way.',
        routine: routine,
      );
    }
    return const CoachReply(
      text: 'I can build you a plan, trim one down to the time you have, tune your food around your '
          'restrictions, or swap the movements for the kit and the joints you actually have. Pick one below.',
    );
  }

  /// Twenty-five minutes: the first four movements of day one, short rests.
  Routine _shortSession(UserProfile p, ExerciseRepository repo) {
    final full = buildCoachPlan(p, repo);
    final day = full.days.first;
    final items = [
      for (final i in day.items.take(4))
        RoutineItem(
          exerciseId: i.exerciseId,
          exerciseName: i.exerciseName,
          sets: i.sets > 3 ? 3 : i.sets,
          reps: i.reps,
          restSec: i.restSec > 60 ? 60 : i.restSec,
          notes: i.notes,
        ),
    ];
    return Routine(
      id: newUuid(),
      name: '25-minute ${day.focus.split(', ').first} session',
      description: 'Trimmed from your plan to fit the time you have.',
      authorId: p.id,
      authorName: 'Ritmo Coach for ${p.name}',
      days: [RoutineDay(title: 'Short session', focus: day.focus, items: items)],
      createdAt: DateTime.now(),
      tags: const ['ai', 'short'],
      source: 'ai',
    );
  }

  /// Knees, and joints generally. Named swaps rather than "listen to your
  /// body", because a swap is something you can actually do this evening.
  String _jointAdvice(UserProfile p) {
    final low = p.goal == Goal.loseFat || p.goal == Goal.endurance;
    return 'Keep the training, change the loading. Swap deep squats for box squats or a leg press to a comfortable depth, '
        'lunges for split squats with a shorter step, and jumping or plyometric work for step-ups and sled or hill walking'
        '${low ? ', and take the running to a bike or a rower for a fortnight' : ''}. '
        'Warm up the joint before you load it: five minutes easy cycling, then twenty slow bodyweight reps through the range that does not hurt. '
        'Pain during a set means stop that movement, not stop training — everything above still moves you towards ${p.goal.label.toLowerCase()}. '
        'If it is sharp, swollen or lasts more than a fortnight, that is a physio question, not a coaching one.';
  }

  String _dietAdvice(UserProfile p, {bool short = false}) {
    final protein = (p.weightKg * (p.goal == Goal.buildMuscle || p.goal == Goal.getStronger ? 1.8 : 1.5)).round();
    final sources = <String>[];
    final vegan = p.diet.contains('Vegan');
    final veg = vegan || p.diet.contains('Vegetarian');
    final noLactose = vegan || p.diet.contains('Lactose-free');
    final noNuts = p.diet.contains('Nut allergy');
    if (!veg) sources.addAll(['chicken', 'fish', 'eggs']);
    if (!noLactose) sources.add('greek yogurt');
    sources.addAll(['lentils', 'tofu', 'chickpeas']);
    if (!noNuts) sources.add('peanut butter');
    final calories = switch (p.goal) {
      Goal.loseFat => 'a modest 300-500 kcal deficit',
      Goal.buildMuscle => 'a small 200-300 kcal surplus',
      _ => 'maintenance calories',
    };
    final head = 'Aim for about $protein g protein per day from ${sources.take(4).join(', ')}, at $calories.';
    if (short) return head;
    final restr = p.diet.isEmpty ? '' : ' Everything above already respects: ${p.diet.join(', ')}.';
    return '$head Eat a carb-plus-protein snack 60-90 minutes before training and 20-40 g protein within two hours after.$restr';
  }

  Routine _buildRoutine(UserProfile p, ExerciseRepository repo) => buildCoachPlan(p, repo);
}

/// The plan the coach hands an athlete who has said nothing but their profile.
///
/// Pure and deterministic — seeded off the athlete's own name — so the same
/// person always gets the same plan back, whether it is the chat asking or
/// the AI coach's card in Community. Give it an [id] to keep the routine
/// stable across rebuilds; leave it out and every call is a new routine.
Routine buildCoachPlan(UserProfile p, ExerciseRepository repo, {String? id}) {
  final rnd = Random(p.name.hashCode);
  final splits = switch (p.daysPerWeek) {
    1 => [
        ['quadriceps', 'chest', 'middle back', 'abdominals']
      ],
    2 => [
        ['quadriceps', 'hamstrings', 'glutes', 'abdominals'],
        ['chest', 'middle back', 'shoulders', 'biceps']
      ],
    3 => [
        ['chest', 'shoulders', 'triceps'],
        ['middle back', 'lats', 'biceps'],
        ['quadriceps', 'hamstrings', 'glutes', 'abdominals']
      ],
    4 => [
        ['chest', 'triceps', 'abdominals'],
        ['middle back', 'lats', 'biceps'],
        ['quadriceps', 'glutes', 'calves'],
        ['shoulders', 'hamstrings', 'abdominals']
      ],
    _ => [
        ['chest', 'triceps'],
        ['middle back', 'lats'],
        ['quadriceps', 'calves'],
        ['shoulders', 'abdominals'],
        ['hamstrings', 'glutes', 'biceps'],
        if (p.daysPerWeek > 5) ['abdominals', 'lower back'],
      ],
  };
  final (sets, reps, rest) = switch (p.goal) {
    Goal.getStronger => (5, 5, 150),
    Goal.buildMuscle => (4, 10, 90),
    Goal.loseFat => (3, 15, 45),
    Goal.endurance => (3, 20, 30),
    Goal.mobility => (2, 12, 30),
    Goal.generalHealth => (3, 12, 60),
  };
  final allowed = p.equipment.isEmpty ? ['body only'] : p.equipment;
  final days = <RoutineDay>[];
  for (var i = 0; i < splits.length; i++) {
    final items = <RoutineItem>[];
    for (final muscle in splits[i]) {
      var pool = repo.search(
        muscle: muscle,
        category: p.goal == Goal.mobility ? 'stretching' : 'strength',
        allowedEquipment: allowed,
      ).where((e) => e.images.isNotEmpty && e.level != 'expert').toList();
      if (pool.isEmpty) pool = repo.search(muscle: muscle, allowedEquipment: allowed);
      if (pool.isEmpty) continue;
      final pick = pool[rnd.nextInt(pool.length)];
      items.add(RoutineItem(exerciseId: pick.id, exerciseName: pick.name, sets: sets, reps: reps, restSec: rest));
    }
    if (p.goal == Goal.loseFat || p.goal == Goal.endurance) {
      final cardio = repo.search(category: 'cardio', allowedEquipment: allowed);
      if (cardio.isNotEmpty) {
        final c = cardio[rnd.nextInt(cardio.length)];
        items.add(RoutineItem(exerciseId: c.id, exerciseName: c.name, sets: 1, reps: 1, restSec: 0, notes: '10 minute finisher'));
      }
    }
    days.add(RoutineDay(title: 'Day ${i + 1}', focus: splits[i].join(', '), items: items));
  }
  return Routine(
    id: id ?? newUuid(),
    // No emoji in the name: CanvasKit has no emoji font on web, and this
    // name is shown on cards, in the preview and in the routine list.
    name: '${p.goal.label} · ${p.daysPerWeek}-day plan',
    description: 'Generated offline from your profile: ${p.goal.label}, ${allowed.join(', ')}.',
    authorId: p.id,
    authorName: 'Ritmo Coach for ${p.name}',
    days: days,
    createdAt: DateTime.now(),
    tags: ['ai', p.goal.name],
    source: 'ai',
  );
}
