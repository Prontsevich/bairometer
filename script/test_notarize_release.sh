#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/Bairometer-notarization-tests.XXXXXX")"
FAKE_TOOLS="$FIXTURE_ROOT/tools"
PRIVATE_TEMP="$FIXTURE_ROOT/private-tmp"
TOOL_LOG="$FIXTURE_ROOT/tool.log"
mkdir -p "$FAKE_TOOLS" "$PRIVATE_TEMP"

cleanup() {
  rm -rf "$FIXTURE_ROOT"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

cat >"$FAKE_TOOLS/package-release" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

VERSION="$1"
BUILD_NUMBER="$2"
ARCHITECTURE="$3"
[[ "${4:-}" == "--signed-submission" ]]
OUTPUT_DIRECTORY="${BAIROMETER_RELEASE_OUTPUT_DIRECTORY:?}"
APP="$OUTPUT_DIRECTORY/Bairometer.app"
rm -rf "$APP"
mkdir -p \
  "$APP/Contents/MacOS" \
  "$APP/Contents/Helpers" \
  "$APP/Contents/Resources/en.lproj" \
  "$APP/Contents/Resources/ru.lproj" \
  "$APP/Contents/Resources/GRDB_GRDB.bundle"

cat >"$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>io.github.Prontsevich.Bairometer</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
</dict>
</plist>
PLIST

printf '#!/usr/bin/env bash\nexit 0\n' >"$APP/Contents/MacOS/Bairometer"
printf '#!/usr/bin/env bash\nexit 0\n' >"$APP/Contents/Helpers/BairometerClaudeStatusLine"
chmod +x \
  "$APP/Contents/MacOS/Bairometer" \
  "$APP/Contents/Helpers/BairometerClaudeStatusLine"
printf 'icon' >"$APP/Contents/Resources/AppIcon.icns"
printf 'profile' >"$APP/Contents/embedded.provisionprofile"
printf '"fixture" = "fixture";\n' >"$APP/Contents/Resources/en.lproj/Localizable.strings"
printf '"fixture" = "fixture";\n' >"$APP/Contents/Resources/ru.lproj/Localizable.strings"

ARCHIVE="$OUTPUT_DIRECTORY/Bairometer-$VERSION-$ARCHITECTURE-signed.zip"
rm -f "$ARCHIVE"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
printf 'package %s\n' "$ARCHIVE" >>"${FAKE_TOOL_LOG:?}"
SCRIPT

cat >"$FAKE_TOOLS/xcrun" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

printf 'xcrun %s\n' "$*" >>"${FAKE_TOOL_LOG:?}"
if [[ "$1" == "notarytool" && "$2" == "submit" ]]; then
  printf '%s\n' "${FAKE_PRIVATE_STDERR:-private-notary-detail}" >&2
  printf '{"id":"%s","status":"%s"}\n' \
    "${FAKE_SUBMISSION_ID:-fixture-submission}" \
    "${FAKE_NOTARY_STATUS:-Accepted}"
  exit "${FAKE_SUBMIT_EXIT:-0}"
fi

if [[ "$1" == "stapler" && "$2" == "staple" ]]; then
  [[ "${FAKE_STAPLE_EXIT:-0}" -eq 0 ]] || exit "$FAKE_STAPLE_EXIT"
  mkdir -p "$3/Contents/_CodeSignature"
  printf 'ticket' >"$3/Contents/_CodeSignature/notarization-ticket"
  exit 0
fi

if [[ "$1" == "stapler" && "$2" == "validate" ]]; then
  [[ -s "$3/Contents/_CodeSignature/notarization-ticket" ]]
  exit 0
fi

exit 2
SCRIPT

cat >"$FAKE_TOOLS/codesign" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

printf 'codesign %s\n' "$*" >>"${FAKE_TOOL_LOG:?}"
if [[ "$1" == "--verify" ]]; then
  exit "${FAKE_CODESIGN_VERIFY_EXIT:-0}"
fi
if [[ "$1" == "-dvvv" ]]; then
  printf 'Authority=%s\n' "${BAIROMETER_DEVELOPER_IDENTITY:?}" >&2
  printf 'TeamIdentifier=%s\n' "${BAIROMETER_DEVELOPMENT_TEAM:?}" >&2
  printf 'flags=0x10000(runtime)\n' >&2
  printf 'Timestamp=fixture\n' >&2
  exit 0
fi
if [[ " $* " == *" --entitlements "* ]]; then
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.application-identifier</key>
  <string>${BAIROMETER_DEVELOPMENT_TEAM}.io.github.Prontsevich.Bairometer</string>
  <key>com.apple.developer.team-identifier</key>
  <string>${BAIROMETER_DEVELOPMENT_TEAM}</string>
  <key>keychain-access-groups</key>
  <array>
    <string>${BAIROMETER_DEVELOPMENT_TEAM}.io.github.Prontsevich.Bairometer</string>
  </array>
</dict>
</plist>
PLIST
  exit 0
fi
exit 2
SCRIPT

cat >"$FAKE_TOOLS/lipo" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
printf 'lipo %s\n' "$*" >>"${FAKE_TOOL_LOG:?}"
printf '%s\n' "${FAKE_ARCHITECTURE:-arm64}"
SCRIPT

cat >"$FAKE_TOOLS/spctl" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
printf 'spctl %s\n' "$*" >>"${FAKE_TOOL_LOG:?}"
exit "${FAKE_SPCTL_EXIT:-0}"
SCRIPT

cat >"$FAKE_TOOLS/ditto" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

destination="${!#}"
if [[ "$1" == "-c" ]]; then
  printf 'final-candidate-create %s\n' "$*" >>"${FAKE_TOOL_LOG:?}"
elif [[ "$1" == "-x" && "$destination" == */submitted ]]; then
  printf 'submission-extract %s\n' "$*" >>"${FAKE_TOOL_LOG:?}"
elif [[ "$1" == "-x" && "$destination" == */final-archive ]]; then
  printf 'final-candidate-extract %s\n' "$*" >>"${FAKE_TOOL_LOG:?}"
else
  printf 'ditto %s\n' "$*" >>"${FAKE_TOOL_LOG:?}"
fi
exec /usr/bin/ditto "$@"
SCRIPT

cat >"$FAKE_TOOLS/release-validator" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

validator_pass=0
if [[ -s "${FAKE_VALIDATOR_COUNTER:?}" ]]; then
  validator_pass="$(<"$FAKE_VALIDATOR_COUNTER")"
fi
validator_pass=$((validator_pass + 1))
printf '%s\n' "$validator_pass" >"$FAKE_VALIDATOR_COUNTER"
printf 'validate-pass-%s %s\n' "$validator_pass" "$*" >>"${FAKE_TOOL_LOG:?}"
if [[ "${FAKE_VALIDATOR_FAIL_PASS:-0}" -eq "$validator_pass" ]]; then
  exit 41
fi
exec /bin/bash "${REAL_RELEASE_VALIDATOR:?}" "$@"
SCRIPT

cat >"$FAKE_TOOLS/publish-copy" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

printf 'publish-copy %s\n' "$*" >>"${FAKE_TOOL_LOG:?}"
if [[ "${FAKE_PUBLISH_COPY_EXIT:-0}" -ne 0 ]]; then
  printf 'partial-publish' >"$2"
  exit "$FAKE_PUBLISH_COPY_EXIT"
fi
exec /bin/cp "$@"
SCRIPT

cat >"$FAKE_TOOLS/publish-compare" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

printf 'publish-compare %s\n' "$*" >>"${FAKE_TOOL_LOG:?}"
[[ "${FAKE_PUBLISH_COMPARE_EXIT:-0}" -eq 0 ]] || exit "$FAKE_PUBLISH_COMPARE_EXIT"
exec /usr/bin/cmp "$@"
SCRIPT

cat >"$FAKE_TOOLS/publish-rename" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

printf 'publish-rename %s\n' "$*" >>"${FAKE_TOOL_LOG:?}"
source_path="$2"
destination_path="$3"
[[ "$(/usr/bin/dirname "$source_path")" == "$(/usr/bin/dirname "$destination_path")" ]] || exit 72
exec /bin/mv "$@"
SCRIPT

chmod +x "$FAKE_TOOLS/package-release" "$FAKE_TOOLS/xcrun" \
  "$FAKE_TOOLS/codesign" "$FAKE_TOOLS/lipo" "$FAKE_TOOLS/spctl" \
  "$FAKE_TOOLS/ditto" "$FAKE_TOOLS/release-validator" \
  "$FAKE_TOOLS/publish-copy" "$FAKE_TOOLS/publish-compare" \
  "$FAKE_TOOLS/publish-rename"

run_fixture() {
  local output_directory="$1"
  shift
  mkdir -p "$output_directory"
  env \
    TMPDIR="$PRIVATE_TEMP" \
    BAIROMETER_DEVELOPMENT_TEAM="TEST_TEAM" \
    BAIROMETER_DEVELOPER_IDENTITY="Developer ID Application: Fixture (TEST_TEAM)" \
    BAIROMETER_PROVISIONING_PROFILE="$FIXTURE_ROOT/fixture.provisionprofile" \
    BAIROMETER_NOTARYTOOL_PROFILE="FIXTURE_PRIVATE_PROFILE" \
    BAIROMETER_NOTARYTOOL_KEYCHAIN="$FIXTURE_ROOT/fixture.keychain-db" \
    BAIROMETER_NOTARIZATION_TEST_MODE=1 \
    BAIROMETER_TEST_OUTPUT_DIRECTORY="$output_directory" \
    BAIROMETER_TEST_PACKAGE_RELEASE_SCRIPT="$FAKE_TOOLS/package-release" \
    BAIROMETER_TEST_RELEASE_VALIDATOR="$FAKE_TOOLS/release-validator" \
    BAIROMETER_TEST_XCRUN_COMMAND="$FAKE_TOOLS/xcrun" \
    BAIROMETER_TEST_DITTO_COMMAND="$FAKE_TOOLS/ditto" \
    BAIROMETER_TEST_CODESIGN_COMMAND="$FAKE_TOOLS/codesign" \
    BAIROMETER_TEST_LIPO_COMMAND="$FAKE_TOOLS/lipo" \
    BAIROMETER_TEST_SPCTL_COMMAND="$FAKE_TOOLS/spctl" \
    BAIROMETER_TEST_PUBLISH_COPY_COMMAND="$FAKE_TOOLS/publish-copy" \
    BAIROMETER_TEST_PUBLISH_COMPARE_COMMAND="$FAKE_TOOLS/publish-compare" \
    BAIROMETER_TEST_PUBLISH_RENAME_COMMAND="$FAKE_TOOLS/publish-rename" \
    FAKE_VALIDATOR_COUNTER="$output_directory/validator-count" \
    FAKE_TOOL_LOG="$TOOL_LOG" \
    REAL_RELEASE_VALIDATOR="$ROOT_DIR/script/validate_release_bundle.sh" \
    "$@" \
    /bin/bash "$ROOT_DIR/script/notarize_release.sh" 1.2.3 7 arm64
}

assert_full_publish_order() {
  local previous_line=0
  local operation
  local operation_line
  for operation in \
    "xcrun notarytool submit" \
    "xcrun stapler staple" \
    "validate-pass-1" \
    "final-candidate-create" \
    "final-candidate-extract" \
    "validate-pass-2" \
    "publish-copy" \
    "publish-compare" \
    "publish-rename"; do
    operation_line="$(
      grep -n "^$operation " "$TOOL_LOG" |
        /usr/bin/head -n 1 |
        /usr/bin/cut -d: -f1
    )"
    [[ -n "$operation_line" ]] || fail "missing logged operation: $operation"
    [[ "$operation_line" -gt "$previous_line" ]] || \
      fail "operation ran out of order: $operation"
    previous_line="$operation_line"
  done
}

