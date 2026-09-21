# Claude Code StatusLine Source

Claude Code can run the bundled `AILimitBarClaudeStatusLine` helper. It reads the
documented `statusLine` JSON from stdin and writes a normalized Bairometer
snapshot to the app-owned SQLite database. This is a local estimate, not
authoritative account-level quota.

Claude Code accounts can alternatively use [the experimental `/usage` CLI
source](claude-usage-cli.md) for account-wide plan bars. Managed `statusLine`
remains the default and supports multiple explicitly configured accounts.

In Settings, create or edit a Claude Code account, save it, and then use
`Install or Repair Helper`. Add the displayed `statusLine` object to
`~/.claude/settings.json` explicitly. Bairometer does not edit Claude Code
settings automatically. The generated command contains that account's stable
`--account-id`; it does not accept a database path or a user-managed snapshot
path.

The database remains at `~/Library/Application Support/AI Limitbar/AI Limitbar.sqlite`;
these are retained technical storage names. Bairometer enables SQLite WAL mode,
foreign keys, and a bounded write timeout so
the helper can update it while the app is closed or reading. Invalid helper input
does not change the last stored snapshot.

On the first database launch, Bairometer imports supported legacy JSON accounts,
snapshots, refresh settings, and Claude Code statusLine data. It does not delete
or rewrite those files, so they remain recovery backups. A custom legacy snapshot
path is read only once; Settings then shows an actionable migration warning and
requires the managed helper for future updates. The database never stores
credentials, cookies, WebKit data, raw provider responses, or raw statusLine
payloads.
