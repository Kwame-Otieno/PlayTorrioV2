#!/bin/bash

# Check local secrets file exists
if [ ! -f lib/api/trakt_secrets.local.dart ]; then
  echo "=== ERROR: lib/api/trakt_secrets.local.dart not found ==="
  echo "=== Create it with your Trakt credentials before building ==="
  exit 1
fi

echo "=== Fetching upstream updates ==="
git fetch upstream
git merge upstream/main

echo "=== Reapplying patches ==="
git apply patches/my-fixes.patch

if [ $? -eq 0 ]; then
  echo "=== Patches applied successfully ==="
  echo "=== Building ==="
  flutter build linux --release
  echo "=== Done! PlayTorrio updated ==="
else
  echo "=== Patch failed — conflicts need manual resolution ==="
  echo "=== Check PATCHES.md for context on each fix ==="
fi