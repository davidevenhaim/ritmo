import 'dart:math';

/// Exercise from the open-source free-exercise-db dataset (bundled offline)
/// or from the wger community API (fetched live).
class Exercise {
  const Exercise({
    required this.id,
    required this.name,
    required this.category,
    required this.equipment,
    required this.primary,
    required this.secondary,
    required this.instructions,
    required this.images,
    this.level,
    this.mechanic,
    this.force,
    this.source = 'free-exercise-db',
  });

  final String id;
  final String name;
  final String category;
  final String equipment;
  final List<String> primary;
  final List<String> secondary;
  final List<String> instructions;
  final List<String> images;
  final String? level;
  final String? mechanic;
  final String? force;
  final String source;

  static const imageBase =
      'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/';

  String? imageUrl(int index) {
    if (images.isEmpty) return null;
    final path = images[index % images.length];
    return path.startsWith('http') ? path : '$imageBase$path';
  }

  factory Exercise.fromJson(Map<String, dynamic> j) => Exercise(
        id: j['id'] as String,
        name: j['name'] as String,
        category: (j['category'] ?? 'strength') as String,
        equipment: (j['equipment'] ?? 'none') as String,
        primary: List<String>.from(j['primary'] ?? const []),
        secondary: List<String>.from(j['secondary'] ?? const []),
        instructions: List<String>.from(j['instructions'] ?? const []),
        images: List<String>.from(j['images'] ?? const []),
        level: j['level'] as String?,
        mechanic: j['mechanic'] as String?,
        force: j['force'] as String?,
        source: (j['source'] ?? 'free-exercise-db') as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'equipment': equipment,
        'primary': primary,
        'secondary': secondary,
        'instructions': instructions,
        'images': images,
        'level': level,
        'mechanic': mechanic,
        'force': force,
        'source': source,
      };
}

enum Goal {
  loseFat('Lose fat', '🔥'),
  buildMuscle('Build muscle', '💪'),
  getStronger('Get stronger', '🏋️'),
  endurance('Endurance', '🏃'),
  mobility('Mobility & calm', '🧘'),
  generalHealth('General health', '❤️');

  const Goal(this.label, this.emoji);
  final String label;
  final String emoji;
}

/// A goal on the Me screen's goals card (Nocturne handoff, section 1.4).
/// Two are derived from the profile and recompute every build; the rest the
/// user adds and we persist.
class PersonalGoal {
  const PersonalGoal({
    required this.id,
    required this.name,
    required this.current,
    required this.target,
    this.unit = '',
    this.note = '',
    this.derived = false,
    this.exerciseId,
    this.exerciseName,
    this.deadline,
  });

  final String id;
  final String name;
  final double current;
  final double target;

  /// Set when the goal is a specific exercise out of the catalogue — "10
  /// strict pull-ups" pointing at `Pullups` — so the card can show the
  /// movement and the app can tell that training it moves this goal.
  final String? exerciseId;
  final String? exerciseName;

  /// Suffix on both numbers, e.g. "s" for a handstand hold.
  final String unit;
  final String note;

  /// Derived goals are computed from the profile and cannot be deleted.
  final bool derived;

  /// The day the goal is due, as a date. Null means "no date, just chase it".
  /// A goal with one shows a countdown on the card and a marker on the
  /// calendar, which is the whole point of putting a date on it.
  final DateTime? deadline;

  /// Whole days between today and the deadline: 0 on the day itself,
  /// negative once it has passed. Null when the goal has no date.
  int? get daysLeft {
    if (deadline == null) return null;
    final n = DateTime.now();
    return DateTime(deadline!.year, deadline!.month, deadline!.day).difference(DateTime(n.year, n.month, n.day)).inDays;
  }

  /// Past its day and still short of the target.
  bool get overdue => (daysLeft ?? 1) < 0 && pct < 1;

  /// "12 days left", "due today", "3 days over" — the line under the bar.
  String? get dueLabel {
    final d = daysLeft;
    if (d == null) return null;
    if (pct >= 1) return 'done';
    if (d == 0) return 'due today';
    if (d == 1) return 'due tomorrow';
    if (d > 0) return '$d days left';
    return '${-d} day${d == -1 ? '' : 's'} over';
  }

  double get pct => target <= 0 ? 0 : (current / target).clamp(0.0, 1.0);

  static String _n(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  /// "14 / 20s" — the handoff's value line.
  String get value => '${_n(current)} / ${_n(target)}$unit';

  PersonalGoal copyWith({double? current, double? target, String? note, DateTime? deadline, bool clearDeadline = false}) => PersonalGoal(
        id: id,
        name: name,
        current: current ?? this.current,
        target: target ?? this.target,
        unit: unit,
        note: note ?? this.note,
        derived: derived,
        exerciseId: exerciseId,
        exerciseName: exerciseName,
        deadline: clearDeadline ? null : (deadline ?? this.deadline),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'current': current,
        'target': target,
        'unit': unit,
        'note': note,
        if (exerciseId != null) 'exerciseId': exerciseId,
        if (exerciseName != null) 'exerciseName': exerciseName,
        if (deadline != null) 'deadline': deadline!.toIso8601String(),
      };

  factory PersonalGoal.fromJson(Map<String, dynamic> j) => PersonalGoal(
        id: j['id'],
        name: j['name'] ?? 'Goal',
        current: (j['current'] as num?)?.toDouble() ?? 0,
        target: (j['target'] as num?)?.toDouble() ?? 1,
        unit: j['unit'] ?? '',
        note: j['note'] ?? '',
        exerciseId: j['exerciseId'] as String?,
        exerciseName: j['exerciseName'] as String?,
        deadline: j['deadline'] == null ? null : DateTime.tryParse(j['deadline']),
      );
}

/// What a goal on a specific exercise counts. Reps and holds are what the
/// catalogue's own work is measured in; load is there for the barbell lifts,
/// even though the app does not record it per set yet.
enum GoalMetric {
  reps('Reps', ' reps', 10),
  seconds('Hold', 's', 30),
  kilos('Load', ' kg', 60);

  const GoalMetric(this.label, this.unit, this.defaultTarget);
  final String label;
  final String unit;
  final double defaultTarget;
}

/// A goal the "Set a goal" sheet offers ready-made. Every number in it is a
/// starting point: the athlete moves [target] and the deadline before saving,
/// so "Run 5 km" and "Run 21 km" are the same template.
class GoalTemplate {
  const GoalTemplate({
    required this.id,
    required this.label,
    required this.pattern,
    required this.unit,
    required this.target,
    required this.step,
    required this.min,
    required this.max,
    required this.note,
    required this.days,
  });

  /// Icon key the sheet maps onto the Phosphor set.
  final String id;

  /// The short name on the chooser row ("Run a distance").
  final String label;

  /// The goal's own name, with `{}` where the number lands.
  final String pattern;

  final String unit;

  /// Starting target, the amount one tap moves it, and the range it lives in.
  final double target;
  final double step;
  final double min;
  final double max;

  /// How the goal is actually trained — becomes the goal's note.
  final String note;

  /// The deadline offered first, in days from today. Chosen per goal: a squat
  /// number takes a season, a plank takes a month.
  final int days;

  String nameFor(double v) => pattern.replaceFirst('{}', fmt(v));

