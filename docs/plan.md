# Bairometer Plan

## Purpose

Bairometer is a macOS menu bar app for monitoring AI provider usage limits in
one place. The app should make it clear which limits are known precisely, which
are estimates, and which require opening the provider's own usage page.

Bairometer is the public product identity. The existing `AILimitBar` package,
executables, bundle identifier, storage paths, signing identity, archive names,
and repository remain technical compatibility identifiers.

The first version focuses on visibility and reliability, not on perfect
coverage. A provider integration is acceptable only if the app can explain where
the number came from and how fresh it is.

## Initial Providers

- OpenAI Codex
- Claude Code
- Ollama Cloud
- Mock provider for UI and storage development

## MVP Scope

The MVP should provide a working macOS menu bar app with:

- An image-only menu bar status item with a compact warning/error badge.
- A compact provider list with current usage snapshots.
- Manual refresh.
- A settings window for enabling providers.
- A local JSON snapshot store.
- Provider adapters behind a shared interface.
- Clear source and confidence labels for every displayed value.

The MVP does not need a WidgetKit widget yet. The widget should come after the
menu bar app can reliably produce normalized snapshots.

## MVP Implementation Status

The current implementation is a SwiftPM-based macOS app with a SwiftUI
`MenuBarExtra`, normalized provider snapshots, local SQLite storage, provider
account settings, and a project-local build/run script.

The app ships with:

- `MockProviderAdapter` for refreshable local-estimate data.
- `CodexAppServerProviderAdapter` with a manual fallback and an opt-in
  experimental app-server source for one local Codex CLI identity.
- `OllamaCloudProviderAdapter` with manual and opt-in experimental web-page modes.
- `ClaudeCodeProviderAdapter` with manual and opt-in managed statusLine modes.
- One app-owned GRDB/SQLite database for persisted accounts, snapshots,
  refresh settings, and safe source diagnostics.
- Account-owned credential contexts backed by separate real macOS Keychain
  items; credential UI remains hidden until a provider implementation makes it
  actionable.

The MVP fetches live data only through explicitly opted-in experimental source
paths. The Codex app-server source uses the documented local app-server protocol
but remains experimental because CLI compatibility can change. Ollama's
experimental page source is live but undocumented and is not treated as
authoritative. Claude Code can write a Bairometer-owned managed database
snapshot as an explicit local estimate; the remaining provider paths are manual-confidence
fallbacks.

Short-lived Codex and Claude CLI processes run from a dedicated private
temporary directory. Bairometer normalizes `PWD` to that directory and removes
inherited `OLDPWD` and `INIT_CWD` hints so scheduled refresh cannot accidentally
start a provider CLI in Documents, Downloads, Music, or another user workspace.

## Work Tracking

Private Linear is the source of truth for active strategy, priorities, project
documents, status, execution context, dependencies, and acceptance. This
product is organized under Team `Development` and the `Bairometer` product
Initiative. Each active item is a Linear Issue: new intake starts in `Triage`,
finite multi-Issue outcomes use a Project, and ordinary standalone work uses
`Improvements & Fixes`. Its implementation pull request is attached from the
private Issue side after the PR exists, without copying private planning context
or Issue identifiers into public GitHub issues, branches, commits, or pull
requests.

The roadmap in `docs/tasks.md` preserves product scope, acceptance criteria, and
completed-history evidence rather than duplicating active task state. GitHub
Releases are the public changelog. Their notes are derived from completed work,
merged pull requests, and commits after private planning context is removed;
Linear project updates are for current status, not published release history.

If Linear is temporarily unavailable, `docs/backlog.md` records raw intake and
necessary pending synchronization only. Reconcile and retire those temporary
entries after access returns; it must not become a parallel live tracker.

## Non-Goals For MVP

- Perfect real-time quota accuracy for every provider.
- Browser automation as a default data source.
- Unofficial scraping that cannot be isolated behind a clearly marked
  experimental provider mode.
- Cross-device usage reconciliation.
- Team administration dashboards.
- A second backlog system outside Linear.

## Product Principles

- Be honest about data quality.
- Prefer official APIs and CLI surfaces over scraping.
- Keep secrets in Keychain, not in plain JSON files.
- Keep the widget passive: it should render stored snapshots, not authenticate
  or fetch provider data directly.
- Treat provider integrations as replaceable adapters.
- Design for a small, glanceable menu bar experience before adding richer views.
- Target macOS 15+ technology and current system UI patterns instead of
  preserving older OS compatibility.
- Prefer standard SwiftUI controls and structures for pointer behavior, focus
  behavior, keyboard interaction, and accessibility.

## Platform Baseline

Bairometer is a modern-only macOS app. The project targets macOS 15 Sequoia as
the minimum supported baseline. This preserves the current SwiftUI window
behavior without compatibility branches for older releases. The app does not
depend on Liquid Glass; the product-specific terminal-fieldset visual system
remains the dashboard and Settings design baseline.

Modern-only means:

- The SwiftPM manifest uses SwiftPM 6.2, macOS 15, and Swift 6 language mode.
- The deployment target can move forward when current SwiftUI/macOS APIs make
  the app simpler, more native, or more visually correct.
- Standard system controls, sidebars, toolbars, sheets, focus handling, pointer
  states, and keyboard behavior are preferred over hand-built replacements.
- SwiftUI scenes and system controls are preferred for UI and windowing. AppKit
  is limited to narrow application activation and termination boundaries where
  the menu-bar-only `LSUIElement` lifecycle needs explicit platform cooperation;
  it must not own Settings windows or feature state.
- Compatibility fallbacks for older macOS releases are out of scope unless this
  product decision is explicitly reopened.

## Usage Snapshot Model

Every provider should normalize its state into a common snapshot shape:

```json
{
  "providerID": "claude-code",
  "displayName": "Claude Code",
  "status": "ok",
  "planName": "Max",
  "periodLabel": "5-hour window",
  "usedPercent": 64,
  "remainingLabel": "Approx. 36% remaining",
  "resetAt": "2026-07-07T18:00:00Z",
  "limitWindows": [
    {
      "id": "weekly",
      "displayName": "Weekly",
      "usedPercent": 52,
      "remainingLabel": "Approx. 48% remaining",
      "resetAt": "2026-07-14T00:00:00Z"
    },
    {
      "id": "rolling-5-hour",
      "displayName": "5-hour",
      "usedPercent": 64,
      "remainingLabel": "Approx. 36% remaining",
      "resetAt": "2026-07-07T18:00:00Z"
    }
  ],
  "lastUpdatedAt": "2026-07-07T10:15:00Z",
  "confidence": "local-estimate",
  "source": "Claude Code local usage data",
  "warnings": []
}
```

Fields can be absent when the provider cannot supply them. The UI should handle
missing values deliberately instead of inventing defaults.

## Confidence Levels

- `live`: fetched from an official current usage API or equivalent live source.
- `delayed`: official data, but known to lag.
- `local-estimate`: derived from local CLI history, logs, or local accounting.
- `manual`: provider page must be opened to inspect the current state.
- `unknown`: the app cannot determine the current state.

Confidence is part of the product, not an implementation detail. It should be
visible enough that users do not mistake estimates for authoritative limits.

## Provider Adapter Contract

Each provider adapter should be responsible for:

- Detecting whether it is configured.
- Fetching or deriving a usage snapshot.
- Returning structured errors.
- Reporting the data source and confidence level.
- Providing a provider usage URL when available.

Adapters should not write UI state directly. They should return normalized
snapshots to an app-level store.

Experimental web-page sources must keep their authentication boundary inside an
Bairometer-owned WebKit view. They may receive a minimal, validated bridge
payload from that view, but must not read, import, export, or persist cookies,
tokens, raw HTML, browser storage, or raw bridge payloads. A parsing or session
failure must preserve the last valid normalized snapshot.

## Provider Assumptions

### OpenAI Codex

Bairometer keeps `manual` as the default and fallback OpenAI Codex source. One
explicitly selected account may use `app-server`, which starts a short-lived
local `codex app-server --listen stdio://` process for a refresh. It performs
the documented JSONL initialization handshake, requests
`account/rateLimits/read`, then terminates the process. This is not terminal
automation: Bairometer never starts an interactive CLI, drives `/status`
through a PTY, reads browser content, or reads local Codex authentication or
session files.

