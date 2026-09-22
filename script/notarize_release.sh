#!/usr/bin/env bash
set -euo pipefail
umask 077

usage() {
  echo "usage: $0 MAJOR.MINOR.PATCH BUILD_NUMBER arm64|x86_64" >&2
}

if [[ $# -ne 3 ]]; then
  usage
  exit 2
fi

VERSION="$1"
BUILD_NUMBER="$2"
ARCHITECTURE="$3"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: version must use MAJOR.MINOR.PATCH with numeric components" >&2
  exit 2
fi
if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  echo "error: build number must use one to three numeric components" >&2
  exit 2
fi
case "$ARCHITECTURE" in
  arm64|x86_64)
    ;;
  *)
    usage
    exit 2
    ;;
esac

NOTARYTOOL_PROFILE="${BAIROMETER_NOTARYTOOL_PROFILE:-}"
NOTARYTOOL_KEYCHAIN="${BAIROMETER_NOTARYTOOL_KEYCHAIN:-}"
if [[ -z "$NOTARYTOOL_PROFILE" ]]; then
  echo "error: notarization requires BAIROMETER_NOTARYTOOL_PROFILE." >&2
  echo "Set it to a caller-owned Keychain profile; no profile value is stored in this repository." >&2
  exit 1
fi
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Bairometer"
OUTPUT_DIRECTORY="$ROOT_DIR/dist"
PACKAGE_RELEASE_SCRIPT="$ROOT_DIR/script/package_release.sh"
RELEASE_VALIDATOR="$ROOT_DIR/script/validate_release_bundle.sh"
XCRUN_COMMAND="/usr/bin/xcrun"
DITTO_COMMAND="/usr/bin/ditto"
PLUTIL_COMMAND="/usr/bin/plutil"
SUBMISSION_COPY_COMMAND="/bin/cp"
SUBMISSION_COMPARE_COMMAND="/usr/bin/cmp"
PUBLISH_COPY_COMMAND="/bin/cp"
PUBLISH_COMPARE_COMMAND="/usr/bin/cmp"
PUBLISH_RENAME_COMMAND="/bin/mv"
if [[ "${BAIROMETER_NOTARIZATION_TEST_MODE:-0}" == "1" ]]; then
  OUTPUT_DIRECTORY="${BAIROMETER_TEST_OUTPUT_DIRECTORY:?}"
  PACKAGE_RELEASE_SCRIPT="${BAIROMETER_TEST_PACKAGE_RELEASE_SCRIPT:?}"
  RELEASE_VALIDATOR="${BAIROMETER_TEST_RELEASE_VALIDATOR:-$RELEASE_VALIDATOR}"
  XCRUN_COMMAND="${BAIROMETER_TEST_XCRUN_COMMAND:?}"
  DITTO_COMMAND="${BAIROMETER_TEST_DITTO_COMMAND:-$DITTO_COMMAND}"
  PLUTIL_COMMAND="${BAIROMETER_TEST_PLUTIL_COMMAND:-$PLUTIL_COMMAND}"
  PUBLISH_COPY_COMMAND="${BAIROMETER_TEST_PUBLISH_COPY_COMMAND:?}"
  PUBLISH_COMPARE_COMMAND="${BAIROMETER_TEST_PUBLISH_COMPARE_COMMAND:?}"
  PUBLISH_RENAME_COMMAND="${BAIROMETER_TEST_PUBLISH_RENAME_COMMAND:?}"
fi
SIGNED_ARCHIVE="$OUTPUT_DIRECTORY/$APP_NAME-$VERSION-$ARCHITECTURE-signed.zip"
FINAL_ARCHIVE="$OUTPUT_DIRECTORY/$APP_NAME-$VERSION-$ARCHITECTURE.zip"
PRIVATE_WORK_DIRECTORY=""
PUBLISH_TEMPORARY=""
PUBLISH_PREFIX="$OUTPUT_DIRECTORY/.$APP_NAME-$VERSION-$ARCHITECTURE.publish."

remove_publish_temporary() {
  [[ -n "$PUBLISH_TEMPORARY" ]] || return 0
  if [[ "$PUBLISH_TEMPORARY" != "$PUBLISH_PREFIX"* ||
        "${#PUBLISH_TEMPORARY}" -le "${#PUBLISH_PREFIX}" ||
        "$(/usr/bin/dirname "$PUBLISH_TEMPORARY")" != "$OUTPUT_DIRECTORY" ]]; then
    echo "error: refusing to remove an unexpected publish path" >&2
    return 1
  fi
  if ! /bin/rm -f -- "$PUBLISH_TEMPORARY"; then
    echo "error: could not remove task-owned publish temporary" >&2
    return 1
  fi
  PUBLISH_TEMPORARY=""
}

