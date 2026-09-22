#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/release.yml"
SETUP_SCRIPT="$ROOT_DIR/script/setup_ci_release_credentials.sh"
CLEANUP_SCRIPT="$ROOT_DIR/script/cleanup_ci_release_credentials.sh"
FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/Bairometer-release-workflow-tests.XXXXXX")"
FAKE_TOOLS="$FIXTURE_ROOT/tools"
FAKE_TOOL_LOG="$FIXTURE_ROOT/tool.log"
mkdir -p "$FAKE_TOOLS"

cleanup() {
  rm -rf "$FIXTURE_ROOT"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

ruby - "$WORKFLOW" <<'RUBY'
require "yaml"

workflow_path = ARGV.fetch(0)
workflow_text = File.read(workflow_path)
workflow = YAML.safe_load(workflow_text, aliases: true)
triggers = workflow["on"] || workflow[true]
abort "workflow must be manual-only" unless triggers.is_a?(Hash) && triggers.keys == ["workflow_dispatch"]
abort "permissions must be contents: read" unless workflow["permissions"] == {"contents" => "read"}

jobs = workflow.fetch("jobs")
authorize = jobs.fetch("authorize")
build = jobs.fetch("build-notarized-artifacts")
abort "build must depend on authorization" unless build["needs"] == "authorize"
abort "protected release environment is missing" unless build.dig("environment", "name") == "protected-release"

authorization_run = authorize.fetch("steps").map { |step| step["run"].to_s }.join("\n")
abort "manual event gate is missing" unless authorization_run.include?("workflow_dispatch")
abort "main ref gate is missing" unless authorization_run.include?("refs/heads/main")
abort "protected ref gate is missing" unless authorization_run.include?("RELEASE_REF_PROTECTED")

matrix = build.dig("strategy", "matrix", "include")
expected_matrix = [
  {"architecture" => "arm64", "runner" => "macos-26"},
  {"architecture" => "x86_64", "runner" => "macos-26-intel"}
]
abort "release runner matrix is incorrect" unless matrix == expected_matrix
abort "matrix runner selection is missing" unless build["runs-on"] == "${{ matrix.runner }}"

steps = build.fetch("steps")
toolchain_index = steps.index { |step| step["name"] == "Select installed Xcode 26 toolchain" }
credential_steps = steps.select { |step| step.to_s.include?("${{ secrets.") }
abort "secrets must be scoped to one setup step" unless credential_steps.length == 1
credential_step = credential_steps.fetch(0)
credential_index = steps.index(credential_step)
abort "Xcode 26 must be selected before credential use" unless toolchain_index && toolchain_index < credential_index
abort "Xcode 26 selection is missing" unless steps.fetch(toolchain_index).fetch("run").include?("Xcode_26")
abort "Xcode version selection must not close xcodebuild stdout early" if steps.fetch(toolchain_index).fetch("run").include?("xcodebuild -version |")
abort "credential setup script is not used" unless credential_step["run"] == "/bin/bash script/setup_ci_release_credentials.sh"
abort "credential setup step is missing an outcome identifier" unless credential_step["id"] == "release_credentials"
required_secrets = %w[
  DEVELOPER_ID_P12_BASE64
  DEVELOPER_ID_P12_PASSWORD
  DEVELOPER_ID_PROVISIONING_PROFILE_BASE64
  NOTARYTOOL_APPLE_ID
  NOTARYTOOL_TEAM_ID
  NOTARYTOOL_PASSWORD
]
credential_environment = credential_step.fetch("env").values.join("\n")
required_secrets.each do |secret|
  abort "missing workflow secret #{secret}" unless credential_environment.include?("secrets.#{secret}")
end

uses = steps.map { |step| step["uses"] }.compact
abort "workflow must use only pinned official actions" unless uses.all? do |entry|
  entry.match?(/\Aactions\/(checkout|upload-artifact)@[0-9a-f]{40}\z/)
end
abort "checkout action is missing" unless uses.any? { |entry| entry.start_with?("actions/checkout@") }
abort "artifact action is missing" unless uses.any? { |entry| entry.start_with?("actions/upload-artifact@") }
checkout = steps.find { |step| step["uses"].to_s.start_with?("actions/checkout@") }
abort "checkout must not persist its token" unless checkout.dig("with", "persist-credentials") == false

pipeline_index = steps.index { |step| step["name"] == "Build, notarize, and staple release" }
validation_index = steps.index { |step| step["name"] == "Independently validate final archive" }
upload_index = steps.index { |step| step["name"] == "Upload architecture-specific artifact" }
cleanup_index = steps.index { |step| step["name"] == "Destroy ephemeral release credentials" }
abort "release pipeline ordering is incomplete" unless [pipeline_index, validation_index, upload_index, cleanup_index].all?
abort "cleanup must precede artifact upload" unless pipeline_index < validation_index && validation_index < cleanup_index && cleanup_index < upload_index
abort "artifact upload must be the final step" unless upload_index == steps.length - 1

pipeline_run = steps.fetch(pipeline_index).fetch("run")
abort "existing notarization pipeline is not called" unless pipeline_run.include?("script/notarize_release.sh")
abort "private pipeline logging is missing" unless pipeline_run.include?("release-pipeline.log") && pipeline_run.include?("2>&1")
validation_run = steps.fetch(validation_index).fetch("run")
abort "independent final archive extraction is missing" unless validation_run.include?("/usr/bin/ditto -x -k")
abort "independent trust validation is missing" unless validation_run.include?("script/validate_release_bundle.sh") && validation_run.include?("--require-notarization")

upload = steps.fetch(upload_index)
abort "artifact upload must use implicit success gating" if upload.key?("if")
abort "artifact name is not architecture-specific" unless upload.dig("with", "name").include?("${{ matrix.architecture }}")
abort "artifact path is not architecture-specific" unless upload.dig("with", "path").include?("${{ matrix.architecture }}")
retention_days = upload.dig("with", "retention-days")
abort "artifact retention is not short-lived" unless retention_days.is_a?(Integer) && retention_days <= 3

cleanup = steps.fetch(cleanup_index)
abort "cleanup must run after credential setup" unless cleanup["if"] == "${{ always() && steps.release_credentials.outcome == 'success' }}"
abort "cleanup script is not used" unless cleanup["run"] == "/bin/bash script/cleanup_ci_release_credentials.sh"

forbidden_publication = /(?:gh\s+release|create-release|softprops\/action-gh-release|actions\/create-release|contents:\s*write)/
abort "release publication must remain disabled" if workflow_text.match?(forbidden_publication)
RUBY

cat >"$FAKE_TOOLS/security" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

command_name="$1"
printf 'security-command %s\n' "$command_name" >>"${FAKE_TOOL_LOG:?}"
case "$command_name" in
  create-keychain)
    keychain_path="${!#}"
    printf 'fixture-keychain' >"$keychain_path"
    ;;
  import)
    exit "${FAKE_IMPORT_EXIT:-0}"
    ;;
  cms)
    output_path=""
    while [[ $# -gt 0 ]]; do
      if [[ "$1" == "-o" ]]; then
        output_path="$2"
        break
      fi
      shift
    done
    [[ -n "$output_path" ]]
    printf 'fixture-profile-plist' >"$output_path"
    ;;
  find-identity)
    printf '  1) %s "Developer ID Application: Fixture (TESTTEAM01)"\n' \
      "${FAKE_IDENTITY_FINGERPRINT:-0123456789ABCDEF0123456789ABCDEF01234567}"
    printf '     1 valid identities found\n'
    ;;
  delete-keychain)
    /bin/rm -f -- "${!#}"
    ;;
