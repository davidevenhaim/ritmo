import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'ai_coach.dart';
import 'backend.dart';
import 'exercise_repository.dart';
import 'health_service.dart';
import 'local_store.dart';
import 'models.dart';
import 'recommender.dart';
import 'remote_coach.dart';
import 'social_backend.dart';
import 'social_repository.dart';
import 'video_service.dart';

final storeProvider = Provider<LocalStore>((ref) => throw UnimplementedError('override in main'));

final exerciseRepoProvider = FutureProvider<ExerciseRepository>((ref) => ExerciseRepository.load());

final wgerClientProvider = Provider<WgerClient>((ref) => WgerClient());

// ------------------------------------------------------------------ auth
/// Signed-in hosted user, or null (no backend configured, or signed out).
class AuthNotifier extends Notifier<AuthUser?> {
  @override
  AuthUser? build() {
    final sub = authChanges().listen((user) {
      final before = state?.id;
      state = user;
      if (user != null && user.id != before) {
        // First time we see this account on this device: merge profiles.
        unawaited(ref.read(profileProvider.notifier).adopt(user));
      }
    });
    ref.onDispose(sub.cancel);
    return currentAuthUser();
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthUser?>(AuthNotifier.new);

/// Local seed community, or the hosted graph once signed in.
final socialBackendProvider = Provider<SocialBackend>((ref) {
  final auth = ref.watch(authProvider);
  final SocialBackend backend = BackendConfig.enabled && auth != null
      ? SupabaseSocialBackend(supabase, auth.id)
      : LocalSocialBackend(ref.watch(storeProvider));
  ref.onDispose(backend.dispose);
  return backend;
});

// ---------------------------------------------------------------- profile
class ProfileNotifier extends Notifier<UserProfile?> {
  @override
  UserProfile? build() {
    final j = ref.read(storeProvider).getMap('profile');
    return j == null ? null : UserProfile.fromJson(j);
  }

  Future<void> save(UserProfile p) async {
    state = p;
    await ref.read(storeProvider).put('profile', p.toJson());
    final backend = ref.read(socialBackendProvider);
    if (backend.isRemote && p.id == ref.read(authProvider)?.id) {
      try {
        await backend.syncProfile(p);
      } catch (e) {
        debugPrint('profile sync failed: $e');
      }
    }
  }

  /// Called once per sign-in. A completed hosted profile wins; otherwise the
  /// local onboarding profile is uploaded under the account's id.
  Future<void> adopt(AuthUser user) async {
    final backend = ref.read(socialBackendProvider);
    if (!backend.isRemote) return;
    final local = state;
    if (local?.id == user.id) return;
    try {
      final remote = await backend.fetchProfile(user.id);
      UserProfile next;
      if (remote != null && remote.complete) {
        next = remote.profile;
      } else if (local != null) {
        next = local.copyWith(id: user.id);
        try {
          await backend.syncProfile(next);
        } catch (_) {
          // Most likely a handle collision: keep the server-assigned handle.
          next = next.copyWith(handle: remote?.profile.handle ?? next.handle);
          await backend.syncProfile(next);
        }
      } else if (remote != null) {
        next = remote.profile;
      } else {
        return;
      }
      state = next;
      await ref.read(storeProvider).put('profile', next.toJson());
      if (local != null) await ref.read(routinesProvider.notifier).rekeyAuthor(local.id, next);
      ref.invalidate(socialProvider);
    } catch (e) {
      debugPrint('profile adopt failed: $e');
    }
  }

  /// Trust flags come from the server (or the demo's instant approval);
  /// they are stored with the profile but never uploaded from here.
  Future<void> setFlags({bool? creator, bool? moderator}) async {
    final p = state;
    if (p == null) return;
    if ((creator ?? p.creator) == p.creator && (moderator ?? p.moderator) == p.moderator) return;
    state = p.copyWith(creator: creator, moderator: moderator);
    await ref.read(storeProvider).put('profile', state!.toJson());
  }

  /// Profile picture, stored on-device as base64 (v0.5). Pass null to go
  /// back to the emoji. Not uploaded: the hosted profile keeps the emoji.
  Future<void> setPhoto(String? base64) async {
    final p = state;
    if (p == null) return;
    state = p.copyWith(photo: base64);
    await ref.read(storeProvider).put('profile', state!.toJson());
  }

  Future<void> reset() async {
    await ref.read(storeProvider).clear();
    await signOut();
    state = null;
  }
}

final profileProvider = NotifierProvider<ProfileNotifier, UserProfile?>(ProfileNotifier.new);

// --------------------------------------------------------------- settings
class Settings {
  const Settings({this.apiKey = '', this.model = 'claude-opus-5'});
  final String apiKey;
  final String model;
  bool get hasKey => apiKey.trim().isNotEmpty;
}

class SettingsNotifier extends Notifier<Settings> {
  @override
  Settings build() {
    final s = ref.read(storeProvider);
    return Settings(apiKey: s.getString('apiKey') ?? '', model: s.getString('model') ?? 'claude-opus-5');
  }

  Future<void> setApiKey(String key) async {
    state = Settings(apiKey: key.trim(), model: state.model);
    await ref.read(storeProvider).putString('apiKey', key.trim());
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, Settings>(SettingsNotifier.new);

// --------------------------------------------------------------- routines
class RoutinesNotifier extends Notifier<List<Routine>> {
  @override
  List<Routine> build() {
    final local = ref.read(storeProvider).getList('routines').map(Routine.fromJson).toList();
    final backend = ref.watch(socialBackendProvider);
    if (backend.isRemote) unawaited(_pull(backend, local));
    return local;
  }

  /// Merge the hosted library with what is on this device. Legacy local ids
  /// get a UUID and are uploaded so every routine exists in both places.
  Future<void> _pull(SocialBackend backend, List<Routine> local) async {
    final uid = ref.read(authProvider)?.id;
    if (uid == null) return;
    try {
      final remote = await backend.myRoutines(uid);
      final remoteIds = remote.map((r) => r.id).toSet();
      final merged = [...remote];
      for (final r in local) {
        if (remoteIds.contains(r.id)) continue;
        final upload = isUuid(r.id) ? r : r.copyWith(id: newUuid());
        merged.add(upload);
        await backend.saveRoutine(upload);
      }
      merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      state = merged;
      await _persist();
    } catch (e) {
      debugPrint('routine pull failed: $e');
    }
  }

  Future<void> _persist() =>
      ref.read(storeProvider).put('routines', state.map((r) => r.toJson()).toList());

  Future<Routine> upsert(Routine r) async {
    final backend = ref.read(socialBackendProvider);
    if (backend.isRemote && !isUuid(r.id)) r = r.copyWith(id: newUuid());
    final i = state.indexWhere((x) => x.id == r.id);
    state = i < 0 ? [r, ...state] : [...state]..[i < 0 ? 0 : i] = r;
    await _persist();
    if (backend.isRemote) {
      try {
        await backend.saveRoutine(r);
      } catch (e) {
        debugPrint('routine save failed: $e');
      }
    }
    return r;
  }

  Future<void> remove(String id) async {
    state = state.where((r) => r.id != id).toList();
    await _persist();
    try {
      await ref.read(socialBackendProvider).deleteRoutine(id);
    } catch (e) {
      debugPrint('routine delete failed: $e');
    }
  }

  /// "Try it": copy a community routine into my routines and tell the author.
  Future<Routine> clone(Routine r, UserProfile me) async {
    final social = ref.read(socialProvider);
    final handle = social.users[r.authorId]?.handle ?? r.authorName;
    final copy = r.copyWith(
      id: newUuid(),
      authorId: me.id,
      authorName: me.name,
      source: 'me',
      tags: [...r.tags, 'from @$handle'],
    );
    await upsert(copy);
    try {
      await ref.read(socialBackendProvider).recordTry(r, copy);
    } catch (e) {
      debugPrint('record try failed: $e');
    }
    return copy;
  }

  /// After sign-in the local profile id changes; keep routine ownership intact.
  Future<void> rekeyAuthor(String oldId, UserProfile me) async {
    state = state.map((r) => r.authorId == oldId ? r.copyWith(authorId: me.id, authorName: me.name) : r).toList();
    await _persist();
  }

  Routine? byId(String id) => state.where((r) => r.id == id).firstOrNull;
}

final routinesProvider = NotifierProvider<RoutinesNotifier, List<Routine>>(RoutinesNotifier.new);

// ------------------------------------------------------------------- social
class SocialState {
  const SocialState({
    this.posts = const [],
    this.users = const {},
    this.liked = const {},
    this.recommended = const {},
    this.following = const {},
    this.notifications = const [],
    this.comments = const {},
    this.reports = const [],
    this.loading = false,
    this.error,
  });
  final List<Post> posts;
  final Map<String, SocialUser> users;
  final Set<String> liked;
  final Set<String> recommended;
  final Set<String> following;
  final List<AppNotification> notifications;

  /// Loaded comment threads by post id.
  final Map<String, List<Comment>> comments;

  /// Open moderation queue (v0.3), loaded on demand.
  final List<Report> reports;
  final bool loading;
  final String? error;

  int get unread => notifications.where((n) => !n.read).length;

  SocialState copyWith({
    List<Post>? posts,
    Map<String, SocialUser>? users,
    Set<String>? liked,
    Set<String>? recommended,
    Set<String>? following,
    List<AppNotification>? notifications,
    Map<String, List<Comment>>? comments,
    List<Report>? reports,
    bool? loading,
    String? error,
  }) =>
      SocialState(
        posts: posts ?? this.posts,
        users: users ?? this.users,
        liked: liked ?? this.liked,
        recommended: recommended ?? this.recommended,
        following: following ?? this.following,
        notifications: notifications ?? this.notifications,
        comments: comments ?? this.comments,
        reports: reports ?? this.reports,
        loading: loading ?? this.loading,
        error: error,
      );
}

class SocialNotifier extends Notifier<SocialState> {
  SocialBackend get _backend => ref.read(socialBackendProvider);

  @override
  SocialState build() {
    final backend = ref.watch(socialBackendProvider);
    var alive = true;
    ref.onDispose(() => alive = false);
    final sub = backend.changes.listen((_) {
      if (alive) unawaited(refresh());
    });
    ref.onDispose(sub.cancel);
    unawaited(refresh(initial: true));
    return const SocialState(loading: true);
  }

  Future<void> refresh({bool initial = false}) async {
    final me = ref.read(profileProvider);
    if (me == null) {
      state = const SocialState();
      return;
    }
    try {
      final snap = await _backend.load(me);
      if (!ref.mounted) return;
      if (_backend.isRemote) {
        final remote = await _backend.fetchProfile(me.id);
        if (!ref.mounted) return;
        if (remote != null) {
          unawaited(ref.read(profileProvider.notifier).setFlags(creator: remote.profile.creator, moderator: remote.profile.moderator));
        }
      }
      state = state.copyWith(
        posts: snap.posts,
        users: {...snap.users, me.id: _meAsUser(me)},
        liked: snap.liked,
        recommended: snap.recommended,
        following: snap.following,
        notifications: snap.notifications,
        loading: false,
      );
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, error: 'Could not load the feed: $e');
    }
  }

  SocialUser _meAsUser(UserProfile me) =>
      SocialUser(id: me.id, name: me.name, handle: me.handle, emoji: me.emoji, bio: me.bio, goal: me.goal, diet: me.diet, creator: me.creator);

  /// Who wrote something: me, a loaded member, or a placeholder.
  SocialUser userOf(String id) {
    final me = ref.read(profileProvider);
    if (me != null && id == me.id) return _meAsUser(me);
    return state.users[id] ?? SocialUser(id: id, name: 'Member', handle: id.length > 8 ? id.substring(0, 8) : id, emoji: '🙂', bio: '', goal: Goal.generalHealth);
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      debugPrint('social action failed: $e');
      await refresh();
    }
  }

  Future<void> toggleLike(String postId) async {
    final on = !state.liked.contains(postId);
    final liked = {...state.liked};
    on ? liked.add(postId) : liked.remove(postId);
    state = state.copyWith(
      liked: liked,
      posts: state.posts.map((p) => p.id == postId ? p.copyWith(likes: p.likes + (on ? 1 : -1)) : p).toList(),
    );
    await _guard(() => _backend.setLike(postId, on));
  }

  Future<void> recommend(String postId) async {
    if (state.recommended.contains(postId)) return;
    state = state.copyWith(
      recommended: {...state.recommended, postId},
      posts: state.posts.map((p) => p.id == postId ? p.copyWith(recommends: p.recommends + 1) : p).toList(),
    );
    await _guard(() => _backend.recommend(postId));
  }

  Future<void> toggleFollow(String userId) async {
    final on = !state.following.contains(userId);
    final f = {...state.following};
    on ? f.add(userId) : f.remove(userId);
    state = state.copyWith(following: f);
    await _guard(() => _backend.setFollow(userId, on));
  }

  Future<void> publish(Post post) async {
    state = state.copyWith(posts: [post, ...state.posts]);
    await _guard(() async {
      final stored = await _backend.publish(post);
      state = state.copyWith(posts: state.posts.map((p) => p.id == post.id ? stored : p).toList());
    });
    // The demo has no webhook: poll once after the pretend transcode.
    if (post.video != null && !_backend.isRemote) {
      Future<void>.delayed(const Duration(seconds: 7), () => refreshVideo(post.video!.id));
    }
  }

  // ------------------------------------------------------------- v0.3
  Future<void> deletePost(String id) async {
    state = state.copyWith(posts: state.posts.where((p) => p.id != id).toList());
    await _guard(() => _backend.deletePost(id));
  }

  /// Re-read one clip and patch it into the feed (ready / failed).
  Future<void> refreshVideo(String videoId) async {
    try {
      final v = await _backend.video(videoId);
      if (v == null) return;
      state = state.copyWith(posts: state.posts.map((p) => p.video?.id == videoId ? p.copyWith(video: v) : p).toList());
    } catch (e) {
      debugPrint('video refresh failed: $e');
    }
  }

  final _viewed = <String>{};
  void recordView(String postId) {
    if (!_viewed.add(postId)) return;
    unawaited(_backend.recordView(postId).catchError((e) => debugPrint('view failed: $e')));
  }

  Future<bool> report({required ReportTarget target, required String targetId, required ReportReason reason, String details = ''}) async {
    final me = ref.read(profileProvider);
    if (me == null) return false;
    try {
      return await _backend.report(target: target, targetId: targetId, reason: reason, details: details, me: me);
    } catch (e) {
      debugPrint('report failed: $e');
      return false;
    }
  }

  Future<void> loadReports() async {
    try {
      state = state.copyWith(reports: await _backend.openReports());
    } catch (e) {
      state = state.copyWith(error: 'Could not load the queue: $e');
    }
  }

  Future<void> moderate(Report report, ModerationAction action, {String note = ''}) async {
    state = state.copyWith(reports: state.reports.where((r) => !(r.target == report.target && r.targetId == report.targetId)).toList());
    await _guard(() => _backend.moderate(report, action, note: note));
    await refresh();
  }

  Future<List<Post>> postsBy(String userId) async {
    final me = ref.read(profileProvider);
    final posts = await _backend.postsBy(userId, viewerId: me?.id ?? '');
    final known = {...state.users};
    if (!known.containsKey(userId)) {
      final u = await _backend.user(userId);
      if (u != null) state = state.copyWith(users: {...state.users, u.id: u});
    }
    return posts;
  }

  Future<SocialUser> loadUser(String id) async {
    final cached = state.users[id];
    if (cached != null) return cached;
    final u = await _backend.user(id);
    if (u != null) state = state.copyWith(users: {...state.users, u.id: u});
    return u ?? userOf(id);
  }

  Future<CreatorStats> creatorStats(String userId) => _backend.creatorStats(userId);

  Future<void> applyAsCreator(String statement) async {
    final me = ref.read(profileProvider);
    if (me == null) return;
    await _backend.applyAsCreator(statement, me);
    ref.invalidate(creatorStatusProvider);
    if (!_backend.isRemote) await ref.read(profileProvider.notifier).setFlags(creator: true);
  }

  Future<void> loadComments(String postId) async {
    try {
      final list = await _backend.comments(postId);
      state = state.copyWith(comments: {...state.comments, postId: list});
    } catch (e) {
      debugPrint('comments load failed: $e');
    }
  }

  Future<void> addComment(String postId, String body) async {
    final me = ref.read(profileProvider);
    if (me == null || body.trim().isEmpty) return;
    await _guard(() async {
      final c = await _backend.addComment(postId, body, me);
      state = state.copyWith(
        comments: {...state.comments, postId: [...(state.comments[postId] ?? const []), c]},
        posts: state.posts.map((p) => p.id == postId ? p.copyWith(comments: p.comments + 1) : p).toList(),
      );
    });
  }

  Future<void> markNotificationsRead() async {
    if (state.unread == 0) return;
    state = state.copyWith(notifications: state.notifications.map((n) => n.copyWith(read: true)).toList());
    await _guard(_backend.markAllRead);
  }
}

final socialProvider = NotifierProvider<SocialNotifier, SocialState>(SocialNotifier.new);

// -------------------------------------------------------------- creators
final creatorStatusProvider = FutureProvider<CreatorStatus>((ref) async {
  final me = ref.watch(profileProvider);
  if (me == null) return CreatorStatus.none;
  if (me.creator) return CreatorStatus.approved;
  return ref.watch(socialBackendProvider).creatorStatus(me.id);
});

/// Creators upload; the demo grants it on application.
final canUploadProvider = Provider<bool>((ref) {
  final me = ref.watch(profileProvider);
  return me?.creator ?? false;
});

/// Moderators see the queue. Without a backend everyone does, so the demo can
/// walk the whole flow.
final isModeratorProvider = Provider<bool>((ref) {
  final me = ref.watch(profileProvider);
  return (me?.moderator ?? false) || !ref.watch(socialBackendProvider).isRemote;
});

final videoUploaderProvider = Provider<VideoUploader>((ref) {
  final backend = ref.watch(socialBackendProvider);
  if (!backend.isRemote) return DemoVideoUploader();
  return HostedVideoUploader(endpoint: BackendConfig.videoEndpoint, accessToken: currentAccessToken() ?? '', apiKey: BackendConfig.key);
});

// -------------------------------------------------------------------- steps
final stepsSourceProvider = Provider<StepsSource>((ref) => createStepsSource());

class StepsNotifier extends AsyncNotifier<List<StepDay>> {
  @override
  Future<List<StepDay>> build() async {
    final source = ref.read(stepsSourceProvider);
    if (!source.isReal) return _synced(await source.lastDays(7));
    // Native: only read if the user already connected once.
    final connected = ref.read(storeProvider).getString('health_connected') == '1';
    if (!connected) return const [];
    return _synced(await source.lastDays(7));
  }

  /// Every read of the health store also pushes the days to the backend so
  /// leagues and streaks stay current (v0.4).
  List<StepDay> _synced(List<StepDay> days) {
    if (days.isNotEmpty) unawaited(ref.read(activityProvider.notifier).syncSteps(days));
    return days;
  }

  Future<void> connect() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final source = ref.read(stepsSourceProvider);
      final ok = await source.connect();
      if (!ok) throw StateError('Permission denied. Enable steps for Ritmo in your health settings.');
      await ref.read(storeProvider).putString('health_connected', '1');
      return _synced(await source.lastDays(7));
    });
  }

  Future<void> refresh() async {
    final source = ref.read(stepsSourceProvider);
    state = await AsyncValue.guard(() async => _synced(await source.lastDays(7)));
  }
}

