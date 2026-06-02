#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT="$DIR/.."
SDK_DIR="$ROOT/sdk"
ANDROID_TMP="$SDK_DIR/android_tmp"
IOS_TMP="$SDK_DIR/ios_tmp"
trap 'rm -rf "$ANDROID_TMP" "$IOS_TMP"' EXIT

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
unzip -q "$ANDROID_ZIP" -d "$ANDROID_TMP"

ANDROID_SDK_DIR=$(find "$ANDROID_TMP" -type d -name "SDK" | head -1)
if [[ -z "$ANDROID_SDK_DIR" ]]; then
  echo "error: SDK/ directory not found inside Android zip. The zip structure may be unexpected." >&2
  exit 1
fi

# validate Android — check required classes and methods our plugin calls
echo "validating Android SDK..."
MAIN_AAR=$(ls "$ANDROID_SDK_DIR"/auth_number_product*.aar 2>/dev/null | head -1 || true)
if [[ -z "$MAIN_AAR" ]]; then
  echo "error: auth_number_product*.aar not found in SDK/" >&2
  exit 1
fi

CLASSES_JAR="$ANDROID_TMP/classes.jar"
unzip -p "$MAIN_AAR" classes.jar > "$CLASSES_JAR"
JAR_LISTING=$(unzip -l "$CLASSES_JAR" 2>/dev/null || true)

check_android_class() {
  local cls="$1"
  if echo "$JAR_LISTING" | grep -q "${cls}.class"; then
    echo "  ✓ ${cls##*/}"
  else
    echo "  ✗ ${cls##*/} — not found" >&2
    exit 1
  fi
}

check_android_method() {
  local cls="$1" method="$2"
  local strings
  strings=$(unzip -p "$CLASSES_JAR" "${cls}.class" 2>/dev/null | strings || true)
  if echo "$strings" | grep -q "$method"; then
    echo "  ✓ $method"
  else
    echo "  ! $method — not confirmed (may be obfuscated)" >&2
  fi
}

check_android_class "com/mobile/auth/gatewayauth/PhoneNumberAuthHelper"
check_android_class "com/mobile/auth/gatewayauth/TokenResultListener"
check_android_class "com/mobile/auth/gatewayauth/PreLoginResultListener"
check_android_class "com/mobile/auth/gatewayauth/model/TokenRet"
check_android_class "com/mobile/auth/gatewayauth/ResultCode"

check_android_method "com/mobile/auth/gatewayauth/PhoneNumberAuthHelper" "setAuthSDKInfo"
check_android_method "com/mobile/auth/gatewayauth/PhoneNumberAuthHelper" "checkEnvAvailable"
check_android_method "com/mobile/auth/gatewayauth/PhoneNumberAuthHelper" "accelerateVerify"
check_android_method "com/mobile/auth/gatewayauth/PhoneNumberAuthHelper" "accelerateLoginPage"
check_android_method "com/mobile/auth/gatewayauth/PhoneNumberAuthHelper" "getVerifyToken"
check_android_method "com/mobile/auth/gatewayauth/PhoneNumberAuthHelper" "getLoginToken"
check_android_method "com/mobile/auth/gatewayauth/PhoneNumberAuthHelper" "quitLoginPage"
check_android_method "com/mobile/auth/gatewayauth/PhoneNumberAuthHelper" "quitPrivacyPage"
check_android_method "com/mobile/auth/gatewayauth/PhoneNumberAuthHelper" "setProtocolChecked"
check_android_method "com/mobile/auth/gatewayauth/PhoneNumberAuthHelper" "queryCheckBoxIsChecked"
check_android_method "com/mobile/auth/gatewayauth/PhoneNumberAuthHelper" "privacyAnimationStart"
check_android_method "com/mobile/auth/gatewayauth/PhoneNumberAuthHelper" "checkBoxAnimationStart"
check_android_method "com/mobile/auth/gatewayauth/PhoneNumberAuthHelper" "hideLoginLoading"
check_android_method "com/mobile/auth/gatewayauth/PhoneNumberAuthHelper" "getVersion"
check_android_method "com/mobile/auth/gatewayauth/PhoneNumberAuthHelper" "expandAuthPageCheckedScope"
check_android_method "com/mobile/auth/gatewayauth/PhoneNumberAuthHelper" "setUIClickListener"
check_android_method "com/mobile/auth/gatewayauth/PhoneNumberAuthHelper" "setAuthListener"
check_android_method "com/mobile/auth/gatewayauth/PhoneNumberAuthHelper" "userControlAuthPageCancel"
check_android_method "com/mobile/auth/gatewayauth/PhoneNumberAuthHelper" "removeAuthRegisterXmlConfig"
check_android_method "com/mobile/auth/gatewayauth/PhoneNumberAuthHelper" "removeAuthRegisterViewConfig"
check_android_method "com/mobile/auth/gatewayauth/PhoneNumberAuthHelper" "removePrivacyAuthRegisterViewConfig"
check_android_method "com/mobile/auth/gatewayauth/PhoneNumberAuthHelper" "removePrivacyRegisterXmlConfig"
check_android_method "com/mobile/auth/gatewayauth/PhoneNumberAuthHelper" "SERVICE_TYPE_AUTH"
check_android_method "com/mobile/auth/gatewayauth/model/TokenRet"         "fromJson"