esac
SCRIPT

cat >"$FAKE_TOOLS/xcrun" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

printf 'xcrun-command %s %s\n' "${1:-}" "${2:-}" >>"${FAKE_TOOL_LOG:?}"
if [[ "${1:-}" == "notarytool" && "${2:-}" == "store-credentials" ]]; then
  keychain_argument=""
  validate_argument=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --keychain)
        keychain_argument="$2"
        shift 2
        ;;
      --validate)
        validate_argument=1
        shift
        ;;
      *)
        shift
        ;;
    esac
  done
  [[ "$keychain_argument" == "${BAIROMETER_CI_KEYCHAIN_PATH:?}" ]]
  [[ "$validate_argument" -eq 1 ]]
  printf 'notary-keychain-explicit\n' >>"${FAKE_TOOL_LOG:?}"
  exit "${FAKE_NOTARY_EXIT:-0}"
fi
exit 2
SCRIPT

cat >"$FAKE_TOOLS/plutil" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$1" == "-lint" ]]; then
  exit 0
fi
if [[ "$1" == "-extract" && "$2" == "DeveloperCertificates" ]]; then
  printf '<array><data>fixture</data></array>\n'
  exit 0
fi
if [[ "$1" == "-extract" && "$2" == "DeveloperCertificates.0" ]]; then
  output_path=""
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "-o" ]]; then
      output_path="$2"
      break
    fi
    shift
  done
  [[ -n "$output_path" ]]
  printf 'Zml4dHVyZS1jZXJ0' >"$output_path"
  exit 0
