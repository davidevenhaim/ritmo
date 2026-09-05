import 'models.dart';

/// Seed community for the MVP. In production this is a Supabase/Postgres
/// social graph behind the same shapes (SocialUser, Post, Routine).
class SeedData {
  static const users = <String, SocialUser>{
    'maya': SocialUser(
      id: 'maya', name: 'Maya Chen', handle: 'maya.moves', emoji: '🧘‍♀️',
      bio: 'Mobility coach. Vegan. Will make you touch your toes.',
      goal: Goal.mobility, diet: ['Vegan'], creator: true, followers: 12400,
    ),
    'dario': SocialUser(
      id: 'dario', name: 'Dario Okafor', handle: 'dario_lifts', emoji: '🏋️',
      bio: '200 kg deadlift club. Powerlifting is a personality.',
      goal: Goal.getStronger, creator: true, followers: 8900,
    ),
    'lin': SocialUser(
      id: 'lin', name: 'Lin Park', handle: 'lin.runs', emoji: '🏃‍♀️',
      bio: 'Marathoner. 15k steps a day or I get weird.',
      goal: Goal.endurance, diet: ['Gluten-free'], followers: 2100,
    ),
    'zoe': SocialUser(
      id: 'zoe', name: 'Zoe Alvarez', handle: 'zoe.weird', emoji: '🤸',
      bio: 'Calisthenics + chaos. Inventor of the stairwell workout.',
      goal: Goal.buildMuscle, diet: ['Lactose-free'], followers: 3300,
    ),
    'ben': SocialUser(
      id: 'ben', name: 'Coach Ben', handle: 'coachben', emoji: '🔥',
      bio: 'Certified trainer. Posting the hottest 20-minute burners.',
      goal: Goal.loseFat, creator: true, followers: 41000,
    ),
    'ravi': SocialUser(
      id: 'ravi', name: 'Ravi Menon', handle: 'ravi.keto', emoji: '🥑',
      bio: 'Down 18 kg on keto + kettlebells. Ask me anything.',
      goal: Goal.loseFat, diet: ['Keto', 'Nut allergy'], followers: 760,
    ),
  };

  /// The ready-made routines the builder offers alongside the user's own.
  static List<Routine> get readyMade => [pushPullLegs, kettlebellBurner, stairwell, morningMobility];

  /// What the Community page lists under Coaches: the routines each creator
  /// publishes, on top of whatever they have shared to the feed.
  static List<Routine> get coachProgrammes => [pullStrength, hipsAfterSquats, conditioningLadder];

  /// Studios on the Community page. On-device seed: hosting these (and taking
  /// the booking) is the v1.1 studio plan, and no payment is taken here.
  static const studios = <Studio>[
    Studio(
      id: 'bloc',
      name: 'Bloc Studio',
      where: 'Rothschild 12 · 0.8 km',
      kind: 'Calisthenics',
      classes: [
        StudioClass(id: 'bloc_rings', name: 'Ring basics', weekday: DateTime.friday, hour: 18, minute: 30, coach: 'Dana K.', minutes: 60, spots: 4, price: '₪ 90'),
        StudioClass(id: 'bloc_handstand', name: 'Handstand lab', weekday: DateTime.saturday, hour: 7, minute: 0, coach: 'Ilan M.', minutes: 75, spots: 2, price: '₪ 110'),
        StudioClass(id: 'bloc_open', name: 'Open gym', weekday: DateTime.saturday, hour: 11, minute: 0, coach: '', minutes: 120, spots: 0, price: '₪ 45'),
      ],
    ),
    Studio(
      id: 'northline',
      name: 'Northline Mobility',
      where: 'Ibn Gabirol 88 · 2.1 km',
      kind: 'Flexibility',
      classes: [
        StudioClass(id: 'north_hips', name: 'Hip opening', weekday: DateTime.monday, hour: 19, minute: 15, coach: 'Rita S.', minutes: 50, spots: 8, price: '₪ 80'),
        StudioClass(id: 'north_split', name: 'Split progressions', weekday: DateTime.wednesday, hour: 8, minute: 0, coach: 'Rita S.', minutes: 60, spots: 5, price: '₪ 95'),
      ],
    ),
    Studio(
      id: 'ironworks',
      name: 'Ironworks Barbell',
      where: 'Ha-Masger 34 · 3.4 km',
      kind: 'Strength',
      classes: [
        StudioClass(id: 'iron_technique', name: 'Squat technique', weekday: DateTime.tuesday, hour: 18, minute: 0, coach: 'Dario O.', minutes: 60, spots: 6, price: '₪ 100'),
        StudioClass(id: 'iron_platform', name: 'Platform hours', weekday: DateTime.sunday, hour: 9, minute: 30, coach: '', minutes: 90, spots: 0, price: '₪ 50'),
      ],
    ),
  ];