// ------------------------------------------------------- activity (v0.4)
/// Step sync and workout logging, plus the badges they hand back.
class ActivityNotifier extends Notifier<SyncResult?> {
  @override
  SyncResult? build() {
    ref.watch(socialBackendProvider);
    return null;
  }

  Future<SyncResult?> syncSteps(List<StepDay> days) async {
    final me = ref.read(profileProvider);
    if (me == null || days.isEmpty) return null;
    try {
      final r = await ref.read(socialBackendProvider).syncSteps(days, me);
      state = r;
      _bump();
      return r;
    } catch (e) {
      debugPrint('step sync failed: $e');
      return null;
    }
  }

  Future<SyncResult?> logWorkout({required Routine routine, required String dayTitle, required Duration duration, required int sets}) async {
    final me = ref.read(profileProvider);
    if (me == null) return null;
    final log = WorkoutLog(
      id: newUuid(),
      userId: me.id,
      routineId: routine.id,
      routineName: routine.name,
      dayTitle: dayTitle,
      durationSec: duration.inSeconds,
      sets: sets,
      completedAt: DateTime.now(),
    );
    unawaited(ref.read(scheduleProvider.notifier).markDone(routine.id));
    try {
      final r = await ref.read(socialBackendProvider).logWorkout(log, me);
      state = r;
      _bump();
      return r;
    } catch (e) {
      debugPrint('workout log failed: $e');
      return null;
    }
  }