cleanup() {
  local exit_status=$?
  trap - EXIT
  if ! remove_publish_temporary; then
    exit_status=1
  fi
  if [[ -n "$PRIVATE_WORK_DIRECTORY" ]]; then
    if [[ "$exit_status" -eq 0 ]]; then
      if ! /bin/rm -rf -- "$PRIVATE_WORK_DIRECTORY"; then
        exit_status=1
        echo "error: could not remove private notarization diagnostics" >&2
      fi
    else
      /bin/chmod -R go-rwx "$PRIVATE_WORK_DIRECTORY" 2>/dev/null || true
      echo "Private notarization diagnostics retained at: $PRIVATE_WORK_DIRECTORY" >&2
    fi
  fi
  exit "$exit_status"
}
trap cleanup EXIT

[[ -f "$PACKAGE_RELEASE_SCRIPT" ]] || {
  echo "error: release packaging script is missing at $PACKAGE_RELEASE_SCRIPT" >&2
  exit 1
}
[[ -f "$RELEASE_VALIDATOR" ]] || {
  echo "error: release validator is missing at $RELEASE_VALIDATOR" >&2
  exit 1
}

BAIROMETER_RELEASE_OUTPUT_DIRECTORY="$OUTPUT_DIRECTORY" \
  /bin/bash \
  "$PACKAGE_RELEASE_SCRIPT" \
  "$VERSION" \
  "$BUILD_NUMBER" \
  "$ARCHITECTURE" \
  --signed-submission

[[ -s "$SIGNED_ARCHIVE" ]] || {
  echo "error: signed submission archive was not created at $SIGNED_ARCHIVE" >&2
  exit 1
}

PRIVATE_WORK_DIRECTORY="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/Bairometer-notarization.XXXXXX")"
SUBMISSION_ARCHIVE="$PRIVATE_WORK_DIRECTORY/submission.zip"
SUBMISSION_RESULT="$PRIVATE_WORK_DIRECTORY/submission-result.json"
SUBMISSION_ERROR="$PRIVATE_WORK_DIRECTORY/submission-error.log"
"$SUBMISSION_COPY_COMMAND" "$SIGNED_ARCHIVE" "$SUBMISSION_ARCHIVE"
"$SUBMISSION_COMPARE_COMMAND" -s "$SIGNED_ARCHIVE" "$SUBMISSION_ARCHIVE" || {
  echo "error: private submission copy differs from the signed archive" >&2
  exit 1
}

submission_exit=0
submit_archive() {
  if [[ -n "$NOTARYTOOL_KEYCHAIN" ]]; then
    "$XCRUN_COMMAND" notarytool submit "$SUBMISSION_ARCHIVE" \
      --keychain-profile "$NOTARYTOOL_PROFILE" \
      --keychain "$NOTARYTOOL_KEYCHAIN" \
      --wait \
      --output-format json
  else
    "$XCRUN_COMMAND" notarytool submit "$SUBMISSION_ARCHIVE" \
      --keychain-profile "$NOTARYTOOL_PROFILE" \
      --wait \
      --output-format json
  fi
}
if submit_archive >"$SUBMISSION_RESULT" 2>"$SUBMISSION_ERROR"; then
  submission_exit=0
else
  submission_exit=$?
fi

read_submission_value() {
  local key="$1"
  "$PLUTIL_COMMAND" -extract "$key" raw -o - "$SUBMISSION_RESULT" 2>/dev/null || true
}

SUBMISSION_ID="$(read_submission_value id)"
SUBMISSION_STATUS="$(read_submission_value status)"
if [[ "$submission_exit" -ne 0 || "$SUBMISSION_STATUS" != "Accepted" || -z "$SUBMISSION_ID" ]]; then
  echo "error: notarization was not accepted (submission ID: ${SUBMISSION_ID:-unavailable}; status: ${SUBMISSION_STATUS:-unavailable})." >&2
  echo "Private notarytool output: $SUBMISSION_RESULT and $SUBMISSION_ERROR" >&2
  if [[ -n "$SUBMISSION_ID" ]]; then
    echo "Fetch Apple's private log without printing it to public output:" >&2
    if [[ -n "$NOTARYTOOL_KEYCHAIN" ]]; then
      echo "  xcrun notarytool log \"$SUBMISSION_ID\" --keychain-profile \"\$BAIROMETER_NOTARYTOOL_PROFILE\" --keychain \"\$BAIROMETER_NOTARYTOOL_KEYCHAIN\" \"$PRIVATE_WORK_DIRECTORY/apple-notary-log.json\"" >&2
    else
      echo "  xcrun notarytool log \"$SUBMISSION_ID\" --keychain-profile \"\$BAIROMETER_NOTARYTOOL_PROFILE\" \"$PRIVATE_WORK_DIRECTORY/apple-notary-log.json\"" >&2
    fi
  fi
  exit 1
