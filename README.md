# PlayTorrio — Local Build & Patch Notes

This is a personal fork of [PlayTorrioV2](https://github.com/ayman708-UX/PlayTorrioV2) with bug fixes applied on top of the original. The `update.sh` script handles pulling upstream updates and reapplying all patches automatically.

---

## First Time Setup

```bash
# 1. Install dependencies
flutter pub get

# 2. Add Linux desktop support
flutter create --platforms=linux .

# 3. Add your Trakt credentials
#    Open lib/api/trakt_secrets.local.dart and fill in your values:
#    const String kTraktClientId = 'your_client_id';
#    const String kTraktClientSecret = 'your_client_secret';
#    Get credentials at: https://trakt.tv/oauth/applications

# 4. Build
flutter build linux --release
```

> **Note:** `lib/api/trakt_secrets.local.dart` is git-ignored and must be created manually on each machine. Never commit real credentials.

---

## Updating the App

When the original author releases an update, run:

```bash
./update.sh
```

This will:
1. Pull the latest upstream changes
2. Reapply all patches from `patches/my-fixes.patch`
3. Build the app
4. Deploy to `/opt/play_torrio`

If a patch fails due to upstream changes, check `PATCHES.md` for context on each fix and reapply manually.

---

## Bug Fixes Applied

### Fix 1 — Trakt Login Not Opening in Browser
**File:** `lib/api/trakt_service.dart`  
**Problem:** `_clientId` and `_clientSecret` were using `String.fromEnvironment()` but no values were injected at build time, causing a `403 Forbidden` on all Trakt API requests.  
**Fix:** Moved credentials to a separate `trakt_secrets.local.dart` file that is git-ignored and imported at build time.

---

### Fix 2 — Trakt Token Refreshing in Infinite Loop
**File:** `lib/api/trakt_service.dart`  
**Problem:** The refresh threshold was set to 7 days but Trakt issues 7-day tokens, so the app refreshed immediately after every save — creating an infinite loop on startup.  
**Fix:**
- Added `_cachedToken`, `_cachedExpiry` in-memory cache fields
- Added `_refreshLock` mutex to prevent concurrent refreshes
- Populated cache in `_saveTokens` after every token save
- Added cache check at top of `_getValidToken` to return early
- Persisted expiry to `SharedPreferences` so cache survives app restarts
- Changed refresh threshold from 7 days to 1 day
- Added `synchronized` package to `pubspec.yaml`

---

### Fix 3 — KissKh Rate Limit Crash
**File:** `lib/api/kisskh_service.dart`  
**Problem:** The `_get()` method returned raw response body without checking the HTTP status code. When KissKh returned a `429 Too Many Requests` plain text response, `jsonDecode` crashed with a `FormatException`.  
**Fix:** Added HTTP status code checks before parsing — throws a handled `Exception` on `429` and non-`200` responses instead of crashing.

---

## Secrets Setup

Create this file locally (never commit it):

**`lib/api/trakt_secrets.local.dart`**
```dart
const String kTraktClientId = 'your_client_id';
const String kTraktClientSecret = 'your_client_secret';
```

Get your credentials at: https://trakt.tv/oauth/applications  
Use `urn:ietf:wg:oauth:2.0:oob` as the redirect URI.

---

## File Structure

```
PlayTorrioV2/
├── patches/
│   └── my-fixes.patch        ← all fixes as a reapplicable patch
├── update.sh                 ← one command to update everything
├── PATCHES.md                ← detailed fix documentation
├── lib/api/
│   ├── trakt_service.dart    ← patched
│   ├── trakt_secrets.dart    ← template (safe to commit)
│   └── kisskh_service.dart   ← patched
└── lib/api/trakt_secrets.local.dart  ← YOUR credentials (git-ignored)
```