  static final _now = DateTime.now();

  static final pushPullLegs = Routine(
    id: 'seed_ppl',
    name: 'Push / Pull / Legs',
    description: 'The classic 3-day split. Big compound lifts first, accessories after. Add 2.5 kg whenever you hit the top of the rep range.',
    authorId: 'dario',
    authorName: 'Dario Okafor',
    createdAt: _now.subtract(const Duration(days: 3)),
    tags: ['strength', 'barbell', '3-day'],
    source: 'community',
    days: const [
      RoutineDay(title: 'Push', focus: 'Chest, shoulders, triceps', items: [
        RoutineItem(exerciseId: 'Barbell_Bench_Press_-_Medium_Grip', exerciseName: 'Barbell Bench Press - Medium Grip', sets: 4, reps: 6, restSec: 150),
        RoutineItem(exerciseId: 'Barbell_Incline_Bench_Press_-_Medium_Grip', exerciseName: 'Barbell Incline Bench Press - Medium Grip', sets: 3, reps: 8, restSec: 120),
        RoutineItem(exerciseId: 'Dips_-_Triceps_Version', exerciseName: 'Dips - Triceps Version', sets: 3, reps: 10, restSec: 90),
        RoutineItem(exerciseId: 'Face_Pull', exerciseName: 'Face Pull', sets: 3, reps: 15, restSec: 60),
      ]),
      RoutineDay(title: 'Pull', focus: 'Back, biceps', items: [
        RoutineItem(exerciseId: 'Barbell_Deadlift', exerciseName: 'Barbell Deadlift', sets: 3, reps: 5, restSec: 180),
        RoutineItem(exerciseId: 'Pullups', exerciseName: 'Pullups', sets: 4, reps: 8, restSec: 120),
        RoutineItem(exerciseId: 'Alternating_Kettlebell_Row', exerciseName: 'Alternating Kettlebell Row', sets: 3, reps: 12, restSec: 90),
      ]),
      RoutineDay(title: 'Legs', focus: 'Quads, hamstrings, glutes', items: [
        RoutineItem(exerciseId: 'Barbell_Squat', exerciseName: 'Barbell Squat', sets: 4, reps: 6, restSec: 180),
        RoutineItem(exerciseId: 'Romanian_Deadlift', exerciseName: 'Romanian Deadlift', sets: 3, reps: 10, restSec: 120),
        RoutineItem(exerciseId: 'Barbell_Hip_Thrust', exerciseName: 'Barbell Hip Thrust', sets: 3, reps: 12, restSec: 90),
        RoutineItem(exerciseId: 'Hanging_Leg_Raise', exerciseName: 'Hanging Leg Raise', sets: 3, reps: 12, restSec: 60),
      ]),
    ],
  );

