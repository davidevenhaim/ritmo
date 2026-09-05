import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Thin JSON persistence layer. In the MVP everything lives on-device;
/// the repositories are written so a Supabase/Firestore backend can be
/// swapped in without touching the UI.
class LocalStore {
  LocalStore(this._prefs);
  final SharedPreferences _prefs;

  static Future<LocalStore> open() async => LocalStore(await SharedPreferences.getInstance());

  Map<String, dynamic>? getMap(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  List<Map<String, dynamic>> getList(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> put(String key, Object value) => _prefs.setString(key, jsonEncode(value));
  String? getString(String key) => _prefs.getString(key);
  Future<void> putString(String key, String value) => _prefs.setString(key, value);
  Future<void> remove(String key) => _prefs.remove(key);
  Future<void> clear() => _prefs.clear();
}
