import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ritmo/core/local_store.dart';
import 'package:ritmo/core/models.dart';
import 'package:ritmo/core/remote_coach.dart';
import 'package:ritmo/core/social_backend.dart';

const me = UserProfile(
  id: 'me', name: 'Test Athlete', handle: 'test', emoji: '🙂',
  heightCm: 175, weightKg: 70, age: 30, goal: Goal.buildMuscle,
  diet: [], equipment: ['dumbbell'], daysPerWeek: 3,
);

Future<LocalStore> freshStore() async {
  SharedPreferences.setMockInitialValues({});
  return LocalStore.open();
}

void main() {
  group('LocalSocialBackend', () {
    test('seeds posts, comments and notifications once, then persists', () async {
      final store = await freshStore();
      final b = LocalSocialBackend(store);
      final snap = await b.load(me);
      expect(snap.posts, isNotEmpty);
      expect(snap.notifications.where((n) => !n.read).length, 2);
      expect(snap.users.containsKey('maya'), isTrue);

      final thread = await b.comments('p_ben_video');
      expect(thread.length, 3);
      expect(thread.first.createdAt.isBefore(thread.last.createdAt), isTrue);

      // Second load reads back from the store rather than reseeding.
      final again = await LocalSocialBackend(store).load(me);
      expect(again.posts.map((p) => p.id), snap.posts.map((p) => p.id));
    });

    test('like, recommend, comment and follow update counts and sets', () async {
      final b = LocalSocialBackend(await freshStore());
      final before = (await b.load(me)).posts.firstWhere((p) => p.id == 'p_dario_ppl');

      await b.setLike('p_dario_ppl', true);
      await b.setLike('p_dario_ppl', true); // idempotent
      await b.recommend('p_dario_ppl');
      await b.addComment('p_dario_ppl', 'Solid split', me);
      await b.setFollow('dario', true);

      final snap = await b.load(me);
      final after = snap.posts.firstWhere((p) => p.id == 'p_dario_ppl');
      expect(after.likes, before.likes + 1);
      expect(after.recommends, before.recommends + 1);
      expect(after.comments, before.comments + 1);
      expect(snap.liked, {'p_dario_ppl'});
      expect(snap.recommended, {'p_dario_ppl'});
      expect(snap.following, {'dario'});

      await b.setLike('p_dario_ppl', false);
      final unliked = (await b.load(me)).posts.firstWhere((p) => p.id == 'p_dario_ppl');
      expect(unliked.likes, before.likes);

      await b.markAllRead();
      expect((await b.notifications()).every((n) => n.read), isTrue);
    });

    test('published posts come first', () async {
      final b = LocalSocialBackend(await freshStore());
      await b.load(me);
      final post = Post(id: newUuid(), authorId: me.id, kind: PostKind.workout, title: 'Leg day', body: '', createdAt: DateTime.now());
      await b.publish(post);
      final snap = await b.load(me);
      expect(snap.posts.first.id, post.id);
    });
  });

  group('row mapping', () {
    test('post row with embedded author and routine maps to models', () {
      final row = {
        'id': '7c9e6679-7425-40de-944b-e07fc1f90ae7',
        'author_id': 'a1b2c3d4-0000-4000-8000-000000000001',
        'kind': 'routine',
        'title': 'My PPL',
        'body': 'go',
        'created_at': '2026-09-04T10:00:00Z',
        'like_count': 3,
        'recommend_count': 1,
        'comment_count': 2,
        'tags': ['strength'],
        'hot': true,
        'author': {'id': 'a1b2c3d4-0000-4000-8000-000000000001', 'name': 'Dario', 'handle': 'dario_lifts', 'emoji': '🏋️', 'bio': '', 'goal': 'getStronger', 'diet': []},
        'routine': {
          'id': 'aaaaaaaa-0000-4000-8000-000000000001',
          'author_id': 'a1b2c3d4-0000-4000-8000-000000000001',
          'name': 'PPL',
          'description': '',
          'days': [
            {'title': 'Push', 'focus': 'Chest', 'items': [
              {'exerciseId': 'Pushups', 'exerciseName': 'Pushups', 'sets': 3, 'reps': 10, 'restSec': 60, 'notes': ''}
            ]}
          ],
          'tags': ['strength'],
          'source': 'me',
          'created_at': '2026-09-01T10:00:00Z',
          'author': {'name': 'Dario', 'handle': 'dario_lifts'},
        },
      };
      final p = postFromRow(row);
      expect(p.kind, PostKind.routine);
      expect(p.likes, 3);
      expect(p.hot, isTrue);
      expect(p.routine?.days.single.items.single.exerciseName, 'Pushups');
      expect(p.routine?.authorName, 'Dario');
      expect(userFromRow(Map<String, dynamic>.from(row['author'] as Map)).goal, Goal.getStronger);
    });

    test('profile round-trips through the row shape', () {
      final row = profileToRow(me);
      expect(row['goal'], 'buildMuscle');
      final back = profileFromRow({...row, 'id': me.id});
      expect(back.name, me.name);
      expect(back.equipment, me.equipment);
      expect(back.heightCm, me.heightCm);
      expect(profileRowIsComplete(row), isTrue);
      expect(profileRowIsComplete({'id': 'x', 'handle': 'x', 'name': 'x'}), isFalse);
    });

    test('notification wire kinds round-trip, including try', () {
      final n = AppNotification(id: 'n', kind: NotificationKind.tryIt, createdAt: DateTime(2026, 9, 4), preview: 'PPL');
      expect(n.toJson()['kind'], 'try');
      expect(AppNotification.fromJson(n.toJson()).kind, NotificationKind.tryIt);
      expect(notificationFromRow({'id': 'x', 'kind': 'follow', 'created_at': '2026-09-04T00:00:00Z', 'read': false}).kind, NotificationKind.follow);
    });

    test('uuid helper produces valid v4 ids', () {
      final id = newUuid();
      expect(isUuid(id), isTrue);
      expect(id[14], '4');
      expect(isUuid('mine_123'), isFalse);
      expect(newUuid(), isNot(id));
    });
  });

  group('RemoteCoach SSE parsing', () {
    test('reassembles frames split across chunks and skips junk', () async {
      final frames = [
        'data: {"type":"text","delta":"Hel',
        'lo"}\n\ndata: {"type":"tool","name":"search_exercises","summary":"chest"}\n\n',
        ': keep-alive\n\ndata: not json\n\n',
        'data: {"type":"routine","routine":{"id":"r1","name":"Plan","description":"","authorId":"u","authorName":"Coach","days":[],"createdAt":"2026-09-04T00:00:00Z","tags":[],"source":"ai"}}\n\n',
        'data: {"type":"done","remaining":4}',
      ];
      final events = await parseSse(Stream.fromIterable(frames)).toList();
      expect(events.map((e) => e['type']), ['text', 'tool', 'routine', 'done']);
      expect(events.first['delta'], 'Hello');
      expect(Routine.fromJson(Map<String, dynamic>.from(events[2]['routine'] as Map)).name, 'Plan');
      expect(events.last['remaining'], 4);
    });

    test('routine JSON emitted by the edge function parses into a Routine', () {
      // Shape produced by supabase/functions/_shared/catalogue.ts planToRoutine.
      final json = jsonDecode('''
        {"id":"aaaaaaaa-0000-4000-8000-000000000001","name":"Muscle 3-day","description":"For you\\nNutrition: eat",
         "authorId":"u","authorName":"Ritmo Coach for Test","days":[{"title":"Day 1","focus":"Chest",
         "items":[{"exerciseId":"Pushups","exerciseName":"Pushups","sets":4,"reps":10,"restSec":90,"notes":""}]}],
         "createdAt":"2026-09-04T00:00:00.000Z","tags":["ai","buildMuscle"],"source":"ai"}''');
      final r = Routine.fromJson(Map<String, dynamic>.from(json as Map));
      expect(r.exerciseCount, 1);
      expect(r.source, 'ai');
      expect(isUuid(r.id), isTrue);
    });
  });
}