prepare_existing_final() {
  local output_directory="$1"
  mkdir -p "$output_directory"
  printf 'caller-owned-final' >"$output_directory/Bairometer-1.2.3-arm64.zip"
}

assert_existing_final_preserved() {
  local output_directory="$1"
  local scenario="$2"
  [[ "$(/bin/cat "$output_directory/Bairometer-1.2.3-arm64.zip")" == "caller-owned-final" ]] || \
    fail "$scenario replaced a caller-owned final archive"
}

assert_no_publish_temporary() {
  local output_directory="$1"
  local scenario="$2"
  if find "$output_directory" -maxdepth 1 \
    -name '.Bairometer-*.publish.*' \
    -print -quit | grep -q .; then
    fail "$scenario left a task-owned publish temporary"
  fi
}

set +e
missing_result="$({
  BAIROMETER_NOTARYTOOL_PROFILE= \
    /bin/bash "$ROOT_DIR/script/notarize_release.sh" 1.2.3 7 arm64
} 2>&1)"
missing_status=$?
set -e
[[ "$missing_status" -ne 0 ]] || fail "missing Keychain profile unexpectedly passed"
[[ "$missing_result" == *"requires BAIROMETER_NOTARYTOOL_PROFILE"* ]] || \
  fail "missing Keychain profile error was not actionable"