echo "✓ Android SDK validated"

# Clean stale AARs before copying: if the SDK version's filename changed
# (e.g. auth_number_product-2.14.23-...aar → 2.15.0-...aar), leaving the
# old jar in libs/ would let gradle's fileTree(libs/*.aar) bundle BOTH
# versions and fail with duplicate class definitions at compile time.
mkdir -p "$ROOT/android/libs"
rm -f "$ROOT/android/libs"/*.aar
cp "$ANDROID_SDK_DIR"/*.aar "$ROOT/android/libs/"
echo "✓ Android AARs imported to android/libs/"

# iOS
unzip -q "$IOS_ZIP" -d "$IOS_TMP"

IOS_XCFW_DIR=$(find "$IOS_TMP" -type d -name "xcframeworks" | head -1)
if [[ -z "$IOS_XCFW_DIR" ]]; then
  echo "error: xcframeworks/ directory not found inside iOS zip. The zip structure may be unexpected." >&2
  exit 1
fi

# validate iOS — check required methods in TXCommonHandler.h that our plugin calls
echo "validating iOS SDK..."
HEADER=$(find "$IOS_XCFW_DIR" -name "TXCommonHandler.h" 2>/dev/null | head -1 || true)
if [[ -z "$HEADER" ]]; then
  echo "error: TXCommonHandler.h not found in xcframework" >&2
  exit 1
fi

check_ios_method() {
  local method="$1"
  if grep -q "$method" "$HEADER"; then
    echo "  ✓ $method"
  else
    echo "  ✗ $method — not found in TXCommonHandler.h" >&2
    exit 1
  fi
}

check_ios_method "sharedInstance"
check_ios_method "setAuthSDKInfo"
check_ios_method "checkEnvAvailableWithAuthType"
check_ios_method "accelerateVerifyWithTimeout"
check_ios_method "accelerateLoginPageWithTimeout"
check_ios_method "getVerifyTokenWithTimeout"
check_ios_method "getLoginTokenWithTimeout"
check_ios_method "cancelLoginVCAnimated"
check_ios_method "setCheckboxIsChecked"
check_ios_method "queryCheckBoxIsChecked"
check_ios_method "privacyAnimationStart"
check_ios_method "checkboxAnimationStart"
check_ios_method "closePrivactAlertView"
check_ios_method "hideLoginLoading"
check_ios_method "getVersion"

echo "✓ iOS SDK validated"

# Replace xcframeworks atomically — `cp -r foo.xcframework existing-dir/`
# on macOS MERGES into an existing same-named dir rather than replacing it,
# leaving stale resources behind when an SDK upgrade removes assets (e.g. a
# renamed icon would ship both old and new in the app bundle). Nuke all
# *.xcframework entries first, then copy the new set in fresh — also
# handles the rare case of the SDK dropping a vendored framework entirely.
mkdir -p "$ROOT/ios/aliyun_number_auth/Frameworks"
rm -rf "$ROOT/ios/aliyun_number_auth/Frameworks"/*.xcframework
cp -r "$IOS_XCFW_DIR"/*.xcframework "$ROOT/ios/aliyun_number_auth/Frameworks/"
echo "✓ iOS xcframeworks imported to ios/aliyun_number_auth/Frameworks/"

echo "done"