  static final stairwell = Routine(
    id: 'seed_stairwell',
    name: 'The Stairwell Workout',
    description: 'No gym, no problem. One office stairwell, 18 minutes, questionable looks from coworkers.',
    authorId: 'zoe',
    authorName: 'Zoe Alvarez',
    createdAt: _now.subtract(const Duration(days: 1, hours: 4)),
    tags: ['weird', 'body only', 'no-gym'],
    source: 'community',
    days: const [
      RoutineDay(title: 'Stairwell circuit', focus: 'Full body, 3 rounds', items: [
        RoutineItem(exerciseId: 'Bodyweight_Walking_Lunge', exerciseName: 'Bodyweight Walking Lunge', sets: 3, reps: 20, restSec: 30, notes: 'Two steps per lunge'),
        RoutineItem(exerciseId: 'Pushups', exerciseName: 'Pushups', sets: 3, reps: 15, restSec: 30, notes: 'Hands on the 3rd step'),
        RoutineItem(exerciseId: 'Mountain_Climbers', exerciseName: 'Mountain Climbers', sets: 3, reps: 30, restSec: 30),
        RoutineItem(exerciseId: 'Bench_Dips', exerciseName: 'Bench Dips', sets: 3, reps: 12, restSec: 30, notes: 'Use the landing rail'),
        RoutineItem(exerciseId: 'Plank', exerciseName: 'Plank', sets: 3, reps: 1, restSec: 45, notes: '45 second hold'),
      ]),
    ],
  );

  static final kettlebellBurner = Routine(
    id: 'seed_kb',
    name: '20-min Kettlebell Burner',
    description: 'One bell, EMOM style. Hot, sweaty, done before your coffee gets cold.',
    authorId: 'ben',
    authorName: 'Coach Ben',
    createdAt: _now.subtract(const Duration(hours: 9)),
    tags: ['hot', 'kettlebells', 'fat loss'],
    source: 'community',
    days: const [
      RoutineDay(title: 'EMOM 20', focus: 'Conditioning', items: [
        RoutineItem(exerciseId: 'One-Arm_Kettlebell_Swings', exerciseName: 'One-Arm Kettlebell Swings', sets: 5, reps: 15, restSec: 20),
        RoutineItem(exerciseId: 'Goblet_Squat', exerciseName: 'Goblet Squat', sets: 5, reps: 12, restSec: 20),
        RoutineItem(exerciseId: 'Kettlebell_Turkish_Get-Up_Squat_style', exerciseName: 'Kettlebell Turkish Get-Up (Squat style)', sets: 5, reps: 2, restSec: 20),
        RoutineItem(exerciseId: 'Farmers_Walk', exerciseName: 'Farmers Walk', sets: 5, reps: 1, restSec: 20, notes: '40 m'),
      ]),
    ],
  );

  static final morningMobility = Routine(
    id: 'seed_mobility',
    name: 'Sunrise Mobility Flow',
    description: 'Eight minutes to undo eight hours of sitting. Breathe through your nose the whole way.',
    authorId: 'maya',
    authorName: 'Maya Chen',
    createdAt: _now.subtract(const Duration(days: 2)),
    tags: ['mobility', 'stretching', 'morning'],
    source: 'community',
    days: const [
      RoutineDay(title: 'Flow', focus: 'Spine, hips, shoulders', items: [
        RoutineItem(exerciseId: 'Cat_Stretch', exerciseName: 'Cat Stretch', sets: 2, reps: 10, restSec: 0),
        RoutineItem(exerciseId: 'Childs_Pose', exerciseName: "Child's Pose", sets: 2, reps: 1, restSec: 0, notes: '60 second hold'),
        RoutineItem(exerciseId: 'Downward_Facing_Balance', exerciseName: 'Downward Facing Balance', sets: 2, reps: 8, restSec: 0),
        RoutineItem(exerciseId: 'Push_Up_to_Side_Plank', exerciseName: 'Push Up to Side Plank', sets: 2, reps: 6, restSec: 30),
      ]),
    ],
  );