  static String fmt(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
}

/// The ready-made goals, ordered easiest to commit to first.
const goalTemplates = [
  GoalTemplate(
    id: 'run',
    label: 'Run a distance',
    pattern: 'Run {} km without stopping',
    unit: ' km',
    target: 5,
    step: 0.5,
    min: 1,
    max: 42,
    note: 'Three easy runs a week, one of them longer',
    days: 42,
  ),
  GoalTemplate(
    id: 'rope',
    label: 'Skip unbroken',
    pattern: 'Jump rope for {}s unbroken',
    unit: 's',
    target: 60,
    step: 15,
    min: 15,
    max: 900,
    note: 'Two minutes of rope before every session',
    days: 28,
  ),
  GoalTemplate(
    id: 'pullup',
    label: 'Pull-ups',
    pattern: '{} strict pull-ups in one set',
    unit: ' reps',
    target: 10,
    step: 1,
    min: 1,
    max: 50,
    note: 'A few easy sets most days, never to failure',
    days: 56,
  ),
  GoalTemplate(
    id: 'pushup',
    label: 'Push-ups',
    pattern: '{} push-ups in one set',
    unit: ' reps',
    target: 40,
    step: 5,
    min: 5,
    max: 200,
    note: 'Add a rep to every set each session',
    days: 42,
  ),
  GoalTemplate(
    id: 'plank',
    label: 'Hold a plank',
    pattern: 'Hold a plank for {}s',
    unit: 's',
    target: 120,
    step: 15,
    min: 30,
    max: 900,
    note: 'Finish every session on the floor',
    days: 28,
  ),
  GoalTemplate(
    id: 'handstand',
    label: 'Handstand',
    pattern: 'Hold a {}s freestanding handstand',
    unit: 's',
    target: 30,
    step: 5,
    min: 5,
    max: 300,
    note: 'Wall work three times a week, then the wall comes away',
    days: 84,
  ),
  GoalTemplate(
    id: 'squat',
    label: 'Squat a load',
    pattern: 'Squat {} kg',
    unit: ' kg',
    target: 100,
    step: 5,
    min: 20,
    max: 300,
    note: 'Twice a week, adding a little each time',
    days: 84,
  ),
  GoalTemplate(
    id: 'ride',
    label: 'Ride a distance',
    pattern: 'Ride {} km in one go',
    unit: ' km',
    target: 40,
    step: 5,
    min: 5,
    max: 300,
    note: 'One long ride at the weekend',
    days: 56,
  ),
  GoalTemplate(
    id: 'split',
    label: 'Front split',
    pattern: 'Front split, {}% of the way down',
    unit: '%',
    target: 100,
    step: 5,
    min: 20,
    max: 100,
    note: 'Twelve minutes of mobility, daily',
    days: 84,
  ),
];

/// One day of food logging. Macros are grams.
class NutritionDay {
  const NutritionDay({required this.day, this.kcal = 0, this.protein = 0, this.carbs = 0, this.fat = 0});
  final DateTime day;
  final int kcal;
  final int protein;
  final int carbs;
  final int fat;

  bool isToday() {
    final n = DateTime.now();
    return day.year == n.year && day.month == n.month && day.day == n.day;
  }

  NutritionDay plus({int kcal = 0, int protein = 0, int carbs = 0, int fat = 0}) => NutritionDay(
        day: day,
        kcal: this.kcal + kcal,
        protein: this.protein + protein,
        carbs: this.carbs + carbs,
        fat: this.fat + fat,
      );

  Map<String, dynamic> toJson() => {
        'day': '${day.year}-${day.month}-${day.day}',
        'kcal': kcal,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
      };