accepted_output="$FIXTURE_ROOT/accepted"
: >"$TOOL_LOG"
accepted_result="$(run_fixture "$accepted_output" 2>&1)" || \
  fail "accepted notarization fixture failed: $accepted_result"
[[ "$accepted_result" != *"FIXTURE_PRIVATE_PROFILE"* ]] || \
  fail "Keychain profile value leaked to public output"
[[ "$accepted_result" != *"$FIXTURE_ROOT/fixture.keychain-db"* ]] || \
  fail "Keychain path leaked to public output"
[[ -s "$accepted_output/Bairometer-1.2.3-arm64-signed.zip" ]] || \
  fail "signed submission archive is missing"
[[ -s "$accepted_output/Bairometer-1.2.3-arm64.zip" ]] || \
  fail "final notarized archive is missing"
[[ -f "$accepted_output/Bairometer-1.2.3-arm64.zip" &&
   ! -L "$accepted_output/Bairometer-1.2.3-arm64.zip" ]] || \
  fail "successful publication is not an exact regular final file"
[[ "$accepted_result" == *"Created notarized release"* ]] || \
  fail "successful publication did not report the final archive"

accepted_extract="$FIXTURE_ROOT/accepted-extract"
mkdir -p "$accepted_extract"
/usr/bin/ditto -x -k \
  "$accepted_output/Bairometer-1.2.3-arm64.zip" \
  "$accepted_extract"