  static final pullStrength = Routine(
    id: 'seed_pull_strength',
    name: 'Pull strength — week 4',
    description: 'Fourth week of the pulling block. Scapular work first while you are fresh, then the heavy set, then volume.',
    authorId: 'dario',
    authorName: 'Dario Okafor',
    createdAt: _now.subtract(const Duration(days: 5)),
    tags: ['calisthenics', 'strength', 'coach'],
    source: 'community',
    days: const [
      RoutineDay(title: 'Pull', focus: 'Back, biceps, grip', items: [
        RoutineItem(exerciseId: 'Scapular_Pull-Up', exerciseName: 'Scapular Pull-Up', sets: 3, reps: 8, restSec: 60, notes: 'Shoulders down, arms straight'),
        RoutineItem(exerciseId: 'Pullups', exerciseName: 'Pullups', sets: 5, reps: 5, restSec: 150),
        RoutineItem(exerciseId: 'Inverted_Row', exerciseName: 'Inverted Row', sets: 4, reps: 10, restSec: 90),
        RoutineItem(exerciseId: 'Face_Pull', exerciseName: 'Face Pull', sets: 3, reps: 15, restSec: 60),
        RoutineItem(exerciseId: 'Hanging_Leg_Raise', exerciseName: 'Hanging Leg Raise', sets: 3, reps: 10, restSec: 60),
        RoutineItem(exerciseId: 'Farmers_Walk', exerciseName: 'Farmers Walk', sets: 3, reps: 1, restSec: 90, notes: '40 m'),
      ]),
    ],
  );

  static final hipsAfterSquats = Routine(
    id: 'seed_hips_after_squats',
    name: 'Hips after squats',
    description: 'Twenty minutes for the day after legs. Nothing here is a stretch you have to force.',
    authorId: 'maya',
    authorName: 'Maya Chen',
    createdAt: _now.subtract(const Duration(days: 4)),
    tags: ['mobility', 'recovery', 'coach'],
    source: 'community',
    days: const [
      RoutineDay(title: 'Hips', focus: 'Hips, quads, hamstrings', items: [
        RoutineItem(exerciseId: 'Kneeling_Hip_Flexor', exerciseName: 'Kneeling Hip Flexor', sets: 2, reps: 1, restSec: 15, notes: '45 seconds a side'),
        RoutineItem(exerciseId: 'yoga_24', exerciseName: 'Pigeon Pose', sets: 2, reps: 1, restSec: 15, notes: '60 seconds a side'),
        RoutineItem(exerciseId: 'Seated_Floor_Hamstring_Stretch', exerciseName: 'Seated Floor Hamstring Stretch', sets: 2, reps: 1, restSec: 15, notes: '45 second hold'),
        RoutineItem(exerciseId: 'Quadriceps-SMR', exerciseName: 'Quadriceps-SMR', sets: 1, reps: 1, restSec: 0, notes: '90 seconds a leg'),
        RoutineItem(exerciseId: 'Childs_Pose', exerciseName: "Child's Pose", sets: 1, reps: 1, restSec: 0, notes: 'Two minutes, nose breathing'),
      ]),
    ],
  );

  static final conditioningLadder = Routine(
    id: 'seed_conditioning_ladder',
    name: 'Conditioning ladder',
    description: 'Twelve minutes, descending ladder. Stop a rep short of ugly.',
    authorId: 'ben',
    authorName: 'Coach Ben',
    createdAt: _now.subtract(const Duration(days: 2, hours: 6)),
    tags: ['conditioning', 'fat loss', 'coach'],
    source: 'community',
    days: const [
      RoutineDay(title: 'Ladder', focus: 'Full body conditioning', items: [
        RoutineItem(exerciseId: 'repdb_jump-rope', exerciseName: 'Jump Rope', sets: 4, reps: 1, restSec: 30, notes: '60 seconds'),
        RoutineItem(exerciseId: 'repdb_burpees', exerciseName: 'Burpees', sets: 4, reps: 10, restSec: 45),
        RoutineItem(exerciseId: 'Mountain_Climbers', exerciseName: 'Mountain Climbers', sets: 4, reps: 30, restSec: 30),
        RoutineItem(exerciseId: 'repdb_hollow-body-hold', exerciseName: 'Hollow Body Hold', sets: 4, reps: 1, restSec: 30, notes: '30 second hold'),
      ]),
    ],
  );