The app resolves `codex` from an optional per-account executable override, then
from the shell PATH and standard local install locations. The override is a
local executable path only; Bairometer does not persist credentials, cookies,
tokens, or account files. Automatic discovery never stores its result.

The source selects a limit bucket only when it is explicitly identified as
`codex`: the exact `rateLimitsByLimitId.codex` entry is preferred, otherwise
the response must contain exactly one bucket whose `limitId` is `codex`. It
normalizes a valid `primary` window and an optional valid `secondary` window.
Malformed percentages, missing buckets, invalid reset timestamps, and changed
protocol shapes result in a useful warning or recoverable error; they never
produce a fabricated quota value. If a valid response is received, the snapshot
is `live` and visibly labeled `Codex app-server (Experimental)`. The experimental
label is informational: a successful read remains `OK` unless a real usage
threshold or source failure requires a warning.

Raw JSON-RPC payloads remain process-local and are discarded. The decoder
projects only the limit identifier, percentage, duration, and reset timestamp;
credit balances, opaque reset-credit identifiers, and other account fields are
excluded before snapshot creation or diagnostics. A missing executable,
unauthenticated CLI, unsupported protocol, malformed response, timeout, or
launch failure leaves the manual workflow available and preserves the last
valid snapshot through the existing refresh path.

Reference: <https://developers.openai.com/codex/app-server/>.

### Claude Code

Claude Code has local usage visibility and plan usage displays. Some data may be
derived from local history, so it may not reflect use from other machines or
other Claude surfaces.

Initial integration should separate local estimates from official account-level
usage if both become available.

MVP status: opt-in `local-estimate` source backed by a Bairometer-owned
snapshot written by the Claude Code `statusLine` helper. The implemented source
does not parse Claude interactive screens, private local files, or browser
pages. Milestone 19 adds a separate opt-in experimental source that invokes
the supported non-interactive `/usage` slash command and parses only its plan
limit text from the CLI JSON result envelope.

Research dates: 2026-07-12 and 2026-07-13.

Official sources checked:

- <https://code.claude.com/docs/en/costs>
- <https://code.claude.com/docs/en/commands>
- <https://code.claude.com/docs/en/statusline>
- <https://code.claude.com/docs/en/monitoring-usage>
- <https://code.claude.com/docs/en/analytics>
- <https://code.claude.com/docs/en/headless>
- <https://code.claude.com/docs/en/agent-sdk/slash-commands>
- <https://code.claude.com/docs/en/desktop>

Supported source strategy:

| Source | Output shape | Fit for Bairometer |
| --- | --- | --- |
| Claude Code `/usage`, `/cost`, and `/stats` commands | `/usage` is a built-in slash command that can be dispatched in non-interactive mode on supported CLI versions. `--output-format json` returns a result envelope, while the plan limits inside `result` remain human-readable text. On Claude Code `2.1.207`, the verified text included current session, all-model weekly, and Fable weekly percentages; weekly values included UTC reset times while the session value did not. The envelope reported zero model turns, cost, and token usage. The same screen also includes approximate machine-local activity attribution. | Implemented as the opt-in `claude-usage-cli` experimental source in Milestone 19. It parses only recognized plan-limit lines in memory and ignores the local activity breakdown. The JSON envelope and non-interactive dispatch make this safer than PTY scraping, but the inner text is not a stable machine-readable quota schema and fails closed on drift. |
| Claude Code status line | User-configured command receives JSON session data on stdin, including `rate_limits.five_hour` and `rate_limits.seven_day` with consumed percentages and reset timestamps when available. | Selected opt-in source. Bairometer's helper validates the input and writes a normalized `local-estimate` snapshot to the app-owned database. It remains machine/session-local, not authoritative account-wide usage. |
| OpenTelemetry export | Metrics and logs/events for organization usage, cost, token counters, active time, tool activity, and API request events when telemetry is enabled. | Future team/admin mode can ingest telemetry with `local-estimate` or organization-reporting confidence. It requires explicit telemetry configuration and is not a default personal account source. |
| Claude Code analytics dashboard | Team/Enterprise usage and contribution dashboards, with CSV export; API customers have Console team insights. | Future admin/reporting mode only. Not a live personal remaining-limit source. |
| Claude Console Usage page | Authoritative billing for API users. | Manual source for API billing. It should not be shown as Claude subscription plan remaining quota. |

Selected initial confidence level: `local-estimate` for statusLine snapshots and
`manual` when the helper is not configured.

Selected MVP source mode: configure a Bairometer-owned statusLine helper. The
helper consumes only documented statusLine JSON and writes the normalized
snapshot to `~/Library/Application Support/AI Limitbar/AI Limitbar.sqlite`; this
retained path is part of the technical compatibility contract. The
user must explicitly add the generated `--account-id` command to
`~/.claude/settings.json`; Bairometer does not edit Claude Code settings
automatically.

Implemented post-MVP experimental source: Bairometer locates an explicitly selected
local Claude executable and runs the equivalent of:

```zsh
TZ=UTC LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
  claude --safe-mode -p "/usage" \
  --output-format json --tools "" --no-session-persistence
```

The process client decodes the outer JSON envelope, requires a successful
built-in response with zero model turns, cost, and model-token usage, and parses
only `Current session`, `Current week (all models)`, and generic
`Current week (<model>)` plan-limit lines. It ignores and never persists the
machine-local activity breakdown. The source writes only normalized snapshot
values to SQLite, never raw command output, stderr, credentials, session data,
or activity attribution.

The verified Claude Code `2.1.207` result uses one-line entries such as
`Current week (all models): N% used · resets Jul 17 at 2pm (UTC)`. The session
entry currently has no reset value and is stored with `resetAt == nil`; weekly
entries require a valid UTC reset. Reset parsing accepts values with and without
minutes and resolves a missing year to the next future UTC occurrence.

The `/usage` CLI source represents the one identity currently authenticated in
the selected CLI environment, so only one saved Claude Code account may use it
at a time. Managed `statusLine` remains available for explicit multi-account
configuration and as the documented fallback. A missing executable,
unauthenticated CLI, unsupported command, non-zero inference metadata, changed
text format, malformed or oversized response, invalid percentage/reset value,
timeout, or cancellation preserves the last valid snapshot and surfaces a
sanitized recovery path.

First real provider decision: Claude Code is the initial Milestone 5 provider.
The implementation does not parse Claude's interactive screens or private local
files. It provides an opt-in helper that writes only a normalized local-machine
estimate, not authoritative account-level quota.

Configuration requirements:

- Provider settings persist a source mode for each provider.
- Claude Code supports `manual`, `claude-status-line`, and the opt-in experimental
  `claude-usage-cli` source mode. Managed `statusLine` remains the default.
- Claude Code statusLine setup never persists a user-controlled JSON path.
- Each managed helper command carries a saved account ID, so multiple accounts
  can have independent statusLine snippets.
- Only one account may use `claude-usage-cli` because it represents the active
  identity of the selected local executable. Its optional executable override
  uses a provider-neutral persisted field shared with other CLI-backed sources.
- Existing provider settings without source fields continue to load with the
  current provider default; for Claude Code this is managed `statusLine`.

Legacy JSON snapshot schema version 1 is supported only for one-time migration:

```json
{
  "schemaVersion": 1,
  "planName": "Max",
  "periodLabel": "5-hour window",
  "usedPercent": 64,
  "remainingLabel": "Approx. 36% remaining",
  "resetAt": "2026-07-07T18:00:00Z",
  "limitWindows": [
    {
      "id": "weekly",
      "displayName": "Weekly",
      "usedPercent": 52,
      "remainingLabel": "Approx. 48% remaining",
      "resetAt": "2026-07-14T00:00:00Z"
    },
    {
      "id": "rolling-5-hour",
      "displayName": "5-hour",
      "usedPercent": 64,
      "remainingLabel": "Approx. 36% remaining",
      "resetAt": "2026-07-07T18:00:00Z"
    }
  ],
  "lastUpdatedAt": "2026-07-07T10:15:00Z"
}
```