  factory NutritionDay.fromJson(Map<String, dynamic> j) {
    final parts = (j['day'] as String? ?? '').split('-').map(int.tryParse).toList();
    return NutritionDay(
      day: parts.length == 3 && !parts.contains(null) ? DateTime(parts[0]!, parts[1]!, parts[2]!) : DateTime.now(),
      kcal: (j['kcal'] as num?)?.toInt() ?? 0,
      protein: (j['protein'] as num?)?.toInt() ?? 0,
      carbs: (j['carbs'] as num?)?.toInt() ?? 0,
      fat: (j['fat'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Daily calorie target from the profile. Mifflin-St Jeor with the
/// sex constant averaged (+5 male / -161 female), because onboarding does not
/// ask for sex, then an activity factor from days per week and a goal offset.
/// Shown as an estimate, never as medical advice.
int calorieTarget(UserProfile me) {
  final bmr = 10 * me.weightKg + 6.25 * me.heightCm - 5 * me.age - 78;
  final activity = switch (me.daysPerWeek) { <= 1 => 1.2, <= 3 => 1.375, <= 5 => 1.55, _ => 1.725 };
  final goalFactor = switch (me.goal) {
    Goal.loseFat => 0.82,
    Goal.buildMuscle => 1.1,
    Goal.getStronger => 1.05,
    _ => 1.0,
  };
  return ((bmr * activity * goalFactor) / 10).round() * 10;
}

const dietOptions = [
  'Vegetarian',
  'Vegan',
  'Gluten-free',
  'Lactose-free',
  'Kosher',
  'Halal',
  'Keto',
  'Nut allergy',
  'Low sodium',
  'Diabetic-friendly',
];

const equipmentOptions = [
  'body only',
  'dumbbell',
  'barbell',
  'kettlebells',
  'bands',
  'cable',
  'machine',
  'medicine ball',
  'exercise ball',
  'foam roll',
];

/// The three grades every exercise in the catalogue carries. The sources
/// disagreed ("expert", ungraded); `tool/build_catalogue.py` normalises them
/// on the way in, so anything the app reads is one of these three.
enum ExerciseLevel {
  beginner('Beginner'),
  intermediate('Intermediate'),
  advanced('Advanced');

  const ExerciseLevel(this.label);
  final String label;

  static const catalogue = ['beginner', 'intermediate', 'advanced'];

  /// Tolerant of the older vocabulary, so a stale asset still reads.
  static ExerciseLevel? of(String? raw) => switch (raw?.trim().toLowerCase()) {
        'beginner' || 'novice' => ExerciseLevel.beginner,
        'intermediate' => ExerciseLevel.intermediate,
        'advanced' || 'expert' => ExerciseLevel.advanced,
        _ => null,
      };
}

/// How much training the athlete has behind them (v0.9). Drives which
/// exercises the Start button is allowed to recommend, and the level the
/// exercise library opens on.
enum ExperienceLevel {
  beginner('New to this', 'First few months', {'beginner'}),
  intermediate('Been training a while', 'Comfortable with the basics', {'beginner', 'intermediate'}),
  advanced('Advanced', 'Years under the bar', {'beginner', 'intermediate', 'advanced', 'expert'});

  const ExperienceLevel(this.label, this.hint, this.levels);
  final String label;
  final String hint;

  /// The catalogue levels this athlete gets offered.
  final Set<String> levels;

  bool allows(String? level) => level == null || levels.contains(level.toLowerCase());

  /// The matching grade in the catalogue's own vocabulary.
  ExerciseLevel get exerciseLevel => switch (this) {
        ExperienceLevel.beginner => ExerciseLevel.beginner,
        ExperienceLevel.intermediate => ExerciseLevel.intermediate,
        ExperienceLevel.advanced => ExerciseLevel.advanced,
      };

  static ExperienceLevel byName(String? n) =>
      ExperienceLevel.values.firstWhere((e) => e.name == n, orElse: () => ExperienceLevel.beginner);
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.name,
    required this.handle,
    required this.emoji,
    required this.heightCm,
    required this.weightKg,
    required this.age,
    required this.goal,
    required this.diet,
    required this.equipment,
    required this.daysPerWeek,
    this.experience = ExperienceLevel.beginner,
    this.bio = '',
    this.stepGoal = 8000,
    this.targetWeightKg,
    this.creator = false,
    this.moderator = false,
    this.photo,
  });

  final String id;
  final String name;
  final String handle;
  final String emoji;

  /// Profile picture as a base64 JPEG (v0.5). Kept small (400px) so it fits
  /// in on-device prefs; null means fall back to the emoji.
  final String? photo;
  final double heightCm;
  final double weightKg;
  final int age;
  final Goal goal;
  final List<String> diet;
  final List<String> equipment;
  final int daysPerWeek;
  final ExperienceLevel experience;
  final String bio;
  final int stepGoal;
  final double? targetWeightKg;

  /// Trust flags (v0.3). Granted server-side; the on-device demo grants
  /// creator instantly and treats everyone as a moderator.
  final bool creator;
  final bool moderator;

  double get bmi => weightKg / pow(heightCm / 100, 2);

  UserProfile copyWith({
    String? id,
    String? name,
    String? handle,
    String? emoji,
    double? heightCm,
    double? weightKg,
    int? age,
    Goal? goal,
    List<String>? diet,
    List<String>? equipment,
    int? daysPerWeek,
    ExperienceLevel? experience,
    String? bio,
    int? stepGoal,
    double? targetWeightKg,
    bool? creator,
    bool? moderator,
    Object? photo = _keep,
  }) =>
      UserProfile(
        id: id ?? this.id,
        name: name ?? this.name,
        handle: handle ?? this.handle,
        emoji: emoji ?? this.emoji,
        heightCm: heightCm ?? this.heightCm,
        weightKg: weightKg ?? this.weightKg,
        age: age ?? this.age,
        goal: goal ?? this.goal,
        diet: diet ?? this.diet,
        equipment: equipment ?? this.equipment,
        daysPerWeek: daysPerWeek ?? this.daysPerWeek,
        experience: experience ?? this.experience,
        bio: bio ?? this.bio,
        stepGoal: stepGoal ?? this.stepGoal,
        targetWeightKg: targetWeightKg ?? this.targetWeightKg,
        creator: creator ?? this.creator,
        moderator: moderator ?? this.moderator,
        photo: identical(photo, _keep) ? this.photo : photo as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'handle': handle,
        'emoji': emoji,
        if (photo != null) 'photo': photo,
        'heightCm': heightCm,
        'weightKg': weightKg,
        'age': age,
        'goal': goal.name,
        'diet': diet,
        'equipment': equipment,
        'daysPerWeek': daysPerWeek,
        'experience': experience.name,
        'bio': bio,
        'stepGoal': stepGoal,
        'targetWeightKg': targetWeightKg,
        'creator': creator,
        'moderator': moderator,
      };

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        id: j['id'],
        name: j['name'],
        handle: j['handle'],
        emoji: j['emoji'] ?? '🙂',
        heightCm: (j['heightCm'] as num).toDouble(),
        weightKg: (j['weightKg'] as num).toDouble(),
        age: j['age'] ?? 30,
        goal: Goal.values.firstWhere((g) => g.name == j['goal'],
            orElse: () => Goal.generalHealth),
        diet: List<String>.from(j['diet'] ?? const []),
        equipment: List<String>.from(j['equipment'] ?? const []),
        daysPerWeek: j['daysPerWeek'] ?? 3,
        experience: ExperienceLevel.byName(j['experience'] as String?),
        bio: j['bio'] ?? '',
        stepGoal: j['stepGoal'] ?? 8000,
        targetWeightKg: (j['targetWeightKg'] as num?)?.toDouble(),
        creator: j['creator'] ?? false,
        moderator: j['moderator'] ?? false,
        photo: j['photo'] as String?,
      );
}

/// Sentinel so copyWith can clear [UserProfile.photo] with an explicit null.
const _keep = Object();

class RoutineItem {
  const RoutineItem({
    required this.exerciseId,
    required this.exerciseName,
    this.sets = 3,
    this.reps = 10,
    this.restSec = 60,
    this.notes = '',
  });
  final String exerciseId;
  final String exerciseName;
  final int sets;
  final int reps;
  final int restSec;
  final String notes;

  RoutineItem copyWith({int? sets, int? reps, int? restSec, String? notes}) =>
      RoutineItem(
        exerciseId: exerciseId,
        exerciseName: exerciseName,
        sets: sets ?? this.sets,
        reps: reps ?? this.reps,
        restSec: restSec ?? this.restSec,
        notes: notes ?? this.notes,
      );

  Map<String, dynamic> toJson() => {
        'exerciseId': exerciseId,
        'exerciseName': exerciseName,
        'sets': sets,
        'reps': reps,
        'restSec': restSec,
        'notes': notes,
      };
  factory RoutineItem.fromJson(Map<String, dynamic> j) => RoutineItem(
        exerciseId: j['exerciseId'],
        exerciseName: j['exerciseName'],
        sets: j['sets'] ?? 3,
        reps: j['reps'] ?? 10,
        restSec: j['restSec'] ?? 60,
        notes: j['notes'] ?? '',
      );
}

class RoutineDay {
  const RoutineDay({required this.title, required this.focus, required this.items});
  final String title;
  final String focus;
  final List<RoutineItem> items;

  RoutineDay copyWith({String? title, String? focus, List<RoutineItem>? items}) =>
      RoutineDay(
          title: title ?? this.title,
          focus: focus ?? this.focus,
          items: items ?? this.items);

  Map<String, dynamic> toJson() =>
      {'title': title, 'focus': focus, 'items': items.map((e) => e.toJson()).toList()};
  factory RoutineDay.fromJson(Map<String, dynamic> j) => RoutineDay(
        title: j['title'] ?? 'Day',
        focus: j['focus'] ?? '',
        items: (j['items'] as List? ?? const [])
            .map((e) => RoutineItem.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class Routine {
  const Routine({
    required this.id,
    required this.name,
    required this.description,
    required this.authorId,
    required this.authorName,
    required this.days,
    required this.createdAt,
    this.tags = const [],
    this.source = 'me',
  });
  final String id;
  final String name;
  final String description;
  final String authorId;
  final String authorName;
  final List<RoutineDay> days;
  final DateTime createdAt;
  final List<String> tags;

  /// me | ai | community
  final String source;

  int get exerciseCount => days.fold(0, (n, d) => n + d.items.length);

  Routine copyWith({
    String? id,
    String? name,
    String? description,
    String? authorId,
    String? authorName,
    List<RoutineDay>? days,
    List<String>? tags,
    String? source,
  }) =>
      Routine(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        authorId: authorId ?? this.authorId,
        authorName: authorName ?? this.authorName,
        days: days ?? this.days,
        createdAt: createdAt,
        tags: tags ?? this.tags,
        source: source ?? this.source,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'authorId': authorId,
        'authorName': authorName,
        'days': days.map((d) => d.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'tags': tags,
        'source': source,
      };
  factory Routine.fromJson(Map<String, dynamic> j) => Routine(
        id: j['id'],
        name: j['name'],
        description: j['description'] ?? '',
        authorId: j['authorId'] ?? 'me',
        authorName: j['authorName'] ?? 'Me',
        days: (j['days'] as List? ?? const [])
            .map((d) => RoutineDay.fromJson(Map<String, dynamic>.from(d)))
            .toList(),
        createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
        tags: List<String>.from(j['tags'] ?? const []),
        source: j['source'] ?? 'me',
      );
}

enum PostKind { workout, routine, steps, video, diet, weird }

class SocialUser {
  const SocialUser({
    required this.id,
    required this.name,
    required this.handle,
    required this.emoji,
    required this.bio,
    required this.goal,
    this.diet = const [],
    this.creator = false,
    this.followers = 0,
  });
  final String id;
  final String name;
  final String handle;
  final String emoji;
  final String bio;
  final Goal goal;
  final List<String> diet;
  final bool creator;
  final int followers;
}

enum VideoStatus { uploading, processing, ready, failed, removed }

/// A hosted clip (v0.3). Uploaded straight to Cloudflare Stream or Mux; the
/// row turns [VideoStatus.ready] when the provider webhook lands.
class Video {
  const Video({
    required this.id,
    required this.authorId,
    required this.status,
    this.playbackUrl,
    this.thumbnailUrl,
    this.durationSec,
    this.width,
    this.height,
    this.exerciseIds = const [],
    this.views = 0,
    this.error,
  });
  final String id;
  final String authorId;
  final VideoStatus status;
  final String? playbackUrl;
  final String? thumbnailUrl;
  final double? durationSec;
  final int? width;
  final int? height;
  final List<String> exerciseIds;
  final int views;
  final String? error;

  static const maxSeconds = 60;

  bool get ready => status == VideoStatus.ready && playbackUrl != null;
  double get aspectRatio => (width ?? 0) > 0 && (height ?? 0) > 0 ? width! / height! : 9 / 16;

  Video copyWith({VideoStatus? status, String? playbackUrl, String? thumbnailUrl, List<String>? exerciseIds, int? views, String? error}) => Video(
        id: id,
        authorId: authorId,
        status: status ?? this.status,
        playbackUrl: playbackUrl ?? this.playbackUrl,
        thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
        durationSec: durationSec,
        width: width,
        height: height,
        exerciseIds: exerciseIds ?? this.exerciseIds,
        views: views ?? this.views,
        error: error ?? this.error,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'authorId': authorId,
        'status': status.name,
        'playbackUrl': playbackUrl,
        'thumbnailUrl': thumbnailUrl,
        'durationSec': durationSec,
        'width': width,
        'height': height,
        'exerciseIds': exerciseIds,
        'views': views,
        'error': error,
      };
  factory Video.fromJson(Map<String, dynamic> j) => Video(
        id: j['id'],
        authorId: j['authorId'] ?? '',
        status: VideoStatus.values.firstWhere((s) => s.name == j['status'], orElse: () => VideoStatus.processing),
        playbackUrl: j['playbackUrl'],
        thumbnailUrl: j['thumbnailUrl'],
        durationSec: (j['durationSec'] as num?)?.toDouble(),
        width: j['width'],
        height: j['height'],
        exerciseIds: List<String>.from(j['exerciseIds'] ?? const []),
        views: j['views'] ?? 0,
        error: j['error'],
      );
}

class Post {
  const Post({
    required this.id,
    required this.authorId,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    this.likes = 0,
    this.recommends = 0,
    this.comments = 0,
    this.tags = const [],
    this.routine,
    this.videoUrl,
    this.video,
    this.steps,
    this.hot = false,
    this.hidden = false,
    this.views = 0,
  });
  final String id;
  final String authorId;
  final PostKind kind;
  final String title;
  final String body;
  final DateTime createdAt;
  final int likes;
  final int recommends;
  final int comments;
  final List<String> tags;
  final Routine? routine;

  /// Plain clip URL (seed data, legacy). Hosted uploads use [video].
  final String? videoUrl;
  final Video? video;
  final int? steps;
  final bool hot;

  /// Hidden by reports or a moderator; visible to the author only.
  final bool hidden;
  final int views;

  /// Whatever can play right now: a ready hosted clip or the plain URL.
  String? get playableUrl => video != null ? (video!.ready ? video!.playbackUrl : null) : videoUrl;
  bool get hasVideo => video != null || videoUrl != null;

  Post copyWith({int? likes, int? recommends, int? comments, Video? video, bool? hidden, int? views}) => Post(
        id: id,
        authorId: authorId,
        kind: kind,
        title: title,
        body: body,
        createdAt: createdAt,
        likes: likes ?? this.likes,
        recommends: recommends ?? this.recommends,
        comments: comments ?? this.comments,
        tags: tags,
        routine: routine,
        videoUrl: videoUrl,
        video: video ?? this.video,
        steps: steps,
        hot: hot,
        hidden: hidden ?? this.hidden,
        views: views ?? this.views,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'authorId': authorId,
        'kind': kind.name,
        'title': title,
        'body': body,
        'createdAt': createdAt.toIso8601String(),
        'likes': likes,
        'recommends': recommends,
        'comments': comments,
        'tags': tags,
        'routine': routine?.toJson(),
        'videoUrl': videoUrl,
        'video': video?.toJson(),
        'steps': steps,
        'hot': hot,
        'hidden': hidden,
        'views': views,
      };
  factory Post.fromJson(Map<String, dynamic> j) => Post(
        id: j['id'],
        authorId: j['authorId'],
        kind: PostKind.values.firstWhere((k) => k.name == j['kind'],
            orElse: () => PostKind.workout),
        title: j['title'],
        body: j['body'] ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
        likes: j['likes'] ?? 0,
        recommends: j['recommends'] ?? 0,
        comments: j['comments'] ?? 0,
        tags: List<String>.from(j['tags'] ?? const []),
        routine: j['routine'] == null
            ? null
            : Routine.fromJson(Map<String, dynamic>.from(j['routine'])),
        videoUrl: j['videoUrl'],
        video: j['video'] == null ? null : Video.fromJson(Map<String, dynamic>.from(j['video'])),
        steps: j['steps'],
        hot: j['hot'] ?? false,
        hidden: j['hidden'] ?? false,
        views: j['views'] ?? 0,
      );
}

/// What a breathing pattern is for. The breathe page groups by this, and the
/// order here is the order the groups appear: stress first, because that is
/// what people open the page for.
enum BreathePurpose {
  stress('Stress relief', 'Down from a hard day, in a couple of minutes'),
  sleep('Wind down', 'Slow the night, or the hour after training'),
  train('Around training', 'Sharpen up before, settle down after'),
  mine('Yours', 'Patterns you built');

  const BreathePurpose(this.label, this.note);
  final String label;
  final String note;
}

class BreathingPattern {
  const BreathingPattern({
    required this.id,
    required this.name,
    required this.tagline,
    required this.inhale,
    required this.holdIn,
    required this.exhale,
    required this.holdOut,
    required this.cycles,
    required this.emoji,
    this.purpose = BreathePurpose.stress,
    this.holdInLabel = 'Hold',
    this.custom = false,
  });
  final String id;
  final String name;
  final String tagline;
  final int inhale;
  final int holdIn;
  final int exhale;
  final int holdOut;
  final int cycles;
  final String emoji;

  final BreathePurpose purpose;

  /// What the pause after the inhale is called. Cyclic sighing uses it for the
  /// second sip of air rather than a hold, and the circle should say so.
  final String holdInLabel;

  /// Built here by the athlete rather than shipped with the app.
  final bool custom;

  int get cycleSeconds => inhale + holdIn + exhale + holdOut;
  int get totalSeconds => cycleSeconds * cycles;

  /// "4-7-8-0" — the pattern itself, as it is always written.
  String get rhythm => '$inhale-$holdIn-$exhale-$holdOut';

  /// "5:00" for the timer, "2 min" for a card.
  String get clock => '${totalSeconds ~/ 60}:${(totalSeconds % 60).toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'tagline': tagline,
        'inhale': inhale,
        'holdIn': holdIn,
        'exhale': exhale,
        'holdOut': holdOut,
        'cycles': cycles,
        'emoji': emoji,
      };

  /// Only ever used for the athlete's own patterns, so purpose and the custom
  /// flag are fixed rather than stored.
  factory BreathingPattern.fromJson(Map<String, dynamic> j) => BreathingPattern(
        id: j['id'],
        name: j['name'] ?? 'My pattern',
        tagline: j['tagline'] ?? '',
        inhale: j['inhale'] ?? 4,
        holdIn: j['holdIn'] ?? 0,
        exhale: j['exhale'] ?? 6,
        holdOut: j['holdOut'] ?? 0,
        cycles: j['cycles'] ?? 10,
        emoji: j['emoji'] ?? '🌬',
        purpose: BreathePurpose.mine,
        custom: true,
      );
}

/// The patterns the app ships with (v0.13).
///
/// The stress-relief three are the ones the research actually backs: cyclic
/// sighing came out ahead of box breathing and of mindfulness meditation in
/// the Stanford trial (Balban et al., Cell Reports Medicine 2023), and a
/// longer exhale than inhale at around six breaths a minute is the reliable
/// way to lift HRV. Doses are the ones those protocols use.
const breathingPatterns = [
  BreathingPattern(
    id: 'sigh',
    name: 'Cyclic sighing',
    tagline: 'Two inhales through the nose, then a long exhale through the mouth. Best of the lot in the Stanford trial — five minutes of it.',
    inhale: 3, holdIn: 1, exhale: 7, holdOut: 0, cycles: 27, emoji: '🍃',
    purpose: BreathePurpose.stress,
    holdInLabel: 'Sip more',
  ),
  BreathingPattern(
    id: 'exhale46',
    name: 'Long exhale 4-6',
    tagline: 'Out for longer than you come in. The vagus nerve answers on the exhale — two minutes is enough to feel it.',
    inhale: 4, holdIn: 0, exhale: 6, holdOut: 0, cycles: 12, emoji: '🌊',
    purpose: BreathePurpose.stress,
  ),
  BreathingPattern(
    id: 'coherent',
    name: 'Coherent 5-5',
    tagline: 'Six breaths per minute, even both ways. The HRV sweet spot.',
    inhale: 5, holdIn: 0, exhale: 5, holdOut: 0, cycles: 12, emoji: '🌀',
    purpose: BreathePurpose.stress,
  ),
  BreathingPattern(
    id: '478',
    name: '4-7-8 wind-down',
    tagline: 'A long hold and a longer exhale. For the hour before sleep.',
    inhale: 4, holdIn: 7, exhale: 8, holdOut: 0, cycles: 6, emoji: '🌙',
    purpose: BreathePurpose.sleep,
  ),
  BreathingPattern(
    id: 'box',
    name: 'Box breathing',
    tagline: 'Equal in, hold, out, hold. Steadies you before a heavy lift.',
    inhale: 4, holdIn: 4, exhale: 4, holdOut: 4, cycles: 8, emoji: '🟦',
    purpose: BreathePurpose.train,
  ),
  BreathingPattern(
    id: 'power',
    name: 'Power-up 2-0-2',
    tagline: 'Fast, sharp breaths to wake up before cardio. Sitting down, never near water.',
    inhale: 2, holdIn: 0, exhale: 2, holdOut: 0, cycles: 20, emoji: '⚡',
    purpose: BreathePurpose.train,
  ),
];

class StepDay {
  const StepDay(this.date, this.steps);
  final DateTime date;
  final int steps;
}

class ChatMessage {
  const ChatMessage({required this.role, required this.text, this.routine, this.error = false});
  final String role; // user | coach
  final String text;
  final Routine? routine;
  final bool error;
}

/// A comment on a post (v0.2).
class Comment {
  const Comment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.body,
    required this.createdAt,
  });
  final String id;
  final String postId;
  final String authorId;
  final String body;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'postId': postId,
        'authorId': authorId,
        'body': body,
        'createdAt': createdAt.toIso8601String(),
      };
  factory Comment.fromJson(Map<String, dynamic> j) => Comment(
        id: j['id'],
        postId: j['postId'],
        authorId: j['authorId'],
        body: j['body'] ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
      );
}

enum NotificationKind { follow, like, recommend, comment, tryIt, coach, video, moderation, creator, league, badge }

/// Something someone did to you: a follow, a like, a Try it (v0.2).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.createdAt,
    this.actorId,
    this.postId,
    this.routineId,
    this.preview = '',
    this.read = false,
  });
  final String id;
  final NotificationKind kind;
  final DateTime createdAt;
  final String? actorId;
  final String? postId;
  final String? routineId;
  final String preview;
  final bool read;

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        kind: kind,
        createdAt: createdAt,
        actorId: actorId,
        postId: postId,
        routineId: routineId,
        preview: preview,
        read: read ?? this.read,
      );

