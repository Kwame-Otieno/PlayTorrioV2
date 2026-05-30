import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WatchHistoryService {
  static final WatchHistoryService _instance = WatchHistoryService._internal();
  factory WatchHistoryService() => _instance;

  WatchHistoryService._internal() {
    _init();
  }

  static const String _key = 'watch_history';
  static const String _dismissedKey = 'dismissed_history';
  final _controller = StreamController<List<Map<String, dynamic>>>.broadcast();
  List<Map<String, dynamic>> _current = [];

  Stream<List<Map<String, dynamic>>> get historyStream => _controller.stream;
  List<Map<String, dynamic>> get current => _current;

  Future<void> _init() async {
    _current = await getHistory();
    _controller.add(_current);
  }

  // Save progress
  Future<void> saveProgress({
    required int tmdbId,
    String? imdbId,
    required String title,
    required String posterPath,
    required String method,
    required String sourceId,
    required int position,
    required int duration,
    int? season,
    int? episode,
    String? episodeTitle,
    String? magnetLink,
    int? fileIndex,
    String? streamUrl,
    String? stremioId,
    String? stremioAddonBaseUrl,
    String? stremioType,
    String? mediaType,
  }) async {
    final String uniqueId = season != null && episode != null
    ? '${tmdbId}_S${season}_E$episode'
    : '$tmdbId';

    final entry = {
      'uniqueId': uniqueId,
      'tmdbId': tmdbId,
      'imdbId': imdbId,
      'title': title,
      'posterPath': posterPath,
      'method': method,
      'sourceId': sourceId,
      'position': position,
      'duration': duration,
      'season': season,
      'episode': episode,
      'episodeTitle': episodeTitle,
      'magnetLink': magnetLink,
      'fileIndex': fileIndex,
      'streamUrl': streamUrl,
      'stremioId': stremioId,
      'stremioAddonBaseUrl': stremioAddonBaseUrl,
      'stremioType': stremioType,
      'mediaType': mediaType,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonString = await _safeGetString(prefs, _key);
      List<dynamic> list = jsonString != null ? json.decode(jsonString) : [];

      list.removeWhere((item) => item['uniqueId'] == uniqueId);
      list.insert(0, entry);

      if (list.length > 50) {
        list = list.sublist(0, 50);
      }

      await prefs.setString(_key, json.encode(list));

      final String? dismissedJson = await _safeGetString(prefs, _dismissedKey);
      if (dismissedJson != null) {
        List<dynamic> dismissedList = json.decode(dismissedJson);
        if (dismissedList.contains(uniqueId)) {
          dismissedList.remove(uniqueId);
          await prefs.setString(_dismissedKey, json.encode(dismissedList));
          debugPrint('[WatchHistory] Removed $uniqueId from dismissed list (re-watching)');
        }
      }

      debugPrint('[WatchHistory] Saved progress for $title ($uniqueId) at $position ms');
      debugPrint('[WatchHistory] Method: $method, MagnetLink: ${magnetLink?.substring(0, 50)}..., FileIndex: $fileIndex');

      // ✅ FIX: Use filtered history
      _current = await getHistory();
      _controller.add(_current);
    } catch (e) {
      debugPrint('[WatchHistory] Error saving progress: $e');
    }
  }

  // Get all history - filters out 90%+ watched items
  Future<List<Map<String, dynamic>>> getHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonString = await _safeGetString(prefs, _key);
      if (jsonString == null) return [];

      final List<dynamic> list = json.decode(jsonString);
      final history = list.cast<Map<String, dynamic>>();

      // Filter out items that are 90%+ watched
      return history.where((item) {
        final position = item['position'] as int? ?? 0;
        final duration = item['duration'] as int? ?? 1;
        return duration <= 0 || position * 10 < duration * 9;
      }).toList();
    } catch (e) {
      debugPrint('[WatchHistory] Error fetching history: $e');
      return [];
    }
  }

  // Get specific item progress
  Future<Map<String, dynamic>?> getProgress(int tmdbId, {int? season, int? episode}) async {
    final String uniqueId = season != null && episode != null
    ? '${tmdbId}_S${season}_E$episode'
    : '$tmdbId';

    try {
      final history = await getHistory();
      final match = history.firstWhere(
        (item) => item['uniqueId'] == uniqueId,
        orElse: () => {},
      );
      return match.isNotEmpty ? match : null;
    } catch (e) {
      return null;
    }
  }

  // Remove item
  Future<void> removeItem(String uniqueId) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final String? jsonString = await _safeGetString(prefs, _key);
      if (jsonString != null) {
        List<dynamic> list = json.decode(jsonString);
        list.removeWhere((item) => item['uniqueId'] == uniqueId);
        await prefs.setString(_key, json.encode(list));

        // ✅ FIX: Use filtered history
        _current = await getHistory();
        _controller.add(_current);
      }

      final String? dismissedJson = await _safeGetString(prefs, _dismissedKey);
      List<dynamic> dismissedList = dismissedJson != null ? json.decode(dismissedJson) : [];
      if (!dismissedList.contains(uniqueId)) {
        dismissedList.add(uniqueId);
        if (dismissedList.length > 100) {
          dismissedList = dismissedList.sublist(dismissedList.length - 100);
        }
        await prefs.setString(_dismissedKey, json.encode(dismissedList));
        debugPrint('[WatchHistory] Added $uniqueId to dismissed list');
      }
    } catch (e) {
      debugPrint('[WatchHistory] Error removing item: $e');
    }
  }

  // Check if item is dismissed
  Future<bool> isDismissed(String uniqueId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonString = await _safeGetString(prefs, _dismissedKey);
      if (jsonString == null) return false;
      final List<dynamic> list = json.decode(jsonString);
      return list.contains(uniqueId);
    } catch (e) {
      return false;
    }
  }

  Future<String?> _safeGetString(SharedPreferences prefs, String key) async {
    final stored = prefs.get(key);
    if (stored == null) return null;
    if (stored is String) return stored;
    debugPrint('[WatchHistory] Key "$key" has unexpected type ${stored.runtimeType}, clearing');
    await prefs.remove(key);
    return null;
  }

  void dispose() {
    _controller.close();
  }
}


