#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Bairometer"
BUNDLE_ID="io.github.Prontsevich.Bairometer"
MIN_SYSTEM_VERSION="15.0"
HELPER_NAME="BairometerClaudeStatusLine"

CONFIGURATION="debug"
VERSION=""
BUILD_NUMBER=""
ARCHITECTURE=""
SIGNING_TEMP_DIRECTORY=""

cleanup() {
  if [[ -n "$SIGNING_TEMP_DIRECTORY" ]]; then
    rm -rf "$SIGNING_TEMP_DIRECTORY"
  fi
}

trap cleanup EXIT

usage() {
  echo "usage: $0 [--configuration debug|release] [--version MAJOR.MINOR.PATCH --build-number BUILD] [--arch arm64|x86_64]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --configuration)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      CONFIGURATION="$2"
      shift 2
      ;;
    --version)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      VERSION="$2"
      shift 2
      ;;
    --build-number)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      BUILD_NUMBER="$2"
      shift 2
      ;;
    --arch)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      ARCHITECTURE="$2"
      shift 2
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

case "$CONFIGURATION" in
  debug|release)
    ;;
  *)
    usage
    exit 2
    ;;
esac

if [[ -n "$VERSION" && ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: version must use MAJOR.MINOR.PATCH with numeric components" >&2
  exit 2
fi

if [[ -n "$BUILD_NUMBER" && ! "$BUILD_NUMBER" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  echo "error: build number must use one to three numeric components" >&2
  exit 2
fi

if [[ -n "$VERSION" && -z "$BUILD_NUMBER" ]] || [[ -z "$VERSION" && -n "$BUILD_NUMBER" ]]; then
  echo "error: version and build number must be provided together" >&2
  exit 2
fi

case "$ARCHITECTURE" in
  ""|arm64|x86_64)
    ;;
  *)
    usage
    exit 2
    ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
APP_HELPERS="$APP_CONTENTS/Helpers"
HELPER_BINARY="$APP_HELPERS/$HELPER_NAME"
APP_RESOURCES="$APP_CONTENTS/Resources"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ASSET_CATALOG="$ROOT_DIR/Resources/Assets.xcassets"
APP_RESOURCE_BUNDLE="$APP_NAME"_"$APP_NAME".bundle
LOCAL_SIGNING_PROJECT="$ROOT_DIR/Support/LocalSigning/BairometerLocalSigning.xcodeproj"
LOCAL_SIGNING_SCHEME="BairometerLocalSigning"
LOCAL_SIGNING_DERIVED_DATA="$ROOT_DIR/.build/local-signing"
DEVELOPMENT_TEAM="${BAIROMETER_DEVELOPMENT_TEAM:-}"
DEVELOPER_IDENTITY="${BAIROMETER_DEVELOPER_IDENTITY:-}"
PROVISIONING_PROFILE="${BAIROMETER_PROVISIONING_PROFILE:-}"

if [[ "$CONFIGURATION" == "debug" && -z "$DEVELOPMENT_TEAM" ]]; then
  echo "error: DEBUG staging requires BAIROMETER_DEVELOPMENT_TEAM." >&2
  echo "Set it to your Apple Development Team ID, for example:" >&2
  echo "  BAIROMETER_DEVELOPMENT_TEAM=YOUR_TEAM_ID $0 --configuration debug" >&2
  exit 1
fi

if [[ "$CONFIGURATION" == "release" ]]; then
  if [[ -z "$DEVELOPMENT_TEAM" ]]; then
    echo "error: RELEASE staging requires BAIROMETER_DEVELOPMENT_TEAM." >&2
    exit 1
  fi
  if [[ -z "$DEVELOPER_IDENTITY" ]]; then
    echo "error: RELEASE staging requires BAIROMETER_DEVELOPER_IDENTITY." >&2
    exit 1
  fi
  if [[ -z "$PROVISIONING_PROFILE" || ! -f "$PROVISIONING_PROFILE" ]]; then
    echo "error: RELEASE staging requires an existing BAIROMETER_PROVISIONING_PROFILE." >&2
    exit 1
  fi
fi

BUILD_ARGS=(--configuration "$CONFIGURATION")
if [[ -n "$ARCHITECTURE" ]]; then
  BUILD_ARGS+=(--arch "$ARCHITECTURE")
fi

swift build "${BUILD_ARGS[@]}"
BUILD_DIRECTORY="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
BUILD_BINARY="$BUILD_DIRECTORY/$APP_NAME"
BUILD_HELPER="$BUILD_DIRECTORY/$HELPER_NAME"

[[ -x "$BUILD_BINARY" ]] || { echo "error: missing app executable at $BUILD_BINARY" >&2; exit 1; }
[[ -x "$BUILD_HELPER" ]] || { echo "error: missing helper executable at $BUILD_HELPER" >&2; exit 1; }
[[ -d "$ASSET_CATALOG" ]] || { echo "error: missing app asset catalog at $ASSET_CATALOG" >&2; exit 1; }

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_HELPERS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$BUILD_HELPER" "$HELPER_BINARY"
chmod +x "$APP_BINARY" "$HELPER_BINARY"

shopt -s nullglob
for resource_bundle in "$BUILD_DIRECTORY"/*.bundle; do
  resource_name="$(basename "$resource_bundle")"
  case "$resource_name" in
    *Tests.bundle)
      continue
      ;;
    "$APP_RESOURCE_BUNDLE")
      resource_directory="$resource_bundle"
      if [[ -d "$resource_bundle/Contents/Resources" ]]; then
        resource_directory="$resource_bundle/Contents/Resources"
      fi
      for localization in en ru; do
        localized_resources="$resource_directory/$localization.lproj"
        [[ -d "$localized_resources" ]] || {
          echo "error: missing $localization localization resources in $resource_name" >&2
          exit 1
        }
        /usr/bin/ditto "$localized_resources" "$APP_RESOURCES/$localization.lproj"
      done
      ;;
    *)
      /usr/bin/ditto "$resource_bundle" "$APP_RESOURCES/$resource_name"
      ;;
  esac
done
shopt -u nullglob

for localization in en ru; do
  [[ -s "$APP_RESOURCES/$localization.lproj/Localizable.strings" ]] || {
    echo "error: missing staged $localization Localizable.strings" >&2
    exit 1
  }
done

ASSET_INFO_PLIST="$(mktemp "${TMPDIR:-/tmp}/Bairometer-assets.XXXXXX")"
xcrun actool \
  --compile "$APP_RESOURCES" \
  --platform macosx \
  --minimum-deployment-target "$MIN_SYSTEM_VERSION" \
  --app-icon AppIcon \
  --output-partial-info-plist "$ASSET_INFO_PLIST" \
  --output-format human-readable-text \
  "$ASSET_CATALOG"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>Bairometer</string>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>en</string>
    <string>ru</string>
  </array>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

/usr/libexec/PlistBuddy -c "Merge $ASSET_INFO_PLIST" "$INFO_PLIST"
rm -f "$ASSET_INFO_PLIST"

[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDevelopmentRegion' "$INFO_PLIST")" == "en" ]] || {
  echo "error: staged bundle must use English as its development region" >&2
  exit 1
}
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleLocalizations:0' "$INFO_PLIST")" == "en" ]] || {
  echo "error: staged bundle is missing English localization metadata" >&2
  exit 1
}
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleLocalizations:1' "$INFO_PLIST")" == "ru" ]] || {
  echo "error: staged bundle is missing Russian localization metadata" >&2
  exit 1
}

for localization in en ru; do
  resource_directory="$BUILD_DIRECTORY/$APP_RESOURCE_BUNDLE"
  if [[ -d "$resource_directory/Contents/Resources" ]]; then
    resource_directory="$resource_directory/Contents/Resources"
  fi
  built_strings="$resource_directory/$localization.lproj/Localizable.strings"
  staged_strings="$APP_RESOURCES/$localization.lproj/Localizable.strings"
  /usr/bin/plutil -lint "$staged_strings" >/dev/null
  cmp -s "$built_strings" "$staged_strings" || {
    echo "error: staged $localization localization table differs from the built resource" >&2
    exit 1
  }
done

if [[ -n "$VERSION" ]]; then
  /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_NUMBER" "$INFO_PLIST"
fi

/usr/bin/plutil -lint "$INFO_PLIST" >/dev/null
if [[ "$CONFIGURATION" == "debug" ]]; then
  [[ -d "$LOCAL_SIGNING_PROJECT" ]] || {
    echo "error: missing local signing support project" >&2
    exit 1
  }

  /usr/bin/xcodebuild \
    -project "$LOCAL_SIGNING_PROJECT" \
    -scheme "$LOCAL_SIGNING_SCHEME" \
    -configuration Debug \
    -destination "platform=macOS" \
    -derivedDataPath "$LOCAL_SIGNING_DERIVED_DATA" \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
    -quiet \
    build

  SIGNING_TEMPLATE_APP="$LOCAL_SIGNING_DERIVED_DATA/Build/Products/Debug/$LOCAL_SIGNING_SCHEME.app"
  SIGNING_PROFILE="$SIGNING_TEMPLATE_APP/Contents/embedded.provisionprofile"
  [[ -f "$SIGNING_PROFILE" ]] || {
    echo "error: Xcode did not embed a local development provisioning profile" >&2
    exit 1
  }

  SIGNING_TEMP_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/Bairometer-signing.XXXXXX")"
  SIGNING_ENTITLEMENTS="$SIGNING_TEMP_DIRECTORY/entitlements.plist"
  SIGNING_PROFILE_PLIST="$SIGNING_TEMP_DIRECTORY/profile.plist"
  STAGED_ENTITLEMENTS="$SIGNING_TEMP_DIRECTORY/staged-entitlements.plist"

  /usr/bin/codesign \
    --display \
    --entitlements - \
    --xml \
    "$SIGNING_TEMPLATE_APP" \
    >"$SIGNING_ENTITLEMENTS" \
    2>/dev/null
  /usr/bin/security cms \
    -D \
    -i "$SIGNING_PROFILE" \
    -o "$SIGNING_PROFILE_PLIST"
  /usr/bin/plutil -lint "$SIGNING_ENTITLEMENTS" "$SIGNING_PROFILE_PLIST" >/dev/null

  PROFILE_TEAM="$(
    /usr/libexec/PlistBuddy \
      -c "Print :TeamIdentifier:0" \
      "$SIGNING_PROFILE_PLIST"
  )"
  PROFILE_APP_IDENTIFIER="$(
    /usr/libexec/PlistBuddy \
      -c "Print :Entitlements:com.apple.application-identifier" \
      "$SIGNING_PROFILE_PLIST"
  )"
  SIGNED_APP_IDENTIFIER="$(
    /usr/libexec/PlistBuddy \
      -c "Print :com.apple.application-identifier" \
      "$SIGNING_ENTITLEMENTS"
  )"
  SIGNED_TEAM="$(
    /usr/libexec/PlistBuddy \
      -c "Print :com.apple.developer.team-identifier" \
      "$SIGNING_ENTITLEMENTS"
  )"
  SIGNED_KEYCHAIN_GROUP="$(
    /usr/libexec/PlistBuddy \
      -c "Print :keychain-access-groups:0" \
      "$SIGNING_ENTITLEMENTS"
  )"
  EXPECTED_APP_IDENTIFIER="$PROFILE_TEAM.$BUNDLE_ID"
  PROFILE_KEYCHAIN_GROUPS="$(
    /usr/bin/plutil \
      -extract "Entitlements.keychain-access-groups" \
      json \
      -o - \
      "$SIGNING_PROFILE_PLIST"
  )"

  [[ "$PROFILE_TEAM" == "$DEVELOPMENT_TEAM" ]] || {
    echo "error: local development profile belongs to an unexpected team" >&2
    exit 1
  }
  [[ "$PROFILE_APP_IDENTIFIER" == "$EXPECTED_APP_IDENTIFIER" ||
     "$PROFILE_APP_IDENTIFIER" == "$PROFILE_TEAM.*" ]] || {
    echo "error: local development profile does not authorize the app identifier" >&2
    exit 1
  }
  [[ "$SIGNED_APP_IDENTIFIER" == "$EXPECTED_APP_IDENTIFIER" ]] || {
    echo "error: Xcode signing entitlements contain an unexpected app identifier" >&2
    exit 1
  }
  [[ "$SIGNED_TEAM" == "$PROFILE_TEAM" ]] || {
    echo "error: Xcode signing entitlements contain an unexpected team" >&2
    exit 1
  }
  [[ "$SIGNED_KEYCHAIN_GROUP" == "$EXPECTED_APP_IDENTIFIER" ]] || {
    echo "error: Xcode signing entitlements contain an unexpected Keychain group" >&2
    exit 1
  }
  if [[ "$PROFILE_KEYCHAIN_GROUPS" != *"\"$EXPECTED_APP_IDENTIFIER\""* &&
        "$PROFILE_KEYCHAIN_GROUPS" != *"\"$PROFILE_TEAM.*\""* ]]; then
    echo "error: local development profile does not authorize the Keychain group" >&2
    exit 1
  fi

  SIGNING_AUTHORITY="$(
    /usr/bin/codesign -dvvv "$SIGNING_TEMPLATE_APP" 2>&1 |
      /usr/bin/sed -n "s/^Authority=//p" |
      /usr/bin/head -n 1
  )"
  [[ "$SIGNING_AUTHORITY" == "Apple Development:"* ]] || {
    echo "error: Xcode did not select an Apple Development signing identity" >&2
    exit 1
  }

  cp "$SIGNING_PROFILE" "$APP_CONTENTS/embedded.provisionprofile"
  /usr/bin/codesign \
    --force \
    --sign "$SIGNING_AUTHORITY" \
    --timestamp=none \
    "$HELPER_BINARY"
  /usr/bin/codesign \
    --force \
    --sign "$SIGNING_AUTHORITY" \
    --entitlements "$SIGNING_ENTITLEMENTS" \
    --timestamp=none \
    --generate-entitlement-der \
    "$APP_BUNDLE"
else
  SIGNING_TEMP_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/Bairometer-signing.XXXXXX")"
  SIGNING_ENTITLEMENTS="$SIGNING_TEMP_DIRECTORY/entitlements.plist"
  SIGNING_PROFILE_PLIST="$SIGNING_TEMP_DIRECTORY/profile.plist"
  PROFILE_CERTIFICATE_BASE64="$SIGNING_TEMP_DIRECTORY/profile-certificate.base64"
  PROFILE_CERTIFICATE_DER="$SIGNING_TEMP_DIRECTORY/profile-certificate.der"
  STAGED_ENTITLEMENTS="$SIGNING_TEMP_DIRECTORY/staged-entitlements.plist"

  /usr/bin/security cms \
    -D \
    -i "$PROVISIONING_PROFILE" \
    -o "$SIGNING_PROFILE_PLIST"
  /usr/bin/plutil -lint "$SIGNING_PROFILE_PLIST" >/dev/null

  PROFILE_NAME="$(
    /usr/libexec/PlistBuddy -c "Print :Name" "$SIGNING_PROFILE_PLIST"
  )"
  PROFILE_TEAM="$(
    /usr/libexec/PlistBuddy \
      -c "Print :TeamIdentifier:0" \
      "$SIGNING_PROFILE_PLIST"
  )"
  PROFILE_PLATFORM="$(
    /usr/libexec/PlistBuddy -c "Print :Platform:0" "$SIGNING_PROFILE_PLIST"
  )"
  PROFILE_ALL_DEVICES="$(
    /usr/libexec/PlistBuddy \
      -c "Print :ProvisionsAllDevices" \
      "$SIGNING_PROFILE_PLIST"
  )"
  PROFILE_APP_IDENTIFIER="$(
    /usr/libexec/PlistBuddy \
      -c "Print :Entitlements:com.apple.application-identifier" \
      "$SIGNING_PROFILE_PLIST"
  )"
  PROFILE_SIGNED_TEAM="$(
    /usr/libexec/PlistBuddy \
      -c "Print :Entitlements:com.apple.developer.team-identifier" \
      "$SIGNING_PROFILE_PLIST"
  )"
  PROFILE_KEYCHAIN_GROUPS="$(
    /usr/bin/plutil \
      -extract "Entitlements.keychain-access-groups" \
      json \
      -o - \
      "$SIGNING_PROFILE_PLIST"
  )"
  EXPECTED_APP_IDENTIFIER="$DEVELOPMENT_TEAM.$BUNDLE_ID"

  [[ "$PROFILE_TEAM" == "$DEVELOPMENT_TEAM" ]] || {
    echo "error: Developer ID profile belongs to an unexpected team" >&2
    exit 1
  }
  [[ "$PROFILE_SIGNED_TEAM" == "$DEVELOPMENT_TEAM" ]] || {
    echo "error: Developer ID profile authorizes an unexpected signing team" >&2
    exit 1
  }
  [[ "$PROFILE_PLATFORM" == "OSX" ]] || {
    echo "error: Developer ID profile is not a macOS profile" >&2
    exit 1
  }
  [[ "$PROFILE_ALL_DEVICES" == "true" ]] || {
    echo "error: release profile is not a Developer ID profile" >&2
    exit 1
  }
  [[ "$PROFILE_APP_IDENTIFIER" == "$EXPECTED_APP_IDENTIFIER" ]] || {
    echo "error: Developer ID profile does not authorize the app identifier" >&2
    exit 1
  }
  if [[ "$PROFILE_KEYCHAIN_GROUPS" != *"\"$EXPECTED_APP_IDENTIFIER\""* &&
        "$PROFILE_KEYCHAIN_GROUPS" != *"\"$DEVELOPMENT_TEAM.*\""* ]]; then
    echo "error: Developer ID profile does not authorize the Keychain group" >&2
    exit 1
  fi

  PROFILE_CERTIFICATE_COUNT="$(
    /usr/bin/plutil \
      -extract DeveloperCertificates \
      xml1 \
      -o - \
      "$SIGNING_PROFILE_PLIST" |
      /usr/bin/grep -c '<data>'
  )"
  [[ "$PROFILE_CERTIFICATE_COUNT" == "1" ]] || {
    echo "error: Developer ID profile must contain exactly one certificate" >&2
    exit 1
  }
  /usr/bin/plutil \
    -extract DeveloperCertificates.0 \
    raw \
    -o "$PROFILE_CERTIFICATE_BASE64" \
    "$SIGNING_PROFILE_PLIST"
  /usr/bin/base64 \
    -D \
    -i "$PROFILE_CERTIFICATE_BASE64" \
    -o "$PROFILE_CERTIFICATE_DER"
  PROFILE_CERTIFICATE_SHA1="$(
    /usr/bin/openssl x509 \
      -inform DER \
      -in "$PROFILE_CERTIFICATE_DER" \
      -noout \
      -fingerprint \
      -sha1 |
      /usr/bin/cut -d= -f2 |
      /usr/bin/tr -d ':'
  )"
  SIGNING_IDENTITY_SHA1="$(
    /usr/bin/security find-identity -p codesigning -v |
      /usr/bin/awk -v identity="\"$DEVELOPER_IDENTITY\"" \
        'index($0, identity) { print $2; exit }'
  )"
  [[ -n "$SIGNING_IDENTITY_SHA1" ]] || {
    echo "error: Developer ID signing identity was not found" >&2
    exit 1
  }
  [[ "$SIGNING_IDENTITY_SHA1" == "$PROFILE_CERTIFICATE_SHA1" ]] || {
    echo "error: Developer ID profile does not contain the selected identity" >&2
    exit 1
  }

  cat >"$SIGNING_ENTITLEMENTS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.application-identifier</key>
  <string>$EXPECTED_APP_IDENTIFIER</string>
  <key>com.apple.developer.team-identifier</key>
  <string>$DEVELOPMENT_TEAM</string>
  <key>keychain-access-groups</key>
  <array>
    <string>$EXPECTED_APP_IDENTIFIER</string>
  </array>
</dict>
</plist>
PLIST
  /usr/bin/plutil -lint "$SIGNING_ENTITLEMENTS" >/dev/null

  cp "$PROVISIONING_PROFILE" "$APP_CONTENTS/embedded.provisionprofile"
  /usr/bin/codesign \
    --force \
    --sign "$DEVELOPER_IDENTITY" \
    --identifier "$BUNDLE_ID.ClaudeStatusLine" \
    --options runtime \
    --timestamp \
    "$HELPER_BINARY"
  /usr/bin/codesign \
    --force \
    --sign "$DEVELOPER_IDENTITY" \
    --identifier "$BUNDLE_ID" \
    --entitlements "$SIGNING_ENTITLEMENTS" \
    --options runtime \
    --timestamp \
    --generate-entitlement-der \
    "$APP_BUNDLE"
fi
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

if [[ "$CONFIGURATION" == "debug" ]]; then
  /usr/bin/codesign \
    --display \
    --entitlements - \
    --xml \
    "$APP_BUNDLE" \
    >"$STAGED_ENTITLEMENTS" \
    2>/dev/null
  cmp -s "$SIGNING_ENTITLEMENTS" "$STAGED_ENTITLEMENTS" || {
    echo "error: staged app entitlements differ from Xcode-authorized entitlements" >&2
    exit 1
  }
  PROFILE_EXPIRATION="$(
    /usr/libexec/PlistBuddy \
      -c "Print :ExpirationDate" \
      "$SIGNING_PROFILE_PLIST"
  )"
  echo "Staged $APP_BUNDLE (Apple Development; profile expires $PROFILE_EXPIRATION)"
else
  /usr/bin/codesign \
    --display \
    --entitlements - \
    --xml \
    "$APP_BUNDLE" \
    >"$STAGED_ENTITLEMENTS" \
    2>/dev/null
  /bin/bash \
    "$ROOT_DIR/script/validate_release_entitlements.sh" \
    "$STAGED_ENTITLEMENTS" \
    "$DEVELOPMENT_TEAM" \
    "$BUNDLE_ID"
  STAGED_APP_IDENTIFIER="$(
    /usr/libexec/PlistBuddy \
      -c "Print :com.apple.application-identifier" \
      "$STAGED_ENTITLEMENTS"
  )"
  STAGED_TEAM="$(
    /usr/libexec/PlistBuddy \
      -c "Print :com.apple.developer.team-identifier" \
      "$STAGED_ENTITLEMENTS"
  )"
  STAGED_KEYCHAIN_GROUP="$(
    /usr/libexec/PlistBuddy \
      -c "Print :keychain-access-groups:0" \
      "$STAGED_ENTITLEMENTS"
  )"
  [[ "$STAGED_APP_IDENTIFIER" == "$EXPECTED_APP_IDENTIFIER" ]] || {
    echo "error: staged release contains an unexpected app identifier" >&2
    exit 1
  }
  [[ "$STAGED_TEAM" == "$DEVELOPMENT_TEAM" ]] || {
    echo "error: staged release contains an unexpected signing team" >&2
    exit 1
  }
  [[ "$STAGED_KEYCHAIN_GROUP" == "$EXPECTED_APP_IDENTIFIER" ]] || {
    echo "error: staged release contains an unexpected Keychain group" >&2
    exit 1
  }
  RELEASE_SIGNING_STATE="$(
    /usr/bin/codesign -dvvv --entitlements :- "$APP_BUNDLE" 2>&1
  )"
  HELPER_SIGNING_STATE="$(
    /usr/bin/codesign -dvvv "$HELPER_BINARY" 2>&1
  )"
  [[ -f "$APP_CONTENTS/embedded.provisionprofile" ]] || {
    echo "error: Developer ID release is missing its provisioning profile" >&2
    exit 1
  }
  [[ "$RELEASE_SIGNING_STATE" == *"Authority=$DEVELOPER_IDENTITY"* ]] || {
    echo "error: app is not signed by the requested Developer ID identity" >&2
    exit 1
  }
  [[ "$RELEASE_SIGNING_STATE" == *"TeamIdentifier=$DEVELOPMENT_TEAM"* ]] || {
    echo "error: app signature contains an unexpected team" >&2
    exit 1
  }
  [[ "$RELEASE_SIGNING_STATE" == *"flags="*"runtime"* ]] || {
    echo "error: app signature is missing Hardened Runtime" >&2
    exit 1
  }
  [[ "$RELEASE_SIGNING_STATE" == *"Timestamp="* ]] || {
    echo "error: app signature is missing a secure timestamp" >&2
    exit 1
  }
  [[ "$HELPER_SIGNING_STATE" == *"Authority=$DEVELOPER_IDENTITY"* ]] || {
    echo "error: helper is not signed by the requested Developer ID identity" >&2
    exit 1
  }
  [[ "$HELPER_SIGNING_STATE" == *"TeamIdentifier=$DEVELOPMENT_TEAM"* ]] || {
    echo "error: helper signature contains an unexpected team" >&2
    exit 1
  }
  [[ "$HELPER_SIGNING_STATE" == *"flags="*"runtime"* ]] || {
    echo "error: helper signature is missing Hardened Runtime" >&2
    exit 1
  }
  [[ "$HELPER_SIGNING_STATE" == *"Timestamp="* ]] || {
    echo "error: helper signature is missing a secure timestamp" >&2
    exit 1
  }
  echo "Staged $APP_BUNDLE (Developer ID; profile $PROFILE_NAME)"
fi
