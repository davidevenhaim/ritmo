import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'models.dart';
import 'session_theme.dart';

/// Offline catalogue: 1,443 exercises merged from free-exercise-db
/// (Unlicense), RepDB, yoga-api and 36 written in-house, bundled as an asset
/// so search works without a network. Every row is graded beginner /
/// intermediate / advanced — see `tool/build_catalogue.py`.
class ExerciseRepository {
  ExerciseRepository(this._all) : _byId = {for (final e in _all) e.id: e};

  final List<Exercise> _all;
  final Map<String, Exercise> _byId;

  List<Exercise> get all => _all;
  Exercise? byId(String id) => _byId[id];

  static Future<ExerciseRepository> load() async {
    final raw = await rootBundle.loadString('assets/data/exercises.json');
    final list = (jsonDecode(raw) as List)
        .map((e) => Exercise.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return ExerciseRepository(list);
  }

  List<String> get muscles {
    final s = <String>{};
    for (final e in _all) {
      s.addAll(e.primary);
    }
    return s.toList()..sort();
  }

  List<String> get equipmentTypes {
    final s = <String>{for (final e in _all) e.equipment};
    return s.toList()..sort();
  }

  List<String> get categories {
    final s = <String>{for (final e in _all) e.category};
    return s.toList()..sort();
  }

  /// Every exercise in a theme, compound work first (Nocturne builder).
  List<Exercise> forTheme(
    SessionTheme theme, {
    String query = '',
    List<String>? allowedEquipment,
    ExerciseLevel? level,
    int limit = 400,
  }) {
    final q = query.trim().toLowerCase();
    final out = <Exercise>[];
    for (final e in _all) {
      if (!theme.has(e)) continue;
      if (level != null && ExerciseLevel.of(e.level) != level) continue;
      if (allowedEquipment != null &&
          allowedEquipment.isNotEmpty &&
          !allowedEquipment.contains(e.equipment) &&
          e.equipment != 'none' &&
          e.equipment != 'other') {
        continue;
      }
      if (q.isNotEmpty && !'${e.name} ${e.primary.join(' ')} ${e.equipment}'.toLowerCase().contains(q)) continue;
      out.add(e);
    }
    out.sort((a, b) {
      final ra = SessionTheme.rank(a);
      final rb = SessionTheme.rank(b);
      return ra != rb ? ra - rb : a.name.compareTo(b.name);
    });
    return out.take(limit).toList();
  }

  /// How many exercises a theme card should claim.
  int countFor(SessionTheme theme) => _all.where(theme.has).length;

  /// How the theme's library splits across the three grades, for the chips
  /// over the builder's library.
  Map<ExerciseLevel, int> levelCounts(SessionTheme theme, {List<String>? allowedEquipment}) {
    final out = {for (final l in ExerciseLevel.values) l: 0};
    for (final e in forTheme(theme, allowedEquipment: allowedEquipment, limit: 1 << 20)) {
      final l = ExerciseLevel.of(e.level);
      if (l != null) out[l] = out[l]! + 1;
    }
    return out;
  }

  List<Exercise> search({
    String query = '',
    String? muscle,
    String? equipment,
    String? category,
    String? level,
    List<String>? allowedEquipment,
    int limit = 200,
  }) {
    final q = query.trim().toLowerCase();
    final out = <Exercise>[];
    for (final e in _all) {
      if (muscle != null && !e.primary.contains(muscle) && !e.secondary.contains(muscle)) continue;
      if (equipment != null && e.equipment != equipment) continue;
      if (category != null && e.category != category) continue;
      if (level != null && e.level != level) continue;
      if (allowedEquipment != null &&
          allowedEquipment.isNotEmpty &&
          !allowedEquipment.contains(e.equipment) &&
          e.equipment != 'none' &&
          e.equipment != 'other') {
        continue;
      }
      if (q.isNotEmpty) {
        final hay = '${e.name} ${e.primary.join(' ')} ${e.equipment} ${e.category}'.toLowerCase();
        if (!hay.contains(q)) continue;
      }
      out.add(e);
      if (out.length >= limit) break;
    }
    if (q.isNotEmpty) {
      // Names that start with the query first.
      out.sort((a, b) {
        final sa = a.name.toLowerCase().startsWith(q) ? 0 : 1;
        final sb = b.name.toLowerCase().startsWith(q) ? 0 : 1;
        return sa != sb ? sa.compareTo(sb) : a.name.compareTo(b.name);
      });
    }
    return out;
  }
}

/// Live community exercises from wger (AGPL, https://wger.de). Read-only browse
/// of the public API; a nightly sync into our own DB is on the roadmap.
class WgerClient {
  WgerClient({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static const _base = 'https://wger.de/api/v2';

  Future<List<Exercise>> fetchPage({int offset = 0, int limit = 20}) async {
    final uri = Uri.parse('$_base/exerciseinfo/?language=2&limit=$limit&offset=$offset');
    final res = await _client.get(uri, headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('wger returned ${res.statusCode}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final results = json['results'] as List;
    final out = <Exercise>[];
    for (final r in results) {
      final m = Map<String, dynamic>.from(r as Map);
      final translations = (m['translations'] as List? ?? const []);
      final en = translations.cast<Map>().where((t) => t['language'] == 2).firstOrNull ??
          (translations.isNotEmpty ? translations.first as Map : null);
      if (en == null) continue;
      final name = (en['name'] as String? ?? '').trim();
      if (name.isEmpty) continue;
      final desc = _stripHtml(en['description'] as String? ?? '');
      final images = (m['images'] as List? ?? const [])
          .map((i) => (i as Map)['image'] as String? ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      final muscles = (m['muscles'] as List? ?? const [])
          .map((mu) => ((mu as Map)['name_en'] as String? ?? '').toLowerCase())
          .where((s) => s.isNotEmpty)
          .toList();
      final equipment = (m['equipment'] as List? ?? const [])
          .map((e) => ((e as Map)['name'] as String? ?? '').toLowerCase())
          .firstOrNull;
      out.add(Exercise(
        id: 'wger_${m['id']}',
        name: name,
        category: ((m['category'] as Map?)?['name'] as String? ?? 'strength').toLowerCase(),
        equipment: equipment ?? 'none',
        primary: muscles,
        secondary: const [],
        instructions: desc.isEmpty ? const [] : [desc],
        images: images,
        source: 'wger',
      ));
    }
    return out;
  }

  static String _stripHtml(String s) =>
      s.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}