fi

echo "Notarization accepted (submission ID: $SUBMISSION_ID)."

assert_archive_shape() {
  local extraction_directory="$1"
  local extracted_app="$extraction_directory/$APP_NAME.app"
  [[ -d "$extracted_app" ]] || {
    echo "error: archive does not expand to $APP_NAME.app" >&2
    exit 1
  }
  if find "$extraction_directory" -mindepth 1 -maxdepth 1 \
    ! -name "$APP_NAME.app" \
    ! -name '__MACOSX' \
    -print -quit | grep -q .; then
    echo "error: archive contains an unexpected top-level item" >&2
    exit 1
  fi
}

SUBMITTED_EXTRACTION="$PRIVATE_WORK_DIRECTORY/submitted"
mkdir -p "$SUBMITTED_EXTRACTION"
"$DITTO_COMMAND" -x -k "$SUBMISSION_ARCHIVE" "$SUBMITTED_EXTRACTION"
assert_archive_shape "$SUBMITTED_EXTRACTION"
STAPLED_APP="$SUBMITTED_EXTRACTION/$APP_NAME.app"
STAPLER_OUTPUT="$PRIVATE_WORK_DIRECTORY/stapler-staple.log"

if ! "$XCRUN_COMMAND" stapler staple "$STAPLED_APP" \
  >"$STAPLER_OUTPUT" \
  2>&1; then
  echo "error: stapling failed for the accepted submission" >&2
  exit 1
fi
/bin/bash \
  "$RELEASE_VALIDATOR" \
  "$STAPLED_APP" \
  "$VERSION" \
  "$BUILD_NUMBER" \
  "$ARCHITECTURE" \
  --require-notarization

FINAL_CANDIDATE="$PRIVATE_WORK_DIRECTORY/$APP_NAME-$VERSION-$ARCHITECTURE.zip"
"$DITTO_COMMAND" -c -k --sequesterRsrc --keepParent "$STAPLED_APP" "$FINAL_CANDIDATE"
[[ -s "$FINAL_CANDIDATE" ]] || {
  echo "error: notarized release archive was not created" >&2
  exit 1
}

FINAL_EXTRACTION="$PRIVATE_WORK_DIRECTORY/final-archive"
mkdir -p "$FINAL_EXTRACTION"
"$DITTO_COMMAND" -x -k "$FINAL_CANDIDATE" "$FINAL_EXTRACTION"
assert_archive_shape "$FINAL_EXTRACTION"
/bin/bash \
  "$RELEASE_VALIDATOR" \
  "$FINAL_EXTRACTION/$APP_NAME.app" \
  "$VERSION" \
  "$BUILD_NUMBER" \
  "$ARCHITECTURE" \
  --require-notarization

require_publish_destination() {
  if [[ -L "$FINAL_ARCHIVE" ||
        (-e "$FINAL_ARCHIVE" && ! -f "$FINAL_ARCHIVE") ]]; then
    echo "error: final archive path is obstructed; expected an absent path or regular file: $FINAL_ARCHIVE" >&2
    return 1
  fi
}

require_publish_destination
PUBLISH_TEMPORARY="$(/usr/bin/mktemp "$PUBLISH_PREFIX"XXXXXX)"
/bin/chmod 600 "$PUBLISH_TEMPORARY"
if ! "$PUBLISH_COPY_COMMAND" "$FINAL_CANDIDATE" "$PUBLISH_TEMPORARY"; then
  echo "error: could not copy the validated archive into the release directory" >&2
  exit 1
fi
/bin/chmod 600 "$PUBLISH_TEMPORARY"
if ! "$PUBLISH_COMPARE_COMMAND" -s "$FINAL_CANDIDATE" "$PUBLISH_TEMPORARY"; then
  echo "error: release-directory publish copy differs from the validated archive" >&2
  exit 1
fi
require_publish_destination
if ! "$PUBLISH_RENAME_COMMAND" -f "$PUBLISH_TEMPORARY" "$FINAL_ARCHIVE"; then
  echo "error: could not atomically publish the validated release archive" >&2
  exit 1
fi
if [[ -e "$PUBLISH_TEMPORARY" || -L "$PUBLISH_TEMPORARY" ]]; then
  echo "error: atomic publication did not consume the publish temporary" >&2
  exit 1
fi
if [[ -L "$FINAL_ARCHIVE" || ! -f "$FINAL_ARCHIVE" || ! -s "$FINAL_ARCHIVE" ]]; then
  echo "error: published release is not a nonempty regular file: $FINAL_ARCHIVE" >&2
  exit 1
fi
PUBLISH_TEMPORARY=""
echo "Created notarized release $FINAL_ARCHIVE"