  /// Wire name used by the backend (`try` is a Dart keyword).
  static const _wire = {
    NotificationKind.follow: 'follow',
    NotificationKind.like: 'like',
    NotificationKind.recommend: 'recommend',
    NotificationKind.comment: 'comment',
    NotificationKind.tryIt: 'try',
    NotificationKind.coach: 'coach',
    NotificationKind.video: 'video',
    NotificationKind.moderation: 'moderation',
    NotificationKind.creator: 'creator',
    NotificationKind.league: 'league',
    NotificationKind.badge: 'badge',
  };
  static NotificationKind kindFromWire(String? s) =>
      _wire.entries.where((e) => e.value == s).map((e) => e.key).firstOrNull ?? NotificationKind.like;
  String get wireKind => _wire[kind]!;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': wireKind,
        'createdAt': createdAt.toIso8601String(),
        'actorId': actorId,
        'postId': postId,
        'routineId': routineId,
        'preview': preview,
        'read': read,
      };
  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'],
        kind: kindFromWire(j['kind']),
        createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
        actorId: j['actorId'],
        postId: j['postId'],
        routineId: j['routineId'],
        preview: j['preview'] ?? '',
        read: j['read'] ?? false,
      );
}

// ------------------------------------------------------------ v0.3 trust
enum ReportTarget { post, comment, profile }