  void _bump() {
    ref.invalidate(streaksProvider);
    ref.invalidate(leagueRanksProvider);
    ref.invalidate(standingsProvider);
    final me = ref.read(profileProvider);
    if (me != null) ref.invalidate(badgesProvider(me.id));
    unawaited(ref.read(socialProvider.notifier).refresh());
  }
}

final activityProvider = NotifierProvider<ActivityNotifier, SyncResult?>(ActivityNotifier.new);

final streaksProvider = FutureProvider<Streaks>((ref) async {
  final me = ref.watch(profileProvider);
  if (me == null) return const Streaks();
  return ref.watch(socialBackendProvider).streaks(me);
});

/// My last finished sessions, for "Recent training" on the home page.
final recentWorkoutsProvider = FutureProvider<List<WorkoutLog>>((ref) async {
  final me = ref.watch(profileProvider);
  if (me == null) return const [];
  ref.watch(activityProvider); // refresh after a workout is logged
  return ref.watch(socialBackendProvider).recentWorkouts(me);
});

/// Today's step count for each person I follow. Real numbers only arrive for
/// people who share a league with me; the demo backend walks its seeded people.
final friendStepsProvider = Provider<Map<String, int>>((ref) {
  final social = ref.watch(socialProvider);
  if (ref.watch(socialBackendProvider).isRemote) return const {};
  final today = DateTime.now();
  return {for (final id in social.following) id: LocalSocialBackend.seedSteps(id, today)};
});

