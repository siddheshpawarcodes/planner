#!/bin/sh
# Fetches the Vosk small English model (Apache 2.0, about 41 MB) into the
# Android assets, where the "Hey Planner" wake word loads it from. The model
# is git-ignored; run this once after cloning, before building for Android.
set -eu
cd "$(dirname "$0")/.."
name=vosk-model-small-en-us-0.15
dest=android/app/src/main/assets/vosk-model
if [ -f "$dest/uuid" ] && [ "$(cat "$dest/uuid")" = "$name" ]; then
  echo "Vosk model already in $dest"
  exit 0
fi
tmp=$(mktemp -d)
curl -fSL -o "$tmp/model.zip" "https://alphacephei.com/vosk/models/$name.zip"
unzip -q "$tmp/model.zip" -d "$tmp"
rm -rf "$dest"
mkdir -p "$(dirname "$dest")"
mv "$tmp/$name" "$dest"
# Vosk's StorageService copies the model out of the APK once and compares
# this file to decide whether a newer model needs copying again.
echo "$name" > "$dest/uuid"
rm -rf "$tmp"
echo "Vosk model ready in $dest"