[[ -s "$accepted_extract/Bairometer.app/Contents/_CodeSignature/notarization-ticket" ]] || \
  fail "final archive did not preserve the stapled ticket"
[[ "$(grep -c '^xcrun stapler validate ' "$TOOL_LOG")" -eq 2 ]] || \
  fail "stapler validation did not run for both final app copies"
[[ "$(grep -c '^codesign --verify --deep --strict ' "$TOOL_LOG")" -eq 2 ]] || \
  fail "codesign verification did not run for both final app copies"
[[ "$(grep -c '^spctl --assess --type execute ' "$TOOL_LOG")" -eq 2 ]] || \
  fail "Gatekeeper assessment did not run for both final app copies"
grep -q -- "--keychain $FIXTURE_ROOT/fixture.keychain-db" "$TOOL_LOG" || \
  fail "notarytool submit did not receive the explicit Keychain path"
assert_full_publish_order
assert_no_publish_temporary "$accepted_output" "successful publication"

default_keychain_output="$FIXTURE_ROOT/default-keychain"
: >"$TOOL_LOG"
default_keychain_result="$(run_fixture \
  "$default_keychain_output" \
  BAIROMETER_NOTARYTOOL_KEYCHAIN= \
  2>&1)" || \
  fail "default Keychain notarization fixture failed: $default_keychain_result"
