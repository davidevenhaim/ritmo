import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import 'models.dart';
import 'social_backend.dart';

/// A clip chosen from the camera roll, measured before upload.
class PickedClip {
  const PickedClip({required this.name, required this.bytes, required this.duration, this.mimeType = 'video/mp4', this.path});
  final String name;
  final Uint8List bytes;
  final Duration duration;
  final String mimeType;
  final String? path;

  bool get tooLong => duration.inMilliseconds > Video.maxSeconds * 1000 + 500;
  double get seconds => duration.inMilliseconds / 1000;
}

class ClipTooLong implements Exception {
  const ClipTooLong(this.seconds);
  final double seconds;
  @override
  String toString() => 'Clips are capped at ${Video.maxSeconds} seconds; this one is ${seconds.toStringAsFixed(0)}s. Trim it and try again.';
}

class UploadRejected implements Exception {
  const UploadRejected(this.message, {this.code});
  final String message;
  final String? code;
  @override
  String toString() => message;
}

/// Opens the gallery, reads the file and measures it. Returns null when the
/// user cancels. Throws [ClipTooLong] over the cap.
Future<PickedClip?> pickClip() async {
  final picker = ImagePicker();
  final file = await picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: Video.maxSeconds));
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  final duration = await measureDuration(file);
  final clip = PickedClip(
    name: file.name.isEmpty ? 'clip.mp4' : file.name,
    bytes: bytes,
    duration: duration,
    mimeType: file.mimeType ?? 'video/mp4',
    path: file.path,
  );
  if (clip.tooLong) throw ClipTooLong(clip.seconds);
  return clip;
}

/// Duration through the platform player. The gallery cap only applies to
/// camera captures, so this is the real gate before any bytes leave the device.
Future<Duration> measureDuration(XFile file) async {
  final controller = kIsWeb ? VideoPlayerController.networkUrl(Uri.parse(file.path)) : VideoPlayerController.file(File(file.path));
  try {
    await controller.initialize().timeout(const Duration(seconds: 15));
    return controller.value.duration;
  } catch (_) {
    return Duration.zero; // unknown; the server checks again after transcoding
  } finally {
    await controller.dispose();
  }
}

/// Puts a clip somewhere it can play from. The hosted uploader talks to the
/// `video` edge function and then to Cloudflare Stream or Mux directly.
abstract class VideoUploader {
  Future<Video> upload(PickedClip clip, {required String authorId, List<String> exerciseIds = const [], void Function(double)? onProgress});
}

/// Demo: no bytes move. The clip becomes a placeholder video that turns ready
/// after a short "transcode" so the processing state is visible in the feed.
class DemoVideoUploader implements VideoUploader {
  DemoVideoUploader({this.processing = const Duration(seconds: 4)});
  final Duration processing;

  static const demoClip = 'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4';

  @override
  Future<Video> upload(PickedClip clip, {required String authorId, List<String> exerciseIds = const [], void Function(double)? onProgress}) async {
    if (clip.tooLong) throw ClipTooLong(clip.seconds);
    for (var i = 1; i <= 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      onProgress?.call(i / 5);
    }
    return Video(
      id: newUuid(),
      authorId: authorId,
      status: VideoStatus.processing,
      durationSec: clip.seconds == 0 ? null : clip.seconds,
      exerciseIds: exerciseIds,
      width: 16,
      height: 9,
    );
  }
}

class HostedVideoUploader implements VideoUploader {
  HostedVideoUploader({required this.endpoint, required this.accessToken, required this.apiKey, http.Client? client}) : _client = client ?? http.Client();
  final String endpoint;
  final String accessToken;
  final String apiKey;
  final http.Client _client;

  Map<String, String> get _auth => {'Authorization': 'Bearer $accessToken', 'apikey': apiKey, 'Content-Type': 'application/json'};

  @override
  Future<Video> upload(PickedClip clip, {required String authorId, List<String> exerciseIds = const [], void Function(double)? onProgress}) async {
    if (clip.tooLong) throw ClipTooLong(clip.seconds);
    onProgress?.call(0.02);
    final res = await _client.post(
      Uri.parse('$endpoint/create'),
      headers: _auth,
      body: jsonEncode({'filename': clip.name, 'duration_sec': clip.seconds, 'exercise_ids': exerciseIds}),
    );
    final body = _json(res);
    if (res.statusCode != 200) throw UploadRejected(body['error']?.toString() ?? 'Upload refused (${res.statusCode})', code: body['code']?.toString());
    final ticket = UploadTicket.fromJson(body);
    onProgress?.call(0.1);

    final ok = await sendBytes(_client, ticket, clip, onProgress: (p) => onProgress?.call(0.1 + 0.85 * p));
    if (!ok) throw const UploadRejected('The video host rejected the file');
    onProgress?.call(1);
    return Video(
      id: ticket.videoId,
      authorId: authorId,
      status: VideoStatus.processing,
      durationSec: clip.seconds == 0 ? null : clip.seconds,
      exerciseIds: exerciseIds,
    );
  }

  /// Cloudflare wants a multipart form with a `file` field; Mux wants the raw
  /// body on a PUT. Progress is coarse because `http` does not stream uploads.
  static Future<bool> sendBytes(http.Client client, UploadTicket ticket, PickedClip clip, {void Function(double)? onProgress}) async {
    onProgress?.call(0.05);
    http.BaseResponse res;
    if (ticket.method == 'put') {
      res = await client.put(Uri.parse(ticket.uploadUrl), headers: {'Content-Type': clip.mimeType}, body: clip.bytes);
    } else {
      final req = http.MultipartRequest('POST', Uri.parse(ticket.uploadUrl))
        ..files.add(http.MultipartFile.fromBytes('file', clip.bytes, filename: clip.name));
      res = await client.send(req);
    }
    onProgress?.call(1);
    return res.statusCode >= 200 && res.statusCode < 300;
  }

  Future<void> delete(String videoId) async {
    await _client.post(Uri.parse('$endpoint/delete'), headers: _auth, body: jsonEncode({'video_id': videoId}));
  }

  static Map<String, dynamic> _json(http.Response r) {
    try {
      return Map<String, dynamic>.from(jsonDecode(r.body) as Map);
    } catch (_) {
      return {'error': r.body};
    }
  }
}

/// What `/video/create` hands back.
class UploadTicket {
  const UploadTicket({required this.videoId, required this.uploadUrl, required this.method, required this.provider});
  final String videoId;
  final String uploadUrl;
  final String method; // form | put
  final String provider;

  factory UploadTicket.fromJson(Map<String, dynamic> j) => UploadTicket(
        videoId: j['video_id'] as String,
        uploadUrl: j['upload_url'] as String,
        method: (j['method'] ?? 'form') as String,
        provider: (j['provider'] ?? 'cloudflare') as String,
      );
}
