#!/usr/bin/env bash
set -euo pipefail

HOST_PROCESS="BairometerTest"
HOST_APP_NAME="BairometerUITestHost"
STORAGE_ARGUMENT="--bairometer-storage-directory"

usage() {
  echo "usage: $0 --ui-test-host <dashboard-empty|dashboard-healthy|dashboard-mixed|dashboard-openrouter|dashboard-minimax|settings|settings-dirty-editor|settings-openrouter|settings-openrouter-missing-management> [--ui-test-language en|ru] [--ui-test-appearance light|dark] [--ui-test-height compact|standard|tall]" >&2
}

[[ "${1:-}" == "--ui-test-host" && $# -ge 2 ]] || { usage; exit 2; }
SCENARIO="$2"
LANGUAGE="en"
APPEARANCE="dark"
HEIGHT="standard"
shift 2

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ui-test-language)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      LANGUAGE="$2"
      shift 2
      ;;
    --ui-test-appearance)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      APPEARANCE="$2"
      shift 2
      ;;
    --ui-test-height)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      HEIGHT="$2"
      shift 2
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

case "$SCENARIO" in
  dashboard-empty|dashboard-healthy|dashboard-mixed|dashboard-openrouter|dashboard-minimax|settings|settings-dirty-editor|settings-openrouter|settings-openrouter-missing-management) ;;
  *) echo "error: invalid UI test scenario: $SCENARIO" >&2; exit 2 ;;
esac
case "$LANGUAGE" in
  en|ru) ;;
  *) echo "error: invalid UI test language: $LANGUAGE" >&2; exit 2 ;;
esac
case "$APPEARANCE" in
  light|dark) ;;
  *) echo "error: invalid UI test appearance: $APPEARANCE" >&2; exit 2 ;;
esac
case "$HEIGHT" in
  compact|standard|tall) ;;
  *) echo "error: invalid UI test height: $HEIGHT" >&2; exit 2 ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST_BUNDLE="$ROOT_DIR/dist/$HOST_APP_NAME.app"
HOST_STORAGE_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/bairometer-ui-test-host.XXXXXX")"
HOST_PID=""
OPEN_PID=""

cleanup() {
  if [[ -n "$HOST_PID" ]] && kill -0 "$HOST_PID" >/dev/null 2>&1; then
    kill "$HOST_PID" >/dev/null 2>&1 || true
  fi
  if [[ -n "$OPEN_PID" ]] && kill -0 "$OPEN_PID" >/dev/null 2>&1; then
    kill "$OPEN_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$HOST_STORAGE_DIRECTORY"
}

trap cleanup EXIT INT TERM

pkill -x "$HOST_PROCESS" >/dev/null 2>&1 || true
"$ROOT_DIR/script/stage_ui_test_host_bundle.sh"

/usr/bin/open -n -W "$HOST_BUNDLE" --args \
  --ui-test-host "$SCENARIO" \
  --ui-test-language "$LANGUAGE" \
  --ui-test-appearance "$APPEARANCE" \
  --ui-test-height "$HEIGHT" \
  "$STORAGE_ARGUMENT" "$HOST_STORAGE_DIRECTORY" &
OPEN_PID="$!"

for _ in {1..100}; do
  HOST_PID="$(pgrep -x "$HOST_PROCESS" | head -n 1 || true)"
  if [[ -n "$HOST_PID" ]]; then
    break
  fi
  if ! kill -0 "$OPEN_PID" >/dev/null 2>&1; then
    wait "$OPEN_PID"
    exit $?
  fi
  sleep 0.1
done

[[ -n "$HOST_PID" ]] || {
  echo "error: Launch Services did not start $HOST_PROCESS" >&2
  exit 1
}

echo "UI test host started (scenario $SCENARIO, PID $HOST_PID)"
wait "$OPEN_PID"