[[ -s "$default_keychain_output/Bairometer-1.2.3-arm64.zip" ]] || \
  fail "default Keychain fixture did not create the final archive"
default_keychain_submit="$(
  grep '^xcrun notarytool submit ' "$TOOL_LOG" | /usr/bin/head -n 1
)"
[[ -n "$default_keychain_submit" ]] || \
  fail "default Keychain fixture did not submit for notarization"
[[ " $default_keychain_submit " != *" --keychain "* ]] || \
  fail "default Keychain fixture passed an empty explicit Keychain"
[[ "$default_keychain_result" != *"FIXTURE_PRIVATE_PROFILE"* ]] || \
  fail "default Keychain profile value leaked to public output"

directory_obstruction_output="$FIXTURE_ROOT/directory-obstruction"
directory_obstruction="$directory_obstruction_output/Bairometer-1.2.3-arm64.zip"
mkdir -p "$directory_obstruction"
printf 'caller-owned-marker' >"$directory_obstruction/marker"
: >"$TOOL_LOG"
set +e
directory_obstruction_result="$(run_fixture \
  "$directory_obstruction_output" \
  2>&1)"
directory_obstruction_status=$?
set -e
[[ "$directory_obstruction_status" -ne 0 ]] || \
  fail "directory obstruction unexpectedly passed"
[[ "$directory_obstruction_result" == *"final archive path is obstructed"* ]] || \
  fail "directory obstruction did not report an actionable error"
[[ "$directory_obstruction_result" != *"Created notarized release"* ]] || \
  fail "directory obstruction reported a created release"
[[ -d "$directory_obstruction" &&
   "$(/bin/cat "$directory_obstruction/marker")" == "caller-owned-marker" ]] || \
  fail "directory obstruction was replaced or modified"
if find "$directory_obstruction" -mindepth 1 -maxdepth 1 \
  ! -name marker \
  -print -quit | grep -q .; then
  fail "publish temporary was moved inside the directory obstruction"
fi
assert_no_publish_temporary \
  "$directory_obstruction_output" \
  "directory obstruction"
if grep -q '^publish-rename ' "$TOOL_LOG"; then
  fail "atomic rename ran against a directory obstruction"
fi

symlink_obstruction_output="$FIXTURE_ROOT/symlink-obstruction"
mkdir -p "$symlink_obstruction_output"
symlink_target="$symlink_obstruction_output/caller-owned-target"
symlink_obstruction="$symlink_obstruction_output/Bairometer-1.2.3-arm64.zip"
printf 'caller-owned-target' >"$symlink_target"
/bin/ln -s "caller-owned-target" "$symlink_obstruction"
: >"$TOOL_LOG"
set +e
symlink_obstruction_result="$(run_fixture \
  "$symlink_obstruction_output" \
  2>&1)"
symlink_obstruction_status=$?
set -e
[[ "$symlink_obstruction_status" -ne 0 ]] || \
  fail "symlink obstruction unexpectedly passed"
[[ "$symlink_obstruction_result" == *"final archive path is obstructed"* ]] || \
  fail "symlink obstruction did not report an actionable error"
[[ "$symlink_obstruction_result" != *"Created notarized release"* ]] || \
  fail "symlink obstruction reported a created release"
[[ -L "$symlink_obstruction" &&
   "$(/usr/bin/readlink "$symlink_obstruction")" == "caller-owned-target" &&
   "$(/bin/cat "$symlink_target")" == "caller-owned-target" ]] || \
  fail "symlink obstruction or its target was replaced"