`schemaVersion` and `lastUpdatedAt` are required. Dates use ISO 8601 strings.
`usedPercent` and each `limitWindows[].usedPercent` value are optional, but if
present they must be in the inclusive `0...100` range. The adapter maps this
payload to a normalized `UsageSnapshot` with `local-estimate` confidence and
adds a warning that the data is local only. The legacy single-window fields
remain supported; `limitWindows` is used when the helper can report more than
one provider-defined window.

The bundled statusLine helper maps `rate_limits.five_hour` to
`rolling-5-hour` / `5-hour` and `rate_limits.seven_day` to `seven-day` / `7-day`.
It writes only windows with valid percentages, converts `resets_at` Unix
timestamps to ISO 8601, and leaves the last valid file untouched when Claude
does not provide subscription rate-limit data.

The schema intentionally excludes free-form provider warnings, raw responses,
credentials, cookies, and tokens so the app does not persist arbitrary provider
text outside Keychain.

OpenAI Codex remains manual-first, with an opt-in local app-server rate-limit
source for one authenticated CLI identity. Ollama Cloud remains manual-first by
default because the checked API docs do not expose account usage or
remaining-limit endpoints; its planned web-page mode is isolated and clearly
marked as experimental.

### Ollama Cloud

Ollama Cloud supports cloud model access and an authenticated account usage
page. Its documented API does not currently expose account usage or
remaining-limit endpoints.

Research result: the authenticated `https://ollama.com/settings` page has
server-rendered usage in two variants. The legacy variant renders session and
weekly usage percentages with reset information. The current variant renders an
`Included usage` block with a monthly spend meter (`$X of $Y used`), a reset
timestamp, and per-model request segments. No separate usage JSON response was
observed during the page-load checks. Research re-verified on 2026-09-11
against the live monthly variant.

Current implementation status: manual-confidence placeholder remains the default,
and Milestone 14 adds an explicit opt-in `ollama-web-page` source mode. This does
not turn the undocumented page into a supported Ollama API.

Research dates: 2026-07-07, 2026-07-13, and 2026-09-11.

Official sources checked:

- <https://docs.ollama.com/cloud>
- <https://docs.ollama.com/api/introduction>
- <https://docs.ollama.com/api/authentication>
- <https://docs.ollama.com/api/usage>
- <https://docs.ollama.com/api/tags>
- <https://docs.ollama.com/llms.txt>

Supported source strategy:

| Source | Output shape | Fit for Bairometer |
| --- | --- | --- |
| Local Ollama API at `http://localhost:11434/api` | Per-request response metrics such as `total_duration`, `load_duration`, `prompt_eval_count`, `eval_count`, and related timing fields. Streaming responses include usage fields in the final chunk. | Useful for request-level local model accounting only when Bairometer observes or proxies requests. It does not provide account-level Ollama Cloud usage or remaining quota. |
| Ollama Cloud API at `https://ollama.com/api` | Same Ollama model interaction API for cloud models, authenticated with an API key. Documented endpoints include model generation/chat, embeddings, tags, running models, model details, and model management. | Supports cloud model calls, but the checked docs do not list a billing, account usage, quota, or remaining-limit endpoint. |
| Ollama API keys/settings | API keys for programmatic access to `ollama.com`; keys can be revoked and currently do not expire. | Required for future cloud model API calls. Not enough to expose usage limits. |
| Ollama account settings page | The authenticated `https://ollama.com/settings` page server-renders usage in two variants: legacy `Session usage` / `Weekly usage` percentage cards with reset information, and a current monthly `Included usage` block with a spend meter (`$X of $Y used`), a reset timestamp, and per-model request segments. | Current manual fallback. Planned experimental source only through a Bairometer-owned WebKit connection and semantic DOM parsing. Its `Experimental` source label is informational when a read succeeds. It must not reuse another browser's session or store raw page/session data. |

Current confidence level: `manual`.

Planned web-page confidence level: `live` only for a successfully parsed current
settings page, with source text `Ollama settings web page (Experimental)`. The
experimental label is informational when parsing succeeds; `live` describes
freshness of the provider-displayed value and does not imply that the DOM
integration is a documented or stable API.

Current source mode: open Ollama account/settings pages and label the snapshot
as manual. Do not call Ollama Cloud APIs for usage monitoring until a documented
account usage endpoint exists.

Implemented source mode: `ollama-web-page` is opt-in and starts with an
Bairometer-owned `WKWebView` connection. Each account stores only an opaque
WebKit data-store UUID in provider configuration; WebKit owns the persistent
session data. The user completes sign-in in that view, and the app never reuses
or extracts a session from Codex, Safari, Chrome, or another browser.

The WebKit user script is guarded to `https://ollama.com/settings` and extracts
only semantic usage values: legacy `Session usage` and `Weekly usage` values
from their individual usage cards, even when Ollama wraps both cards in a shared
section, and the monthly `Included usage` block with its `$X of $Y used` amounts
and reset timestamp when Ollama serves the monthly spend-meter variant. Either
variant may appear; both can appear together. Interactive
login may follow the expected Ollama WorkOS/Google/GitHub authentication
redirects; reset times are carried through when exposed by the page.
Scheduled refresh never follows auth redirects. Interactive login remains open
until it completes or the user cancels the connection sheet, while scheduled
refresh keeps a 20-second load timeout. Swift validates the
typed bridge payload before mapping every present window to `UsageLimitWindow`
entries (legacy `Session`/`Weekly`, monthly `Monthly` with the spend amounts as
its remaining label),
discards the in-memory payload after validation, and leaves the last valid
snapshot in place after a missing session, parser drift, incomplete data,
timeout, or load failure. Scheduled refresh never foregrounds the login UI or
attempts unattended reauthentication. If Bairometer later becomes an Ollama
request proxy, it can expose its own `local-estimate` counters for observed
requests, but those must remain labeled as partial and not account-wide.

Milestone 22.3 owns a separate, visual-only `WKUserScript` that adapts the
Ollama-owned settings and sign-in pages to the effective macOS appearance. It
may change only colors, backgrounds, borders, text contrast, and color scheme.
It must not alter visibility, layout, controls, focus, submission, navigation,
usage extraction, or bridge payloads. The stylesheet is guarded to the exact
HTTPS hosts `ollama.com` and `signin.ollama.com`; it is never injected into
WorkOS, Google, GitHub, or other third-party OAuth pages. The visual script and
the semantic usage-extraction script remain independent.

### Release Distribution

Milestone 20 establishes a GitHub Release path for people who want the app
without building from source. The current release target is macOS 15 or later
on Apple Silicon or Intel and uses the stable bundle identifier
`io.github.Prontsevich.AILimitBar`. A version tag must produce two
architecture-specific assets, `AILimitBar-<version>-arm64.zip` and
`AILimitBar-<version>-x86_64.zip`, each expanding directly to
`AILimitBar.app`. Each ZIP is created with `ditto --keepParent` so Finder
preserves the application-bundle shape and macOS metadata.

One shared staging script owns the app-bundle shape used by local development
and release packaging. It copies the app executable, the bundled Claude Code
helper, compiles the selected `AppIcon` asset catalog into the bundle, and
copies production SwiftPM resource bundles while excluding test bundles.
The release packaging script builds one selected architecture at a time in
release configuration, stages the app and helper as thin binaries, supplies
both app bundle version keys, signs the nested helper and outer bundle with a
caller-supplied Developer ID Application identity, enables Hardened Runtime and
secure timestamps, embeds the matching Developer ID provisioning profile,
verifies the authorized default Keychain group, then validates a round trip
through that architecture-specific ZIP archive. A separate local notarization
wrapper requires an explicit caller-owned Keychain profile such as
`AILIMITBAR_NOTARYTOOL_PROFILE=YOUR_NOTARYTOOL_PROFILE`. It creates a clearly
named signed submission archive, waits for Apple `Accepted` status, staples the
app extracted from that exact archive, and creates the final ZIP only after the
stapled app passes exact metadata, architecture, signature, entitlement,
ticket, and Gatekeeper validation. It extracts the final ZIP into a private
temporary directory and repeats the complete validation. Team-specific
identity, profile, certificate, private-key, Apple credential, and notary-log
material remain outside the repository and public logs.