fi
exit 2
SCRIPT

cat >"$FAKE_TOOLS/plist-buddy" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
printf 'TESTTEAM01\n'
SCRIPT

cat >"$FAKE_TOOLS/openssl" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == "x509" ]]
printf 'sha1 Fingerprint=01:23:45:67:89:AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67\n'
SCRIPT

cat >"$FAKE_TOOLS/uuidgen" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
printf 'fixture-ephemeral-keychain-password\n'
SCRIPT

chmod +x \
  "$FAKE_TOOLS/security" \
  "$FAKE_TOOLS/xcrun" \
  "$FAKE_TOOLS/plutil" \
  "$FAKE_TOOLS/plist-buddy" \
  "$FAKE_TOOLS/openssl" \
  "$FAKE_TOOLS/uuidgen"

run_setup() {
  local runner_temp="$1"
  local github_environment_file="$2"
  shift 2
  env \
    RUNNER_TEMP="$runner_temp" \
    GITHUB_ENV="$github_environment_file" \
    BAIROMETER_CI_PRIVATE_DIRECTORY="$runner_temp/Bairometer-ci-release-private" \
    BAIROMETER_CI_KEYCHAIN_PATH="$runner_temp/Bairometer-ci-release.keychain-db" \
    BAIROMETER_CI_DEVELOPER_ID_P12_BASE64="cDEyLWZpeHR1cmU=" \
    BAIROMETER_CI_DEVELOPER_ID_P12_PASSWORD="p12-fixture-password" \
    BAIROMETER_CI_PROVISIONING_PROFILE_BASE64="cHJvZmlsZS1maXh0dXJl" \
    BAIROMETER_CI_NOTARYTOOL_APPLE_ID="fixture@example.invalid" \
    BAIROMETER_CI_NOTARYTOOL_TEAM_ID="TESTTEAM01" \
    BAIROMETER_CI_NOTARYTOOL_PASSWORD="notary-fixture-password" \
    BAIROMETER_CI_CREDENTIAL_TEST_MODE=1 \
    BAIROMETER_TEST_SECURITY_COMMAND="$FAKE_TOOLS/security" \
    BAIROMETER_TEST_XCRUN_COMMAND="$FAKE_TOOLS/xcrun" \
    BAIROMETER_TEST_PLUTIL_COMMAND="$FAKE_TOOLS/plutil" \
    BAIROMETER_TEST_PLIST_BUDDY_COMMAND="$FAKE_TOOLS/plist-buddy" \
    BAIROMETER_TEST_OPENSSL_COMMAND="$FAKE_TOOLS/openssl" \
    BAIROMETER_TEST_UUIDGEN_COMMAND="$FAKE_TOOLS/uuidgen" \
    FAKE_TOOL_LOG="$FAKE_TOOL_LOG" \
    "$@" \
    /bin/bash "$SETUP_SCRIPT"
}

assert_no_private_material() {
  local runner_temp="$1"
  local scenario="$2"
  [[ ! -e "$runner_temp/Bairometer-ci-release-private" &&
     ! -L "$runner_temp/Bairometer-ci-release-private" ]] || \
    fail "$scenario retained private diagnostics or decoded material"
  [[ ! -e "$runner_temp/Bairometer-ci-release.keychain-db" &&
     ! -L "$runner_temp/Bairometer-ci-release.keychain-db" ]] || \
    fail "$scenario retained the ephemeral keychain"
}