assert_no_publish_temporary \
  "$symlink_obstruction_output" \
  "symlink obstruction"
if grep -q '^publish-rename ' "$TOOL_LOG"; then
  fail "atomic rename ran against a symlink obstruction"
fi

invalid_output="$FIXTURE_ROOT/invalid"
: >"$TOOL_LOG"
set +e
invalid_result="$(run_fixture \
  "$invalid_output" \
  FAKE_NOTARY_STATUS=Invalid \
  FAKE_SUBMISSION_ID=invalid-submission \
  FAKE_PRIVATE_STDERR=PRIVATE_NOTARY_LOG_CONTENT \
  2>&1)"
invalid_status=$?
set -e
[[ "$invalid_status" -ne 0 ]] || fail "Invalid notarization unexpectedly passed"
[[ "$invalid_result" == *"submission ID: invalid-submission; status: Invalid"* ]] || \
  fail "Invalid notarization did not report safe submission metadata"
[[ "$invalid_result" == *'--keychain-profile "$BAIROMETER_NOTARYTOOL_PROFILE"'* ]] || \
  fail "Invalid notarization did not provide a safe private-log command"
[[ "$invalid_result" != *"FIXTURE_PRIVATE_PROFILE"* ]] || \
  fail "Keychain profile value leaked on failure"
[[ "$invalid_result" != *"PRIVATE_NOTARY_LOG_CONTENT"* ]] || \
  fail "private notarytool output leaked on failure"
[[ ! -e "$invalid_output/Bairometer-1.2.3-arm64.zip" ]] || \
  fail "Invalid notarization created a final archive"
if grep -q '^xcrun stapler staple ' "$TOOL_LOG"; then
  fail "Invalid notarization proceeded to stapling"
fi

submit_failure_output="$FIXTURE_ROOT/submit-failure"
: >"$TOOL_LOG"
set +e
submit_failure_result="$(run_fixture \
  "$submit_failure_output" \
  FAKE_NOTARY_STATUS=Accepted \
  FAKE_SUBMISSION_ID=nonzero-submission \
  FAKE_SUBMIT_EXIT=12 \
  2>&1)"
submit_failure_status=$?
set -e
[[ "$submit_failure_status" -ne 0 ]] || \
  fail "nonzero notarytool exit unexpectedly passed"
[[ "$submit_failure_result" == *"submission ID: nonzero-submission; status: Accepted"* ]] || \
  fail "nonzero notarytool exit did not report safe submission metadata"
[[ ! -e "$submit_failure_output/Bairometer-1.2.3-arm64.zip" ]] || \
  fail "nonzero notarytool exit created a final archive"
if grep -q '^xcrun stapler staple ' "$TOOL_LOG"; then
  fail "nonzero notarytool exit proceeded to stapling"
fi

first_validator_output="$FIXTURE_ROOT/first-validator-failure"
prepare_existing_final "$first_validator_output"
: >"$TOOL_LOG"
set +e
first_validator_result="$(run_fixture \
  "$first_validator_output" \
  FAKE_VALIDATOR_FAIL_PASS=1 \
  2>&1)"
first_validator_status=$?
set -e
[[ "$first_validator_status" -ne 0 ]] || \
  fail "first validator failure unexpectedly passed"
assert_existing_final_preserved \
  "$first_validator_output" \
  "first validator failure"
assert_no_publish_temporary \
  "$first_validator_output" \
  "first validator failure"
grep -q '^validate-pass-1 ' "$TOOL_LOG" || \
  fail "first validator pass was not logged"
if grep -q '^final-candidate-create ' "$TOOL_LOG"; then
  fail "final candidate was created after first validator failure"
fi
if grep -q '^publish-' "$TOOL_LOG"; then
  fail "publication began after first validator failure"
fi