enum ReportReason {
  spam('Spam or ads'),
  harassment('Harassment or hate'),
  unsafeAdvice('Dangerous advice'),
  nudity('Nudity or sexual content'),
  violence('Violence or injury'),
  copyright('Stolen content'),
  automated('Automated screening'),
  other('Something else');

  const ReportReason(this.label);
  final String label;

  static const _wire = {
    ReportReason.unsafeAdvice: 'unsafe_advice',
  };
  String get wire => _wire[this] ?? name;
  static ReportReason fromWire(String? s) =>
      values.where((r) => r.wire == s).firstOrNull ?? ReportReason.other;

  /// Reasons a member can pick; `automated` is written by the screener only.
  static List<ReportReason> get selectable => values.where((r) => r != automated).toList();
}

enum ReportStatus { open, actioned, dismissed }

enum ModerationAction {
  dismiss('Dismiss', 'Nothing wrong here'),
  hide('Hide', 'Keep it out of the feed'),
  restore('Restore', 'Put it back in the feed'),
  remove('Remove', 'Delete it and tell the author'),
  warn('Warn', 'Keep it up, message the author'),
  ban('Suspend', 'Suspend the author');

  const ModerationAction(this.label, this.hint);
  final String label;
  final String hint;
}

/// A member flagged something (v0.3). The queue joins in a target preview.
class Report {
  const Report({
    required this.id,
    required this.target,
    required this.targetId,
    required this.reason,
    required this.createdAt,
    this.reporterId,
    this.details = '',
    this.status = ReportStatus.open,
    this.action,
    this.targetTitle = '',
    this.targetAuthorId,
    this.targetHidden = false,
  });
  final String id;
  final String? reporterId; // null = automated screening
  final ReportTarget target;
  final String targetId;
  final ReportReason reason;
  final String details;
  final ReportStatus status;
  final ModerationAction? action;
  final DateTime createdAt;