preexisting_private_runner="$FIXTURE_ROOT/preexisting-private-runner"
preexisting_private_environment="$FIXTURE_ROOT/preexisting-private-github-env"
preexisting_private="$preexisting_private_runner/Bairometer-ci-release-private"
mkdir -p "$preexisting_private"
printf 'caller-owned-marker' >"$preexisting_private/.credential-owner"
printf 'caller-owned-private' >"$preexisting_private/caller-marker"
: >"$preexisting_private_environment"
: >"$FAKE_TOOL_LOG"
set +e
preexisting_private_result="$(run_setup \
  "$preexisting_private_runner" \
  "$preexisting_private_environment" \
  2>&1)"
preexisting_private_status=$?
set -e
[[ "$preexisting_private_status" -ne 0 ]] || \
  fail "pre-existing private directory unexpectedly passed"
[[ "$preexisting_private_result" == *"private release directory already exists"* ]] || \
  fail "pre-existing private directory was not reported"
[[ "$(/bin/cat "$preexisting_private/.credential-owner")" == "caller-owned-marker" &&
   "$(/bin/cat "$preexisting_private/caller-marker")" == "caller-owned-private" ]] || \
  fail "pre-existing private directory or marker was modified"
[[ ! -s "$FAKE_TOOL_LOG" ]] || \
  fail "credential tooling ran after a private-directory collision"
set +e
preexisting_private_cleanup_result="$(env \
  RUNNER_TEMP="$preexisting_private_runner" \
  BAIROMETER_CI_PRIVATE_DIRECTORY="$preexisting_private" \
  BAIROMETER_CI_KEYCHAIN_PATH="$preexisting_private_runner/Bairometer-ci-release.keychain-db" \
  BAIROMETER_CI_CREDENTIAL_TEST_MODE=1 \
  BAIROMETER_TEST_SECURITY_COMMAND="$FAKE_TOOLS/security" \
  FAKE_TOOL_LOG="$FAKE_TOOL_LOG" \
  /bin/bash "$CLEANUP_SCRIPT" \
  2>&1)"
preexisting_private_cleanup_status=$?
set -e
[[ "$preexisting_private_cleanup_status" -ne 0 ]] || \
  fail "standalone cleanup accepted a caller-owned private directory"
[[ "$(/bin/cat "$preexisting_private/caller-marker")" == "caller-owned-private" ]] || \
  fail "standalone cleanup removed caller-owned private material"

preexisting_keychain_runner="$FIXTURE_ROOT/preexisting-keychain-runner"
preexisting_keychain_environment="$FIXTURE_ROOT/preexisting-keychain-github-env"
preexisting_keychain="$preexisting_keychain_runner/Bairometer-ci-release.keychain-db"
mkdir -p "$preexisting_keychain_runner"
printf 'caller-owned-keychain' >"$preexisting_keychain"
: >"$preexisting_keychain_environment"
: >"$FAKE_TOOL_LOG"
set +e
preexisting_keychain_result="$(run_setup \
  "$preexisting_keychain_runner" \
  "$preexisting_keychain_environment" \
  2>&1)"
preexisting_keychain_status=$?
set -e
[[ "$preexisting_keychain_status" -ne 0 ]] || \
  fail "pre-existing keychain unexpectedly passed"
[[ "$preexisting_keychain_result" == *"release keychain path already exists"* ]] || \
  fail "pre-existing keychain was not reported"
[[ "$(/bin/cat "$preexisting_keychain")" == "caller-owned-keychain" ]] || \
  fail "pre-existing keychain was modified"
[[ ! -s "$FAKE_TOOL_LOG" ]] || \
  fail "credential tooling ran after a keychain collision"
set +e
preexisting_keychain_cleanup_result="$(env \
  RUNNER_TEMP="$preexisting_keychain_runner" \
  BAIROMETER_CI_PRIVATE_DIRECTORY="$preexisting_keychain_runner/Bairometer-ci-release-private" \
  BAIROMETER_CI_KEYCHAIN_PATH="$preexisting_keychain" \
  BAIROMETER_CI_CREDENTIAL_TEST_MODE=1 \
  BAIROMETER_TEST_SECURITY_COMMAND="$FAKE_TOOLS/security" \
  FAKE_TOOL_LOG="$FAKE_TOOL_LOG" \
  /bin/bash "$CLEANUP_SCRIPT" \
  2>&1)"
