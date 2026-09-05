import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_coach.dart';
import 'backend.dart';
import 'exercise_repository.dart';
import 'models.dart';

/// Coach backed by the `coach` Supabase edge function (v0.2).
///
/// The function holds the Anthropic key, enforces the weekly quota, logs tool
/// calls for evals, and streams the reply as server-sent events. This client
/// only relays text deltas and picks up the saved routine.
class RemoteCoach implements Coach {
  RemoteCoach({required this.endpoint, required this.accessToken, required this.apiKey, http.Client? client})
      : _client = client ?? http.Client();

  final String endpoint;
  final String accessToken;
  final String apiKey;
  final http.Client _client;

  @override
  Future<CoachReply> reply({
    required List<ChatMessage> history,
    required UserProfile profile,
    required ExerciseRepository repo,
    List<StepDay> recentSteps = const [],
    void Function(String delta)? onText,
  }) async {
    final avg = recentSteps.isEmpty ? null : recentSteps.map((s) => s.steps).reduce((a, b) => a + b) / recentSteps.length;
    final req = http.Request('POST', Uri.parse(endpoint))
      ..headers['content-type'] = 'application/json'
      ..headers['authorization'] = 'Bearer $accessToken'
      ..headers['apikey'] = apiKey
      ..body = jsonEncode({
        'messages': [for (final m in history) {'role': m.role, 'text': m.text}],
        'steps_avg': ?avg,
      });

    final res = await _client.send(req).timeout(const Duration(minutes: 3));
    if (res.statusCode != 200) {
      final body = await res.stream.bytesToString();
      String detail = body;
      try {
        detail = (jsonDecode(body)['error'] ?? body).toString();
      } catch (_) {}
      throw CoachException(res.statusCode == 429 ? detail : 'Coach $detail');
    }

    final text = StringBuffer();
    Routine? routine;
    await for (final event in parseSse(res.stream.transform(utf8.decoder))) {
      switch (event['type']) {
        case 'text':
          final delta = event['delta'] as String? ?? '';
          text.write(delta);
          onText?.call(delta);
        case 'routine':
          routine = Routine.fromJson(Map<String, dynamic>.from(event['routine'] as Map));
        case 'error':
          throw CoachException(event['message'] as String? ?? 'Coach error');
        case 'done':
          break;
      }
    }
    return CoachReply(text: text.toString().trim(), routine: routine);
  }
}

/// Splits a server-sent-event byte stream into decoded `data:` JSON objects.
/// Exposed for tests; tolerant of chunk boundaries landing mid-line.
Stream<Map<String, dynamic>> parseSse(Stream<String> chunks) async* {
  var buffer = '';
  await for (final chunk in chunks) {
    buffer += chunk;
    while (true) {
      final i = buffer.indexOf('\n\n');
      if (i < 0) break;
      final frame = buffer.substring(0, i);
      buffer = buffer.substring(i + 2);
      for (final line in frame.split('\n')) {
        if (!line.startsWith('data:')) continue;
        final raw = line.substring(5).trim();
        if (raw.isEmpty) continue;
        try {
          yield Map<String, dynamic>.from(jsonDecode(raw) as Map);
        } catch (_) {
          // Ignore malformed frames; the function only emits JSON.
        }
      }
    }
  }
  if (buffer.trim().startsWith('data:')) {
    final raw = buffer.trim().substring(5).trim();
    try {
      yield Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {}
  }
}

/// True when the hosted coach can be used right now.
bool remoteCoachAvailable() => BackendConfig.enabled && currentAccessToken() != null;