final badgesProvider = FutureProvider.family<List<UserBadge>, String>((ref, userId) => ref.watch(socialBackendProvider).badges(userId));

class LeaguesNotifier extends AsyncNotifier<List<League>> {
  @override
  Future<List<League>> build() async {
    final me = ref.watch(profileProvider);
    if (me == null) return const [];
    return ref.watch(socialBackendProvider).myLeagues(me);
  }

  Future<League> create(String name, String emoji) async {
    final me = ref.read(profileProvider)!;
    final l = await ref.read(socialBackendProvider).createLeague(name, emoji, me);
    state = AsyncData([l, ...(state.value ?? const [])]);
    ref.invalidate(leagueRanksProvider);
    return l;
  }

  Future<League> join(String code) async {
    final me = ref.read(profileProvider)!;
    final l = await ref.read(socialBackendProvider).joinLeague(code, me);
    final current = state.value ?? const <League>[];
    state = AsyncData(current.any((x) => x.id == l.id) ? current : [l, ...current]);
    ref.invalidate(leagueRanksProvider);
    return l;
  }

  Future<void> leave(String id) async {
    final me = ref.read(profileProvider)!;
    await ref.read(socialBackendProvider).leaveLeague(id, me);
    state = AsyncData((state.value ?? const []).where((l) => l.id != id).toList());
    ref.invalidate(leagueRanksProvider);
  }
}