second_validator_output="$FIXTURE_ROOT/second-validator-failure"
prepare_existing_final "$second_validator_output"
: >"$TOOL_LOG"
set +e
second_validator_result="$(run_fixture \
  "$second_validator_output" \
  FAKE_VALIDATOR_FAIL_PASS=2 \
  2>&1)"
second_validator_status=$?
set -e
[[ "$second_validator_status" -ne 0 ]] || \
  fail "second validator failure unexpectedly passed"
assert_existing_final_preserved \
  "$second_validator_output" \
  "second validator failure"
assert_no_publish_temporary \
  "$second_validator_output" \
  "second validator failure"
grep -q '^final-candidate-create ' "$TOOL_LOG" || \
  fail "second validator fixture did not create a final candidate"
grep -q '^final-candidate-extract ' "$TOOL_LOG" || \
  fail "second validator fixture did not extract the final candidate"
grep -q '^validate-pass-2 ' "$TOOL_LOG" || \
  fail "second validator pass was not logged"
if grep -q '^publish-' "$TOOL_LOG"; then
  fail "publication began before the second validator passed"
fi

publish_copy_output="$FIXTURE_ROOT/publish-copy-failure"
prepare_existing_final "$publish_copy_output"
: >"$TOOL_LOG"
set +e
publish_copy_result="$(run_fixture \
  "$publish_copy_output" \
  FAKE_PUBLISH_COPY_EXIT=51 \
  2>&1)"
publish_copy_status=$?
set -e
[[ "$publish_copy_status" -ne 0 ]] || \
  fail "publish copy failure unexpectedly passed"
assert_existing_final_preserved "$publish_copy_output" "publish copy failure"
assert_no_publish_temporary "$publish_copy_output" "publish copy failure"
grep -q '^validate-pass-2 ' "$TOOL_LOG" || \
  fail "publish copy began before second validation"
grep -q '^publish-copy ' "$TOOL_LOG" || \
  fail "publish copy failure was not logged"
if grep -q '^publish-compare ' "$TOOL_LOG" || \
   grep -q '^publish-rename ' "$TOOL_LOG"; then
  fail "publish continued after copy failure"
fi

publish_compare_output="$FIXTURE_ROOT/publish-compare-failure"
prepare_existing_final "$publish_compare_output"
: >"$TOOL_LOG"
set +e
publish_compare_result="$(run_fixture \
  "$publish_compare_output" \
  FAKE_PUBLISH_COMPARE_EXIT=52 \
  2>&1)"
publish_compare_status=$?
set -e
[[ "$publish_compare_status" -ne 0 ]] || \
  fail "publish compare failure unexpectedly passed"
assert_existing_final_preserved \
  "$publish_compare_output" \
  "publish compare failure"
assert_no_publish_temporary \
  "$publish_compare_output" \
  "publish compare failure"
grep -q '^validate-pass-2 ' "$TOOL_LOG" || \
  fail "publish compare began before second validation"
grep -q '^publish-copy ' "$TOOL_LOG" || \
  fail "publish compare fixture did not copy the candidate"
grep -q '^publish-compare ' "$TOOL_LOG" || \
  fail "publish compare failure was not logged"
if grep -q '^publish-rename ' "$TOOL_LOG"; then
  fail "publish rename ran after compare failure"
fi

staple_output="$FIXTURE_ROOT/staple-failure"
prepare_existing_final "$staple_output"
: >"$TOOL_LOG"
set +e
staple_result="$(run_fixture \
  "$staple_output" \
  FAKE_STAPLE_EXIT=9 \
  2>&1)"
staple_status=$?
set -e
[[ "$staple_status" -ne 0 ]] || fail "stapler failure unexpectedly passed"
assert_existing_final_preserved "$staple_output" "stapler failure"
assert_no_publish_temporary "$staple_output" "stapler failure"
[[ -s "$staple_output/Bairometer-1.2.3-arm64-signed.zip" ]] || \
  fail "stapler failure removed the signed submission archive"

echo "PASS: notarization fixtures"
