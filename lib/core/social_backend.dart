import 'dart:async';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'backend.dart';
import 'badge_rules.dart';
import 'local_store.dart';
import 'models.dart';
import 'social_repository.dart';

/// Everything the feed, profile and notifications need in one load.
class SocialSnapshot {
  const SocialSnapshot({
    required this.posts,
    required this.users,
    required this.liked,
    required this.recommended,
    required this.following,
    required this.notifications,
  });
  final List<Post> posts;
  final Map<String, SocialUser> users;
  final Set<String> liked;
  final Set<String> recommended;
  final Set<String> following;
  final List<AppNotification> notifications;
}

/// The social graph behind the UI (v0.2).
///
/// [LocalSocialBackend] is the on-device demo with the seeded community;
/// [SupabaseSocialBackend] is the hosted graph. Providers pick one based on
/// [BackendConfig.enabled] and whether the user is signed in, so screens never
/// know which one they are talking to.
abstract class SocialBackend {
  bool get isRemote;

  Future<SocialSnapshot> load(UserProfile me);
  Future<void> setLike(String postId, bool on);
  Future<void> recommend(String postId);
  Future<void> setFollow(String userId, bool on);

  /// Returns the stored post (the hosted backend assigns ids and timestamps).
  Future<Post> publish(Post post);

  Future<List<Comment>> comments(String postId);
  Future<Comment> addComment(String postId, String body, UserProfile me);

  /// "Try it": [original] was copied into my library as [copy].
  Future<void> recordTry(Routine original, Routine copy);

  Future<List<AppNotification>> notifications();
  Future<void> markAllRead();

  Future<void> syncProfile(UserProfile me);
  /// The hosted profile and whether onboarding data has been filled in
  /// (a freshly trigger-created row only has a handle and a name).
  Future<({UserProfile profile, bool complete})?> fetchProfile(String id);

  Future<List<Routine>> myRoutines(String userId);
  Future<void> saveRoutine(Routine r);
  Future<void> deleteRoutine(String id);

  // ----------------------------------------------------------- v0.3
  Future<void> deletePost(String id);

  /// Latest state of a hosted clip (status flips to ready via webhook).
  Future<Video?> video(String id);

  /// Counts once per viewer per day. Fire and forget.
  Future<void> recordView(String postId);

  /// Everything one member posted, newest first. Hidden posts only for the author.
  Future<List<Post>> postsBy(String userId, {required String viewerId});
  Future<SocialUser?> user(String id);

  /// Returns false when this member already reported the target.
  Future<bool> report({required ReportTarget target, required String targetId, required ReportReason reason, String details = '', required UserProfile me});

  /// Open reports with a target preview. Moderators only on the hosted graph.
  Future<List<Report>> openReports();
  Future<void> moderate(Report report, ModerationAction action, {String note = ''});

  Future<CreatorStats> creatorStats(String userId);
  Future<CreatorStatus> creatorStatus(String userId);
  Future<void> applyAsCreator(String statement, UserProfile me);

  // ----------------------------------------------------------- v0.4
  /// Push the last days of steps; returns badges just earned and fresh streaks.
  Future<SyncResult> syncSteps(List<StepDay> days, UserProfile me);
  Future<SyncResult> logWorkout(WorkoutLog log, UserProfile me);
  Future<Streaks> streaks(UserProfile me);
  Future<List<UserBadge>> badges(String userId);

  /// My last finished sessions, newest first (v0.5 home page).
  Future<List<WorkoutLog>> recentWorkouts(UserProfile me, {int limit = 5});

  Future<List<League>> myLeagues(UserProfile me);
  Future<League> createLeague(String name, String emoji, UserProfile me);
  Future<League> joinLeague(String code, UserProfile me);
  Future<void> leaveLeague(String leagueId, UserProfile me);
  Future<List<Standing>> standings(String leagueId, UserProfile me);
  Future<List<LeagueRank>> myLeagueRanks(UserProfile me);

  /// Public leagues near the user, nearest first, for the + menu (v0.5).
  Future<List<League>> nearbyLeagues(UserProfile me);

  /// Fires when other people change the feed (hosted backend only).
  Stream<void> get changes;

  void dispose() {}
}

// =========================================================== local (demo)
class LocalSocialBackend implements SocialBackend {
  LocalSocialBackend(this._store);
  final LocalStore _store;

  static const _seedVersion = '5';

  @override
  bool get isRemote => false;

  @override
  Stream<void> get changes => const Stream.empty();

  bool get _seeded => _store.getString('seed_v') == _seedVersion;

  @override
  Future<SocialSnapshot> load(UserProfile me) async {
    List<Post> posts;
    List<AppNotification> notifications;
    if (_seeded) {
      posts = _store.getList('posts').map(Post.fromJson).toList();
      notifications = _store.getList('notifications').map(AppNotification.fromJson).toList();
    } else {
      posts = SeedData.posts();
      notifications = SeedData.notifications();
      await _store.putString('seed_v', _seedVersion);
      await _store.put('posts', posts.map((p) => p.toJson()).toList());
      await _store.put('notifications', notifications.map((n) => n.toJson()).toList());
      await _store.put('comments', SeedData.comments().map((c) => c.toJson()).toList());
      await _store.put('reports', SeedData.reports().map((r) => r.toJson()).toList());
    }
    // Demo transcoding: uploads become playable a few seconds after posting.
    posts = posts.map(_settleVideo).toList();
    posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return SocialSnapshot(
      posts: posts,
      users: SeedData.users,
      liked: _keys('liked'),
      recommended: _keys('recommended'),
      following: _keys('following'),
      notifications: notifications,
    );
  }

  /// Demo clips are "processing" until [_demoTranscode] after creation, then
  /// play the placeholder clip.
  static const _demoTranscode = Duration(seconds: 6);
  Post _settleVideo(Post p) {
    final v = p.video;
    if (v == null || v.status != VideoStatus.processing) return p;
    if (DateTime.now().difference(p.createdAt) < _demoTranscode) return p;
    return p.copyWith(video: v.copyWith(status: VideoStatus.ready, playbackUrl: v.playbackUrl ?? _demoClip));
  }

  static const _demoClip = 'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4';

  Set<String> _keys(String k) => (_store.getMap(k)?.keys ?? const Iterable<String>.empty()).toSet();
  Future<void> _putKeys(String k, Set<String> v) => _store.put(k, {for (final id in v) id: true});

  Future<void> _mutatePost(String postId, Post Function(Post) f) async {
    final posts = _store.getList('posts').map(Post.fromJson).map((p) => p.id == postId ? f(p) : p).toList();
    await _store.put('posts', posts.map((p) => p.toJson()).toList());
  }