preexisting_keychain_cleanup_status=$?
set -e
[[ "$preexisting_keychain_cleanup_status" -ne 0 ]] || \
  fail "standalone cleanup accepted a caller-owned keychain"
[[ "$(/bin/cat "$preexisting_keychain")" == "caller-owned-keychain" ]] || \
  fail "standalone cleanup removed a caller-owned keychain"

private_symlink_runner="$FIXTURE_ROOT/private-symlink-runner"
private_symlink_environment="$FIXTURE_ROOT/private-symlink-github-env"
private_symlink_target="$FIXTURE_ROOT/private-symlink-target"
private_symlink="$private_symlink_runner/Bairometer-ci-release-private"
mkdir -p "$private_symlink_runner" "$private_symlink_target"
printf 'caller-owned-symlink-target' >"$private_symlink_target/marker"
/bin/ln -s "$private_symlink_target" "$private_symlink"
: >"$private_symlink_environment"
set +e
private_symlink_result="$(run_setup \
  "$private_symlink_runner" \
  "$private_symlink_environment" \
  2>&1)"
private_symlink_status=$?
set -e
[[ "$private_symlink_status" -ne 0 ]] || \
  fail "pre-existing private-directory symlink unexpectedly passed"
[[ -L "$private_symlink" &&
   "$(/bin/cat "$private_symlink_target/marker")" == "caller-owned-symlink-target" ]] || \
  fail "pre-existing private-directory symlink was modified"

keychain_symlink_runner="$FIXTURE_ROOT/keychain-symlink-runner"
keychain_symlink_environment="$FIXTURE_ROOT/keychain-symlink-github-env"
keychain_symlink_target="$FIXTURE_ROOT/keychain-symlink-target"
keychain_symlink="$keychain_symlink_runner/Bairometer-ci-release.keychain-db"
mkdir -p "$keychain_symlink_runner"
printf 'caller-owned-keychain-target' >"$keychain_symlink_target"
/bin/ln -s "$keychain_symlink_target" "$keychain_symlink"
: >"$keychain_symlink_environment"
set +e
keychain_symlink_result="$(run_setup \
  "$keychain_symlink_runner" \
  "$keychain_symlink_environment" \
  2>&1)"
keychain_symlink_status=$?
set -e
[[ "$keychain_symlink_status" -ne 0 ]] || \
  fail "pre-existing keychain symlink unexpectedly passed"
[[ -L "$keychain_symlink" &&
   "$(/bin/cat "$keychain_symlink_target")" == "caller-owned-keychain-target" ]] || \
  fail "pre-existing keychain symlink was modified"

missing_runner="$FIXTURE_ROOT/missing-runner"
missing_environment="$FIXTURE_ROOT/missing-github-env"
mkdir -p "$missing_runner"
: >"$missing_environment"
: >"$FAKE_TOOL_LOG"
set +e
missing_result="$(run_setup \
  "$missing_runner" \
  "$missing_environment" \
  BAIROMETER_CI_DEVELOPER_ID_P12_BASE64= \
  2>&1)"
missing_status=$?
set -e
[[ "$missing_status" -ne 0 ]] || fail "missing credential preflight unexpectedly passed"
[[ "$missing_result" == *"required protected release credentials are missing"* ]] || \
  fail "missing credential preflight was not actionable"
[[ ! -s "$FAKE_TOOL_LOG" ]] || \
  fail "credential tooling ran before missing-secret preflight"
assert_no_private_material "$missing_runner" "missing credential preflight"

invalid_import_runner="$FIXTURE_ROOT/invalid-import-runner"
invalid_import_environment="$FIXTURE_ROOT/invalid-import-github-env"
mkdir -p "$invalid_import_runner"
: >"$invalid_import_environment"
: >"$FAKE_TOOL_LOG"
set +e
invalid_import_result="$(run_setup \
  "$invalid_import_runner" \
  "$invalid_import_environment" \
  FAKE_IMPORT_EXIT=44 \
  2>&1)"
invalid_import_status=$?
set -e
[[ "$invalid_import_status" -ne 0 ]] || fail "invalid P12 import unexpectedly passed"
[[ "$invalid_import_result" == *"signing material could not be imported"* ]] || \
  fail "invalid P12 import was not actionable"
