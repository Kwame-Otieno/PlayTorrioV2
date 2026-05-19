import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/trakt_service.dart';
import '../api/simkl_service.dart';

/// Lightweight service to track which episodes the user has manually
/// marked as "done watching". Persisted via SharedPreferences so the
/// state is shared across *all* detail screens (torrent & streaming).
///
/// Syncs to Trakt and Simkl when toggling watched state.
class EpisodeWatchedService {
  static final EpisodeWatchedService _instance = EpisodeWatchedService._();
  factory EpisodeWatchedService() => _instance;
  EpisodeWatchedService._();

  static const String _key = 'episodes_watched';

  // In-memory cache: "tmdbId_S{season}_E{episode}" → true
  Map<String, bool>? _cache;

  Future<Map<String, bool>> _load() async {
    if (_cache != null) return _cache!;
    final prefs = await SharedPreferences.getInstance();
    // Guard: value may be a raw Map (wrong type from an older build) or a
    // JSON-encoded String (correct). Use prefs.get() to avoid the cast crash.
    final stored = prefs.get(_key);
    if (stored != null) {
      try {
        Map<String, dynamic> decoded;
        if (stored is String) {
          decoded = json.decode(stored) as Map<String, dynamic>;
        } else if (stored is Map) {
          decoded = Map<String, dynamic>.from(stored);
          // Self-heal: re-write as proper JSON string.
          await prefs.setString(_key, json.encode(decoded));
        } else {
          debugPrint('[EpisodeWatched] Unexpected type ${stored.runtimeType} for $_key, resetting');
          await prefs.remove(_key);
          _cache = {};
          return _cache!;
        }
        _cache = decoded.map((k, v) => MapEntry(k, v == true));
      } catch (e) {
        debugPrint('[EpisodeWatched] Failed to decode $_key: $e — resetting');
        await prefs.remove(_key);
        _cache = {};
      }
    } else {
      _cache = {};
    }
    return _cache!;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, json.encode(_cache));
  }

  String _id(int tmdbId, int season, int episode) =>
      '${tmdbId}_S${season}_E$episode';

  Future<bool> isWatched(int tmdbId, int season, int episode) async {
    final map = await _load();
    return map[_id(tmdbId, season, episode)] == true;
  }

  Future<Set<String>> getWatchedSet(int tmdbId) async {
    final map = await _load();
    return map.keys.where((k) => k.startsWith('${tmdbId}_') && map[k] == true).toSet();
  }

  Future<void> toggle(int tmdbId, int season, int episode) async {
    final map = await _load();
    final id = _id(tmdbId, season, episode);
    final current = map[id] == true;
    map[id] = !current;
    await _save();
    debugPrint('[EpisodeWatched] ${!current ? "Marked" : "Unmarked"} $id');
    // Sync to tracking services in background
    _syncEpisodeState(tmdbId, season, episode, !current);
  }

  Future<void> setWatched(int tmdbId, int season, int episode, bool watched) async {
    final map = await _load();
    final id = _id(tmdbId, season, episode);
    map[id] = watched;
    await _save();
    // Sync to tracking services in background
    _syncEpisodeState(tmdbId, season, episode, watched);
  }

  /// Set watched without triggering external sync (used during import).
  Future<void> setWatchedLocal(int tmdbId, int season, int episode, bool watched) async {
    final map = await _load();
    final id = _id(tmdbId, season, episode);
    map[id] = watched;
    await _save();
  }

  // ── Sync to Trakt & Simkl ──────────────────────────────────────────────
  void _syncEpisodeState(int tmdbId, int season, int episode, bool watched) {
    // Trakt
    TraktService().isLoggedIn().then((loggedIn) {
      if (!loggedIn) return;
      if (watched) {
        TraktService().addToHistory(
          tmdbId: tmdbId,
          mediaType: 'tv',
          season: season,
          episode: episode,
        );
      } else {
        TraktService().removeFromHistory(
          tmdbId: tmdbId,
          mediaType: 'tv',
          season: season,
          episode: episode,
        );
      }
    });

    // Simkl
    SimklService().isLoggedIn().then((loggedIn) {
      if (!loggedIn) return;
      if (watched) {
        SimklService().addToHistory(shows: [
          {
            'ids': {'tmdb': tmdbId},
            'seasons': [
              {
                'number': season,
                'episodes': [
                  {'number': episode}
                ]
              }
            ]
          }
        ]);
      } else {
        SimklService().removeFromHistory(shows: [
          {
            'ids': {'tmdb': tmdbId},
            'seasons': [
              {
                'number': season,
                'episodes': [
                  {'number': episode}
                ]
              }
            ]
          }
        ]);
      }
    });
  }
}
