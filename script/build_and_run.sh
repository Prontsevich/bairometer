#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${1:-}" == "--ui-test-host" ]]; then
  exec "$SCRIPT_DIR/run_ui_test_host.sh" "$@"
fi

MODE="${1:-run}"
APP_NAME="Bairometer"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
SMOKE_TEST_FILTER="BairometerTests.AppModelTests/testDailyUseSmokePersistsAccountSettingsAndSnapshot"
SMOKE_STORAGE_ARGUMENT="--bairometer-storage-directory"
SMOKE_STORAGE_DIRECTORY=""
SMOKE_PID=""

case "$MODE" in
  run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify)
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--ui-test-host <scenario> ...]" >&2
    exit 2
    ;;
esac

cleanup() {
  if [[ -n "$SMOKE_PID" ]] && kill -0 "$SMOKE_PID" >/dev/null 2>&1; then
    kill "$SMOKE_PID" >/dev/null 2>&1 || true
    for _ in {1..50}; do
      if ! kill -0 "$SMOKE_PID" >/dev/null 2>&1; then
        break
      fi
      sleep 0.1
    done
    if kill -0 "$SMOKE_PID" >/dev/null 2>&1; then
      kill -KILL "$SMOKE_PID" >/dev/null 2>&1 || true
    fi
  fi

  if [[ -n "$SMOKE_STORAGE_DIRECTORY" ]]; then
    rm -rf "$SMOKE_STORAGE_DIRECTORY"
  fi
}

trap cleanup EXIT

case "$MODE" in
  --verify|verify)
    echo "Running deterministic app-layer smoke test"
    cd "$ROOT_DIR"
    swift test --filter "$SMOKE_TEST_FILTER"
    ;;
  *)
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    ;;
esac

"$ROOT_DIR/script/stage_app_bundle.sh" --configuration debug
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

wait_for_pid() {
  local pid=""
  local attempt
  for attempt in {1..50}; do
    pid="$(pgrep -x "$APP_NAME" | head -n 1 || true)"
    if [[ -n "$pid" ]]; then
      echo "$pid"
      return 0
    fi
    sleep 0.1
  done
  return 1
}

wait_for_new_pid() {
  local baseline="$1"
  local pid
  local baseline_pid
  local is_existing
  local attempt

  for attempt in {1..50}; do
    for pid in $(pgrep -x "$APP_NAME" || true); do
      is_existing=false
      while IFS= read -r baseline_pid; do
        if [[ -n "$baseline_pid" && "$pid" == "$baseline_pid" ]]; then
          is_existing=true
          break
        fi
      done <<< "$baseline"

      if [[ "$is_existing" == false ]]; then
        echo "$pid"
        return 0
      fi
    done
    sleep 0.1
  done

  echo "error: Launch Services did not start a new $APP_NAME process" >&2
  return 1
}

wait_for_stable_pid() {
  local pid="$1"
  local attempt

  for attempt in {1..10}; do
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      echo "error: $APP_NAME process exited during startup" >&2
      return 1
    fi
    sleep 0.1
  done
}

open_app_with_storage() {
  /usr/bin/open -n "$APP_BUNDLE" --args "$SMOKE_STORAGE_ARGUMENT" "$1"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    open_app
    APP_PID="$(wait_for_pid)"
    lldb -p "$APP_PID"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    SMOKE_STORAGE_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/bairometer-verify.XXXXXX")"
    EXISTING_PIDS="$(pgrep -x "$APP_NAME" || true)"
    open_app_with_storage "$SMOKE_STORAGE_DIRECTORY"
    SMOKE_PID="$(wait_for_new_pid "$EXISTING_PIDS")"
    wait_for_stable_pid "$SMOKE_PID"
    echo "Launch Services startup smoke test passed (PID $SMOKE_PID)"
    ;;
esac
