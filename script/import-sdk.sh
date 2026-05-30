#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT="$DIR/.."
SDK_DIR="$ROOT/sdk"

# check sdk/ directory
if [[ ! -d "$SDK_DIR" ]]; then
  echo "error: sdk/ directory not found. Create sdk/ in the plugin root and put the official zip files inside." >&2
  exit 1
fi

# find zip files
ANDROID_ZIP=$(ls "$SDK_DIR"/numberAuthSDK_APP_Android_v*.zip 2>/dev/null | sort -V | tail -1 || true)
IOS_ZIP=$(ls "$SDK_DIR"/numberAuthSDK_APP_iOS_v*_static.zip 2>/dev/null | sort -V | tail -1 || true)

if [[ -z "$ANDROID_ZIP" ]]; then
  echo "error: Android SDK zip not found in sdk/ (expected: numberAuthSDK_APP_Android_v*.zip)" >&2
  exit 1
fi

if [[ -z "$IOS_ZIP" ]]; then
  echo "error: iOS SDK zip not found in sdk/ (expected: numberAuthSDK_APP_iOS_v*_static.zip)" >&2
  exit 1
fi

echo "Android: $(basename "$ANDROID_ZIP")"
echo "iOS:     $(basename "$IOS_ZIP")"

# Android
ANDROID_TMP="$SDK_DIR/android_tmp"
unzip -q "$ANDROID_ZIP" -d "$ANDROID_TMP"

ANDROID_SDK_DIR=$(find "$ANDROID_TMP" -type d -name "SDK" | head -1)
if [[ -z "$ANDROID_SDK_DIR" ]]; then
  rm -rf "$ANDROID_TMP"
  echo "error: SDK/ directory not found inside Android zip. The zip structure may be unexpected." >&2
  exit 1
fi

mkdir -p "$ROOT/android/libs"
cp "$ANDROID_SDK_DIR"/*.aar "$ROOT/android/libs/"
rm -rf "$ANDROID_TMP"
echo "✓ Android AARs imported to android/libs/"

# iOS
IOS_TMP="$SDK_DIR/ios_tmp"
unzip -q "$IOS_ZIP" -d "$IOS_TMP"

IOS_XCFW_DIR=$(find "$IOS_TMP" -type d -name "xcframeworks" | head -1)
if [[ -z "$IOS_XCFW_DIR" ]]; then
  rm -rf "$IOS_TMP"
  echo "error: xcframeworks/ directory not found inside iOS zip. The zip structure may be unexpected." >&2
  exit 1
fi

mkdir -p "$ROOT/ios/aliyun_number_auth/Frameworks"
cp -r "$IOS_XCFW_DIR"/*.xcframework "$ROOT/ios/aliyun_number_auth/Frameworks/"
rm -rf "$IOS_TMP"
echo "✓ iOS xcframeworks imported to ios/aliyun_number_auth/Frameworks/"

echo "done"
