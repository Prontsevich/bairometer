#!/usr/bin/env bash
set -euo pipefail
umask 077

RUNNER_TEMP_DIRECTORY="${RUNNER_TEMP:-}"
PRIVATE_DIRECTORY="${BAIROMETER_CI_PRIVATE_DIRECTORY:-}"
KEYCHAIN_PATH="${BAIROMETER_CI_KEYCHAIN_PATH:-}"
OWNERSHIP_TOKEN="${BAIROMETER_CI_CREDENTIAL_OWNER:-}"
SECURITY_COMMAND="/usr/bin/security"
if [[ "${BAIROMETER_CI_CREDENTIAL_TEST_MODE:-0}" == "1" ]]; then
  SECURITY_COMMAND="${BAIROMETER_TEST_SECURITY_COMMAND:?}"
fi

[[ -n "$RUNNER_TEMP_DIRECTORY" && "$RUNNER_TEMP_DIRECTORY" == /* &&
   "$RUNNER_TEMP_DIRECTORY" != "/" ]] || {
  echo "error: refusing release credential cleanup with an unsafe RUNNER_TEMP" >&2
  exit 1
}
[[ "$PRIVATE_DIRECTORY" == "$RUNNER_TEMP_DIRECTORY/Bairometer-ci-release-private" ]] || {
  echo "error: refusing to remove an unexpected private release directory" >&2
  exit 1
}
[[ "$KEYCHAIN_PATH" == "$RUNNER_TEMP_DIRECTORY/Bairometer-ci-release.keychain-db" ]] || {
  echo "error: refusing to remove an unexpected release keychain" >&2
  exit 1
}

OWNERSHIP_MARKER="$PRIVATE_DIRECTORY/.credential-owner"
KEYCHAIN_OWNERSHIP_MARKER="$PRIVATE_DIRECTORY/.keychain-owner"
if [[ ! -e "$PRIVATE_DIRECTORY" && ! -L "$PRIVATE_DIRECTORY" &&
      ! -e "$KEYCHAIN_PATH" && ! -L "$KEYCHAIN_PATH" ]]; then
  echo "No owned protected release credentials to destroy."
  exit 0
fi
[[ "$OWNERSHIP_TOKEN" =~ ^[A-Za-z0-9-]{16,128}$ ]] || {
  echo "error: refusing release credential cleanup without ownership proof" >&2
  exit 1
}
[[ -d "$PRIVATE_DIRECTORY" && ! -L "$PRIVATE_DIRECTORY" ]] || {
  echo "error: refusing release credential cleanup without an owned private directory" >&2
  exit 1
}
[[ -f "$OWNERSHIP_MARKER" && ! -L "$OWNERSHIP_MARKER" ]] || {
  echo "error: refusing release credential cleanup without an ownership marker" >&2
  exit 1
}
MARKER_TOKEN="$(/bin/cat "$OWNERSHIP_MARKER")"
[[ "$MARKER_TOKEN" == "$OWNERSHIP_TOKEN" ]] || {
  echo "error: refusing release credential cleanup for a different invocation" >&2
  exit 1
}
cleanup_status=0
if [[ -e "$KEYCHAIN_PATH" || -L "$KEYCHAIN_PATH" ]]; then
  [[ -f "$KEYCHAIN_OWNERSHIP_MARKER" && ! -L "$KEYCHAIN_OWNERSHIP_MARKER" ]] || {
    echo "error: refusing release keychain cleanup without ownership proof" >&2
    exit 1
  }
  KEYCHAIN_MARKER_TOKEN="$(/bin/cat "$KEYCHAIN_OWNERSHIP_MARKER")"
  [[ "$KEYCHAIN_MARKER_TOKEN" == "$OWNERSHIP_TOKEN" ]] || {
    echo "error: refusing release keychain cleanup for a different invocation" >&2
    exit 1
  }
  if [[ -L "$KEYCHAIN_PATH" ]]; then
    if ! /bin/rm -f -- "$KEYCHAIN_PATH"; then
      cleanup_status=1
    fi
  else
    if ! "$SECURITY_COMMAND" delete-keychain "$KEYCHAIN_PATH" >/dev/null 2>&1; then
      cleanup_status=1
    fi
    if ! /bin/rm -f -- "$KEYCHAIN_PATH"; then
      cleanup_status=1
    fi
  fi
fi
/bin/chmod -R go-rwx "$PRIVATE_DIRECTORY" 2>/dev/null || true
if ! /bin/rm -rf -- "$PRIVATE_DIRECTORY"; then
  cleanup_status=1
fi

if [[ "$cleanup_status" -ne 0 ]]; then
  echo "error: ephemeral release credential cleanup failed" >&2
  exit 1
fi
echo "Destroyed ephemeral protected release credentials."