  // Preview of what was reported, filled by the backend.
  final String targetTitle;
  final String? targetAuthorId;
  final bool targetHidden;

  bool get automated => reporterId == null;

  Report copyWith({ReportStatus? status, ModerationAction? action, String? targetTitle, String? targetAuthorId, bool? targetHidden}) => Report(
        id: id,
        reporterId: reporterId,
        target: target,
        targetId: targetId,
        reason: reason,
        details: details,
        status: status ?? this.status,
        action: action ?? this.action,
        createdAt: createdAt,
        targetTitle: targetTitle ?? this.targetTitle,
        targetAuthorId: targetAuthorId ?? this.targetAuthorId,
        targetHidden: targetHidden ?? this.targetHidden,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'reporterId': reporterId,
        'target': target.name,
        'targetId': targetId,
        'reason': reason.wire,
        'details': details,
        'status': status.name,
        'action': action?.name,
        'createdAt': createdAt.toIso8601String(),
      };
  factory Report.fromJson(Map<String, dynamic> j) => Report(
        id: j['id'],
        reporterId: j['reporterId'],
        target: ReportTarget.values.firstWhere((t) => t.name == j['target'], orElse: () => ReportTarget.post),
        targetId: j['targetId'],
        reason: ReportReason.fromWire(j['reason']),
        details: j['details'] ?? '',
        status: ReportStatus.values.firstWhere((s) => s.name == j['status'], orElse: () => ReportStatus.open),
        action: ModerationAction.values.where((a) => a.name == j['action']).firstOrNull,
        createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
      );
}

/// One row of the creator dashboard.
class PostStat {
  const PostStat({
    required this.postId,
    required this.title,
    required this.kind,
    this.views = 0,
    this.likes = 0,
    this.comments = 0,
    this.recommends = 0,
    this.tries = 0,
  });
  final String postId;
  final String title;
  final PostKind kind;
  final int views;
  final int likes;
  final int comments;
  final int recommends;
  final int tries;

  factory PostStat.fromJson(Map<String, dynamic> j) => PostStat(
        postId: j['postId'],
        title: j['title'] ?? '',
        kind: PostKind.values.firstWhere((k) => k.name == j['kind'], orElse: () => PostKind.workout),
        views: (j['views'] as num?)?.toInt() ?? 0,
        likes: (j['likes'] as num?)?.toInt() ?? 0,
        comments: (j['comments'] as num?)?.toInt() ?? 0,
        recommends: (j['recommends'] as num?)?.toInt() ?? 0,
        tries: (j['tries'] as num?)?.toInt() ?? 0,
      );
}

/// Creator analytics (v0.3): totals plus the last seven days of views.
class CreatorStats {
  const CreatorStats({
    this.followers = 0,
    this.following = 0,
    this.posts = 0,
    this.views = 0,
    this.likes = 0,
    this.recommends = 0,
    this.comments = 0,
    this.tries = 0,
    this.viewsByDay = const [0, 0, 0, 0, 0, 0, 0],
    this.topPosts = const [],
  });
  final int followers, following, posts, views, likes, recommends, comments, tries;
  final List<int> viewsByDay;
  final List<PostStat> topPosts;

  /// Likes + comments + recommends per hundred views.
  double get engagementPct => views == 0 ? 0 : (likes + comments + recommends) * 100 / views;

  factory CreatorStats.fromJson(Map<String, dynamic> j) => CreatorStats(
        followers: (j['followers'] as num?)?.toInt() ?? 0,
        following: (j['following'] as num?)?.toInt() ?? 0,
        posts: (j['posts'] as num?)?.toInt() ?? 0,
        views: (j['views'] as num?)?.toInt() ?? 0,
        likes: (j['likes'] as num?)?.toInt() ?? 0,
        recommends: (j['recommends'] as num?)?.toInt() ?? 0,
        comments: (j['comments'] as num?)?.toInt() ?? 0,
        tries: (j['tries'] as num?)?.toInt() ?? 0,
        viewsByDay: (j['viewsByDay'] as List? ?? const []).map((e) => (e as num).toInt()).toList(),
        topPosts: (j['topPosts'] as List? ?? const []).map((e) => PostStat.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      );
}

enum CreatorStatus { none, pending, approved, rejected }

// ------------------------------------------------------- v0.4 leagues
/// A weekly step league (v0.4): 2 to 50 members, Monday to Sunday.
class League {
  const League({
    required this.id,
    required this.name,
    required this.emoji,
    required this.ownerId,
    required this.inviteCode,
    this.memberCount = 0,
    this.maxMembers = 20,
    this.createdAt,
    this.area = '',
    this.distanceKm,
    this.isPublic = false,
  });
  final String id;
  final String name;
  final String emoji;
  final String ownerId;
  final String inviteCode;
  final int memberCount;
  final int maxMembers;
  final DateTime? createdAt;

  /// Where the league meets or walks, e.g. "Florentin, Tel Aviv" (v0.5).
  final String area;

  /// Straight-line distance from the user, when known.
  final double? distanceKm;

  /// Listed under "Join a league nearby"; private leagues are code-only.
  final bool isPublic;

  bool get isFull => memberCount >= maxMembers;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'ownerId': ownerId,
        'inviteCode': inviteCode,
        'memberCount': memberCount,
        'maxMembers': maxMembers,
        'createdAt': createdAt?.toIso8601String(),
        'area': area,
        'distanceKm': distanceKm,
        'isPublic': isPublic,
      };
  factory League.fromJson(Map<String, dynamic> j) => League(
        id: j['id'],
        name: j['name'] ?? 'League',
        emoji: j['emoji'] ?? '🏆',
        ownerId: j['ownerId'] ?? '',
        inviteCode: j['inviteCode'] ?? '',
        memberCount: j['memberCount'] ?? 0,
        maxMembers: j['maxMembers'] ?? 20,
        createdAt: DateTime.tryParse(j['createdAt'] ?? ''),
        area: j['area'] ?? '',
        distanceKm: (j['distanceKm'] as num?)?.toDouble(),
        isPublic: j['isPublic'] ?? false,
      );
}