final leaguesProvider = AsyncNotifierProvider<LeaguesNotifier, List<League>>(LeaguesNotifier.new);

final standingsProvider = FutureProvider.family<List<Standing>, String>((ref, leagueId) async {
  final me = ref.watch(profileProvider);
  if (me == null) return const [];
  return ref.watch(socialBackendProvider).standings(leagueId, me);
});

final leagueRanksProvider = FutureProvider<List<LeagueRank>>((ref) async {
  final me = ref.watch(profileProvider);
  if (me == null) return const [];
  return ref.watch(socialBackendProvider).myLeagueRanks(me);
});

final stepsProvider = AsyncNotifierProvider<StepsNotifier, List<StepDay>>(StepsNotifier.new);

/// Today's steps, or 0 while loading or before Health is connected.
final todayStepsProvider = Provider<int>((ref) {
  final days = ref.watch(stepsProvider).value ?? const <StepDay>[];
  if (days.isEmpty) return 0;
  final now = DateTime.now();
  final today = days.where((d) => d.date.year == now.year && d.date.month == now.month && d.date.day == now.day).firstOrNull;
  return (today ?? days.last).steps;
});

// ------------------------------------------------------ schedule (v0.5)
/// Workouts the user put on their calendar. On-device only.
class ScheduleNotifier extends Notifier<List<ScheduledWorkout>> {
  @override
  List<ScheduledWorkout> build() {
    final list = ref.read(storeProvider).getList('schedule').map(ScheduledWorkout.fromJson).toList()..sort((a, b) => a.at.compareTo(b.at));
    return list;
  }

  Future<void> _persist() => ref.read(storeProvider).put('schedule', state.map((s) => s.toJson()).toList());

  Future<ScheduledWorkout> add({
    required Routine routine,
    required int dayIndex,
    required DateTime at,
    String note = '',
    List<TrainingGuest> guests = const [],
  }) async {
    final day = routine.days.isEmpty ? null : routine.days[dayIndex.clamp(0, routine.days.length - 1)];
    final s = ScheduledWorkout(
      id: newUuid(),
      guests: guests,
      routineId: routine.id,
      routineName: routine.name,
      dayIndex: dayIndex,
      dayTitle: day?.title ?? '',
      at: at,
      note: note,
    );
    state = [...state, s]..sort((a, b) => a.at.compareTo(b.at));
    await _persist();
    return s;
  }

  Future<void> remove(String id) async {
    state = state.where((s) => s.id != id).toList();
    await _persist();
  }

  /// Book a studio class onto the plan. There is no routine behind it — the
  /// studio runs the hour — so the row carries the studio and the coach and
  /// the plan opens the booking instead of the player.
  Future<ScheduledWorkout> book({required Studio studio, required StudioClass klass}) async {
    final s = ScheduledWorkout(
      id: newUuid(),
      routineId: '',
      routineName: klass.name,
      dayIndex: 0,
      dayTitle: studio.name,
      at: klass.nextAt(),
      note: klass.meta,
      classId: klass.id,
    );
    state = [...state, s]..sort((a, b) => a.at.compareTo(b.at));
    await _persist();
    return s;
  }

  /// Cancel a booking by class id; the plan row goes with it.
  Future<void> cancelClass(String classId) async {
    state = state.where((s) => s.classId != classId).toList();
    await _persist();
  }

  Future<void> reschedule(String id, DateTime at) async {
    state = [for (final s in state) s.id == id ? s.copyWith(at: at) : s]..sort((a, b) => a.at.compareTo(b.at));
    await _persist();
  }

  /// Called when a workout is logged: ticks off the nearest matching entry
  /// scheduled for today (or overdue) so the home page stays honest.
  Future<void> markDone(String routineId, {int? dayIndex}) async {
    final now = DateTime.now();
    final candidates = state.where((s) => !s.done && s.routineId == routineId && (dayIndex == null || s.dayIndex == dayIndex) && s.at.isBefore(now.add(const Duration(hours: 12)))).toList();
    if (candidates.isEmpty) return;
    final hit = candidates.reduce((a, b) => (a.at.difference(now).abs() <= b.at.difference(now).abs()) ? a : b);
    state = [for (final s in state) s.id == hit.id ? s.copyWith(done: true) : s];
    await _persist();
  }

  /// Not done and either upcoming or missed by less than a day.
  List<ScheduledWorkout> get upcoming {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    return state.where((s) => !s.done && s.at.isAfter(cutoff)).toList();
  }

  /// Ask friends to train with me on a session that is already on my plan.
  /// Demo friends say yes on the spot, the same courtesy the CoG quests get;
  /// hosted friends accept from the invite itself.
  Future<ScheduledWorkout> invite({required String sessionId, required List<SocialUser> friends}) async {
    final accepted = !ref.read(socialBackendProvider).isRemote;
    final session = state.firstWhere((s) => s.id == sessionId);
    final guests = [
      ...session.guests,
      for (final f in friends)
        if (session.guests.every((g) => g.id != f.id)) TrainingGuest(id: f.id, name: f.name, emoji: f.emoji, accepted: accepted),
    ];
    final updated = session.copyWith(guests: guests);
    state = [for (final s in state) s.id == sessionId ? updated : s];
    await _persist();
    return updated;
  }

  Future<void> uninvite(String sessionId, String guestId) async {
    state = [
      for (final s in state) s.id == sessionId ? s.copyWith(guests: s.guests.where((g) => g.id != guestId).toList()) : s,
    ];
    await _persist();
  }

