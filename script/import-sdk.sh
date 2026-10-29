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

# Only this invocation owns the lock and its fresh temporary directory. Never
# remove sdk/android_tmp or sdk/ios_tmp: they may contain somebody else's work.
LOCK_DIR="$SDK_DIR/.import-sdk.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "error: SDK import is locked ($LOCK_DIR). Check for an active or interrupted import." >&2
  exit 1
fi
WORK_DIR=""
COMMITTED=false
TARGETS=("$ROOT/android/libs-maven/com/aliyun/atauth" "$ROOT/android/build.gradle.kts" "$ROOT/ios/aliyun_number_auth/Frameworks")
STARTED=()
HAD_ORIGINAL=()

cleanup() {
  local status=$? rollback_failed=false i target
  trap - EXIT HUP INT TERM
  if [[ "$COMMITTED" != true && -n "$WORK_DIR" ]]; then
    for ((i=${#STARTED[@]}-1; i>=0; i--)); do
      target="${TARGETS[$i]}"
      if [[ -e "$WORK_DIR/backup-$i" ]]; then
        rm -rf "$target"
        if ! mv "$WORK_DIR/backup-$i" "$target"; then rollback_failed=true; fi
      elif [[ "${HAD_ORIGINAL[$i]}" == false ]]; then
        rm -rf "$target"
      fi
    done
  fi
  if [[ "$rollback_failed" == true ]]; then
    echo "error: rollback failed; backups and lock retained in $WORK_DIR" >&2
    exit 1
  fi
  if [[ -n "$WORK_DIR" ]]; then rm -rf "$WORK_DIR"; fi
  rmdir "$LOCK_DIR"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
WORK_DIR=$(mktemp -d "$SDK_DIR/.import-sdk.XXXXXX")
ANDROID_TMP="$WORK_DIR/android"
IOS_TMP="$WORK_DIR/ios"
STAGED="$WORK_DIR/staged"
mkdir -p "$STAGED/atauth" "$STAGED/Frameworks"

for target in "${TARGETS[@]}"; do
  if [[ -L "$target" ]]; then
    echo "error: refusing to replace symlink: $target" >&2
    exit 1
  fi
done
cp "$ROOT/android/build.gradle.kts" "$STAGED/build.gradle.kts"

# find zip files
ANDROID_ZIP=$(ls "$SDK_DIR"/numberAuthSDK_APP_Android_v*.zip 2>/dev/null | sort -V | tail -1 || true)
IOS_ZIP=$(ls "$SDK_DIR"/numberAuthSDK_APP_iOS_v*_dynamic.zip 2>/dev/null | sort -V | tail -1 || true)

if [[ -z "$ANDROID_ZIP" ]]; then
  echo "error: Android SDK zip not found in sdk/ (expected: numberAuthSDK_APP_Android_v*.zip)" >&2
  exit 1
fi

if [[ -z "$IOS_ZIP" ]]; then
  echo "error: iOS SDK zip not found in sdk/ (expected: numberAuthSDK_APP_iOS_v*_dynamic.zip with vendor dSYM)" >&2
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

# Install AARs into a local Maven repository under android/libs-maven/.
# AGP 8+ rejects direct local .aar file deps in a library that produces an
# AAR (hasLocalAarDeps), but accepts AARs resolved through a Maven repo —
# even a local one. The plugin's build.gradle.kts wires this repo into both
# its own project and (via rootProject.allprojects) the consuming app.
#
# Each .aar in the vendor zip is named "<artifact>-<version>[-suffix].aar".
# We parse out artifact + a semver-shaped version and lay them out as:
#   libs-maven/com/aliyun/atauth/<artifact>/<version>/<artifact>-<version>.aar
#   libs-maven/com/aliyun/atauth/<artifact>/<version>/<artifact>-<version>.pom
MAVEN_GROUP_DIR="$STAGED/atauth"
for src_aar in "$ANDROID_SDK_DIR"/*.aar; do
  filename=$(basename "$src_aar")
  # Match: <artifact>-<version> where version is N.N[.N] possibly followed by
  # -<suffix>. The artifact is everything up to the first digit-prefixed token.
  if [[ "$filename" =~ ^(.+)-([0-9]+\.[0-9]+(\.[0-9]+)?)(-.*)?\.aar$ ]]; then
    artifact="${BASH_REMATCH[1]}"
    version="${BASH_REMATCH[2]}"
  else
    echo "error: could not parse artifact/version from $filename" >&2
    exit 1
  fi
  case "$artifact" in
    auth_number_product|main|logger) ;;
    *) echo "error: unreviewed Android SDK dependency: $artifact" >&2; exit 1 ;;
  esac
  if [[ -d "$MAVEN_GROUP_DIR/$artifact" ]]; then
    echo "error: multiple AARs for $artifact" >&2
    exit 1
  fi
  # Keep the host's dependency coordinates in sync with the newly staged AARs.
  coordinate="com.aliyun.atauth:$artifact:"
  if [[ $(grep -c "implementation(\"$coordinate" "$STAGED/build.gradle.kts" || true) != 1 ]]; then
    echo "error: expected one Gradle dependency for $artifact" >&2
    exit 1
  fi
  sed -E "s|(implementation\(\"com\\.aliyun\\.atauth:$artifact:)[^\"@]+(@aar\"\))|\\1$version\\2|" \
    "$STAGED/build.gradle.kts" > "$STAGED/build.gradle.next"
  mv "$STAGED/build.gradle.next" "$STAGED/build.gradle.kts"
  target_dir="$MAVEN_GROUP_DIR/$artifact/$version"
  mkdir -p "$target_dir"
  cp "$src_aar" "$target_dir/$artifact-$version.aar"
  cat > "$target_dir/$artifact-$version.pom" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.aliyun.atauth</groupId>
  <artifactId>$artifact</artifactId>
  <version>$version</version>
  <packaging>aar</packaging>
</project>
EOF
  echo "  ✓ $artifact:$version"
done
for artifact in auth_number_product main logger; do
  if [[ ! -d "$MAVEN_GROUP_DIR/$artifact" ]]; then
    echo "error: required Android SDK dependency missing: $artifact" >&2
    exit 1
  fi
done
echo "✓ Android AARs staged"

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

# SPM supports dynamic binary targets. Include the original, UUID-matched dSYM
# through DebugSymbolsPath so Xcode collects it while archiving the device app.
python3 "$DIR/package_ios_sdk.py" \
  "$IOS_XCFW_DIR/ATAuthSDK_D.xcframework" \
  "$(dirname "$IOS_XCFW_DIR")/frameworks/ATAuthSDK_D.framework.dSYM" \
  "$STAGED/Frameworks/ATAuthSDK_D.xcframework"

# All validation and copying finish before any installed SDK is changed.
# Each rename is atomic on the repository's filesystem; failures/signals during
# the multi-path update restore the previous set. SIGKILL/power loss requires
# manual recovery from the retained .import-sdk.* directory and lock.
STAGED_TARGETS=("$STAGED/atauth" "$STAGED/build.gradle.kts" "$STAGED/Frameworks")
for i in 0 1 2; do
  target="${TARGETS[$i]}"
  mkdir -p "$(dirname "$target")"
  HAD_ORIGINAL[$i]=false
  if [[ -e "$target" ]]; then HAD_ORIGINAL[$i]=true; fi
  STARTED[$i]=true
  if [[ "${HAD_ORIGINAL[$i]}" == true ]]; then mv "$target" "$WORK_DIR/backup-$i"; fi
  mv "${STAGED_TARGETS[$i]}" "$target"
done
COMMITTED=true
echo "✓ Android AARs, Gradle versions and iOS xcframeworks imported"

echo "done"
