# OpenAI Codex Experimental App-Server Source

OpenAI Codex accounts use the `Experimental app-server` source. Only one
account can be configured because it reflects the current local Codex CLI
identity. On refresh, Bairometer starts a short-lived local process:

```text
codex app-server --listen stdio://
```

It completes the documented app-server initialization handshake and requests
`account/rateLimits/read` over JSONL. The app normalizes only the explicitly
identified `codex` rate-limit bucket, its `primary` window, and its optional
`secondary` window. The resulting snapshot is marked `live` and visibly labeled
as experimental because the local CLI protocol may change; a successful read is
still presented as `OK`.

The child runs from Bairometer's dedicated private temporary directory rather
than inheriting the app launch directory. `PWD` points to that directory, while
inherited `OLDPWD` and `INIT_CWD` values are removed to avoid incidental access
to protected user folders during scheduled refresh.

Leave `Codex executable` blank to use automatic discovery from the shell PATH
and standard local install locations, or select a specific executable for that
account. Bairometer does not open a terminal, drive `/status` through a PTY,
read browser content, session files, cookies, tokens, or credentials. It
discards raw JSON-RPC messages and deliberately excludes credits, opaque reset
identifiers, and other unneeded account fields before a snapshot is created.

Only one OpenAI Codex account can use this source at a time, since it reflects
the currently authenticated local Codex CLI identity. If the CLI is missing,
not authenticated, unsupported, malformed, or times out, the account shows a
recoverable diagnostic with steps to update or authenticate Codex CLI and retry.

## Authenticated web boundary

Bairometer does not currently provide an authenticated Codex web source. The
documented app-server account API is preferred for the one active local Codex
CLI identity because it already exposes the relevant account-wide quota, reset,
plan, credit, and token-activity capabilities when they are available. A future
expansion of this structured local source may expose additional native metrics
after a dedicated implementation decision and sanitized real-account
verification.

The app currently preserves the manual/unavailable workflow for API-key-only
and Bedrock identities that do not expose ChatGPT account usage. A future
opt-in web fallback for independently authenticated additional accounts must
first prove its embedded-auth, multi-account isolation, and semantic-extraction
contract; it must never import another app's browser session.

Reference: <https://developers.openai.com/codex/app-server/>.
