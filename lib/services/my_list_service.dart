import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/trakt_service.dart';
import '../api/simkl_service.dart';

/// Persisted "My List" service — stores movies & shows the user bookmarks.
/// Works with both TMDB [Movie] objects and Stremio catalog Map items.
///
/// Each entry is a JSON map with a unified shape:
///   {
///     "uniqueId":    "tmdb_12345"  |  "stremio_tt12345"  |  "custom_...",
///     "tmdbId":      12345         |  null,
///     "imdbId":      "tt12345"     |  null,
///     "title":       "...",
///     "posterPath":  "...",        // relative TMDB path or full URL
///     "mediaType":   "movie" | "tv" | "series",
///     "voteAverage": 7.5,
///     "releaseDate": "2025-01-01",
///     "source":      "tmdb" | "stremio",
///     "stremioType": "movie" | "series" | null,
///     "addedAt":     1700000000000 (epoch ms),
///   }
class MyListService {
  // ── Singleton ──────────────────────────────────────────────────────────
  static final MyListService _instance = MyListService._internal();
  factory MyListService() => _instance;
  MyListService._internal() { _init(); }

  static const String _key = 'my_list_items';

  final _controller = StreamController<List<Map<String, dynamic>>>.broadcast();
  List<Map<String, dynamic>> _items = [];
  bool _loaded = false;

  /// Reactive stream of the current list.
  Stream<List<Map<String, dynamic>>> get stream => _controller.stream;

  /// Synchronous snapshot (empty until first load finishes).
  List<Map<String, dynamic>> get items => List.unmodifiable(_items);

  /// Change notifier that widgets can listen to for rebuilds.
  static final ValueNotifier<int> changeNotifier = ValueNotifier<int>(0);

  // ── Init ───────────────────────────────────────────────────────────────
  Future<void> _init() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();

    // Guard: value may be a raw List (wrong type from an older build) or a
    // JSON-encoded String (correct). Use prefs.get() to avoid the cast crash.
    final stored = prefs.get(_key);
    if (stored != null) {
      try {
        List<dynamic> decoded;
        if (stored is String) {
          decoded = json.decode(stored) as List<dynamic>;
        } else if (stored is List) {
          decoded = stored;
          // Self-heal: rewrite as JSON string so future reads work correctly.
          await prefs.setString(_key, json.encode(decoded));
        } else {
          debugPrint('[MyList] Unexpected type ${stored.runtimeType} for $_key, resetting');
          await prefs.remove(_key);
          _items = [];
          _loaded = true;
          _notify();
          return;
        }
        _items = List<Map<String, dynamic>>.from(
          decoded.map((e) => Map<String, dynamic>.from(e as Map)),
        );
      } catch (e) {
        debugPrint('[MyList] Failed to decode: $e');
        _items = [];
      }
    }

