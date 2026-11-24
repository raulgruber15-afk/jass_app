import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../engine/rating.dart';

/// Speichert Einstellungen und das laufende Spiel nur auf dem Gerät.
class Storage {
  static const _gameKey = 'laufendes_spiel_v1';
  static const _settingsKey = 'einstellungen_v1';
  static const _statsKey = 'statistik_v1';
  static const _soloRatingKey = 'wertung_allein_v1';

  static Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null; // z. B. im Browser ohne Speicher: dann eben ohne
    }
  }

  static Future<Map<String, dynamic>?> _read(String key) async {
    final p = await _prefs();
    final raw = p?.getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      await p?.remove(key); // kaputter Spielstand: verwerfen statt abstürzen
      return null;
    }
  }

  static Future<void> _write(String key, Map<String, dynamic>? value) async {
    final p = await _prefs();
    if (p == null) return;
    if (value == null) {
      await p.remove(key);
    } else {
      await p.setString(key, jsonEncode(value));
    }
  }

  static Future<Map<String, dynamic>?> loadGame() => _read(_gameKey);
  static Future<void> saveGame(Map<String, dynamic> snapshot) =>
      _write(_gameKey, snapshot);
  static Future<void> clearGame() => _write(_gameKey, null);

  static Future<Map<String, dynamic>?> loadSettings() => _read(_settingsKey);
  static Future<void> saveSettings(Map<String, dynamic> s) =>
      _write(_settingsKey, s);

  /// Bilanz allein gegen den Computer, je Stufe: {stufe: [gewonnen, verloren]}.
  static Future<Map<String, List<int>>> loadStats() async {
    final raw = await _read(_statsKey) ?? {};
    final out = <String, List<int>>{};
    raw.forEach((k, v) {
      try {
        final l = (v as List).cast<int>();
        if (l.length == 2) out[k] = l;
      } catch (_) {}
    });
    return out;
  }

  static Future<void> recordResult(String level, {required bool won}) async {
    final stats = await loadStats();
    final l = stats[level] ?? [0, 0];
    l[won ? 0 : 1]++;
    stats[level] = l;
    await _write(_statsKey, stats);
  }

  /// Jass-Wertung allein gegen den Computer.
  static Future<SoloRating> loadSoloRating() async {
    final raw = await _read(_soloRatingKey);
    if (raw == null) return const SoloRating();
    try {
      return SoloRating.fromJson(raw);
    } catch (_) {
      return const SoloRating();
    }
  }

  static Future<void> saveSoloRating(SoloRating r) =>
      _write(_soloRatingKey, r.toJson());
}
