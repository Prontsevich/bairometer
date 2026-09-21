# Claude Code `/usage` CLI Source

Bairometer can read Claude subscription plan limits from the locally
authenticated Claude Code CLI without opening an interactive terminal. This
source is opt-in and Experimental because the outer CLI result is JSON but the
plan-limit values inside `result` remain human-readable text.

## Setup

1. Sign in with the local Claude Code CLI identity that should supply usage.
2. Create or edit a Claude Code account in Bairometer Settings.
3. Select `/usage CLI` under Source.
4. Leave `Claude Path` blank for automatic discovery, or choose an executable.
5. Save the account and use `Test Connection` or Refresh.

Only one saved Claude Code account, including disabled accounts, may select this
source because it represents the active identity of the selected local CLI.
Other Claude accounts can continue using Manual or the managed `statusLine`
helper.

## Process Contract

Bairometer locates `claude` from the saved override, `PATH`, and standard local
install locations, then runs:

```zsh
TZ=UTC LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
  claude --safe-mode -p "/usage" \
  --output-format json --tools "" --no-session-persistence
```

The process has a 15-second timeout and a 1 MiB stdout limit. Cancellation
terminates the child. Stderr is discarded, and raw stdout is decoded in memory
only. A response is accepted only when it is a successful result with zero
turns, zero model tokens, and zero model cost.

The child runs from Bairometer's dedicated private temporary directory rather
than inheriting the app launch directory. `PWD` points to that directory, while
inherited `OLDPWD` and `INIT_CWD` values are removed to avoid incidental access
to protected user folders during scheduled refresh.

## Parsed Data

The parser recognizes only:

- `Current session`
- `Current week (all models)`
- `Current week (<model>)`

Claude Code `2.1.207` was verified with one-line values such as
`Current week (all models): N% used · resets Jul 17 at 2pm (UTC)`. Its
`Current session` line reports a percentage without a reset timestamp, so that
window is stored with `resetAt == nil`; weekly windows require a valid UTC reset.
Fable is optional, and other model-specific weekly labels are normalized into
stable collision-safe IDs.

Machine-local activity attribution, costs, request counts, skills, agents, MCP
details, session identifiers, and every unrecognized section are ignored and
never persisted. SQLite receives only the normalized `UsageSnapshot`, fixed
app-generated compatibility text, and sanitized refresh diagnostics.

## Failure And Fallback

A missing executable, unauthenticated CLI, unsupported envelope, inference
activity, malformed or oversized output, changed plan text, invalid percentage
or weekly reset, timeout, or cancellation fails closed. Bairometer preserves
the last valid snapshot and shows an actionable sanitized error. Switch the
account to Manual or managed `statusLine` if CLI compatibility changes.

A successful read remains `OK` unless the normal usage threshold produces a
warning. The Experimental label describes compatibility risk; it is not itself
a health warning.
