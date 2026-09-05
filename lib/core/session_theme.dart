import 'models.dart';

/// The six themes the routine builder opens with (Nocturne handoff, step 1).
///
/// Each one is a real filter over the bundled catalogue, so the count on a
/// theme card is the number of exercises actually behind it. The theme also
/// carries how its work is done — sets, reps and rest — so a session built
/// from it arrives with sensible numbers instead of blanks.
enum SessionTheme {
  bodyweight('bodyweight', 'Bodyweight', 'No equipment', sets: 3, reps: 12, restSec: 45),
  gym('gym', 'Gym', 'Barbell · machines', sets: 4, reps: 8, restSec: 90),
  flexibility('flexibility', 'Flexibility', 'Mobility · stretch', sets: 3, reps: 45, restSec: 20, hold: true),
  handstand('handstand', 'Handstand', 'Balance · wrists', sets: 4, reps: 5, restSec: 60),
  calisthenics('calisthenics', 'Calisthenics', 'Rings · bars', sets: 4, reps: 8, restSec: 75),
  core('core', 'Core', 'Trunk · anti-rotation', sets: 3, reps: 15, restSec: 45);

  const SessionTheme(this.id, this.name, this.hint, {required this.sets, required this.reps, required this.restSec, this.hold = false});

  final String id;
  final String name;

  /// The 10.5px accent line under the count on a theme card.
  final String hint;

  final int sets;

  /// Reps, or seconds when [hold].
  final int reps;
  final int restSec;

  /// Flexibility work is held, not repeated.
  final bool hold;

  static SessionTheme byId(String id) => SessionTheme.values.firstWhere((t) => t.id == id, orElse: () => SessionTheme.bodyweight);

  /// "3 × 12 · chest" — the meta line on a library tile and timeline row.
  String metaFor(Exercise e) {
    final part = e.primary.isNotEmpty ? e.primary.first : e.category;
    return '$sets × $reps${hold ? 's' : ''} · $part';
  }

  /// Minutes this exercise costs in a session: every set is its rest plus
  /// about forty seconds of work. Drives the proportional timeline segments.
  int minutesFor() {
    final work = hold ? reps : 40;
    return ((sets * (restSec + work)) / 60).round().clamp(2, 30);
  }

  RoutineItem itemFor(Exercise e) => RoutineItem(
        exerciseId: e.id,
        exerciseName: e.name,
        sets: sets,
        reps: hold ? 1 : reps,
        restSec: restSec,
        notes: hold ? 'Hold ${reps}s' : '',
      );

  static const _bodyweightKit = {'body only', 'none'};
  static const _gymKit = {'barbell', 'dumbbell', 'machine', 'cable', 'e-z curl bar', 'kettlebells', 'smith machine', 'trap bar', 'plates'};
  static const _barKit = {'pull up bar', 'rings', 'dip station', 'suspension trainer', 'climbing rope'};

  /// Whether an exercise belongs to this theme.
  bool has(Exercise e) {
    final name = e.name.toLowerCase();
    switch (this) {
      case SessionTheme.bodyweight:
        return _bodyweightKit.contains(e.equipment) && const {'strength', 'plyometrics'}.contains(e.category);
      case SessionTheme.gym:
        return _gymKit.contains(e.equipment) || e.equipment.contains('machine');
      case SessionTheme.flexibility:
        return e.category == 'stretching' || e.category == 'yoga';
      case SessionTheme.handstand:
        return name.contains('handstand') ||
            name.contains('wall walk') ||
            name.contains('pike') ||
            name.contains('wrist') ||
            name.contains('hollow') ||
            name.contains('shoulder tap') ||
            (e.primary.contains('shoulders') && _bodyweightKit.contains(e.equipment));
      case SessionTheme.calisthenics:
        return _barKit.contains(e.equipment) ||
            name.contains('pull-up') ||
            name.contains('pull up') ||
            name.contains('chin-up') ||
            name.contains('muscle-up') ||
            name.contains('dip') ||
            name.contains('lever') ||
            name.contains('ring ') ||
            name.contains('archer');
      case SessionTheme.core:
        return e.primary.contains('abdominals') || e.primary.contains('lower back');
    }
  }

  /// Compound work first, then alphabetical, so the top of a library reads
  /// like the exercises someone would actually start with.
  static int rank(Exercise e) => e.mechanic == 'compound' ? 0 : 1;
}