[[ ! -s "$invalid_import_environment" ]] || \
  fail "invalid P12 import exported release environment values"
grep -q '^security-command delete-keychain$' "$FAKE_TOOL_LOG" || \
  fail "invalid P12 import did not delete the ephemeral keychain"
if grep -q '^xcrun-command notarytool store-credentials$' "$FAKE_TOOL_LOG"; then
  fail "notary credentials were configured after invalid P12 import"
fi
assert_no_private_material "$invalid_import_runner" "invalid P12 import"

mismatched_identity_runner="$FIXTURE_ROOT/mismatched-identity-runner"
mismatched_identity_environment="$FIXTURE_ROOT/mismatched-identity-github-env"
mkdir -p "$mismatched_identity_runner"
: >"$mismatched_identity_environment"
: >"$FAKE_TOOL_LOG"
set +e
mismatched_identity_result="$(run_setup \
  "$mismatched_identity_runner" \
  "$mismatched_identity_environment" \
  FAKE_IDENTITY_FINGERPRINT=FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF \
  2>&1)"
mismatched_identity_status=$?
set -e
[[ "$mismatched_identity_status" -ne 0 ]] || \
  fail "mismatched signing identity unexpectedly passed"
[[ "$mismatched_identity_result" == *"does not match the provisioning profile"* ]] || \
  fail "mismatched signing identity was not actionable"
[[ ! -s "$mismatched_identity_environment" ]] || \
  fail "mismatched signing identity exported release environment values"
if grep -q '^xcrun-command notarytool store-credentials$' "$FAKE_TOOL_LOG"; then
  fail "notary credentials were configured after identity mismatch"
fi
assert_no_private_material "$mismatched_identity_runner" "mismatched signing identity"

invalid_notary_runner="$FIXTURE_ROOT/invalid-notary-runner"
invalid_notary_environment="$FIXTURE_ROOT/invalid-notary-github-env"
mkdir -p "$invalid_notary_runner"
: >"$invalid_notary_environment"
: >"$FAKE_TOOL_LOG"
set +e
invalid_notary_result="$(run_setup \
  "$invalid_notary_runner" \
  "$invalid_notary_environment" \
  FAKE_NOTARY_EXIT=65 \
  2>&1)"
invalid_notary_status=$?
set -e
[[ "$invalid_notary_status" -ne 0 ]] || fail "invalid notary credentials unexpectedly passed"
[[ "$invalid_notary_result" == *"notary credentials could not be validated"* ]] || \
  fail "invalid notary credentials were not actionable"
[[ ! -s "$invalid_notary_environment" ]] || \
  fail "invalid notary credentials exported release environment values"
grep -q '^notary-keychain-explicit$' "$FAKE_TOOL_LOG" || \
  fail "notary validation did not receive the exact ephemeral keychain"
assert_no_private_material "$invalid_notary_runner" "invalid notary credentials"

valid_runner="$FIXTURE_ROOT/valid-runner"
valid_environment="$FIXTURE_ROOT/valid-github-env"
mkdir -p "$valid_runner"
: >"$valid_environment"
: >"$FAKE_TOOL_LOG"
valid_result="$(run_setup "$valid_runner" "$valid_environment" 2>&1)" || \
  fail "valid credential fixture failed: $valid_result"
[[ "$valid_result" == "Configured ephemeral protected release credentials." ]] || \
  fail "valid credential fixture emitted unexpected public output"
[[ -s "$valid_runner/Bairometer-ci-release.keychain-db" ]] || \
  fail "valid credential fixture did not create the ephemeral keychain"
[[ -d "$valid_runner/Bairometer-ci-release-private" ]] || \
  fail "valid credential fixture did not retain private material for the release step"
grep -q '^notary-keychain-explicit$' "$FAKE_TOOL_LOG" || \
  fail "notary profile was not stored in the exact ephemeral keychain"
grep -q '^BAIROMETER_DEVELOPMENT_TEAM=TESTTEAM01$' "$valid_environment" || \
  fail "derived signing team was not exported"
grep -q '^BAIROMETER_DEVELOPER_IDENTITY=Developer ID Application: Fixture (TESTTEAM01)$' \
  "$valid_environment" || \
  fail "matching Developer ID identity was not derived"