  /// The text that goes out to the friend. Deep link mirrors the quest one.
  String inviteText(ScheduledWorkout s, UserProfile me) {
    final when = '${DateFormat('EEE d MMM').format(s.at)} at ${DateFormat.jm().format(s.at)}';
    return '${me.name} invited you to train: ${s.routineName}'
        '${s.dayTitle.isEmpty ? '' : ' · ${s.dayTitle}'} on $when. '
        'Open Ritmo and accept from Friends. ritmo://training/${s.id}';
  }
}

final scheduleProvider = NotifierProvider<ScheduleNotifier, List<ScheduledWorkout>>(ScheduleNotifier.new);

final upcomingWorkoutsProvider = Provider<List<ScheduledWorkout>>((ref) {
  ref.watch(scheduleProvider);
  return ref.read(scheduleProvider.notifier).upcoming;
});

/// The session the Start button offers: picked from the profile, the gear,
/// the experience level and the last two days of training.
final suggestionNudgeProvider = NotifierProvider<SuggestionNudge, int>(SuggestionNudge.new);

class SuggestionNudge extends Notifier<int> {
  @override
  int build() => 0;
  void shuffle() => state = state + 1;
}

final suggestionProvider = Provider<SessionSuggestion?>((ref) {
  final me = ref.watch(profileProvider);
  final repo = ref.watch(exerciseRepoProvider).value;
  if (me == null || repo == null) return null;
  return Recommender.suggest(
    me: me,
    repo: repo,
    recent: ref.watch(recentWorkoutsProvider).value ?? const [],
    library: [...ref.watch(routinesProvider), ...SeedData.readyMade, ...SeedData.coachProgrammes],
    nudge: ref.watch(suggestionNudgeProvider),
  );
});

/// The multi-day plan the AI coach has ready for this athlete (v0.12).
///
/// The chat is closed while we work out how to give it away for everyone, but
/// the coach itself still works: this is the plan it would hand you, built
/// from the profile against the bundled catalogue, and it is what the AI
/// coach's card in Community publishes. The id is stable so opening the
/// preview twice is the same routine.
final aiCoachPlanProvider = Provider<Routine?>((ref) {
  final me = ref.watch(profileProvider);
  final repo = ref.watch(exerciseRepoProvider).value;
  if (me == null || repo == null) return null;
  return buildCoachPlan(me, repo, id: 'ai_coach_${me.id}');
});

/// Class bookings made from Community, by class id.
final bookedClassesProvider = Provider<Set<String>>((ref) => {
      for (final s in ref.watch(scheduleProvider))
        if (s.classId != null) s.classId!,
    });

/// Sessions that have somebody else on them, soonest first. Drives the
/// invite list at the top of Friends.
final trainingInvitesProvider = Provider<List<ScheduledWorkout>>((ref) {
  final cutoff = DateTime.now().subtract(const Duration(hours: 12));
  return [
    for (final s in ref.watch(scheduleProvider))
      if (s.guests.isNotEmpty && s.at.isAfter(cutoff)) s,
  ]..sort((a, b) => a.at.compareTo(b.at));
});

// ------------------------------------------------------- quests (v0.5)
/// "CoG together" shared quests with one friend. Local for now; the invite
/// is a share link and the friend's numbers come from the backend when
/// hosted, or from the demo seed when on-device.
class QuestsNotifier extends Notifier<List<Quest>> {
  @override
  List<Quest> build() => ref.read(storeProvider).getList('quests').map(Quest.fromJson).toList();

  Future<void> _persist() => ref.read(storeProvider).put('quests', state.map((q) => q.toJson()).toList());

  Future<Quest> invite({required SocialUser friend, required QuestPreset preset}) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final q = Quest(
      id: newUuid(),
      title: preset.title,
      kind: preset.kind,
      target: preset.target,
      friendId: friend.id,
      friendName: friend.name,
      friendEmoji: friend.emoji,
      startsAt: start,
      endsAt: start.add(Duration(days: preset.days)),
      // Demo friends say yes immediately; hosted friends accept from their invite.
      accepted: !ref.read(socialBackendProvider).isRemote,
    );
    state = [q, ...state];
    await _persist();
    return q;
  }

  Future<void> end(String id) async {
    state = state.where((q) => q.id != id).toList();
    await _persist();
  }

  String inviteText(Quest q, UserProfile me) =>
      '${me.name} invited you to a Ritmo quest: ${q.title} by ${q.endsAt.day}/${q.endsAt.month}. Open Ritmo and accept from your home page. ritmo://quest/${q.id}';
}

final questsProvider = NotifierProvider<QuestsNotifier, List<Quest>>(QuestsNotifier.new);

/// Progress for every live quest: my steps or workouts since the start, plus
/// the friend's. Demo friends walk their seeded daily counts.
final questProgressProvider = Provider<List<QuestProgress>>((ref) {
  final quests = ref.watch(questsProvider).where((q) => !q.isOver).toList();
  if (quests.isEmpty) return const [];
  final days = ref.watch(stepsProvider).value ?? const <StepDay>[];
  final streaks = ref.watch(streaksProvider).value ?? const Streaks();
  final remote = ref.watch(socialBackendProvider).isRemote;
  final today = DateTime.now();
  return [
    for (final q in quests)
      QuestProgress(
        quest: q,
        mine: switch (q.kind) {
          QuestKind.steps => days.where((d) => !d.date.isBefore(q.startsAt)).fold(0, (n, d) => n + d.steps),
          QuestKind.workouts => streaks.weekWorkouts,
        },
        theirs: !q.accepted
            ? 0
            : switch (q.kind) {
                QuestKind.steps => remote
                    ? 0
                    : [
                        for (var d = q.startsAt; !d.isAfter(today); d = d.add(const Duration(days: 1))) LocalSocialBackend.seedSteps(q.friendId, d),
                      ].fold(0, (n, s) => n + s),
                QuestKind.workouts => remote ? 0 : (today.difference(q.startsAt).inDays ~/ 2).clamp(0, q.target),
              },
      ),
  ];
});