The GitHub Actions `Release` workflow is a protected, manual-only validation
path. A non-secret authorization job requires a protected `main` ref before two
jobs can request the named `protected-release` Environment. Repository settings
must restrict that Environment to `main` and required reviewers. Its secrets
provide an encoded Developer ID P12 and provisioning profile plus Apple
notarization authentication only at the credential setup step; their values do
not live in the repository. The setup fails before build when any input is
missing or when the P12, profile certificate, signing team, imported identity,
or notarization authentication do not agree. It isolates the matching derived
Developer ID identity and a temporary `notarytool` profile in one ephemeral
file-based Keychain.

Native `macos-26` Apple Silicon and `macos-26-intel` jobs each invoke the same
local release notarization wrapper, then independently extract and validate the
final archive's exact bundle shape, architecture, signature, entitlements,
stapler ticket, and Gatekeeper evidence before uploading a three-day workflow
artifact. Pipeline and credential diagnostics remain private, and an always-
running cleanup step verifies an invocation-specific ownership marker before
removing the ephemeral Keychain, decoded material, and private diagnostics on
success or failure. Pre-existing collision paths are never treated as owned,
and cleanup must succeed before artifact upload. The validation workflow has no
tag trigger and does not create a GitHub Release.

A separate protected, manual-only draft publisher accepts a canonical version,
build number, and successful `Release` validation run ID. It has only `actions:
read` and `contents: write` permissions; it does not request the
`protected-release` Environment, signing secrets, or notarization secrets. The
publisher checks that the validation run belongs to this repository, completed
successfully from a manual dispatch of `Release` on `main`, and has the exact
same source commit as the publisher dispatch. It downloads only the expected
native `macos-26` `arm64` and `macos-26-intel` `x86_64` artifacts, verifies
nonempty ZIP archives, renders bilingual English/Russian notes from the
changelog sources, appends SHA-256 checksums, refuses an existing tag or
release conflict, creates an annotated tag at that exact commit, and creates a
GitHub draft release only. If a prior publisher attempt stopped after creating
the matching annotated tag or draft, a rerun verifies that the tag resolves to
the same commit, refreshes the draft title and notes, and uploads the two
expected assets with replacement. A published release or any mismatched tag or
release remains a hard failure. A user publishes the draft after reviewing its
notes, checksums, and assets.

### About Bairometer

Milestone 22.4 adds a compact `About` action beside `Settings` in the menu-bar
panel footer. It opens one fixed-size, non-restoring `About Bairometer` window
on the display that received the menu-bar action. The window is independent of
account, provider, refresh, diagnostic, and persistence state; it shows the
bundled app icon, `Bairometer`, release metadata, and project links only.

The release bundle supplies `CFBundleShortVersionString` and `CFBundleVersion`,
which are displayed as `Version <version> (build <build>)`. Local staged builds
without both values display `Development build`; the About surface does not
invent version metadata or change the existing staging/release version policy.
Its static system links point to the GitHub repository, a new GitHub issue,
direct e-mail, Telegram, and the existing Boosty support page. The About window
uses the app-wide English/Russian localization alongside the other app-owned
surfaces.

The Apple Developer Program gate is complete. Local and protected manual CI
release packaging can now produce Developer ID-signed and Apple-notarized
architecture-specific validation archives with authorized production Keychain
access. Publication remains disabled until clean-Mac checks and the separate
publication gate pass. Certificates, private keys,
provisioning profiles, Team IDs, payment information, Apple credentials,
Keychain profile values, and private notarization logs never belong in Git,
public docs, or public logs; private Linear notes may record the non-secret
Team ID only.

### Multi-Account Authenticated Web Research

Milestone 21 includes an evidence-first research gate for possible Claude and
OpenAI Codex authenticated web sources. The existence of Claude Settings > Usage
and the Codex Usage Dashboard makes both providers plausible candidates, but it
does not establish that their sign-in flows work in an embedded `WKWebView`,
that their page structure is suitable for safe extraction, or that they add
useful values beyond the current Claude and Codex sources.

Official product references:

- <https://support.claude.com/en/articles/9797557-usage-limit-best-practices>
- <https://support.claude.com/en/articles/12429409-manage-usage-credits-for-paid-claude-plans>
- <https://help.openai.com/en/articles/12642688>

The research evaluates Claude and Codex independently. For each available
account type it must verify the real authenticated destination, navigation and
login flow, visible plan-limit and credit fields, reset semantics, localization,
session restoration, reconnect behavior, and whether two accounts remain
isolated in distinct persistent `WKWebsiteDataStore` instances. A provider that
blocks embedded authentication or exposes no useful data beyond the existing
source is a valid negative result, not an implementation failure.

Extraction-method selection happens only after feasibility is established. The
preference order is a documented provider API, a documented structured local
interface, then narrowly scoped semantic DOM extraction. Reading an undocumented
internal JSON request is not an automatic fallback; it requires a separate
architecture and privacy decision. A temporary non-production WebKit probe may
be used to validate real macOS behavior, but Milestone 21 does not ship a new
source mode or generalize the Ollama controller on speculation.

Research must not retain credentials, tokens, cookies, browser storage, raw
HTML, complete network responses, profile data, opaque account identifiers, or
unredacted screenshots. The durable output is a sanitized capability decision
for each provider: feasible through a documented interface, feasible through
semantic DOM, requires a separate private-integration decision, blocked by
embedded authentication, not useful beyond existing sources, or not feasible.
Only a positive result creates a separate implementation milestone with a
confirmed source contract and multi-account verification plan.

#### Codex authenticated-web decision

For the one active local Codex CLI identity, the decision is
**`no-additional-value`**: an authenticated web source is not selected merely
to duplicate app-server data. This is not a global rejection of web support.
The app-server source can represent only one active local CLI identity, so a
future opt-in web fallback may still be valuable for additional independently
authenticated ChatGPT accounts. That question requires its own evidence-first
research before a web source can be selected.

Bairometer does not currently provide an authenticated Codex web source or
semantic DOM parser. LMB-10 therefore did not initiate embedded sign-in,
handle MFA or passkeys, retain a WebKit session, restore a web session after
relaunch, or create per-account Codex `WKWebsiteDataStore` instances. It also
does not claim that two-account web isolation has been demonstrated; that is a
required gate for any future multi-account web fallback.

The documented `codex app-server` account surface is the preferred structured
local source. In addition to the current rate-limit windows, it documents
`account/read` (account type and plan when available),
`account/rateLimits/read` (identified quota buckets, percentages, reset times,
workspace-credit details when returned, reached-limit state, and earned-reset
credit counts), and `account/usage/read` (token-activity summaries and optional
daily buckets). These are distinct native capabilities: plan quota and reset
windows must not be conflated with workspace credits, earned reset credits, or
token history.

The documented `account/read` shapes include ChatGPT, API-key, and Amazon
Bedrock identities; active auth-mode notifications also name externally
supplied ChatGPT tokens, agent identity, and personal access tokens. Account
token-activity data requires a Codex-service-backed identity; API-key-only and
Bedrock authentication do not provide it. Bairometer must show
unavailable/manual state rather than fall back to a web session for an
unsupported identity.

The current app-server adapter intentionally projects only Codex rate-limit
windows. Adding plan, credits, or history remains a separate implementation
decision after a sanitized real-account probe confirms optional-field behavior,
updates the app-server handshake for the installed CLI protocol if needed, and
defines native-unit UI and persistence rules. No production web-source Project
is created from this single-account research result.

References:

- <https://developers.openai.com/codex/app-server/>
- <https://help.openai.com/en/articles/12642688>

## App Architecture

The app should be structured around:

- `MenuBarExtra` for the primary interface.
- A singleton SwiftUI `Window` scene for provider/account configuration, opened
  through `openWindow(id:)` after explicit application activation.
