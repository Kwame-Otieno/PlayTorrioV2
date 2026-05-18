# Patches

| # | Fix | File(s) | Date |
|---|-----|---------|------|
| 1 | Trakt client ID/secret missing | lib/api/trakt_service.dart | 2026-05-16 |
| 2 | Trakt token refresh infinite loop | lib/api/trakt_service.dart | 2026-05-16 |
| 3 | KissKh rate limit crash | lib/api/kisskh_service.dart | 2026-05-16 |
| 4 | Trakt cache not persisting across restarts | lib/api/trakt_service.dart | 2026-05-16 |
| 5 | Trakt credentials exposed in repo | lib/api/trakt_service.dart, lib/api/trakt_secrets.dart | 2026-05-16 |
| 6 | Trakt calendar empty due to timezone | lib/api/trakt_service.dart | 2026-05-17 |
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