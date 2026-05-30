# Patches
   # | Fix | File(s) | Date |
 |---|-----|---------|------|
 | 1 | Trakt client ID/secret missing | lib/api/trakt_service.dart | 2026-05-16 |
 | 2 | Trakt token refresh infinite loop | lib/api/trakt_service.dart | 2026-05-16 |
 | 3 | KissKh rate limit crash | lib/api/kisskh_service.dart | 2026-05-16 |
 | 4 | Trakt cache not persisting across restarts | lib/api/trakt_service.dart | 2026-05-16 |
 | 5 | Trakt credentials exposed in repo | lib/api/trakt_service.dart, lib/api/trakt_secrets.dart | 2026-05-16 |
 | 6 | Trakt calendar empty due to timezone | lib/api/trakt_service.dart | 2026-05-17 |
 | 7 | Trakt 401 clears cache and stops loop | lib/api/trakt_service.dart | 2026-05-18 |
 | 8 | Mutex wraps entire _getValidToken() | lib/api/trakt_service.dart | 2026-05-18 |
 | 9 | Simkl credentials moved to local file | lib/api/simkl_service.dart | 2026-05-18 |
 | 10 | Simkl TMDB ID cast fix string vs int | lib/api/simkl_service.dart | 2026-05-18 |
 | 11 | Resolve SharedPreferences type crashes | Multiple Services | 2026-05-19 |
 | 12 | Optimize WebStreamrService | lib/api/web_streamr_service.dart | 2026-05-29 |
 | 13 | Filter 90%+ watched items from history | lib/services/watch_history_service.dart | 2026-05-30 |

---

## Fixes

## Fix 1: Trakt client ID/secret missing
- **File:** lib/api/trakt_service.dart
- **Problem:** Credentials were using String.fromEnvironment() and never injected, causing 403 on all Trakt requests
- **Fix:** Hardcoded client ID and secret directly
- **Date:** 2026-05-16

## Fix 2: Trakt token refresh infinite loop
- **File:** lib/api/trakt_service.dart
- **Problem:** Refresh threshold (7 days) matched token lifetime causing constant refresh loop
- **Fix:** Added _cachedToken, _cachedExpiry fields, _refreshLock mutex, cache check in _getValidToken, changed threshold from 7 days to 1 day
- **Date:** 2026-05-16

## Fix 3: KissKh rate limit crash
- **File:** lib/api/kisskh_service.dart
- **Problem:** _get() returned raw body without checking HTTP status, causing FormatException when KissKh returned plain text 429 response
- **Fix:** Added status code check before parsing, throwing Exception on 429 and non-200 responses
- **Date:** 2026-05-16

## Fix 4: Trakt cache not persisting across restarts
- **File:** lib/api/trakt_service.dart
- **Problem:** _cachedExpiry reset to null on every app start, making in-memory cache useless across launches
- **Fix:** Persisted expiry to SharedPreferences, restored on cold start to skip unnecessary refreshes
- **Date:** 2026-05-16

## Fix 5: Trakt credentials exposed in repo
- **File:** lib/api/trakt_service.dart, lib/api/trakt_secrets.dart
- **Problem:** Real Trakt client ID and secret were hardcoded directly in trakt_service.dart and committed to the public repo, exposing credentials
- **Fix:** Moved credentials to a git-ignored file lib/api/trakt_secrets.local.dart, added a safe template file lib/api/trakt_secrets.dart with dummy values, imported secrets file in trakt_service.dart, purged old credentials from git history with git filter-branch
- **Date:** 2026-05-16

## Fix 6: Trakt calendar empty due to timezone
- **File:** lib/api/trakt_service.dart
- **Problem:** Calendar API was using UTC date but my timezone is different this made some episodes to be missed
- **Fix:** Changed startDate to use local date instead of UTC so it works correctly regardless of timezone
- **Date:** 2026-05-17

## Fix 7: Trakt 401 clears cache and stops loop
- **File:** lib/api/trakt_service.dart
- **Problem:** When Trakt returned 401 on token refresh the app kept retrying forever since the invalid token was never cleared
- **Fix:** Added 401 check in _refreshToken() to immediately clear all tokens, cache fields and SharedPreferences expiry on revocation
- **Date:** 2026-05-18

## Fix 8: Mutex wraps entire _getValidToken()
- **File:** lib/api/trakt_service.dart
- **Problem:** Multiple async calls hit _getValidToken() simultaneously before cache was populated, causing parallel refresh requests that triggered Trakt rate limiting
- **Fix:** Wrapped the entire _getValidToken() method in _refreshLock.synchronized() so only one call executes at a time and the rest wait for the cached result
- **Date:** 2026-05-18

## Fix 9: Simkl credentials moved to local file
- **File:** lib/api/simkl_service.dart
- **Problem:** Simkl client ID and secret were using String.fromEnvironment() and never injected at build time, causing 403 on all Simkl login attempts
- **Fix:** Moved credentials to git-ignored lib/api/simkl_secrets.local.dart, added safe template simkl_secrets.dart, imported in simkl_service.dart
- **Date:** 2026-05-18

## Fix 10: Simkl TMDB ID cast crash
- **File:** lib/api/simkl_service.dart
- **Problem:** Simkl API returns TMDB IDs as strings but code was casting directly to int? causing a type cast crash on watchlist import
- **Fix:** Changed cast to handle both string and int formats using int.tryParse() as fallback
- **Date:** 2026-05-18

## Fix 11: Resolve SharedPreferences type crashes, Trakt sync loop, watchlist duplicates, and null remove crash
- **File:** Multiple Services
- **Problem:** Various runtime crashes and synchronization errors related to SharedPreferences type casting, Trakt rate limiting, and null safety.
- **Fix:** - **my_list_service:** Implemented safe preference reads, addMovieSilent(), and TMDB ID deduplication.
    - **episode_watched_service:** Enabled safe preference reads for the episodes_watched Map.
    - **watch_history_service:** Created a _safeGetString() helper for consistent preference access.
    - **trakt_service:** Added exponential backoff for 429 errors, corrected episode/expiry preference reads, implemented addMovieSilent() for imports, and fixed description syntax errors.
    - **my_list_screen:** Added null-safe unique ID derivation for removals and a safe UNDO handler.
- **Date:** 2026-05-19

## Fix 12: Optimize WebStreamrService
- **File:** lib/api/web_streamr_service.dart
- **Problem:** Efficiency and reliability issues during stream processing.
- **Fix:** Prioritized 1080p sources, implemented a blacklist for broken sources, and added timeout configurations.
- **Date:** 2026-05-29

## Fix 13: Filter 90%+ watched items from history
- **File:** lib/services/watch_history_service.dart
- **Problem:** Items at 90% or more completion were still appearing in the watch history, cluttering the list with effectively watched content.
- **Fix:** Added automatic filtering in `getHistory()` to exclude items where `position/duration >= 90%` using integer arithmetic (`position * 10 >= duration * 9`). Updated `saveProgress()` and `removeItem()` to use the filtered history via `getHistory()` instead of raw SharedPreferences data, ensuring `current` and `historyStream` always return the filtered list. Progress data remains preserved in SharedPreferences for non-destructive filtering, allowing items to reappear if resumed at <90%.
- **Date:** 2026-05-30