- `UsageSnapshotStore` for persisted snapshots.
- `ProviderRegistry` for available adapters.
- `ProviderAdapter` protocol for provider-specific logic.
- `ProviderRefreshCoordinator` for converting configured adapter refresh
  requests into normalized snapshots.
- Keychain-backed credential storage.
- A refresh coordinator that can run manual and scheduled refreshes.

The first scaffold can use a mock provider and local JSON storage before adding
real provider clients.

Modern macOS UI structure should use system SwiftUI patterns before custom
layout code. Settings, toolbars, sidebars, sheets, forms, pickers, toggles,
menus, and buttons should be native controls unless the product needs behavior
that the system cannot express.

## Snapshot Model Direction

`UsageSnapshot` should continue to represent normalized account state, but the
dashboard needs more than one usage percentage per account. Future snapshot
versions should evolve from percentage-oriented limit windows toward typed
provider capacity observations while keeping the existing summary fields for
compatibility and menu-bar status aggregation.

A limit window should describe one visible quota window, not a hardcoded app
category. Common examples include a weekly window plus rolling 3-hour, 4-hour,
5-hour, or provider-specific hourly windows. Each window should carry a stable
kind or identifier when known, a display label, optional used percentage,
optional remaining/reset text, optional `resetAt`, and confidence/source
metadata inherited from or compatible with the parent snapshot.

When a provider exposes only one value, the dashboard can render that value as a
single limit window. When no machine-readable value exists, the account row
should show an unavailable/manual state instead of inventing progress bars.

## Provider Integration Contract Direction

Bairometer uses a small, versioned internal Provider Integration Contract with
three primary models: `ProviderSurface`, `SourceDescriptor`, and
`CapacityMetric`. It separates provider and product-surface identity, local
account and tenant contexts, source and authentication metadata, and native-unit
capacity observations. Multiple independently authenticated accounts retain
independent credential or browser-session boundaries, refresh lifecycle,
snapshots, and diagnostics.

The contract preserves percentage windows, currency, credits, tokens, requests,
characters, generations, media, compute, unlimited/unavailable states,
overage/boost values, provenance, freshness, confidence, and explicit
derivations without inventing a universal percentage. Trusted adapter code
continues to own authentication, transport, parsing, validation, and
normalization; declarative metadata never becomes a request, scraping, or
credential-exchange runtime.

Currency codes receive structural validation only: exactly three ASCII uppercase
letters. Trusted adapters perform semantic normalization of their native
currency instead of consulting a frozen contract registry; OpenRouter native
currency is `USD`.

`AILimitBarCore` contains a strict OpenRouter `URLSession` client as the first
native-currency transport built on Contract v1. Ordinary credentials have
one fixed capability, `GET https://openrouter.ai/api/v1/key`; elevated
management credentials have the separate fixed capability, `GET
https://openrouter.ai/api/v1/credits`. The client performs bounded,
cancellable streaming reads through a non-persistent default session, rejects
redirects, validates provider and credential roles through distinct redacted
wrappers, privately binds their provider/account/context/slot identity, and
derives metric context from the wrapper instead of accepting a caller
override. A per-request data delegate rejects oversized declared responses in
the response callback, bounds streamed data callbacks, and never collects
non-success bodies. Declared and streamed body sizes and lossless JSON-number
transformation are independently bounded. The client preserves accepted
provider JSON numbers exactly as `Decimal`, requires the documented tier and
management-key classification flags, rejects a management credential shape on
the ordinary endpoint, emits native USD metrics, keeps null or absent key
limits unavailable, strictly parses ASCII delta-seconds and canonical
HTTP-dates in `Retry-After` without retrying, and projects failures into fixed
sanitized types. It does not implement key inventory or a legacy percentage
bridge.

The stable `openrouter-api` source mode registers a live provider adapter and a
hierarchical account refresh coordinator. Each enabled ordinary slot calls only
`GET /api/v1/key`; the optional enabled management slot calls only `GET
/api/v1/credits`. The implementation does not call `/api/v1/keys`. Manual,
scheduled, and launch refreshes share the same path, with at most four
concurrent credential requests across all overlapping invocations for one
account and no same-refresh retry or sleeper loop. A newer account refresh
cancels the prior network tasks while both retain the same account-wide permit
pool; different accounts have independent pools. The initialized app runtime
starts one idempotent launch refresh after constructing `AppModel`.
`Retry-After` or bounded exponential backoff becomes a persisted per-slot
`retryNotBefore` eligibility check for a later refresh.

Successful sources replace only their own context/source metric rows. A failed
or deferred child retains its last valid metrics without erasing siblings or
the root management metric. Success commits metrics, successful refresh state,
and diagnostic clearing atomically; failure commits failed state, retry
boundary, and its sanitized diagnostic atomically; deferral validates identity
without mutation. Disable, delete, credential replacement, cancellation, and a
newer refresh suppress stale results through generation, persisted credential
revision, and transactional source-identity checks at entry and immediately
before commit. The legacy adapter reports error when no source succeeds in the
current run, preserving the prior legacy snapshot and last-success timestamp;
mixed success is a warning. Native USD values are never converted into a
fabricated progress value.

Every OpenRouter account refresh finishes with a lifecycle-locked conditional
management write that re-reads current slot state. A still-active management
slot is a no-op, preserving last-valid credits after failure. A slot deleted or
disabled while its request was in flight causes that same refresh to replace
known root credits with exactly one unavailable sentinel after a final
generation check.

The app layer maintains an additional per-account OpenRouter refresh generation.
Global Refresh All, individual Refresh, and Test Connection capture it before
awaiting adapter work. Every ordinary or management credential add, rename,
replace, enable/disable, recovery, or delete advances it. A compatibility
snapshot returning with an older generation is discarded before app-level
success/failure state, diagnostics, or legacy snapshot persistence can change;
this prevents a cancelled global refresh from recording a false late failure
after Settings mutates a credential.

The implementation-level field semantics, compatibility mapping from
`UsageSnapshot`, persistence migration direction, portable Core ownership,
sanitized Codex/Claude/MiniMax/OpenRouter fixtures, and evidence gate for any
future public schema or SDK are defined in
[`docs/provider-integration-contract.md`](provider-integration-contract.md).
Contract v1 is implemented in `AILimitBarCore` as portable `Codable` domain
models, pure validation, and a one-way legacy percentage bridge. The live
`ProviderAdapter` API, `UsageSnapshot` dashboard projection, and existing GRDB
snapshot schema remain backward compatible. OpenRouter native persistence is
implemented by additive migration v7. The app layer observes the native
snapshot plus per-slot credential metadata, refresh state, and diagnostics, and
projects them into a root shared-credit row with nested ordinary-key USD
metrics. Unknown, unlimited, unavailable, partial, stale, and credential-error
states remain native presentation states rather than fabricated percentages.
Until that gate passes in a separate architecture decision, compatibility is
internal and no public manifest, registry, validator, SDK, or backward-
compatibility promise exists.

## Storage

### Legacy JSON import

Earlier releases persisted provider accounts, refresh settings, normalized
snapshots, and the Bairometer-managed Claude Code `statusLine` payload as
versioned JSON documents in Application Support. They are now legacy import
sources, not active persistence.

Raw legacy arrays and documents with another format version are not imported.
Bairometer never deletes or rewrites the original files, so they remain
available as local backups.

### Active local database

Bairometer uses GRDB over SQLite as its single app-owned persistence
engine. The database location is fixed at
`~/Library/Application Support/AI Limitbar/AI Limitbar.sqlite`; the retained
technical path is not a public-name migration. Users do not
select database or snapshot paths.

GRDB is shared through `AILimitBarCore` by the menu bar app and the bundled
`AILimitBarClaudeStatusLine` executable. SQLite WAL mode, foreign-key
enforcement, transactions, and a two-second busy timeout provide predictable
cross-process behavior. SQLite still permits one writer at a time; each writer
must make a short, validated transaction rather than holding a write lock while
performing provider or UI work.

The database schema is versioned through explicit GRDB migrations. It persists
only provider accounts, refresh settings, current normalized snapshots, and
source diagnostics. Snapshot history, charts, and retention policies are
separate product features and must not be introduced incidentally by the
migration.