/// A workout the user put on their calendar from the + menu (v0.5).
/// On-device only: the phone is the source of truth for the user's own plan.
/// A studio on the Community page (v0.9): a place with a timetable.
///
/// Studios and coaches are the paying side of Ritmo, so this is the one
/// surface where money appears. Booking is on-device in the demo and the
/// class is paid for at the studio; no card details are taken anywhere.
class Studio {
  const Studio({
    required this.id,
    required this.name,
    required this.where,
    required this.kind,
    required this.classes,
  });
  final String id;
  final String name;

  /// "Rothschild 12 · 0.8 km" — street plus how far, as the design shows it.
  final String where;

  /// The tag in the corner of the card: Calisthenics, Flexibility…
  final String kind;
  final List<StudioClass> classes;
}

class StudioClass {
  const StudioClass({
    required this.id,
    required this.name,
    required this.weekday,
    required this.hour,
    required this.minute,
    required this.coach,
    required this.minutes,
    required this.spots,
    required this.price,
  });
  final String id;
  final String name;

  /// 1 = Monday, matching DateTime.weekday.
  final int weekday;
  final int hour;
  final int minute;

  /// Empty for an unstaffed slot like open gym.
  final String coach;
  final int minutes;
  final int spots;

  /// Shown as written, e.g. "₪ 90". Nothing is charged in the app.
  final String price;

  /// The next time this class runs, from [from].
  DateTime nextAt([DateTime? from]) {
    final now = from ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day, hour, minute);
    final delta = (weekday - now.weekday) % 7;
    final at = today.add(Duration(days: delta));
    return at.isAfter(now) ? at : at.add(const Duration(days: 7));
  }

  String get meta => [if (coach.isNotEmpty) coach else 'Unstaffed', '$minutes min', if (spots > 0) '$spots spots'].join(' · ');
}

/// Somebody invited to train with me. Copied off the social user at invite
/// time so the row still reads properly if that person is no longer cached.
class TrainingGuest {
  const TrainingGuest({required this.id, required this.name, required this.emoji, this.accepted = false});
  final String id;
  final String name;
  final String emoji;
  final bool accepted;

  String get firstName => name.split(' ').first;

  TrainingGuest copyWith({bool? accepted}) => TrainingGuest(id: id, name: name, emoji: emoji, accepted: accepted ?? this.accepted);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'emoji': emoji, 'accepted': accepted};
  factory TrainingGuest.fromJson(Map<String, dynamic> j) => TrainingGuest(
        id: j['id'] ?? '',
        name: j['name'] ?? 'Someone',
        emoji: j['emoji'] ?? '🙂',
        accepted: j['accepted'] ?? false,
      );
}

class ScheduledWorkout {
  const ScheduledWorkout({
    required this.id,
    required this.routineId,
    required this.routineName,
    required this.dayIndex,
    required this.dayTitle,
    required this.at,
    this.note = '',
    this.done = false,
    this.guests = const [],
    this.classId,
  });
  final String id;
  final String routineId;
  final String routineName;
  final int dayIndex;
  final String dayTitle;
  final DateTime at;
  final String note;
  final bool done;

  /// Friends invited to this session. Empty for a solo session.
  final List<TrainingGuest> guests;

  /// Set when this session is a class booked from Community. There is no
  /// routine behind it — the studio runs the hour — so the plan row opens the
  /// booking rather than the player.
  final String? classId;

  bool get isClass => classId != null;

  bool get isPast => at.isBefore(DateTime.now());
  bool isOn(DateTime day) => at.year == day.year && at.month == day.month && at.day == day.day;

  ScheduledWorkout copyWith({DateTime? at, String? note, bool? done, List<TrainingGuest>? guests}) => ScheduledWorkout(
        id: id,
        routineId: routineId,
        routineName: routineName,
        dayIndex: dayIndex,
        dayTitle: dayTitle,
        at: at ?? this.at,
        note: note ?? this.note,
        done: done ?? this.done,
        guests: guests ?? this.guests,
        classId: classId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'routineId': routineId,
        'routineName': routineName,
        'dayIndex': dayIndex,
        'dayTitle': dayTitle,
        'at': at.toIso8601String(),
        'note': note,
        'done': done,
        if (guests.isNotEmpty) 'guests': guests.map((g) => g.toJson()).toList(),
        if (classId != null) 'classId': classId,
      };
  factory ScheduledWorkout.fromJson(Map<String, dynamic> j) => ScheduledWorkout(
        id: j['id'],
        routineId: j['routineId'] ?? '',
        routineName: j['routineName'] ?? 'Workout',
        dayIndex: (j['dayIndex'] as num?)?.toInt() ?? 0,
        dayTitle: j['dayTitle'] ?? '',
        at: DateTime.tryParse(j['at'] ?? '') ?? DateTime.now(),
        note: j['note'] ?? '',
        done: j['done'] ?? false,
        guests: [for (final g in (j['guests'] as List? ?? const [])) TrainingGuest.fromJson(Map<String, dynamic>.from(g))],
        classId: j['classId'] as String?,
      );
}

/// What a CoG quest counts.
enum QuestKind {
  steps('steps', '👟'),
  workouts('workouts', '🏋️');

  const QuestKind(this.unit, this.emoji);
  final String unit;
  final String emoji;
}

/// Preset quests offered by "CoG together".
class QuestPreset {
  const QuestPreset({required this.title, required this.kind, required this.target, required this.days, required this.blurb});
  final String title;
  final QuestKind kind;
  final int target;
  final int days;
  final String blurb;
}

const questPresets = [
  QuestPreset(title: '100k steps together', kind: QuestKind.steps, target: 100000, days: 7, blurb: 'Both of you, one counter, one week.'),
  QuestPreset(title: '50k steps weekend', kind: QuestKind.steps, target: 50000, days: 3, blurb: 'Friday to Sunday. Short and loud.'),
  QuestPreset(title: '6 workouts between us', kind: QuestKind.workouts, target: 6, days: 7, blurb: 'Three each, or however you split it.'),
  QuestPreset(title: '10 workouts in 2 weeks', kind: QuestKind.workouts, target: 10, days: 14, blurb: 'The habit-builder.'),
];

/// A shared goal between the user and one friend (v0.5, "CoG together":
/// Common Goal). Progress is the sum of both people's numbers since [startsAt].
class Quest {
  const Quest({
    required this.id,
    required this.title,
    required this.kind,
    required this.target,
    required this.friendId,
    required this.friendName,
    required this.friendEmoji,
    required this.startsAt,
    required this.endsAt,
    this.accepted = false,
    this.friendPhoto,
  });
  final String id;
  final String title;
  final QuestKind kind;
  final int target;
  final String friendId;
  final String friendName;
  final String friendEmoji;
  final String? friendPhoto;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool accepted;