  /// Two open reports so the demo moderation queue is not empty.
  static List<Report> reports() => [
        Report(
          id: 'r_seed_1',
          reporterId: 'lin',
          target: ReportTarget.post,
          targetId: 'p_zoe_stairs',
          reason: ReportReason.unsafeAdvice,
          details: 'Running stairs with a loaded backpack and no warm-up is an ankle waiting to happen.',
          createdAt: _now.subtract(const Duration(hours: 5)),
        ),
        Report(
          id: 'r_seed_2',
          reporterId: 'ravi',
          target: ReportTarget.post,
          targetId: 'p_ben_diet',
          reason: ReportReason.spam,
          details: 'Reads like an ad for his meal plan.',
          createdAt: _now.subtract(const Duration(hours: 2)),
        ),
      ];

  static List<Post> posts() => [
        Post(
          id: 'p_ben_video',
          authorId: 'ben',
          kind: PostKind.video,
          title: '🔥 HOT: 20-minute kettlebell burner',
          body: 'One bell, twenty minutes, every minute on the minute. Save the routine below and tag me when you survive it.',
          createdAt: _now.subtract(const Duration(hours: 9)),
          likes: 412, recommends: 96, comments: 38,
          tags: ['hot', 'kettlebells'],
          routine: kettlebellBurner,
          videoUrl: 'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4',
          video: const Video(
            id: 'v_ben_burner', authorId: 'ben', status: VideoStatus.ready,
            playbackUrl: 'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4',
            durationSec: 58, width: 16, height: 9, views: 6120,
            exerciseIds: ['Kettlebell_Swing', 'Goblet_Squat', 'Kettlebell_Clean_and_Press'],
          ),
          views: 6120,
          hot: true,
        ),
        Post(
          id: 'p_zoe_stairs',
          authorId: 'zoe',
          kind: PostKind.weird,
          title: '🤪 Weird routine: the stairwell workout',
          body: 'My gym membership lapsed so I built a full-body session out of the office stairwell. Coworkers are concerned. Legs are destroyed.',
          createdAt: _now.subtract(const Duration(days: 1, hours: 4)),
          likes: 289, recommends: 71, comments: 52,
          tags: ['weird', 'no-gym'],
          routine: stairwell,
        ),
        Post(
          id: 'p_lin_steps',
          authorId: 'lin',
          kind: PostKind.steps,
          title: 'Steps: 18,204 today',
          body: 'Long run plus a walk-and-talk meeting. Who else is chasing 100k this week?',
          createdAt: _now.subtract(const Duration(hours: 3)),
          likes: 134, recommends: 12, comments: 17,
          tags: ['steps'],
          steps: 18204,
        ),
        Post(
          id: 'p_dario_ppl',
          authorId: 'dario',
          kind: PostKind.routine,
          title: 'Push / Pull / Legs, the version that actually works',
          body: 'Ran this for 12 weeks. Bench +15 kg, deadlift +25 kg. Recommendation: do NOT skip face pulls.',
          createdAt: _now.subtract(const Duration(days: 3)),
          likes: 908, recommends: 244, comments: 121,
          tags: ['strength', 'barbell'],
          routine: pushPullLegs,
        ),
        Post(
          id: 'p_maya_video',
          authorId: 'maya',
          kind: PostKind.video,
          title: 'Sunrise mobility flow (8 minutes)',
          body: 'Filmed at 6:10 this morning. Vegan-fuelled, caffeine-free, somehow still awake.',
          createdAt: _now.subtract(const Duration(days: 2)),
          likes: 356, recommends: 88, comments: 29,
          tags: ['mobility', 'morning'],
          routine: morningMobility,
          videoUrl: 'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
          video: const Video(
            id: 'v_maya_flow', authorId: 'maya', status: VideoStatus.ready,
            playbackUrl: 'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
            durationSec: 44, width: 16, height: 9, views: 4810,
            exerciseIds: ['Cat_Stretch', 'Downward_Facing_Balance', 'Hip_Circles_(stretch)'],
          ),
          views: 4810,
        ),
        Post(
          id: 'p_ravi_diet',
          authorId: 'ravi',
          kind: PostKind.diet,
          title: 'Keto + nut allergy meal prep that does not suck',
          body: 'Sunday prep: 5 x salmon + broccoli + avocado, 5 x egg muffins with spinach, sunflower-seed butter instead of peanut. 1,850 kcal/day, 140 g protein.',
          createdAt: _now.subtract(const Duration(days: 1)),
          likes: 221, recommends: 64, comments: 41,
          tags: ['diet', 'keto', 'nut allergy'],
        ),
        Post(
          id: 'p_ben_diet',
          authorId: 'ben',
          kind: PostKind.diet,
          title: 'Diet recommendation: protein first, then everything else',
          body: 'Clients who hit 1.6 g/kg protein lose fat twice as fast on the same calories. Build every plate around the protein source.',
          createdAt: _now.subtract(const Duration(days: 4)),
          likes: 512, recommends: 130, comments: 63,
          tags: ['diet', 'fat loss'],
        ),
        Post(
          id: 'p_zoe_workout',
          authorId: 'zoe',
          kind: PostKind.workout,
          title: 'Did Dario\'s PPL Pull day, first unassisted pull-ups!',
          body: '4 x 8 pull-ups without the band. Screaming internally. Thanks @dario_lifts.',
          createdAt: _now.subtract(const Duration(hours: 20)),
          likes: 176, recommends: 9, comments: 33,
          tags: ['workout', 'pull day'],
        ),
      ];

