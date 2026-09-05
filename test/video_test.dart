import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ritmo/core/local_store.dart';
import 'package:ritmo/core/models.dart';
import 'package:ritmo/core/social_backend.dart';
import 'package:ritmo/core/video_service.dart';

const me = UserProfile(
  id: 'me', name: 'Test Athlete', handle: 'test', emoji: '🙂',
  heightCm: 175, weightKg: 70, age: 30, goal: Goal.buildMuscle,
  diet: [], equipment: ['dumbbell'], daysPerWeek: 3,
);

Future<LocalStore> freshStore() async {
  SharedPreferences.setMockInitialValues({});
  return LocalStore.open();
}

PickedClip clip({int seconds = 30}) =>
    PickedClip(name: 'burner.mp4', bytes: Uint8List.fromList(List.filled(1024, 7)), duration: Duration(seconds: seconds));

void main() {
  group('video uploaders', () {
    test('demo uploader refuses clips over 60 seconds and returns a processing video', () async {
      final up = DemoVideoUploader();
      expect(() => up.upload(clip(seconds: 61), authorId: me.id), throwsA(isA<ClipTooLong>()));
      final progress = <double>[];
      final v = await up.upload(clip(seconds: 45), authorId: me.id, exerciseIds: ['Pushups'], onProgress: progress.add);
      expect(v.status, VideoStatus.processing);
      expect(v.ready, isFalse);
      expect(v.exerciseIds, ['Pushups']);
      expect(v.durationSec, 45);
      expect(progress.last, 1);
      expect(isUuid(v.id), isTrue);
    });

    test('hosted uploader asks the edge function for a ticket then posts the file as a form', () async {
      final calls = <http.Request>[];
      final client = MockClient((req) async {
        calls.add(req);
        if (req.url.path.endsWith('/create')) {
          final body = jsonDecode(req.body) as Map;
          expect(body['duration_sec'], 30);
          expect(body['exercise_ids'], ['Kettlebell_Swing']);
          expect(req.headers['Authorization'], 'Bearer jwt');
          return http.Response(jsonEncode({'video_id': '7c9e6679-7425-40de-944b-e07fc1f90ae7', 'upload_url': 'https://upload.cloudflarestream.com/abc', 'method': 'form', 'provider': 'cloudflare'}), 200);
        }
        expect(req.url.host, 'upload.cloudflarestream.com');
        expect(req.headers['content-type'], startsWith('multipart/form-data'));
        return http.Response('', 200);
      });
      final up = HostedVideoUploader(endpoint: 'https://x.supabase.co/functions/v1/video', accessToken: 'jwt', apiKey: 'anon', client: client);
      final v = await up.upload(clip(), authorId: me.id, exerciseIds: ['Kettlebell_Swing']);
      expect(v.id, '7c9e6679-7425-40de-944b-e07fc1f90ae7');
      expect(v.status, VideoStatus.processing);
      expect(calls.length, 2);
    });

    test('hosted uploader surfaces the creators-only refusal and uses PUT for Mux', () async {
      var mode = 'refuse';
      final client = MockClient((req) async {
        if (req.url.path.endsWith('/create')) {
          if (mode == 'refuse') return http.Response(jsonEncode({'error': 'creators first', 'code': 'creators_only'}), 403);
          return http.Response(jsonEncode({'video_id': '7c9e6679-7425-40de-944b-e07fc1f90ae8', 'upload_url': 'https://storage.googleapis.com/mux/up', 'method': 'put', 'provider': 'mux'}), 200);
        }
        expect(req.method, 'PUT');
        expect(req.bodyBytes.length, 1024);
        return http.Response('', 200);
      });
      final up = HostedVideoUploader(endpoint: 'https://x/functions/v1/video', accessToken: 'jwt', apiKey: 'anon', client: client);
      await expectLater(up.upload(clip(), authorId: me.id), throwsA(isA<UploadRejected>().having((e) => e.code, 'code', 'creators_only')));
      mode = 'ok';
      final v = await up.upload(clip(), authorId: me.id);
      expect(v.id, endsWith('ae8'));
    });
  });

  group('local backend v0.3', () {
    test('seeds two open reports with post previews', () async {
      final b = LocalSocialBackend(await freshStore());
      await b.load(me);
      final queue = await b.openReports();
      expect(queue.length, 2);
      expect(queue.first.targetTitle, contains('stairwell'));
      expect(queue.first.targetAuthorId, 'zoe');
      expect(queue.first.reason, ReportReason.unsafeAdvice);
    });

    test('a member reports once; the third open report hides the post; restore shows it again', () async {
      final b = LocalSocialBackend(await freshStore());
      await b.load(me);
      expect(await b.report(target: ReportTarget.post, targetId: 'p_dario_ppl', reason: ReportReason.spam, me: me), isTrue);
      expect(await b.report(target: ReportTarget.post, targetId: 'p_dario_ppl', reason: ReportReason.spam, me: me), isFalse);
      var p = (await b.load(me)).posts.firstWhere((p) => p.id == 'p_dario_ppl');
      expect(p.hidden, isFalse);
      await b.report(target: ReportTarget.post, targetId: 'p_dario_ppl', reason: ReportReason.other, me: me.copyWith(id: 'other1'));
      await b.report(target: ReportTarget.post, targetId: 'p_dario_ppl', reason: ReportReason.other, me: me.copyWith(id: 'other2'));
      p = (await b.load(me)).posts.firstWhere((p) => p.id == 'p_dario_ppl');
      expect(p.hidden, isTrue);

      final queue = await b.openReports();
      final r = queue.firstWhere((r) => r.targetId == 'p_dario_ppl');
      expect(r.targetHidden, isTrue);
      await b.moderate(r, ModerationAction.restore, note: 'fine');
      p = (await b.load(me)).posts.firstWhere((p) => p.id == 'p_dario_ppl');
      expect(p.hidden, isFalse);
      expect((await b.openReports()).where((r) => r.targetId == 'p_dario_ppl'), isEmpty);
    });

    test('remove deletes the post and resolves every report on it', () async {
      final b = LocalSocialBackend(await freshStore());
      await b.load(me);
      final r = (await b.openReports()).firstWhere((r) => r.targetId == 'p_ben_diet');
      await b.moderate(r, ModerationAction.remove, note: 'ad');
      expect((await b.load(me)).posts.any((p) => p.id == 'p_ben_diet'), isFalse);
      expect((await b.openReports()).length, 1);
    });

    test('video posts settle from processing to ready after the demo transcode window', () async {
      final store = await freshStore();
      final b = LocalSocialBackend(store);
      await b.load(me);
      final v = Video(id: 'vid1', authorId: me.id, status: VideoStatus.processing, exerciseIds: const ['Pushups']);
      final fresh = Post(id: 'post_fresh', authorId: me.id, kind: PostKind.video, title: 'New clip', body: '', createdAt: DateTime.now(), video: v);
      final old = Post(id: 'post_old', authorId: me.id, kind: PostKind.video, title: 'Old clip', body: '', createdAt: DateTime.now().subtract(const Duration(minutes: 1)), video: v.copyWith());
      await b.publish(fresh);
      await b.publish(old);
      final snap = await b.load(me);
      expect(snap.posts.firstWhere((p) => p.id == 'post_fresh').video!.status, VideoStatus.processing);
      final settled = snap.posts.firstWhere((p) => p.id == 'post_old');
      expect(settled.video!.ready, isTrue);
      expect(settled.playableUrl, isNotNull);
      expect(settled.video!.exerciseIds, ['Pushups']);
      expect((await b.video('vid1'))!.status, VideoStatus.ready);
    });

    test('views count once per session and creator stats aggregate my posts', () async {
      final b = LocalSocialBackend(await freshStore());
      await b.load(me);
      await b.publish(Post(id: 'mine1', authorId: me.id, kind: PostKind.workout, title: 'Legs', body: '', createdAt: DateTime.now(), likes: 10, comments: 2));
      await b.recordView('mine1');
      await b.recordView('mine1');
      final s = await b.creatorStats(me.id);
      expect(s.posts, 1);
      expect(s.views, 1 + 10 * 9 + 2 * 4);
      expect(s.viewsByDay.length, 7);
      expect(s.topPosts.single.title, 'Legs');
      expect(s.engagementPct, greaterThan(0));
      expect(await b.creatorStatus(me.id), CreatorStatus.none);
      await b.applyAsCreator('I post kettlebell flows', me);
      expect(await b.creatorStatus(me.id), CreatorStatus.approved);
    });
  });

  group('row mapping v0.3', () {
    test('video and report rows map to models', () {
      final v = videoFromRow({
        'id': 'a', 'author_id': 'u', 'status': 'ready', 'playback_url': 'https://x/m3u8', 'thumbnail_url': 'https://x/t.jpg',
        'duration_sec': 42.5, 'width': 1080, 'height': 1920, 'exercise_ids': ['Pushups'], 'view_count': 7,
      });
      expect(v.ready, isTrue);
      expect(v.aspectRatio, closeTo(0.5625, 0.001));
      expect(v.views, 7);
      final post = postFromRow({
        'id': 'p', 'author_id': 'u', 'kind': 'video', 'title': 'T', 'created_at': '2026-09-04T10:00:00Z', 'hidden': true, 'view_count': 3,
        'video': {'id': 'a', 'author_id': 'u', 'status': 'processing'},
      });
      expect(post.hidden, isTrue);
      expect(post.views, 3);
      expect(post.hasVideo, isTrue);
      expect(post.playableUrl, isNull);
      final r = reportFromRow({'id': 'r', 'reporter_id': null, 'target_kind': 'post', 'target_id': 'p', 'reason': 'unsafe_advice', 'status': 'open', 'created_at': '2026-09-04T10:00:00Z'});
      expect(r.automated, isTrue);
      expect(r.reason, ReportReason.unsafeAdvice);
      expect(r.reason.wire, 'unsafe_advice');
      expect(Report.fromJson(r.toJson()).reason, ReportReason.unsafeAdvice);
    });

    test('creator stats parse the RPC shape', () {
      final s = CreatorStats.fromJson({
        'followers': 3, 'posts': 2, 'views': 100, 'likes': 5, 'comments': 5, 'recommends': 0, 'tries': 1,
        'viewsByDay': [0, 1, 2, 3, 4, 5, 6],
        'topPosts': [{'postId': 'p', 'title': 'A', 'kind': 'video', 'views': 90, 'likes': 5}],
      });
      expect(s.engagementPct, 10);
      expect(s.viewsByDay.last, 6);
      expect(s.topPosts.single.kind, PostKind.video);
    });

    test('new notification kinds round-trip', () {
      for (final k in [NotificationKind.video, NotificationKind.moderation, NotificationKind.creator]) {
        final n = AppNotification(id: 'n', kind: k, createdAt: DateTime(2026, 9, 4));
        expect(AppNotification.fromJson(n.toJson()).kind, k);
      }
    });
  });
}