// -------------------------------------------------- Me screen data (v0.7)
/// Which days of the current week already carry a logged workout, plus the
/// sets behind them. Drives the streak card's seven cells and the stat row.
final weekTrainingProvider = FutureProvider<({Set<int> days, int sets, int workouts})>((ref) async {
  final me = ref.watch(profileProvider);
  if (me == null) return (days: <int>{}, sets: 0, workouts: 0);
  ref.watch(activityProvider);
  final logs = await ref.watch(socialBackendProvider).recentWorkouts(me, limit: 40);
  final monday = weekStart(DateTime.now());
  final days = <int>{};
  var sets = 0;
  var workouts = 0;
  for (final l in logs) {
    if (l.completedAt.isBefore(monday)) continue;
    days.add(l.completedAt.weekday);
    sets += l.sets;
    workouts++;
  }
  return (days: days, sets: sets, workouts: workouts);
});

/// Every session the app can still see, newest first. The week chart only
/// needs seven days; the calendar reads months back, so it asks for the lot.
final workoutHistoryProvider = FutureProvider<List<WorkoutLog>>((ref) async {
  final me = ref.watch(profileProvider);
  if (me == null) return const [];
  ref.watch(activityProvider);
  return ref.watch(socialBackendProvider).recentWorkouts(me, limit: 400);
});

/// The last seven step days ordered Monday to Sunday, with gaps filled, so
/// the "This week" chart always renders seven bars.
final weekStepsProvider = Provider<List<StepDay>>((ref) {
  final days = ref.watch(stepsProvider).value ?? const <StepDay>[];
  final monday = weekStart(DateTime.now());
  return [
    for (var i = 0; i < 7; i++)
      () {
        final date = monday.add(Duration(days: i));
        final hit = days.where((d) => d.date.year == date.year && d.date.month == date.month && d.date.day == date.day).firstOrNull;
        return StepDay(date, hit?.steps ?? 0);
      }(),
  ];
});

// ------------------------------------------------------------ goals (v0.7)
/// Goals the user set by hand. The two derived ones live in [goalsProvider].
class CustomGoalsNotifier extends Notifier<List<PersonalGoal>> {
  @override
  List<PersonalGoal> build() => ref.read(storeProvider).getList('goals').map(PersonalGoal.fromJson).toList();

  Future<void> _persist() => ref.read(storeProvider).put('goals', state.map((g) => g.toJson()).toList());

  Future<void> add({
    required String name,
    required double target,
    String unit = '',
    String note = '',
    String? exerciseId,
    String? exerciseName,
    DateTime? deadline,
  }) async {
    state = [
      ...state,
      PersonalGoal(
        id: newUuid(),
        name: name,
        current: 0,
        target: target,
        unit: unit,
        note: note,
        exerciseId: exerciseId,
        exerciseName: exerciseName,
        deadline: deadline,
      ),
    ];
    await _persist();
  }

  /// Move the date on a goal already being chased. [clear] drops it back to
  /// an open-ended goal.
  Future<void> setDeadline(String id, DateTime? deadline, {bool clear = false}) async {
    state = [for (final g in state) g.id == id ? g.copyWith(deadline: deadline, clearDeadline: clear || deadline == null) : g];
    await _persist();
  }

  /// Whether this exercise is already somebody's goal, so the library can say
  /// so instead of offering to add it twice.
  bool hasExercise(String exerciseId) => state.any((g) => g.exerciseId == exerciseId);

  Future<void> setProgress(String id, double current) async {
    state = [for (final g in state) g.id == id ? g.copyWith(current: current) : g];
    await _persist();
  }

  Future<void> remove(String id) async {
    state = state.where((g) => g.id != id).toList();
    await _persist();
  }
}

final customGoalsProvider = NotifierProvider<CustomGoalsNotifier, List<PersonalGoal>>(CustomGoalsNotifier.new);

/// Every goal on the Me screen: two derived from the profile so the card is
/// never empty, then whatever the user added.
final goalsProvider = Provider<List<PersonalGoal>>((ref) {
  final me = ref.watch(profileProvider);
  if (me == null) return const [];
  final week = ref.watch(weekTrainingProvider).value;
  final streaks = ref.watch(streaksProvider).value ?? const Streaks();
  final workouts = (week?.workouts ?? streaks.weekWorkouts).toDouble();
  final today = ref.watch(todayStepsProvider);
  return [
    PersonalGoal(
      id: 'derived_week',
      name: 'Train ${me.daysPerWeek}x a week',
      current: workouts,
      target: me.daysPerWeek.toDouble(),
      note: workouts >= me.daysPerWeek ? 'Done for this week' : '${(me.daysPerWeek - workouts).round()} to go before Sunday',
      derived: true,
    ),
    PersonalGoal(
      id: 'derived_steps',
      name: 'Walk ${NumberFormat.decimalPattern().format(me.stepGoal)} steps a day',
      current: today.toDouble(),
      target: me.stepGoal.toDouble(),
      note: streaks.stepStreak > 0 ? '${streaks.stepStreak}-day streak, best ${streaks.stepBest}' : 'Start a streak today',
      derived: true,
    ),
    ...ref.watch(customGoalsProvider),
  ];
});

// ------------------------------------------------------ breathing (v0.13)
/// Patterns the athlete built themselves. On-device, like the schedule and
/// the food log: a breathing pattern is nobody else's business.
class CustomBreathingNotifier extends Notifier<List<BreathingPattern>> {
  @override
  List<BreathingPattern> build() => ref.read(storeProvider).getList('breathing').map(BreathingPattern.fromJson).toList();

  Future<void> _persist() => ref.read(storeProvider).put('breathing', state.map((p) => p.toJson()).toList());