    _loaded = true;
    // Remove duplicates introduced by Trakt import sync-back, and self-heal
    // any items missing a uniqueId.
    await deduplicateByTmdbId();
    _notify();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, json.encode(_items));
    _notify();
  }

  void _notify() {
    _controller.add(List.unmodifiable(_items));
    changeNotifier.value++;
  }

  // ── Unique ID helpers ──────────────────────────────────────────────────
  /// Build a unique ID from a TMDB Movie.
  static String movieId(int tmdbId, String mediaType) => 'tmdb_${mediaType}_$tmdbId';

  /// Build a unique ID from a Stremio catalog item Map.
  static String stremioItemId(Map<String, dynamic> item) {
    final id = item['imdb_id']?.toString() ??
        item['imdbId']?.toString() ??
        item['id']?.toString() ??
        item['name']?.toString() ??
        '';
    final type = item['type']?.toString() ?? 'unknown';
    return 'stremio_${type}_$id';
  }

  // ── Public API ─────────────────────────────────────────────────────────

  /// Whether the given unique ID is already in the list.
  bool contains(String uniqueId) {
    return _items.any((e) => e['uniqueId'] == uniqueId);
  }

  /// Add a TMDB Movie to the list and sync to Trakt/Simkl. No-op if already present.
  Future<void> addMovie({
    required int tmdbId,
    String? imdbId,
    required String title,
    required String posterPath,
    required String mediaType,
    double voteAverage = 0,
    String releaseDate = '',
  }) async {
    await _ensureLoaded();
    final uid = movieId(tmdbId, mediaType);
    if (contains(uid)) return;
    _items.insert(0, {
      'uniqueId': uid,
      'tmdbId': tmdbId,
      'imdbId': imdbId,
      'title': title,
      'posterPath': posterPath,
      'mediaType': mediaType,
      'voteAverage': voteAverage,
      'releaseDate': releaseDate,
      'source': 'tmdb',
      'addedAt': DateTime.now().millisecondsSinceEpoch,
    });
    await _save();
    _traktAdd(tmdbId, imdbId, mediaType);
  }

  /// Same as [addMovie] but does NOT push back to Trakt/Simkl.
  /// Use this when importing items that already originated from those services
  /// to avoid creating duplicates on the remote side.
  Future<void> addMovieSilent({
    required int tmdbId,
    String? imdbId,
    required String title,
    required String posterPath,
    required String mediaType,
    double voteAverage = 0,
    String releaseDate = '',
  }) async {
    await _ensureLoaded();
    final uid = movieId(tmdbId, mediaType);
    if (contains(uid)) return;
    _items.insert(0, {
      'uniqueId': uid,
      'tmdbId': tmdbId,
      'imdbId': imdbId,
      'title': title,
      'posterPath': posterPath,
      'mediaType': mediaType,
      'voteAverage': voteAverage,
      'releaseDate': releaseDate,
      'source': 'tmdb',
      'addedAt': DateTime.now().millisecondsSinceEpoch,
    });
    await _save();
    // No remote sync — item already exists on Trakt/Simkl.
  }

  /// Add a Stremio catalog item (Map) to the list.
  Future<void> addStremioItem(Map<String, dynamic> item) async {
    await _ensureLoaded();
    final uid = stremioItemId(item);
    if (contains(uid)) return;
    _items.insert(0, {
      'uniqueId': uid,
      'tmdbId': null,
      'imdbId': item['imdb_id'] ?? item['imdbId'] ?? item['id'],
      'title': item['name']?.toString() ?? 'Unknown',
      'posterPath': item['poster']?.toString() ?? '',
      'mediaType': item['type']?.toString() ?? 'movie',
      'voteAverage': double.tryParse(item['imdbRating']?.toString() ?? '') ?? 0,
      'releaseDate': item['releaseInfo']?.toString() ?? '',
      'source': 'stremio',
      'stremioType': item['type']?.toString(),
      'addedAt': DateTime.now().millisecondsSinceEpoch,
    });
    await _save();
    final imdb = item['imdb_id']?.toString() ?? item['imdbId']?.toString();
    _traktAdd(null, imdb, item['type']?.toString() ?? 'movie');
  }

  /// Remove by unique ID.
  Future<void> remove(String uniqueId) async {
    await _ensureLoaded();
    final item = _items.cast<Map<String, dynamic>?>().firstWhere(
      (e) => e?['uniqueId'] == uniqueId,
      orElse: () => null,
    );
    final tmdbId = item?['tmdbId'] as int?;
    final imdbId = item?['imdbId']?.toString();
    final mediaType = item?['mediaType']?.toString() ?? 'movie';
    _items.removeWhere((e) => e['uniqueId'] == uniqueId);
    await _save();
    _traktRemove(tmdbId, imdbId, mediaType);
  }

  /// Toggle: add if missing, remove if present. Returns true if now in list.
  Future<bool> toggleMovie({
    required int tmdbId,
    String? imdbId,
    required String title,
    required String posterPath,
    required String mediaType,
    double voteAverage = 0,
    String releaseDate = '',
  }) async {
    final uid = movieId(tmdbId, mediaType);
    if (contains(uid)) {
      await remove(uid);
      return false;
    } else {
      await addMovie(
        tmdbId: tmdbId,
        imdbId: imdbId,
        title: title,
        posterPath: posterPath,
        mediaType: mediaType,
        voteAverage: voteAverage,
        releaseDate: releaseDate,
      );
      return true;
    }
  }

  /// Toggle a Stremio item. Returns true if now in list.
  Future<bool> toggleStremioItem(Map<String, dynamic> item) async {
    final uid = stremioItemId(item);
    if (contains(uid)) {
      await remove(uid);
      return false;
    } else {
      await addStremioItem(item);
      return true;
    }
  }

  /// Remove duplicate entries for the same tmdbId+mediaType, keeping the one
  /// added most recently (highest addedAt). Also self-heals items missing a
  /// uniqueId by deriving it from tmdbId+mediaType.
  Future<int> deduplicateByTmdbId() async {
    final before = _items.length;

    // Self-heal missing uniqueIds.
    for (final item in _items) {
      if (item['uniqueId'] == null) {
        final tmdbId = item['tmdbId'] as int?;
        final mediaType = item['mediaType']?.toString() ?? 'movie';
        if (tmdbId != null) {
          item['uniqueId'] = movieId(tmdbId, mediaType);
        }
      }
    }

    // Group by (tmdbId, mediaType). Keep the entry with the highest addedAt.
    final seen = <String, Map<String, dynamic>>{};
    for (final item in _items) {
      final tmdbId = item['tmdbId'] as int?;
      if (tmdbId == null) continue;
      final mediaType = item['mediaType']?.toString() ?? 'movie';
      final key = '${tmdbId}_$mediaType';
      final existing = seen[key];
      if (existing == null) {
        seen[key] = item;
      } else {
        final existingAt = existing['addedAt'] as int? ?? 0;
        final thisAt = item['addedAt'] as int? ?? 0;
        if (thisAt > existingAt) seen[key] = item;
      }
    }

    // Rebuild: deduped TMDB items + Stremio-only items (no tmdbId).
    final noTmdb = _items.where((e) => e['tmdbId'] == null).toList();
    _items = [...seen.values.toList(), ...noTmdb];

    final removed = before - _items.length;
    if (removed > 0) {
      await _save();
      debugPrint('[MyList] Deduplicated $removed duplicate entries');
    }
    return removed;
  }

  Future<void> _ensureLoaded() async {
    if (!_loaded) await _init();
  }

  // ── Trakt & Simkl background sync ─────────────────────────────────────
  void _traktAdd(int? tmdbId, String? imdbId, String mediaType) {
    if (tmdbId == null && imdbId == null) return;
    TraktService().isLoggedIn().then((loggedIn) {
      if (loggedIn) {
        TraktService().addToWatchlist(
          tmdbId: tmdbId,
          imdbId: imdbId,
          mediaType: mediaType,
        );
      }
    });
    SimklService().isLoggedIn().then((loggedIn) {
      if (loggedIn) {
        SimklService().addToWatchlist(
          tmdbId: tmdbId,
          imdbId: imdbId,
          mediaType: mediaType,
        );
      }
    });
  }

  void _traktRemove(int? tmdbId, String? imdbId, String mediaType) {
    if (tmdbId == null && imdbId == null) return;
    TraktService().isLoggedIn().then((loggedIn) {
      if (loggedIn) {
        TraktService().removeFromWatchlist(
          tmdbId: tmdbId,
          imdbId: imdbId,
          mediaType: mediaType,
        );
      }
    });
    SimklService().isLoggedIn().then((loggedIn) {
      if (loggedIn) {
        SimklService().removeFromWatchlist(
          tmdbId: tmdbId,
          imdbId: imdbId,
          mediaType: mediaType,
        );
      }
    });
  }
}