grep -q "^BAIROMETER_NOTARYTOOL_KEYCHAIN=$valid_runner/Bairometer-ci-release.keychain-db$" \
  "$valid_environment" || \
  fail "exact notary keychain was not exported"
valid_owner_token="$(
  /usr/bin/sed -n 's/^BAIROMETER_CI_CREDENTIAL_OWNER=//p' "$valid_environment"
)"
[[ "$valid_owner_token" =~ ^[A-Za-z0-9-]{16,128}$ ]] || \
  fail "credential ownership token was not exported"
[[ "$(/bin/cat "$valid_runner/Bairometer-ci-release-private/.credential-owner")" == "$valid_owner_token" ]] || \
  fail "credential ownership marker does not match the current invocation"

cleanup_result="$(env \
  RUNNER_TEMP="$valid_runner" \
  BAIROMETER_CI_PRIVATE_DIRECTORY="$valid_runner/Bairometer-ci-release-private" \
  BAIROMETER_CI_KEYCHAIN_PATH="$valid_runner/Bairometer-ci-release.keychain-db" \
  BAIROMETER_CI_CREDENTIAL_OWNER="$valid_owner_token" \
  BAIROMETER_CI_CREDENTIAL_TEST_MODE=1 \
  BAIROMETER_TEST_SECURITY_COMMAND="$FAKE_TOOLS/security" \
  FAKE_TOOL_LOG="$FAKE_TOOL_LOG" \
  /bin/bash "$CLEANUP_SCRIPT" \
  2>&1)" || fail "explicit credential cleanup failed: $cleanup_result"
[[ "$cleanup_result" == "Destroyed ephemeral protected release credentials." ]] || \
  fail "explicit credential cleanup emitted unexpected public output"
assert_no_private_material "$valid_runner" "explicit credential cleanup"

unsafe_runner="$FIXTURE_ROOT/unsafe-runner"
unsafe_private="$FIXTURE_ROOT/caller-owned-private"
unsafe_keychain="$unsafe_runner/Bairometer-ci-release.keychain-db"
mkdir -p "$unsafe_runner" "$unsafe_private"
printf 'caller-owned' >"$unsafe_private/marker"
set +e
unsafe_result="$(env \
  RUNNER_TEMP="$unsafe_runner" \
  BAIROMETER_CI_PRIVATE_DIRECTORY="$unsafe_private" \
  BAIROMETER_CI_KEYCHAIN_PATH="$unsafe_keychain" \
  BAIROMETER_CI_CREDENTIAL_TEST_MODE=1 \
  BAIROMETER_TEST_SECURITY_COMMAND="$FAKE_TOOLS/security" \
  FAKE_TOOL_LOG="$FAKE_TOOL_LOG" \
  /bin/bash "$CLEANUP_SCRIPT" \
  2>&1)"
unsafe_status=$?
set -e
[[ "$unsafe_status" -ne 0 ]] || fail "unsafe cleanup path unexpectedly passed"
[[ -s "$unsafe_private/marker" ]] || fail "unsafe cleanup removed caller-owned material"

for public_output in \
  "$preexisting_private_result" \
  "$preexisting_private_cleanup_result" \
  "$preexisting_keychain_result" \
  "$preexisting_keychain_cleanup_result" \
  "$private_symlink_result" \
  "$keychain_symlink_result" \
  "$missing_result" \
  "$invalid_import_result" \
  "$mismatched_identity_result" \
  "$invalid_notary_result" \
  "$valid_result" \
  "$cleanup_result" \
  "$unsafe_result"; do
  [[ "$public_output" != *"p12-fixture-password"* ]] || \
    fail "P12 password leaked to public fixture output"
  [[ "$public_output" != *"notary-fixture-password"* ]] || \
    fail "notary password leaked to public fixture output"
  [[ "$public_output" != *"fixture@example.invalid"* ]] || \
    fail "Apple ID leaked to public fixture output"
  [[ "$public_output" != *"TESTTEAM01"* ]] || \
    fail "Team ID leaked to public fixture output"
  [[ "$public_output" != *"Developer ID Application: Fixture"* ]] || \
    fail "certificate name leaked to public fixture output"
done

echo "PASS: protected release workflow fixtures"
