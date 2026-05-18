# PlayTorrio — Local Build & Patch Notes

This is a personal fork of [PlayTorrioV2](https://github.com/ayman708-UX/PlayTorrioV2) with bug fixes applied on top of the original. The `update.sh` script handles pulling upstream updates and reapplying all patches automatically.

---

## First Time Setup

### Step 1 — Clone the repo
```bash
git clone https://github.com/Kwame-Otieno/PlayTorrioV2.git
cd PlayTorrioV2
```

### Step 2 — Get Trakt API Credentials
1. Go to https://trakt.tv/oauth/applications
2. Click **New Application**
3. Fill in:
   - **Name:** anything you want
   - **Redirect URI:** `urn:ietf:wg:oauth:2.0:oob`
   - **Permissions:** check `/checkin`, `/scrobble` and `/calendars`
4. Click **Save**
5. Copy your **Client ID** and **Client Secret**

### Step 3 — Create Your Trakt Local Secrets File
1. In the project folder go to `lib/api/`
2. Create a new file called exactly `trakt_secrets.local.dart`
3. Paste this inside and replace with your real credentials:

```dart
const String kTraktClientId = 'your_client_id_here';
const String kTraktClientSecret = 'your_client_secret_here';
```

4. Save the file

> ⚠️ **Important:** This file is git-ignored and will never be committed to the repo. You must create it manually on every machine. Without it the build will fail.

### Step 4 — Get Simkl API Credentials
1. Go to https://simkl.com/settings/developer/
2. Click **New App**
3. Fill in:
   - **Name:** anything you want
   - **Redirect URI:** `urn:ietf:wg:oauth:2.0:oob`
4. Click **Save**
5. Copy your **Client ID** and **Client Secret**

### Step 5 — Create Your Simkl Local Secrets File
1. In the project folder go to `lib/api/`
2. Create a new file called exactly `simkl_secrets.local.dart`
3. Paste this inside and replace with your real credentials:
```dart
const String kSimklClientId = 'your_client_id_here';
const String kSimklClientSecret = 'your_client_secret_here';
```
 
4. Save the file
> ⚠️ **Important:** This file is also git-ignored and must be created manually on every machine.

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
### Step 4 — Install Dependencies
```bash
flutter pub get
```

### Step 5 — Add Linux Desktop Support
```bash
flutter create --platforms=linux .
```

### Step 6 — Build
```bash
flutter build linux --release
```