  // v0.2 seed extras so the local demo shows comments and notifications.
  static List<Comment> comments() {
    final now = DateTime.now();
    Comment c(String id, String post, String author, String body, int hoursAgo) => Comment(
          id: id, postId: post, authorId: author, body: body, createdAt: now.subtract(Duration(hours: hoursAgo)));
    return [
      c('c1', 'p_ben_video', 'zoe', 'Survived. Barely. The get-ups at minute 15 are evil.', 8),
      c('c2', 'p_ben_video', 'lin', 'Swapped the farmers walk for a 400 m run, still counts?', 6),
      c('c3', 'p_ben_video', 'ben', '@lin.runs absolutely counts, that is the spirit', 5),
      c('c4', 'p_dario_ppl', 'maya', 'Add 5 minutes of hip openers before leg day and your squat depth will thank you.', 60),
      c('c5', 'p_dario_ppl', 'ravi', 'Running this with kettlebells instead of a barbell, works great.', 40),
      c('c6', 'p_zoe_stairs', 'dario', 'This is unhinged and I love it.', 30),
    ];
  }

  static List<AppNotification> notifications() {
    final now = DateTime.now();
    return [
      AppNotification(id: 'n1', kind: NotificationKind.follow, actorId: 'maya', createdAt: now.subtract(const Duration(hours: 2))),
      AppNotification(id: 'n2', kind: NotificationKind.tryIt, actorId: 'zoe', routineId: 'seed_ppl', preview: 'Push / Pull / Legs', createdAt: now.subtract(const Duration(hours: 5))),
      AppNotification(id: 'n3', kind: NotificationKind.recommend, actorId: 'ben', preview: 'Your first steps share', createdAt: now.subtract(const Duration(days: 1)), read: true),
    ];
  }
}