  @override
  Future<void> setLike(String postId, bool on) async {
    final liked = _keys('liked');
    if (on == liked.contains(postId)) return;
    on ? liked.add(postId) : liked.remove(postId);
    await _putKeys('liked', liked);
    await _mutatePost(postId, (p) => p.copyWith(likes: max(0, p.likes + (on ? 1 : -1))));
  }

  @override
  Future<void> recommend(String postId) async {
    final rec = _keys('recommended');
    if (rec.contains(postId)) return;
    rec.add(postId);
    await _putKeys('recommended', rec);
    await _mutatePost(postId, (p) => p.copyWith(recommends: p.recommends + 1));
  }

  @override
  Future<void> setFollow(String userId, bool on) async {
    final f = _keys('following');
    on ? f.add(userId) : f.remove(userId);
    await _putKeys('following', f);
  }

  @override
  Future<Post> publish(Post post) async {
    final posts = _store.getList('posts');
    await _store.put('posts', [post.toJson(), ...posts]);
    return post;
  }

  @override
  Future<List<Comment>> comments(String postId) async {
    return _store.getList('comments').map(Comment.fromJson).where((c) => c.postId == postId).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  @override
  Future<Comment> addComment(String postId, String body, UserProfile me) async {
    final c = Comment(
      id: 'c_${DateTime.now().microsecondsSinceEpoch}',
      postId: postId,
      authorId: me.id,
      body: body.trim(),
      createdAt: DateTime.now(),
    );
    await _store.put('comments', [..._store.getList('comments'), c.toJson()]);
    await _mutatePost(postId, (p) => p.copyWith(comments: p.comments + 1));
    return c;
  }

  @override
  Future<void> recordTry(Routine original, Routine copy) async {}

  @override
  Future<List<AppNotification>> notifications() async =>
      _store.getList('notifications').map(AppNotification.fromJson).toList();

  @override
  Future<void> markAllRead() async {
    final n = _store.getList('notifications').map(AppNotification.fromJson).map((x) => x.copyWith(read: true));
    await _store.put('notifications', n.map((x) => x.toJson()).toList());
  }

  @override
  Future<void> syncProfile(UserProfile me) async {}

  @override
  Future<({UserProfile profile, bool complete})?> fetchProfile(String id) async => null;

  @override
  Future<List<Routine>> myRoutines(String userId) async => const [];

  @override
  Future<void> saveRoutine(Routine r) async {}

  @override
  Future<void> deleteRoutine(String id) async {}

  // ----------------------------------------------------------- v0.3
  @override
  Future<void> deletePost(String id) async {
    await _store.put('posts', _store.getList('posts').where((p) => p['id'] != id).toList());
  }

  @override
  Future<Video?> video(String id) async {
    for (final p in _store.getList('posts').map(Post.fromJson)) {
      if (p.video?.id == id) return _settleVideo(p).video;
    }
    return null;
  }

  final _viewed = <String>{};
  @override
  Future<void> recordView(String postId) async {
    if (!_viewed.add(postId)) return;
    await _mutatePost(postId, (p) => p.copyWith(views: p.views + 1));
  }

  @override
  Future<List<Post>> postsBy(String userId, {required String viewerId}) async {
    final posts = _store.getList('posts').map(Post.fromJson).map(_settleVideo).where((p) => p.authorId == userId && (!p.hidden || userId == viewerId)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return posts;
  }

  @override
  Future<SocialUser?> user(String id) async => SeedData.users[id];

  @override
  Future<bool> report({required ReportTarget target, required String targetId, required ReportReason reason, String details = '', required UserProfile me}) async {
    final reports = _store.getList('reports').map(Report.fromJson).toList();
    if (reports.any((r) => r.reporterId == me.id && r.target == target && r.targetId == targetId)) return false;
    reports.add(Report(
      id: 'r_${DateTime.now().microsecondsSinceEpoch}',
      reporterId: me.id,
      target: target,
      targetId: targetId,
      reason: reason,
      details: details.trim(),
      createdAt: DateTime.now(),
    ));
    await _store.put('reports', reports.map((r) => r.toJson()).toList());
    // Mirror the server trigger: three open reports hide a post.
    if (target == ReportTarget.post) {
      final open = reports.where((r) => r.target == target && r.targetId == targetId && r.status == ReportStatus.open).length;
      if (open >= 3) await _mutatePost(targetId, (p) => p.copyWith(hidden: true));
    }
    return true;
  }

  @override
  Future<List<Report>> openReports() async {
    final posts = {for (final p in _store.getList('posts').map(Post.fromJson)) p.id: p};
    final comments = {for (final c in _store.getList('comments').map(Comment.fromJson)) c.id: c};
    return _store.getList('reports').map(Report.fromJson).where((r) => r.status == ReportStatus.open).map((r) {
      switch (r.target) {
        case ReportTarget.post:
          final p = posts[r.targetId];
          return r.copyWith(targetTitle: p?.title ?? '(deleted post)', targetAuthorId: p?.authorId, targetHidden: p?.hidden ?? false);
        case ReportTarget.comment:
          final c = comments[r.targetId];
          return r.copyWith(targetTitle: c?.body ?? '(deleted comment)', targetAuthorId: c?.authorId);
        case ReportTarget.profile:
          return r.copyWith(targetTitle: '@${SeedData.users[r.targetId]?.handle ?? r.targetId}', targetAuthorId: r.targetId);
      }
    }).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  @override
  Future<void> moderate(Report report, ModerationAction action, {String note = ''}) async {
    if (report.target == ReportTarget.post) {
      switch (action) {
        case ModerationAction.hide:
          await _mutatePost(report.targetId, (p) => p.copyWith(hidden: true));
        case ModerationAction.restore:
          await _mutatePost(report.targetId, (p) => p.copyWith(hidden: false));
        case ModerationAction.remove:
          await deletePost(report.targetId);
        case ModerationAction.dismiss:
        case ModerationAction.warn:
        case ModerationAction.ban:
          break;
      }
    } else if (report.target == ReportTarget.comment && action == ModerationAction.remove) {
      await _store.put('comments', _store.getList('comments').where((c) => c['id'] != report.targetId).toList());
    }
    final status = action == ModerationAction.dismiss ? ReportStatus.dismissed : ReportStatus.actioned;
    final reports = _store.getList('reports').map(Report.fromJson).map((r) {
      final same = r.target == report.target && r.targetId == report.targetId && r.status == ReportStatus.open;
      return same ? r.copyWith(status: status, action: action) : r;
    });
    await _store.put('reports', reports.map((r) => r.toJson()).toList());
  }

  @override
  Future<CreatorStats> creatorStats(String userId) async {
    final mine = _store.getList('posts').map(Post.fromJson).where((p) => p.authorId == userId).toList();
    // Seed posts carry no view history; derive a plausible audience from engagement.
    int viewsOf(Post p) => p.views + p.likes * 9 + p.comments * 4 + p.recommends * 6;
    final views = mine.fold(0, (n, p) => n + viewsOf(p));
    final seed = userId.hashCode.abs();
    final byDay = List<int>.generate(7, (i) => views == 0 ? 0 : (views * (6 + (seed + i * 7) % 9) / 70).round());
    final tries = mine.where((p) => p.routine != null).fold(0, (n, p) => n + (p.recommends / 3).round());
    return CreatorStats(
      followers: SeedData.users[userId]?.followers ?? _keys('following').length * 3 + 12,
      following: _keys('following').length,
      posts: mine.length,
      views: views,
      likes: mine.fold(0, (n, p) => n + p.likes),
      recommends: mine.fold(0, (n, p) => n + p.recommends),
      comments: mine.fold(0, (n, p) => n + p.comments),
      tries: tries,
      viewsByDay: byDay,
      topPosts: (mine..sort((a, b) => viewsOf(b).compareTo(viewsOf(a))))
          .take(10)
          .map((p) => PostStat(postId: p.id, title: p.title, kind: p.kind, views: viewsOf(p), likes: p.likes, comments: p.comments, recommends: p.recommends, tries: p.routine == null ? 0 : (p.recommends / 3).round()))
          .toList(),
    );
  }

  @override
  Future<CreatorStatus> creatorStatus(String userId) async =>
      _store.getString('creator_status') == 'approved' ? CreatorStatus.approved : CreatorStatus.none;

  /// Demo: instant approval so uploads can be tried without a backend.
  @override
  Future<void> applyAsCreator(String statement, UserProfile me) async {
    await _store.putString('creator_status', 'approved');
  }

  // ----------------------------------------------------------- v0.4
  List<StepDay> _stepDays() => _store.getList('step_days').map((j) => StepDay(DateTime.parse(j['day'] as String), j['steps'] as int)).toList();
  List<WorkoutLog> _logs() => _store.getList('workout_logs').map(WorkoutLog.fromJson).toList();
  List<UserBadge> _myBadges() => _store.getList('user_badges').map(UserBadge.fromJson).toList();

  static String _dayKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Award what is newly qualified, notify, and report streaks.
  Future<SyncResult> _award(UserProfile me) async {
    final days = _stepDays();
    final logs = _logs();
    final posts = _store.getList('posts').map(Post.fromJson).where((p) => p.authorId == me.id).toList();
    final have = _myBadges().map((b) => b.code).toSet();
    final want = qualifyingBadges(
      days: days,
      logs: logs,
      me: me,
      posts: posts.length,
      videoPosts: posts.where((p) => p.hasVideo).length,
      bestLeagueRank: _bestLeagueRank(),
    );
    final fresh = want.difference(have).toList()..sort();
    if (fresh.isNotEmpty) {
      final now = DateTime.now();
      await _store.put('user_badges', [..._myBadges(), for (final c in fresh) UserBadge(code: c, earnedAt: now)].map((b) => b.toJson()).toList());
      final notes = _store.getList('notifications');
      for (final c in fresh) {
        final b = badgeByCode(c)!;
        notes.insert(0, AppNotification(id: 'n_badge_$c', kind: NotificationKind.badge, createdAt: now, preview: '${b.emoji} ${b.name}: ${b.description}').toJson());
      }
      await _store.put('notifications', notes);
    }
    return SyncResult(newBadges: fresh, streaks: computeStreaks(days: days, logs: logs, me: me));
  }

  int _bestLeagueRank() {
    final results = _store.getList('league_results');
    if (results.isEmpty) return 0;
    return results.map((r) => r['rank'] as int).reduce((a, b) => a < b ? a : b);
  }

  @override
  Future<SyncResult> syncSteps(List<StepDay> days, UserProfile me) async {
    final map = {for (final d in _stepDays()) _dayKey(d.date): d.steps};
    for (final d in days) {
      map[_dayKey(d.date)] = d.steps;
    }
    final keys = map.keys.toList()..sort();
    await _store.put('step_days', [for (final k in keys) {'day': k, 'steps': map[k]}]);
    return _award(me);
  }

  @override
  Future<SyncResult> logWorkout(WorkoutLog log, UserProfile me) async {
    await _store.put('workout_logs', [..._store.getList('workout_logs'), log.toJson()]);
    return _award(me);
  }

  @override
  Future<Streaks> streaks(UserProfile me) async => computeStreaks(days: _stepDays(), logs: _logs(), me: me);

  @override
  Future<List<WorkoutLog>> recentWorkouts(UserProfile me, {int limit = 5}) async {
    final logs = _logs()..sort((a, b) => b.completedAt.compareTo(a.completedAt));
    return logs.take(limit).toList();
  }

  /// Seeded members carry a fixed shelf; mine is earned.
  static const _seedBadges = <String, List<String>>{
    'ben': ['first_workout', 'workouts_50', 'first_post', 'first_video', 'tried_10', 'early_bird'],
    'maya': ['first_workout', 'workouts_10', 'first_post', 'first_video', 'step_streak_7'],
    'lin': ['first_post', 'step_streak_30', 'week_100k', 'league_win', 'league_podium'],
    'dario': ['first_workout', 'workouts_50', 'first_post', 'tried_10'],
    'zoe': ['first_workout', 'workouts_10', 'first_post', 'league_podium'],
    'ravi': ['first_post', 'step_streak_7'],
  };

  @override
  Future<List<UserBadge>> badges(String userId) async {
    if (_seedBadges.containsKey(userId)) {
      return [for (final (i, c) in _seedBadges[userId]!.indexed) UserBadge(code: c, earnedAt: DateTime.now().subtract(Duration(days: 30 - i * 3)))];
    }
    return _myBadges();
  }

  // Two demo leagues: one I am already in, one to join by code.
  static const seedLeagueCode = 'WALK42';
  static const seedJoinCode = 'IRON77';

  Future<void> _seedLeagues(UserProfile me) async {
    if (_store.getString('leagues_seeded') == me.id) {
      await _seedNearby(me);
      return;
    }
    final walkers = League(id: 'lg_walkers', name: 'Lunch Walkers', emoji: '🥪', ownerId: 'lin', inviteCode: seedLeagueCode, memberCount: 5, createdAt: DateTime.now().subtract(const Duration(days: 20)));
    final iron = League(id: 'lg_iron', name: 'Deadlift Club', emoji: '🏋️', ownerId: 'dario', inviteCode: seedJoinCode, memberCount: 3, createdAt: DateTime.now().subtract(const Duration(days: 9)));
    await _store.put('leagues', [walkers.toJson(), iron.toJson(), ..._nearbySeed.map((l) => l.toJson())]);
    await _store.put('league_members', {
      'lg_walkers': ['lin', 'maya', 'zoe', 'ravi', me.id],
      'lg_iron': ['dario', 'ben', 'zoe'],
      'lg_park': ['lin', 'zoe', 'ravi', 'maya', 'ben', 'dario'],
      'lg_dogs': ['ravi', 'maya'],
      'lg_office': ['ben', 'dario', 'lin', 'zoe'],
      'lg_stairs': ['zoe'],
    });
    await _store.putString('leagues_seeded', me.id);
    await _store.putString('leagues_seeded_nearby', me.id);
  }

  /// Installs that existed before v0.5 already carry the seed marker; add the
  /// public leagues to them once.
  Future<void> _seedNearby(UserProfile me) async {
    if (_store.getString('leagues_seeded_nearby') == me.id) return;
    final existing = _store.getList('leagues');
    final ids = existing.map((j) => j['id']).toSet();
    final members = _members();
    const seedMembers = {
      'lg_park': ['lin', 'zoe', 'ravi', 'maya', 'ben', 'dario'],
      'lg_dogs': ['ravi', 'maya'],
      'lg_office': ['ben', 'dario', 'lin', 'zoe'],
      'lg_stairs': ['zoe'],
    };
    for (final l in _nearbySeed) {
      if (ids.contains(l.id)) continue;
      existing.add(l.toJson());
      members[l.id] = List<String>.from(seedMembers[l.id] ?? const []);
    }
    await _store.put('leagues', existing);
    await _store.put('league_members', members);
    await _store.putString('leagues_seeded_nearby', me.id);
  }

  /// Public leagues a demo user could "find nearby". Distances are fixed so
  /// the list is stable across runs.
  static final _nearbySeed = [
    League(id: 'lg_park', name: 'Park Morning Loop', emoji: '🌳', ownerId: 'lin', inviteCode: 'PARK01', area: 'Yarkon Park', distanceKm: 0.8, isPublic: true, createdAt: DateTime.now().subtract(const Duration(days: 40))),
    League(id: 'lg_dogs', name: 'Dog Walkers United', emoji: '🐕', ownerId: 'ravi', inviteCode: 'DOGS22', area: 'Florentin', distanceKm: 1.4, isPublic: true, createdAt: DateTime.now().subtract(const Duration(days: 12))),
    League(id: 'lg_office', name: 'Rothschild Lunch Club', emoji: '🏢', ownerId: 'ben', inviteCode: 'LUNCH9', area: 'Rothschild Blvd', distanceKm: 2.3, isPublic: true, createdAt: DateTime.now().subtract(const Duration(days: 30))),
    League(id: 'lg_stairs', name: 'Stairwell Society', emoji: '🪜', ownerId: 'zoe', inviteCode: 'STAIR5', area: 'Ramat Gan', distanceKm: 4.1, isPublic: true, maxMembers: 10, createdAt: DateTime.now().subtract(const Duration(days: 3))),
  ];

  @override
  Future<List<League>> nearbyLeagues(UserProfile me) async {
    await _seedLeagues(me);
    final members = _members();
    final list = _leagues().where((l) => l.isPublic && !(members[l.id] ?? const []).contains(me.id)).map((l) => _withCount(l, members)).toList()
      ..sort((a, b) => (a.distanceKm ?? 99).compareTo(b.distanceKm ?? 99));
    return list;
  }

  Map<String, List<String>> _members() => (_store.getMap('league_members') ?? {}).map((k, v) => MapEntry(k, List<String>.from(v as List)));
  List<League> _leagues() => _store.getList('leagues').map(League.fromJson).toList();

  @override
  Future<List<League>> myLeagues(UserProfile me) async {
    await _seedLeagues(me);
    final members = _members();
    return _leagues().where((l) => (members[l.id] ?? const []).contains(me.id)).map((l) => _withCount(l, members)).toList();
  }

  League _withCount(League l, Map<String, List<String>> members) => League(
        id: l.id, name: l.name, emoji: l.emoji, ownerId: l.ownerId, inviteCode: l.inviteCode,
        memberCount: (members[l.id] ?? const []).length, maxMembers: l.maxMembers, createdAt: l.createdAt,
        area: l.area, distanceKm: l.distanceKm, isPublic: l.isPublic);

  @override
  Future<League> createLeague(String name, String emoji, UserProfile me) async {
    await _seedLeagues(me);
    final rnd = Random.secure();
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final code = List.generate(6, (_) => alphabet[rnd.nextInt(alphabet.length)]).join();
    final l = League(id: newUuid(), name: name.trim(), emoji: emoji.isEmpty ? '🏆' : emoji, ownerId: me.id, inviteCode: code, memberCount: 1, createdAt: DateTime.now());
    await _store.put('leagues', [..._store.getList('leagues'), l.toJson()]);
    final members = _members()..[l.id] = [me.id];
    await _store.put('league_members', members);
    return l;
  }

  @override
  Future<League> joinLeague(String code, UserProfile me) async {
    await _seedLeagues(me);
    final l = _leagues().where((l) => l.inviteCode == code.trim().toUpperCase()).firstOrNull;
    if (l == null) throw StateError('No league with that code');
    final members = _members();
    final list = members[l.id] ?? [];
    if (list.contains(me.id)) return _withCount(l, members);
    if (list.length >= l.maxMembers) throw StateError('That league is full');
    members[l.id] = [...list, me.id];
    await _store.put('league_members', members);
    return _withCount(l, members);
  }

  @override
  Future<void> leaveLeague(String leagueId, UserProfile me) async {
    final members = _members();
    members[leagueId] = (members[leagueId] ?? []).where((id) => id != me.id).toList();
    if (members[leagueId]!.isEmpty) {
      members.remove(leagueId);
      await _store.put('leagues', _store.getList('leagues').where((j) => j['id'] != leagueId).toList());
    }
    await _store.put('league_members', members);
  }

  /// Deterministic daily steps for a seeded member.
  static int seedSteps(String userId, DateTime day) {
    final seed = userId.hashCode ^ (day.year * 400 + day.month * 31 + day.day);
    final r = Random(seed);
    final base = switch (userId) { 'lin' => 15000, 'maya' => 9000, 'zoe' => 8000, 'ravi' => 6500, 'dario' => 5500, 'ben' => 10500, _ => 7500 };
    return (base * 0.7 + r.nextInt((base * 0.6).round())).round();
  }

  @override
  Future<List<Standing>> standings(String leagueId, UserProfile me) async {
    await _seedLeagues(me);
    final members = _members()[leagueId] ?? const <String>[];
    final wk = weekStart(DateTime.now());
    final today = DateTime.now();
    final mine = {for (final d in _stepDays()) _dayKey(d.date): d.steps};
    final rows = <Standing>[];
    for (final id in members) {
      final days = <int>[];
      for (var i = 0; i < 7; i++) {
        final d = wk.add(Duration(days: i));
        if (d.isAfter(today)) {
          days.add(0);
        } else if (id == me.id) {
          days.add(mine[_dayKey(d)] ?? 0);
        } else {
          days.add(seedSteps(id, d));
        }
      }
      final u = id == me.id ? SocialUser(id: me.id, name: me.name, handle: me.handle, emoji: me.emoji, bio: '', goal: me.goal) : SeedData.users[id];
      rows.add(Standing(userId: id, name: u?.name ?? 'Member', handle: u?.handle ?? id, emoji: u?.emoji ?? '🙂', steps: days.fold(0, (n, v) => n + v), rank: 0, days: days));
    }
    rows.sort((a, b) => b.steps != a.steps ? b.steps.compareTo(a.steps) : a.handle.compareTo(b.handle));
    return [for (final (i, r) in rows.indexed) Standing(userId: r.userId, name: r.name, handle: r.handle, emoji: r.emoji, steps: r.steps, rank: i + 1, days: r.days)];
  }

  @override
  Future<List<LeagueRank>> myLeagueRanks(UserProfile me) async {
    final out = <LeagueRank>[];
    final daysLeft = 8 - DateTime.now().weekday;
    for (final l in await myLeagues(me)) {
      final s = await standings(l.id, me);
      final mine = s.where((x) => x.userId == me.id).firstOrNull;
      out.add(LeagueRank(leagueId: l.id, name: l.name, emoji: l.emoji, rank: mine?.rank ?? 0, of: s.length, steps: mine?.steps ?? 0, leaderSteps: s.firstOrNull?.steps ?? 0, daysLeft: daysLeft));
    }
    return out;
  }

  @override
  void dispose() {}
}

// ============================================================== supabase
class SupabaseSocialBackend implements SocialBackend {
  SupabaseSocialBackend(this._client, this.userId);
  final sb.SupabaseClient _client;
  final String userId;

  static const _postSelect = '*, author:profiles(*), routine:routines(*, author:profiles(name, handle)), video:videos(*)';

  @override
  bool get isRemote => true;

  final _changes = StreamController<void>.broadcast();
  sb.RealtimeChannel? _channel;

  @override
  Stream<void> get changes {
    _channel ??= _client
        .channel('sogym-feed-$userId')
        .onPostgresChanges(
          event: sb.PostgresChangeEvent.insert,
          schema: 'public',
          table: 'posts',
          callback: (_) => _changes.add(null),
        )
        .onPostgresChanges(
          event: sb.PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: sb.PostgresChangeFilter(type: sb.PostgresChangeFilterType.eq, column: 'user_id', value: userId),
          callback: (_) => _changes.add(null),
        )
        .onPostgresChanges(
          // Own uploads turning ready (or failed) after the provider webhook.
          event: sb.PostgresChangeEvent.update,
          schema: 'public',
          table: 'videos',
          filter: sb.PostgresChangeFilter(type: sb.PostgresChangeFilterType.eq, column: 'author_id', value: userId),
          callback: (_) => _changes.add(null),
        )
        .subscribe();
    return _changes.stream;
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _changes.close();
  }

  @override
  Future<SocialSnapshot> load(UserProfile me) async {
    final results = await Future.wait([
      _client.from('posts').select(_postSelect).order('created_at', ascending: false).limit(100),
      _client.from('likes').select('post_id').eq('user_id', userId),
      _client.from('recommends').select('post_id').eq('user_id', userId),
      _client.from('follows').select('followee_id').eq('follower_id', userId),
      _client.from('notifications').select().eq('user_id', userId).order('created_at', ascending: false).limit(50),
    ]);
    final rows = results[0];
    final users = <String, SocialUser>{};
    final posts = <Post>[];
    for (final row in rows) {
      final author = row['author'];
      if (author is Map) {
        final u = userFromRow(Map<String, dynamic>.from(author));
        users[u.id] = u;
      }
      posts.add(postFromRow(row));
    }
    // Actors in notifications may not have posted; fetch the missing ones.
    final notes = results[4].map(notificationFromRow).toList();
    final missing = notes.map((n) => n.actorId).whereType<String>().where((id) => !users.containsKey(id)).toSet();
    if (missing.isNotEmpty) {
      final extra = await _client.from('profiles').select().inFilter('id', missing.toList());
      for (final row in extra) {
        final u = userFromRow(row);
        users[u.id] = u;
      }
    }
    return SocialSnapshot(
      posts: posts,
      users: users,
      liked: results[1].map((r) => r['post_id'] as String).toSet(),
      recommended: results[2].map((r) => r['post_id'] as String).toSet(),
      following: results[3].map((r) => r['followee_id'] as String).toSet(),
      notifications: notes,
    );
  }

  @override
  Future<void> setLike(String postId, bool on) async {
    if (on) {
      await _client.from('likes').upsert({'post_id': postId, 'user_id': userId});
    } else {
      await _client.from('likes').delete().eq('post_id', postId).eq('user_id', userId);
    }
  }

  @override
  Future<void> recommend(String postId) =>
      _client.from('recommends').upsert({'post_id': postId, 'user_id': userId});

  @override
  Future<void> setFollow(String otherId, bool on) async {
    if (on) {
      await _client.from('follows').upsert({'follower_id': userId, 'followee_id': otherId});
    } else {
      await _client.from('follows').delete().eq('follower_id', userId).eq('followee_id', otherId);
    }
  }

  @override
  Future<Post> publish(Post post) async {
    // A routine attached to a post must exist server-side first.
    if (post.routine != null) await saveRoutine(post.routine!);
    final row = await _client
        .from('posts')
        .insert({
          'author_id': userId,
          'kind': post.kind.name,
          'title': post.title,
          'body': post.body,
          'routine_id': post.routine?.id,
          'video_url': post.videoUrl,
          'video_id': post.video?.id,
          'steps': post.steps,
          'hot': post.hot,
          'tags': post.tags,
        })
        .select(_postSelect)
        .single();
    return postFromRow(row);
  }

  @override
  Future<List<Comment>> comments(String postId) async {
    final rows = await _client.from('comments').select().eq('post_id', postId).order('created_at', ascending: true);
    return rows.map(commentFromRow).toList();
  }

  @override
  Future<Comment> addComment(String postId, String body, UserProfile me) async {
    final row = await _client
        .from('comments')
        .insert({'post_id': postId, 'author_id': userId, 'body': body.trim()})
        .select()
        .single();
    return commentFromRow(row);
  }

  @override
  Future<void> recordTry(Routine original, Routine copy) async {
    if (!isUuid(original.id)) return; // seeded community routine, nothing to record
    await saveRoutine(copy, forkedFrom: original.id);
    await _client.from('routine_tries').upsert({'routine_id': original.id, 'user_id': userId});
  }

  @override
  Future<List<AppNotification>> notifications() async {
    final rows = await _client.from('notifications').select().eq('user_id', userId).order('created_at', ascending: false).limit(50);
    return rows.map(notificationFromRow).toList();
  }

  @override
  Future<void> markAllRead() =>
      _client.from('notifications').update({'read': true}).eq('user_id', userId).eq('read', false);

  @override
  Future<void> syncProfile(UserProfile me) =>
      _client.from('profiles').update(profileToRow(me)).eq('id', userId);

  @override
  Future<({UserProfile profile, bool complete})?> fetchProfile(String id) async {
    final row = await _client.from('profiles').select().eq('id', id).maybeSingle();
    return row == null ? null : (profile: profileFromRow(row), complete: profileRowIsComplete(row));
  }

  @override
  Future<List<Routine>> myRoutines(String uid) async {
    final rows = await _client
        .from('routines')
        .select('*, author:profiles(name, handle)')
        .eq('author_id', uid)
        .order('created_at', ascending: false);
    return rows.map(routineFromRow).toList();
  }

  @override
  Future<void> saveRoutine(Routine r, {String? forkedFrom}) async {
    await _client.from('routines').upsert({
      'id': isUuid(r.id) ? r.id : newUuid(),
      'author_id': userId,
      'name': r.name,
      'description': r.description,
      'days': r.days.map((d) => d.toJson()).toList(),
      'tags': r.tags,
      'source': r.source == 'ai' ? 'ai' : 'me',
      'forked_from': ?forkedFrom,
    });
  }

  @override
  Future<void> deleteRoutine(String id) async {
    if (!isUuid(id)) return;
    await _client.from('routines').delete().eq('id', id).eq('author_id', userId);
  }

  // ----------------------------------------------------------- v0.3
  @override
  Future<void> deletePost(String id) => _client.from('posts').delete().eq('id', id).eq('author_id', userId);

  @override
  Future<Video?> video(String id) async {
    final row = await _client.from('videos').select().eq('id', id).maybeSingle();
    return row == null ? null : videoFromRow(row);
  }

  @override
  Future<void> recordView(String postId) => _client.rpc('record_view', params: {'p_post': postId});

  @override
  Future<List<Post>> postsBy(String uid, {required String viewerId}) async {
    final rows = await _client.from('posts').select(_postSelect).eq('author_id', uid).order('created_at', ascending: false).limit(100);
    return rows.map(postFromRow).toList();
  }

  @override
  Future<SocialUser?> user(String id) async {
    final row = await _client.from('profiles').select().eq('id', id).maybeSingle();
    return row == null ? null : userFromRow(row);
  }

  @override
  Future<bool> report({required ReportTarget target, required String targetId, required ReportReason reason, String details = '', required UserProfile me}) async {
    if (!isUuid(targetId)) return false; // seeded content has no server row
    try {
      await _client.from('reports').insert({
        'reporter_id': userId,
        'target_kind': target.name,
        'target_id': targetId,
        'reason': reason.wire,
        'details': details.trim(),
      });
      return true;
    } on sb.PostgrestException catch (e) {
      if (e.code == '23505') return false; // already reported
      rethrow;
    }
  }

  @override
  Future<List<Report>> openReports() async {
    final rows = await _client.from('reports').select().eq('status', 'open').order('created_at', ascending: true).limit(100);
    final reports = rows.map(reportFromRow).toList();
    final postIds = reports.where((r) => r.target == ReportTarget.post).map((r) => r.targetId).toSet().toList();
    final commentIds = reports.where((r) => r.target == ReportTarget.comment).map((r) => r.targetId).toSet().toList();
    final profileIds = reports.where((r) => r.target == ReportTarget.profile).map((r) => r.targetId).toSet().toList();
    final posts = <String, Map<String, dynamic>>{};
    final comments = <String, Map<String, dynamic>>{};
    final profiles = <String, Map<String, dynamic>>{};
    if (postIds.isNotEmpty) {
      for (final r in await _client.from('posts').select('id, title, author_id, hidden').inFilter('id', postIds)) {
        posts[r['id'] as String] = r;
      }
    }
    if (commentIds.isNotEmpty) {
      for (final r in await _client.from('comments').select('id, body, author_id').inFilter('id', commentIds)) {
        comments[r['id'] as String] = r;
      }
    }
    if (profileIds.isNotEmpty) {
      for (final r in await _client.from('profiles').select('id, handle').inFilter('id', profileIds)) {
        profiles[r['id'] as String] = r;
      }
    }
    return reports.map((r) {
      switch (r.target) {
        case ReportTarget.post:
          final p = posts[r.targetId];
          return r.copyWith(targetTitle: (p?['title'] ?? '(deleted post)') as String, targetAuthorId: p?['author_id'] as String?, targetHidden: (p?['hidden'] ?? false) as bool);
        case ReportTarget.comment:
          final c = comments[r.targetId];
          return r.copyWith(targetTitle: (c?['body'] ?? '(deleted comment)') as String, targetAuthorId: c?['author_id'] as String?);
        case ReportTarget.profile:
          return r.copyWith(targetTitle: '@${profiles[r.targetId]?['handle'] ?? r.targetId}', targetAuthorId: r.targetId);
      }
    }).toList();
  }

  @override
  Future<void> moderate(Report report, ModerationAction action, {String note = ''}) =>
      _client.rpc('moderate', params: {'p_report': report.id, 'p_action': action.name, 'p_note': note});

  @override
  Future<CreatorStats> creatorStats(String uid) async {
    final data = await _client.rpc('creator_stats', params: {'p_user': uid});
    return CreatorStats.fromJson(Map<String, dynamic>.from(data as Map));
  }

  @override
  Future<CreatorStatus> creatorStatus(String uid) async {
    final row = await _client.from('creator_applications').select('status').eq('user_id', uid).maybeSingle();
    if (row == null) return CreatorStatus.none;
    return CreatorStatus.values.firstWhere((s) => s.name == row['status'], orElse: () => CreatorStatus.pending);
  }

  @override
  Future<void> applyAsCreator(String statement, UserProfile me) =>
      _client.from('creator_applications').upsert({'user_id': userId, 'statement': statement.trim(), 'status': 'pending'});

  // ----------------------------------------------------------- v0.4
  static SyncResult _syncResult(dynamic data) {
    final j = Map<String, dynamic>.from(data as Map);
    return SyncResult(
      newBadges: List<String>.from(j['badges'] ?? const []),
      streaks: Streaks.fromJson(Map<String, dynamic>.from(j['streaks'] as Map? ?? const {})),
    );
  }

  @override
  Future<SyncResult> syncSteps(List<StepDay> days, UserProfile me) async {
    final payload = [
      for (final d in days) {'day': '${d.date.year.toString().padLeft(4, '0')}-${d.date.month.toString().padLeft(2, '0')}-${d.date.day.toString().padLeft(2, '0')}', 'steps': d.steps, 'source': 'health'}
    ];
    return _syncResult(await _client.rpc('sync_steps', params: {'p_days': payload}));
  }

  @override
  Future<SyncResult> logWorkout(WorkoutLog log, UserProfile me) async => _syncResult(await _client.rpc('log_workout', params: {
        'p_routine': log.routineId != null && isUuid(log.routineId!) ? log.routineId : null,
        'p_routine_name': log.routineName,
        'p_day_title': log.dayTitle,
        'p_duration_sec': log.durationSec,
        'p_sets': log.sets,
      }));

  @override
  Future<Streaks> streaks(UserProfile me) async => Streaks.fromJson(Map<String, dynamic>.from(await _client.rpc('my_streaks') as Map));

  @override
  Future<List<WorkoutLog>> recentWorkouts(UserProfile me, {int limit = 5}) async {
    final rows = await _client
        .from('workout_logs')
        .select('id, routine_id, routine_name, day_title, duration_sec, sets, completed_at')
        .eq('user_id', userId)
        .order('completed_at', ascending: false)
        .limit(limit);
    return rows
        .map((r) => WorkoutLog(
              id: r['id'] as String,
              userId: userId,
              routineId: r['routine_id'] as String?,
              routineName: (r['routine_name'] ?? '') as String,
              dayTitle: (r['day_title'] ?? '') as String,
              durationSec: (r['duration_sec'] as num?)?.toInt() ?? 0,
              sets: (r['sets'] as num?)?.toInt() ?? 0,
              completedAt: DateTime.tryParse(r['completed_at'] ?? '') ?? DateTime.now(),
            ))
        .toList();
  }

  @override
  Future<List<UserBadge>> badges(String uid) async {
    final rows = await _client.from('user_badges').select('badge, earned_at').eq('user_id', uid).order('earned_at', ascending: false);
    return rows.map((r) => UserBadge(code: r['badge'] as String, earnedAt: DateTime.tryParse(r['earned_at'] ?? '') ?? DateTime.now())).toList();
  }

  static const _leagueSelect = '*, members:league_members(count)';

  @override
  Future<List<League>> myLeagues(UserProfile me) async {
    final rows = await _client.from('leagues').select(_leagueSelect).order('created_at', ascending: false);
    return rows.map(leagueFromRow).toList();
  }

  Future<League> _league(String id) async => leagueFromRow(await _client.from('leagues').select(_leagueSelect).eq('id', id).single());

  @override
  Future<League> createLeague(String name, String emoji, UserProfile me) async =>
      _league(await _client.rpc('create_league', params: {'p_name': name.trim(), 'p_emoji': emoji}) as String);

  @override
  Future<League> joinLeague(String code, UserProfile me) async =>
      _league(await _client.rpc('join_league', params: {'p_code': code.trim()}) as String);

  @override
  Future<void> leaveLeague(String leagueId, UserProfile me) => _client.rpc('leave_league', params: {'p_league': leagueId});

  @override
  Future<List<League>> nearbyLeagues(UserProfile me) async {
    // Server ranks by member count; distance needs the user's coarse location,
    // which the app does not collect yet (see migration 0004 notes).
    final data = await _client.rpc('nearby_leagues') as List;
    return data.map((e) => leagueFromRow(Map<String, dynamic>.from(e as Map))).toList();
  }

  @override
  Future<List<Standing>> standings(String leagueId, UserProfile me) async {
    final data = await _client.rpc('league_standings', params: {'p_league': leagueId}) as List;
    return data.map((e) => Standing.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  @override
  Future<List<LeagueRank>> myLeagueRanks(UserProfile me) async {
    final data = await _client.rpc('my_league_ranks') as List;
    return data.map((e) => LeagueRank.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }
}

League leagueFromRow(Map<String, dynamic> r) {
  final members = r['members'];
  final count = members is List && members.isNotEmpty ? ((members.first as Map)['count'] as num?)?.toInt() ?? 0 : (r['member_count'] as num?)?.toInt() ?? 0;
  return League(
    id: r['id'] as String,
    name: (r['name'] ?? 'League') as String,
    emoji: (r['emoji'] ?? '🏆') as String,
    ownerId: (r['owner_id'] ?? '') as String,
    inviteCode: (r['invite_code'] ?? '') as String,
    memberCount: count,
    maxMembers: (r['max_members'] as num?)?.toInt() ?? 20,
    createdAt: DateTime.tryParse(r['created_at'] ?? ''),
    area: (r['area'] ?? '') as String,
    distanceKm: (r['distance_km'] as num?)?.toDouble(),
    isPublic: (r['is_public'] ?? false) as bool,
  );
}

// ---------------------------------------------------------------- mapping
// Row shapes come from supabase/migrations/*.sql. Kept here so models.dart
// stays free of backend knowledge.

SocialUser userFromRow(Map<String, dynamic> r) => SocialUser(
      id: r['id'] as String,
      name: (r['name'] ?? 'Athlete') as String,
      handle: (r['handle'] ?? 'athlete') as String,
      emoji: (r['emoji'] ?? '🙂') as String,
      bio: (r['bio'] ?? '') as String,
      goal: Goal.values.firstWhere((g) => g.name == r['goal'], orElse: () => Goal.generalHealth),
      diet: List<String>.from(r['diet'] ?? const []),
      creator: (r['creator'] ?? false) as bool,
      followers: (r['follower_count'] as num?)?.toInt() ?? 0,
    );

UserProfile profileFromRow(Map<String, dynamic> r) => UserProfile(
      id: r['id'] as String,
      name: (r['name'] ?? 'Athlete') as String,
      handle: (r['handle'] ?? 'athlete') as String,
      emoji: (r['emoji'] ?? '🙂') as String,
      heightCm: (r['height_cm'] as num?)?.toDouble() ?? 170,
      weightKg: (r['weight_kg'] as num?)?.toDouble() ?? 70,
      age: (r['age'] as num?)?.toInt() ?? 30,
      goal: Goal.values.firstWhere((g) => g.name == r['goal'], orElse: () => Goal.generalHealth),
      diet: List<String>.from(r['diet'] ?? const []),
      equipment: List<String>.from(r['equipment'] ?? const []),
      daysPerWeek: (r['days_per_week'] as num?)?.toInt() ?? 3,
      bio: (r['bio'] ?? '') as String,
      stepGoal: (r['step_goal'] as num?)?.toInt() ?? 8000,
      targetWeightKg: (r['target_weight_kg'] as num?)?.toDouble(),
      creator: (r['creator'] ?? false) as bool,
      moderator: (r['moderator'] ?? false) as bool,
    );

/// True when a hosted profile has been filled in beyond the trigger defaults.
bool profileRowIsComplete(Map<String, dynamic> r) => r['height_cm'] != null && r['weight_kg'] != null;

Map<String, dynamic> profileToRow(UserProfile p) => {
      'name': p.name,
      'handle': p.handle.toLowerCase(),
      'emoji': p.emoji,
      'bio': p.bio,
      'goal': p.goal.name,
      'diet': p.diet,
      'equipment': p.equipment,
      'height_cm': p.heightCm,
      'weight_kg': p.weightKg,
      'target_weight_kg': p.targetWeightKg,
      'age': p.age,
      'days_per_week': p.daysPerWeek,
      'step_goal': p.stepGoal,
    };

Routine routineFromRow(Map<String, dynamic> r) {
  final author = r['author'];
  final authorName = author is Map ? (author['name'] ?? 'Athlete') as String : 'Athlete';
  return Routine(
    id: r['id'] as String,
    name: r['name'] as String,
    description: (r['description'] ?? '') as String,
    authorId: r['author_id'] as String,
    authorName: authorName,
    days: (r['days'] as List? ?? const []).map((d) => RoutineDay.fromJson(Map<String, dynamic>.from(d as Map))).toList(),
    createdAt: DateTime.tryParse(r['created_at'] ?? '') ?? DateTime.now(),
    tags: List<String>.from(r['tags'] ?? const []),
    source: (r['source'] ?? 'community') as String,
  );
}

Video videoFromRow(Map<String, dynamic> r) => Video(
      id: r['id'] as String,
      authorId: (r['author_id'] ?? '') as String,
      status: VideoStatus.values.firstWhere((s) => s.name == r['status'], orElse: () => VideoStatus.processing),
      playbackUrl: r['playback_url'] as String?,
      thumbnailUrl: r['thumbnail_url'] as String?,
      durationSec: (r['duration_sec'] as num?)?.toDouble(),
      width: (r['width'] as num?)?.toInt(),
      height: (r['height'] as num?)?.toInt(),
      exerciseIds: List<String>.from(r['exercise_ids'] ?? const []),
      views: (r['view_count'] as num?)?.toInt() ?? 0,
      error: r['error'] as String?,
    );

Report reportFromRow(Map<String, dynamic> r) => Report(
      id: r['id'] as String,
      reporterId: r['reporter_id'] as String?,
      target: ReportTarget.values.firstWhere((t) => t.name == r['target_kind'], orElse: () => ReportTarget.post),
      targetId: r['target_id'] as String,
      reason: ReportReason.fromWire(r['reason'] as String?),
      details: (r['details'] ?? '') as String,
      status: ReportStatus.values.firstWhere((s) => s.name == r['status'], orElse: () => ReportStatus.open),
      action: ModerationAction.values.where((a) => a.name == r['action']).firstOrNull,
      createdAt: DateTime.tryParse(r['created_at'] ?? '') ?? DateTime.now(),
    );

Post postFromRow(Map<String, dynamic> r) {
  final routine = r['routine'];
  final video = r['video'];
  return Post(
    id: r['id'] as String,
    authorId: r['author_id'] as String,
    kind: PostKind.values.firstWhere((k) => k.name == r['kind'], orElse: () => PostKind.workout),
    title: r['title'] as String,
    body: (r['body'] ?? '') as String,
    createdAt: DateTime.tryParse(r['created_at'] ?? '') ?? DateTime.now(),
    likes: (r['like_count'] as num?)?.toInt() ?? 0,
    recommends: (r['recommend_count'] as num?)?.toInt() ?? 0,
    comments: (r['comment_count'] as num?)?.toInt() ?? 0,
    tags: List<String>.from(r['tags'] ?? const []),
    routine: routine is Map ? routineFromRow(Map<String, dynamic>.from(routine)) : null,
    videoUrl: r['video_url'] as String?,
    video: video is Map ? videoFromRow(Map<String, dynamic>.from(video)) : null,
    steps: (r['steps'] as num?)?.toInt(),
    hot: (r['hot'] ?? false) as bool,
    hidden: (r['hidden'] ?? false) as bool,
    views: (r['view_count'] as num?)?.toInt() ?? 0,
  );
}

Comment commentFromRow(Map<String, dynamic> r) => Comment(
      id: r['id'] as String,
      postId: r['post_id'] as String,
      authorId: r['author_id'] as String,
      body: (r['body'] ?? '') as String,
      createdAt: DateTime.tryParse(r['created_at'] ?? '') ?? DateTime.now(),
    );

AppNotification notificationFromRow(Map<String, dynamic> r) => AppNotification(
      id: r['id'] as String,
      kind: AppNotification.kindFromWire(r['kind'] as String?),
      createdAt: DateTime.tryParse(r['created_at'] ?? '') ?? DateTime.now(),
      actorId: r['actor_id'] as String?,
      postId: r['post_id'] as String?,
      routineId: r['routine_id'] as String?,
      preview: (r['preview'] ?? '') as String,
      read: (r['read'] ?? false) as bool,
    );

final _uuidRe = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false);
bool isUuid(String s) => _uuidRe.hasMatch(s);

/// RFC 4122 v4 id so client-created rows keep the same id locally and hosted.
String newUuid() {
  final rnd = Random.secure();
  final b = List<int>.generate(16, (_) => rnd.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