Migration v2 adds the provider-neutral `provider_accounts.executable_path`
column and copies any existing Codex value from the legacy
`codex_executable_path` column. The legacy column remains unused rather than
being destructively removed. Codex app-server and Claude `/usage` CLI share the
new account field while keeping provider-specific discovery and process clients.

Migration v3 binds account-scoped source diagnostics to their provider account
with cascading deletion. Existing diagnostics for missing accounts are removed
during migration, while global diagnostics remain available. An account deletion
therefore removes its snapshots and diagnostics atomically; late provider or
connection results for that account are discarded by `AppModel`.

Migration v6 adds normalized account-context trees and credential slots without
rewriting existing provider accounts or snapshots. Contexts keep app-owned
stable IDs, local display names, region and parent links. Ordinary credentials
attach to leaf `credential` contexts; an optional management credential attaches
to the account root and is unique per saved account. Each slot has its own
enabled state, opaque Keychain reference, lifecycle state, refresh timestamps,
and fixed sanitized diagnostic code. Existing accounts load with no contexts
until a credential-backed source explicitly configures them.

Migration v7 adds current native Contract v1 snapshot metadata and normalized
metric rows without rewriting or removing legacy snapshots. It also extends
per-slot refresh state with completion time, `retryNotBefore`, and consecutive
failure count, and adds a defaulted persisted credential revision to existing
slots. OpenRouter success updates one context/source metric set, state, and
diagnostic in one transaction; failure updates state and diagnostic in one
transaction. Both validate the complete snapshot or outcome, enabled account,
exact credential identity, revision, and refresh generation under the account
lifecycle lock. Exact `Decimal` values use canonical plain-text JSON
representation. Storage contains no history, raw provider payload, provider
error text, upstream opaque ID, or credential material.

Every raw credential is stored as its own local, non-synchronizing generic
password in the macOS Data Protection Keychain. SQLite never stores the value.
All create, read, replace, and delete queries set
`kSecUseDataProtectionKeychain = true` and explicitly select non-synchronizing
items. Creation uses
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, so items remain available
after the first unlock for background menu-bar refresh but do not synchronize
or migrate to another device. The app omits `kSecAttrAccessGroup` from item
queries and therefore uses its provisioned application identifier as the
default private Keychain access group.

Create, recovery, replacement, delete, and account-delete operations are
serialized per account across store instances in the process. They use
inaccessible `pending-creation` and `pending-deletion` metadata to make
SQLite/Keychain partial failures recoverable: the local reference remains
tracked until activation or confirmed Keychain deletion. Replacement updates
the existing Keychain item without changing its reference. Generic account
deletion refuses to cascade credential rows; secure account deletion first
disables all slots, removes every Keychain item idempotently, and only then
removes the account and its database children.

The locally staged DEBUG bundle is signed with an installed Apple Development
identity and embeds the Xcode-managed Mac development provisioning profile for
`io.github.Prontsevich.AILimitBar`. A minimal app target under
`Support/LocalSigning` asks Xcode automatic signing to authorize the exact
`com.apple.application-identifier` and default `keychain-access-groups` values;
the staging script copies that profile and Xcode-expanded entitlements to the
real SwiftPM-built bundle, then requires `codesign --verify --deep --strict`.
The support target does not build or replace the product executable. DEBUG
staging requires an explicit caller-owned team ID, for example
`AILIMITBAR_DEVELOPMENT_TEAM=YOUR_TEAM_ID`; no developer Team ID is stored in
the repository.