  bool get isOver => DateTime.now().isAfter(endsAt);
  int get daysLeft {
    final d = endsAt.difference(DateTime.now()).inDays;
    return d < 0 ? 0 : d;
  }

  Quest copyWith({bool? accepted}) => Quest(
        id: id,
        title: title,
        kind: kind,
        target: target,
        friendId: friendId,
        friendName: friendName,
        friendEmoji: friendEmoji,
        friendPhoto: friendPhoto,
        startsAt: startsAt,
        endsAt: endsAt,
        accepted: accepted ?? this.accepted,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'kind': kind.name,
        'target': target,
        'friendId': friendId,
        'friendName': friendName,
        'friendEmoji': friendEmoji,
        'friendPhoto': friendPhoto,
        'startsAt': startsAt.toIso8601String(),
        'endsAt': endsAt.toIso8601String(),
        'accepted': accepted,
      };
  factory Quest.fromJson(Map<String, dynamic> j) => Quest(
        id: j['id'],
        title: j['title'] ?? 'Quest',
        kind: QuestKind.values.firstWhere((k) => k.name == j['kind'], orElse: () => QuestKind.steps),
        target: (j['target'] as num?)?.toInt() ?? 0,
        friendId: j['friendId'] ?? '',
        friendName: j['friendName'] ?? 'Friend',
        friendEmoji: j['friendEmoji'] ?? '🙂',
        friendPhoto: j['friendPhoto'] as String?,
        startsAt: DateTime.tryParse(j['startsAt'] ?? '') ?? DateTime.now(),
        endsAt: DateTime.tryParse(j['endsAt'] ?? '') ?? DateTime.now(),
        accepted: j['accepted'] ?? false,
      );
}

/// Both sides of a quest, computed by the quest provider.
class QuestProgress {
  const QuestProgress({required this.quest, required this.mine, required this.theirs});
  final Quest quest;
  final int mine;
  final int theirs;
  int get total => mine + theirs;
  double get pct => quest.target == 0 ? 0 : (total / quest.target).clamp(0.0, 1.0);
  bool get complete => total >= quest.target;
}

/// One row of a league table for the current week.
class Standing {
  const Standing({
    required this.userId,
    required this.name,
    required this.handle,
    required this.emoji,
    required this.steps,
    required this.rank,
    this.days = const [0, 0, 0, 0, 0, 0, 0],
  });
  final String userId;
  final String name;
  final String handle;
  final String emoji;
  final int steps;
  final int rank;

  /// Monday to Sunday.
  final List<int> days;

  factory Standing.fromJson(Map<String, dynamic> j) => Standing(
        userId: j['userId'],
        name: j['name'] ?? 'Member',
        handle: j['handle'] ?? '',
        emoji: j['emoji'] ?? '🙂',
        steps: (j['steps'] as num?)?.toInt() ?? 0,
        rank: (j['rank'] as num?)?.toInt() ?? 0,
        days: (j['days'] as List? ?? const []).map((e) => (e as num).toInt()).toList(),
      );
  Map<String, dynamic> toJson() => {'userId': userId, 'name': name, 'handle': handle, 'emoji': emoji, 'steps': steps, 'rank': rank, 'days': days};
}

/// My position in one league, compact enough for a watch complication.
class LeagueRank {
  const LeagueRank({required this.leagueId, required this.name, required this.emoji, required this.rank, required this.of, required this.steps, required this.leaderSteps, required this.daysLeft});
  final String leagueId;
  final String name;
  final String emoji;
  final int rank;
  final int of;
  final int steps;
  final int leaderSteps;
  final int daysLeft;

  int get gapToLeader => leaderSteps - steps;

  factory LeagueRank.fromJson(Map<String, dynamic> j) => LeagueRank(
        leagueId: j['leagueId'],
        name: j['name'] ?? 'League',
        emoji: j['emoji'] ?? '🏆',
        rank: (j['rank'] as num?)?.toInt() ?? 0,
        of: (j['of'] as num?)?.toInt() ?? 0,
        steps: (j['steps'] as num?)?.toInt() ?? 0,
        leaderSteps: (j['leaderSteps'] as num?)?.toInt() ?? 0,
        daysLeft: (j['daysLeft'] as num?)?.toInt() ?? 0,
      );
}

/// Badge catalogue entry. Mirrors public.badges.
class AppBadge {
  const AppBadge({required this.code, required this.name, required this.emoji, required this.description, this.tier = 1});
  final String code;
  final String name;
  final String emoji;
  final String description;
  final int tier;
}

class UserBadge {
  const UserBadge({required this.code, required this.earnedAt});
  final String code;
  final DateTime earnedAt;
  Map<String, dynamic> toJson() => {'code': code, 'earnedAt': earnedAt.toIso8601String()};
  factory UserBadge.fromJson(Map<String, dynamic> j) => UserBadge(code: j['code'], earnedAt: DateTime.tryParse(j['earnedAt'] ?? '') ?? DateTime.now());
}

/// Streak summary returned by my_streaks().
class Streaks {
  const Streaks({this.stepStreak = 0, this.stepBest = 0, this.workoutStreak = 0, this.weekWorkouts = 0, this.weekSteps = 0, this.totalWorkouts = 0});
  final int stepStreak;
  final int stepBest;
  final int workoutStreak;
  final int weekWorkouts;
  final int weekSteps;
  final int totalWorkouts;

  factory Streaks.fromJson(Map<String, dynamic> j) => Streaks(
        stepStreak: (j['stepStreak'] as num?)?.toInt() ?? 0,
        stepBest: (j['stepBest'] as num?)?.toInt() ?? 0,
        workoutStreak: (j['workoutStreak'] as num?)?.toInt() ?? 0,
        weekWorkouts: (j['weekWorkouts'] as num?)?.toInt() ?? 0,
        weekSteps: (j['weekSteps'] as num?)?.toInt() ?? 0,
        totalWorkouts: (j['totalWorkouts'] as num?)?.toInt() ?? 0,
      );
}

/// A finished session from the workout player.
class WorkoutLog {
  const WorkoutLog({required this.id, required this.userId, required this.completedAt, this.routineId, this.routineName = '', this.dayTitle = '', this.durationSec = 0, this.sets = 0});
  final String id;
  final String userId;
  final String? routineId;
  final String routineName;
  final String dayTitle;
  final int durationSec;
  final int sets;
  final DateTime completedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'routineId': routineId,
        'routineName': routineName,
        'dayTitle': dayTitle,
        'durationSec': durationSec,
        'sets': sets,
        'completedAt': completedAt.toIso8601String(),
      };
  factory WorkoutLog.fromJson(Map<String, dynamic> j) => WorkoutLog(
        id: j['id'],
        userId: j['userId'] ?? '',
        routineId: j['routineId'],
        routineName: j['routineName'] ?? '',
        dayTitle: j['dayTitle'] ?? '',
        durationSec: j['durationSec'] ?? 0,
        sets: j['sets'] ?? 0,
        completedAt: DateTime.tryParse(j['completedAt'] ?? '') ?? DateTime.now(),
      );
}

/// What a sync or a logged workout hands back: new badges plus fresh streaks.
class SyncResult {
  const SyncResult({this.newBadges = const [], this.streaks = const Streaks()});
  final List<String> newBadges;
  final Streaks streaks;
}

/// Monday of the week containing [d], as a date.
DateTime weekStart(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - 1));
}
