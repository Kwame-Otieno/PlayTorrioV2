#!/bin/bash
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