  Future<BreathingPattern> add({
    required String name,
    required int inhale,
    required int holdIn,
    required int exhale,
    required int holdOut,
    required int cycles,
  }) async {
    final p = BreathingPattern(
      id: newUuid(),
      name: name,
      tagline: 'Yours: $inhale in, $holdIn hold, $exhale out, $holdOut hold.',
      inhale: inhale,
      holdIn: holdIn,
      exhale: exhale,
      holdOut: holdOut,
      cycles: cycles,
      emoji: '🌬',
      purpose: BreathePurpose.mine,
      custom: true,
    );
    state = [...state, p];
    await _persist();
    return p;
  }

  Future<void> remove(String id) async {
    state = state.where((p) => p.id != id).toList();
    await _persist();
  }
}

final customBreathingProvider = NotifierProvider<CustomBreathingNotifier, List<BreathingPattern>>(CustomBreathingNotifier.new);

/// Every pattern the breathe page shows: the ones we ship, then the athlete's
/// own, grouped by what they are for.
final breathingByPurposeProvider = Provider<Map<BreathePurpose, List<BreathingPattern>>>((ref) {
  final all = [...breathingPatterns, ...ref.watch(customBreathingProvider)];
  return {
    for (final purpose in BreathePurpose.values)
      if (all.any((p) => p.purpose == purpose)) purpose: [for (final p in all) if (p.purpose == purpose) p],
  };
});

// -------------------------------------------------------- nutrition (v0.7)
/// Today's food log. On-device only, like the schedule: what someone eats is
/// not something the app sends anywhere.
class NutritionNotifier extends Notifier<NutritionDay> {
  @override
  NutritionDay build() {
    final j = ref.read(storeProvider).getMap('nutrition');
    final stored = j == null ? null : NutritionDay.fromJson(j);
    if (stored != null && stored.isToday()) return stored;
    final n = DateTime.now();
    return NutritionDay(day: DateTime(n.year, n.month, n.day));
  }

  Future<void> log({int kcal = 0, int protein = 0, int carbs = 0, int fat = 0}) async {
    state = state.plus(kcal: kcal, protein: protein, carbs: carbs, fat: fat);
    await ref.read(storeProvider).put('nutrition', state.toJson());
  }

  Future<void> clear() async {
    final n = DateTime.now();
    state = NutritionDay(day: DateTime(n.year, n.month, n.day));
    await ref.read(storeProvider).put('nutrition', state.toJson());
  }
}

final nutritionProvider = NotifierProvider<NutritionNotifier, NutritionDay>(NutritionNotifier.new);

final calorieTargetProvider = Provider<int>((ref) {
  final me = ref.watch(profileProvider);
  return me == null ? 2000 : calorieTarget(me);
});

/// Public leagues near the user, for "Join a league nearby".
final nearbyLeaguesProvider = FutureProvider<List<League>>((ref) async {
  final me = ref.watch(profileProvider);
  if (me == null) return const [];
  ref.watch(leaguesProvider); // refresh after a join
  return ref.watch(socialBackendProvider).nearbyLeagues(me);
});

// -------------------------------------------------------------------- coach
enum CoachMode { cloud, device, offline }

/// Which coach answers right now: hosted (signed in), on-device Claude with a
/// user key (demo), or the offline rule-based coach.
final coachModeProvider = Provider<CoachMode>((ref) {
  final auth = ref.watch(authProvider);
  if (BackendConfig.enabled && auth != null) return CoachMode.cloud;
  if (ref.watch(settingsProvider).hasKey) return CoachMode.device;
  return CoachMode.offline;
});

class CoachState {
  const CoachState({this.messages = const [], this.busy = false, this.streaming});
  final List<ChatMessage> messages;
  final bool busy;

  /// Partial reply text while the hosted coach streams.
  final String? streaming;
  CoachState copyWith({List<ChatMessage>? messages, bool? busy, String? streaming, bool clearStreaming = false}) =>
      CoachState(
        messages: messages ?? this.messages,
        busy: busy ?? this.busy,
        streaming: clearStreaming ? null : (streaming ?? this.streaming),
      );
}

class CoachNotifier extends Notifier<CoachState> {
  @override
  CoachState build() => const CoachState();

  Coach _pick() {
    final settings = ref.read(settingsProvider);
    switch (ref.read(coachModeProvider)) {
      case CoachMode.cloud:
        return RemoteCoach(endpoint: BackendConfig.coachEndpoint, accessToken: currentAccessToken() ?? '', apiKey: BackendConfig.key);
      case CoachMode.device:
        return ClaudeCoach(apiKey: settings.apiKey, model: settings.model);
      case CoachMode.offline:
        return LocalCoach();
    }
  }

  Future<void> send(String text) async {
    final profile = ref.read(profileProvider);
    final repo = await ref.read(exerciseRepoProvider.future);
    if (profile == null) return;
    final history = [...state.messages, ChatMessage(role: 'user', text: text)];
    state = state.copyWith(messages: history, busy: true, clearStreaming: true);

    final steps = ref.read(stepsProvider).value ?? const <StepDay>[];
    final coach = _pick();

    try {
      final reply = await coach.reply(
        history: history,
        profile: profile,
        repo: repo,
        recentSteps: steps,
        onText: (delta) => state = state.copyWith(streaming: '${state.streaming ?? ''}$delta'),
      );
      if (reply.routine != null) await ref.read(routinesProvider.notifier).upsert(reply.routine!);
      state = state.copyWith(
        messages: [...history, ChatMessage(role: 'coach', text: reply.text, routine: reply.routine)],
        busy: false,
        clearStreaming: true,
      );
    } catch (e) {
      state = state.copyWith(
        messages: [...history, ChatMessage(role: 'coach', text: 'Coach is unreachable: $e', error: true)],
        busy: false,
        clearStreaming: true,
      );
    }
  }

  void clear() => state = const CoachState();
}

final coachProvider = NotifierProvider<CoachNotifier, CoachState>(CoachNotifier.new);