A free Personal Team profile is sufficient for local verification but expires
seven days after issuance and must be refreshed by Xcode. It is not a
distribution identity. Release staging instead requires explicit
`AILIMITBAR_DEVELOPMENT_TEAM`, `AILIMITBAR_DEVELOPER_IDENTITY`, and
`AILIMITBAR_PROVISIONING_PROFILE` inputs. The script verifies that the
Developer ID profile authorizes the exact application identifier and default
Keychain group, contains the selected certificate, and targets all macOS
devices. It signs the helper before the app with Hardened Runtime and secure
timestamps and requires `codesign --verify --deep --strict` before and after
the signing-only archive round trip. `script/notarize_release.sh` separately
requires `AILIMITBAR_NOTARYTOOL_PROFILE=YOUR_NOTARYTOOL_PROFILE`, and accepts an
explicit file-based Keychain through `AILIMITBAR_NOTARYTOOL_KEYCHAIN`. It
submits a private copy of the architecture-specific signed ZIP with
`notarytool --wait`, requires `Accepted`, staples the exact submitted app, and
revalidates the final app and extracted ZIP with codesign, stapler, and
Gatekeeper. Protected manual CI uses this path with ephemeral credentials;
clean-Mac validation and public publication remain subsequent trusted-
distribution gates.
Platform references:
[TN3137: On Mac keychain APIs and implementations](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains),
[TN3125: Inside Code Signing: Provisioning Profiles](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles),
and [Developer account overview](https://developer.apple.com/help/account/basics/about-your-developer-account).

The DEBUG-only verification seam proves create/read, cross-rebuild replace/read,
and deletion without printing credential material:

```zsh
verification_dir="$(mktemp -d)"
AILIMITBAR_DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  ./script/stage_app_bundle.sh --configuration debug
dist/AILimitBar.app/Contents/MacOS/AILimitBar \
  --ai-limitbar-keychain-verification create \
  --ai-limitbar-storage-directory "$verification_dir"
AILIMITBAR_DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  ./script/stage_app_bundle.sh --configuration debug
dist/AILimitBar.app/Contents/MacOS/AILimitBar \
  --ai-limitbar-keychain-verification replace \
  --ai-limitbar-storage-directory "$verification_dir"
dist/AILimitBar.app/Contents/MacOS/AILimitBar \
  --ai-limitbar-keychain-verification delete \
  --ai-limitbar-storage-directory "$verification_dir"
```

The seam refuses to create when any account already exists and refuses replace
or delete unless the database contains exactly its expected disposable account,
context tree, and slot. The second staging step is part of the verification: a
same-build read is insufficient evidence that the provisioned application
identifier and default Keychain access group remain stable across a changed
code-directory hash. The command requires an Apple Account configured in Xcode;
`AILIMITBAR_DEVELOPMENT_TEAM` selects that account's team, and automatic signing
registers the local Mac and refreshes the development profile when needed.

Account display names are globally unique across all saved accounts, including
disabled accounts, because the menu-bar dashboard uses the account name as its
primary identifier. Before persistence, Bairometer trims leading/trailing
whitespace and compares names case-insensitively. The database stores a
normalized display-name key under a unique constraint; Settings validates the
same rule before attempting a write. A legacy import that finds a collision
retains every account with deterministic ` (2)`, ` (3)`, and later suffixes and
surfaces a migration warning rather than discarding or overwriting data.

The Claude Code source is a Bairometer-managed database source. The
helper validates its documented `statusLine` input and writes the normalized
local-estimate snapshot directly to the database, including when Bairometer is
not running. The Settings UI does not expose a generic local JSON path.

On the first database launch, the app imports valid legacy `providers.json`,
`snapshots.json`, refresh settings, and the managed Claude `statusline.json`
inside an idempotent migration. Original files remain as backups. A configured
custom local-snapshot path is imported once when valid, then shown as a
migration warning so the user can switch to the bundled helper; the app does
not silently keep following arbitrary external files indefinitely. Malformed or
unsupported legacy data must not replace a valid database row.

Credentials, API keys, cookies, raw provider responses, opaque account/auth
fields, and WebKit browser data never enter the database. Credentials remain in
Keychain and Ollama browser sessions remain in their per-account
`WKWebsiteDataStore`.

### Future WidgetKit sharing

Provisional App Group identifier: `group.com.lestroy.ai-limitbar`. This must be
verified against the final Apple Developer Team and bundle identifiers after
the Apple Developer Program membership gate is complete and before registering
the App Group or signing a WidgetKit build.

Widget constraints:

- The widget is passive: it reads a versioned, normalized snapshot projection
  from App Group storage and renders it. The exact database-sharing mechanism
  must be validated for WidgetKit before implementation.
- The widget must not authenticate, call providers, read Keychain credentials,
  parse legacy provider files, or write provider configuration.
- Missing, stale, unavailable, or manual-confidence snapshots must be displayed
  honestly without invented usage values.
- Timeline reloads should follow stored snapshot freshness and the app's
  configured refresh interval; provider refresh remains the app's job.

Stored snapshots must not contain raw tokens, API keys, cookies, or provider
session data.

The refresh schedule offers Manual, 1 min, 5 min, 10 min, 15 min, 30 min,
and 1 hr. Snapshots are considered stale after 24 hours in manual-only mode or
after two missed configured refresh intervals in scheduled mode. Staleness is
runtime UI state derived from `lastUpdatedAt`; it is not persisted as a snapshot
field.

Provider refreshes retry transient `ProviderAdapterError` failures with a small
exponential backoff. Configuration, schema, and validation errors are permanent
by default and are surfaced immediately without retry.

## Security

- Store provider credentials in Keychain.
- Use one Keychain item per credential slot. Keep only an opaque local reference
  and non-sensitive context configuration in SQLite.
- Treat disabled, missing, pending-creation, and pending-deletion credentials as
  sanitized typed failures. Never return a stored secret through metadata,
  diagnostics, logs, or error descriptions.
- Preserve a retryable inaccessible tombstone when SQLite and Keychain cleanup
  do not both succeed; account deletion must not silently orphan credential
  items.
- Require Apple Development signing, an embedded authorized profile, and the
  exact default Keychain group for local staged DEBUG credential verification.
- Require Developer ID signing, authorized production provisioning, Hardened
  Runtime, secure timestamps, and exact default Keychain-group validation for
  release bundles; require accepted notarization, stapling, ticket validation,
  Gatekeeper assessment, and a validated final archive round trip before local
  distribution validation.
- Do not log secrets.
- Do not store raw provider responses if they may contain sensitive account
  details.
- Keep any experimental scraping or browser-derived provider mode disabled by
  default and clearly marked.
- Keep Ollama WebKit sessions isolated per account and delete the corresponding
  WebKit data store when the account is deleted.

## UI Direction

The menu bar UI should behave like a compact dashboard. Opening the panel should
let the user assess all enabled accounts quickly and then move on.

The menu-bar status item itself is image-only. It keeps one neutral base icon
instead of attempting to communicate state through tiny gauge-needle variants.
One small upper-right badge carries the only visual state: red when an enabled
account has a refresh failure or error, yellow when there is no error and an
enabled account has a warning, and absent otherwise. Red takes precedence over
yellow. The item does not show a percentage, account name, or visible title;
explicit accessibility text communicates the same state without relying on
color. Milestone 24 later maps threshold `Warning` to yellow and `Critical` to
red without changing this icon contract.

The menu-bar dashboard and its account-details popover are an intentional
product-specific exception to the broader Liquid Glass baseline. They follow the
approved terminal-fieldset composition in
[`docs/dashboard-design.md`](dashboard-design.md): thin bordered account panels,
an account-name border interruption, compact outlined usage meters, and no
decorative glass, blur, or hover-card effects. Codex CLI `/status` and lazygit
are the visual references for monospaced label/value inspection, warm adaptive
terminal colors, thin separators, and flat actions; they are not a request to
emulate ANSI or text-mode controls. Interactive controls must still retain
native pointer, keyboard, focus, disabled, accessibility, and a restrained
neutral hover state. Fieldset legends and their right-aligned controls are
independent overlays centered on the border, so refresh progress cannot move a
legend; normal usage meters use the border color while amber stays reserved for
warning/stale status copy. Overlay masks use their intrinsic content width, and
each border-mounted glyph masks only its own fixed hit target with the fieldset
surface rather than sharing a control-strip plate. The account list reserves
title clearance at its top, wider inter-panel spacing, and a capped scrolling
viewport so extra accounts never enlarge the popover or break adjacent borders.

The production AppKit boundary freezes each dashboard opening anchor. It
converts the clicked status-button bounds to screen coordinates once, creates a
transparent nonactivating mouse-ignoring anchor host for that presentation, and
shows a transient `NSPopover` relative to the stable host rather than the
mirrored status-button view. Outside interaction therefore closes the popover
without allowing status-item migration to reanchor it. The host is released on
close or presentation failure; only a later explicit status-item click captures
a new display anchor.

The dashboard viewport is a device-local preference rather than account or
provider data. The current General Settings pane offers `Compact` (320 pt),
`Standard` (460 pt), and `Tall` (640 pt) viewport presets stored in
`UserDefaults`. A preset sets the visible dashboard viewport height and longer
account lists scroll within it. General also contains the app-owned `LANGUAGE`
fieldset for the System Default, English, or Russian choice in `UserDefaults`;
it does not alter account/provider data. Language, refresh, dashboard-height,
and the global Used/Left limit-display default are grouped there as shared
preferences.

Used/Left is presentation state. `UsageLimitWindow.usedPercent` remains the
canonical normalized value; Left is its clamped complement. A window resolves
to its explicit GRDB override keyed by provider ID, saved account ID, and stable
provider-owned window ID, or otherwise to the global `UserDefaults` default.
Missing and invalid global values default to Used. Overrides persist across
refreshes and temporary window omission, cascade when their account is deleted,
and are removed only by Use global or when the meter toggle reaches the global
mode. The displayed label, meter fill, help, and accessibility value share the
effective percentage. Severity, thresholds, notifications, analytics, and the
menu-bar state continue to derive only from canonical `usedPercent`.

Dashboard rows should:

- Show accounts in user-defined order, not grouped by provider by default.
- Use the globally unique account name as the fieldset legend. Keep provider
  context out of the normal dashboard body.
- Render one compact outlined, keyboard-accessible full-width usage-window
  button and one `NN% used` or `NN% left` value per known limit window, such as
  weekly plus provider-defined 3-hour, 4-hour, 5-hour, or other rolling
  windows. Its title, value, meter, and reset text share one hit target; hover
  provides a restrained terminal border/fill and pointing-hand cursor. Pointer
  activation does not retain focus; keyboard navigation enables a terminal
  outline without the system-blue focus ring, and Escape clears it. Activation
  toggles the effective mode without changing canonical usage. From the neutral
  panel, Tab enters the first usage window and Shift-Tab enters the last; both
  keys wrap across usage windows. Space and Return activate the focused window.
  Escape clears meter focus, or closes the dashboard from the neutral state.
- Show a relative reset label when available, but keep normal-state refresh
  timestamps out of the dashboard.
- Keep unavailable, manual, stale, warning, and error states visible inline
  without hiding other accounts.
- Avoid scrolling for common small setups; 3-5 accounts should remain readable
  at a glance.

Account details should be available on demand rather than permanently occupying
the dashboard. Use an explicit Info button to open a single matching technical
inspector with aligned source, confidence, warnings, precise refresh timestamps,
exact reset details, per-window Use global / Used / Left controls, and secondary
per-account actions. Diagnostics appear in its one nested `NOTE` block. Hover
may be added as a convenience, but it must not be the only way to access details.

The settings UI should support:

- A singleton native SwiftUI Settings window opened through an explicit app
  action that activates the menu-bar-only process and calls `openWindow(id:)`.
- A compact terminal segmented navigation control for General, Accounts, and
  Providers instead of a permanent top tile bar or navigation sidebar.
- A General section for language, refresh schedule, and dashboard-height
  preferences. Thresholds and appearance choices remain future work.
- An Accounts master-detail layout with an account-name-first list, provider as
  secondary text, footer add/delete controls, and selected-account detail pane.
- OpenRouter account details with locally named ordinary credential CRUD,
  replacement/recovery, enable/disable, secure deletion, and one separately
  disclosed optional elevated management credential. Secret fields never
  support readback, and deleting the account securely removes its credential
  items before local account state.
- Enabling/disabling providers.
- Ordering accounts through native drag-and-drop, with Move Up/Down context-menu
  actions as a keyboard/accessibility fallback.
- Showing the single current verified or experimental source for each real
  provider; only the built-in Mock provider uses the internal manual source.
- A visible Refresh All icon action in the account-list footer and a
  selected-account Refresh action, with Test Connection and Open Usage in an
  overflow menu without a separate disclosure chevron.
- The overflow trigger should use the same terminal action treatment as the
  other account actions; its popup may use a narrow native `NSMenu` bridge when
  the SwiftUI Settings renderer cannot reproduce the standard macOS menu
  presentation.
- Read-first account details with explicit Edit, Save, and Cancel actions.
- Top-aligned Create and Edit account fieldsets for account data and source
  configuration; a keyboard-accessible terminal provider selector and focused
  text fields remain inside those groups, rather than relying on an adaptive
  `Form` column layout.
- A single discard-confirmation flow for meaningful unsaved account changes
  when switching accounts or Settings sections.
- Reset of transient account-editor state when Settings closes, so reopening
  starts from a clean Accounts view.
- Testing provider connection and opening the provider's usage page.

Settings follows the terminal-adjacent design contract in
[`docs/settings-design.md`](settings-design.md). It shares compact spacing, thin
fieldset borders, restrained semantic status color, and a monospaced text
hierarchy with the dashboard without becoming a literal terminal UI. Terminal
selectors, sidebar selection, toggles, and actions share one palette with visible
hover and pressed feedback; account-editor choice and focus treatments use the
same terminal layer, while file panels, menus, dialogs, and keyboard behavior
remain native where platform semantics matter. Opaque sidebar
backgrounds, system-blue selection, and decorative glass that fight the
composition should be removed, while Light and Dark appearance remain
system-adaptive.

Settings windowing uses a singleton SwiftUI `Window` scene rather than the
system-managed `Settings` scene or an AppKit-owned `NSWindowController`. The
entry action explicitly activates the `LSUIElement` process through the current
`NSApplication.activate()` API and then calls `openWindow(id:)`. New windows use
deterministic default placement, existing windows come forward without moving or
duplicating, and unwanted restoration is disabled so a closed window does not
reappear during launch or Spaces changes. The window remains a normal window,
not an always-on-top panel.

## Daily-Use Smoke Verification

Milestone 22.2 keeps
`AILIMITBAR_DEVELOPMENT_TEAM=YOUR_TEAM_ID ./script/build_and_run.sh --verify`
as the single public smoke command. The command first exercises an app-layer
integration scenario with a deterministic fake provider and disposable
storage: create an account, change the refresh schedule, refresh, persist a
normalized snapshot, recreate `AppModel`, and verify that account
configuration, settings, and snapshot state reload. The targeted test is
`AILimitBarTests.AppModelTests/testDailyUseSmokePersistsAccountSettingsAndSnapshot`.
It then stages the normal debug `.app`, launches it through Launch Services with
the internal `--ai-limitbar-storage-directory` argument, waits for a new
`AILimitBar` process to remain alive, and fails if startup does not succeed.

The automated path must not touch the user's normal Application Support
database, Keychain, isolated WebKit stores, provider CLIs, or network sources.
The test and staged-app launch each use disposable storage and leave no test
persistence residue. `--verify` identifies the smoke process against the
pre-launch PID set and terminates only that process; the staged bundle remains
available for manual QA. Process launch proves startup only; menu-bar
interaction, Settings focus, pointer behavior, and other GUI details remain
explicit manual QA rather than being inferred from a running PID.

## Regular-Window UI Test Host

Debug builds can stage a separate regular-window app at
`dist/AILimitBarUITestHost.app`. The host reuses the production `AILimitBar`
executable and renders the real `MenuBarPanelView` and `SettingsView` with
deterministic synthetic fixtures. Its runtime owns isolated GRDB and
`UserDefaults` state, uses only scripted adapters with a single refresh attempt,
and does not create the production status item, WebKit controller, provider
clients, credentials, or executable overrides.

The host bundle uses `io.github.Prontsevich.AILimitBar.UITestHost`, the
`AILimitBarTest` process name, and `LSUIElement=false`. This lets accessibility
tooling inspect app-owned SwiftUI presentation and keyboard behavior while the
production app remains running. Stable language-independent identifiers cover
dashboard actions and meters, Settings navigation and options, account-name
editing, and the discard confirmation flow. Scenarios cover empty, healthy,
mixed-state, OpenRouter native capacity, Settings, OpenRouter credential
settings, and dirty-editor presentation across explicit language, appearance,
and dashboard-height variants. The full command and AX contract is documented
in [`docs/ui-test-host.md`](ui-test-host.md).

This host does not represent the production `NSStatusItem`, `NSPopover`
anchoring, `LSUIElement` activation or Spaces behavior, OAuth/WebKit, Keychain,
or real provider processes and network integrations. Those boundaries retain
their existing staged-app, integration, telemetry, and manual verification.

## Planned Product Constraints

Detailed future scope is private in Linear. The public constraints that remain
stable are:

- App-owned presentation strings use semantic `surface.section.element` keys in
  the English and Russian `Localizable.strings` tables under
  `Sources/AILimitBar/Resources`. Each key carries its English fallback in code
  and English/Russian table values; a missing Russian value therefore remains
  readable English instead of exposing a technical key. The package default
  localization and staged bundle development region are English, and the staging
  script places both `en.lproj` and `ru.lproj` directly in
  `AILimitBar.app/Contents/Resources` so normal SwiftUI and Foundation lookup
  work from the shipped app.
- Automated localization regression coverage parses both catalogs and requires
  matching non-empty key/value sets plus compatible format placeholders. It
  checks English fallback for unsupported locales, durable `AppLanguage`
  selection without disturbing refresh or dashboard preferences, locale-aware
  presentation formatting, and the staged bundle's localization metadata and
  copied resources. These checks use only synthetic values and complement,
  rather than replace, staged visual and interaction QA.
- `AppLanguage` stores only `system`, `en`, or `ru` in `UserDefaults`. System
  Default follows the current system locale, while explicit English and Russian
  use their corresponding locales. One app-wide preference object injects the
  effective locale into the menu-bar panel, Settings, and utility-window SwiftUI
  roots so an already-open surface updates without relaunching or recreating
  provider state.
- Localization must preserve provider data, account names, technical
  identifiers, and stored values while translating app-owned presentation.
- Used percentages are presentation values: format them with the effective
  locale, preserve a provider-supplied fraction to at most one decimal place,
  and omit a trailing zero for whole values. The same formatted value is used
  for the dashboard, accessibility, and menu-bar summary; normalized provider
  snapshots retain their original numeric `Double` values.
- Thresholds and notifications must operate on provider-defined limit windows,
  remain opt-in where system permission is involved, and never fabricate state
  from unavailable data.
- Appearance customization must preserve textual and accessibility status; color
  cannot be the sole warning or critical signal.
- A WidgetKit extension must be passive, read only normalized shared snapshots,
  and keep provider refresh, authentication, and parsing in the main app.

The app is intentionally menu-bar-only. Local development, debugging, logging,
telemetry, and verification should all run the same staged `LSUIElement` app
bundle so lifecycle behavior does not change between development modes. AppKit
is permitted at narrow application-lifecycle boundaries for explicit activation
and normal termination; it should not own a window, Settings content, or feature
state.

## Open Questions

- Which exact account types should be supported first for OpenAI Codex?
- How stable will the human-readable plan-limit text inside Claude Code's
  non-interactive `/usage` JSON result remain across CLI releases?
- Can the authenticated Ollama settings page retain the semantic usage and reset
  fields required by the experimental parser as the site evolves?
- What refresh interval is useful without hitting provider limits?

## First Implementation Slice

Build a macOS app skeleton with:

- Mock provider.
- `UsageSnapshot` model.
- `ProviderAdapter` protocol.
- JSON snapshot store.
- Menu bar provider list.
- Settings window placeholder.
- Manual refresh.

Real provider integrations should be added only after this skeleton is working.

## Local Development

Build:

```zsh
swift build
```

Test:

```zsh
swift test
```

Run and verify the menu bar app process:

```zsh
AILIMITBAR_DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  ./script/build_and_run.sh --verify
```
