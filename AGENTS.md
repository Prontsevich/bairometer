# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project Overview

AI Limitbar is a macOS menu-bar-only app (`LSUIElement`) for viewing normalized
AI provider usage snapshots. Built with SwiftUI on Swift 6.2 / macOS 15+.

## Build & Test

```zsh
swift build                                           # Build all targets
swift test                                            # Run full test suite
AILIMITBAR_DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  ./script/build_and_run.sh                           # Stage DEBUG .app and launch
```

Useful run modes: `--verify`, `--debug`, `--logs`, `--telemetry`.

The run script builds the SwiftPM product, stages the DEBUG `.app` bundle in
`dist/`, and launches it. DEBUG staging requires the caller's explicit
`AILIMITBAR_DEVELOPMENT_TEAM`; Xcode automatic signing supplies an installed
Apple Development identity and an Xcode-managed profile that authorizes the
restricted application-identifier and default Keychain-group entitlements.
Release staging requires an explicit Developer ID Application identity and a
matching Developer ID provisioning profile supplied outside the repository. It
signs the helper before the app, enables Hardened Runtime, requests secure
timestamps, and preserves the authorized default Keychain group. Local trusted
packaging additionally requires a caller-owned Keychain profile such as
`AILIMITBAR_NOTARYTOOL_PROFILE=YOUR_NOTARYTOOL_PROFILE`; callers using an
isolated file-based Keychain also provide its path through
`AILIMITBAR_NOTARYTOOL_KEYCHAIN`. The wrapper submits the signed architecture-
specific ZIP, staples the accepted app, and revalidates the final archive with
codesign, stapler, and Gatekeeper. The manual-only protected CI workflow runs
the same pipeline on native Apple Silicon and Intel runners and uploads short-
lived workflow artifacts after an independent trust-validation pass. GitHub
Release publication and tag triggers remain disabled. All run modes use the
same bundle shape.

## Architecture

### Targets

| Target | Type | Purpose |
| --- | --- | --- |
| `AILimitBar` | Executable | Main menu-bar app (SwiftUI `MenuBarExtra`) |
| `AILimitBarClaudeStatusLine` | Executable | Bundled helper for Claude Code `statusLine` |
| `AILimitBarCore` | Library | Shared models, providers, services, stores |
| `AILimitBarCoreTests` | Tests | Core layer: providers, DB, snapshots, refresh |
| `AILimitBarTests` | Tests | App layer: orchestration, dashboard presentation |

### Layers

```
AILimitBar (app)
├── App/        — SwiftUI app entry, lifecycle
├── Models/     — Dashboard presentation models
├── Support/    — Telemetry, statusLine installer, WebKit controller
├── ViewModels/ — AppModel and extensions (accounts, persistence, refresh)
└── Views/      — MenuBarPanel, Settings, account details, terminal styling

AILimitBarCore (library)
├── Models/    — UsageSnapshot, ProviderConfiguration, RefreshSettings
├── Providers/ — ProviderAdapter protocol + 5 adapters (Codex, Claude, Ollama, Mock, Manual)
├── Services/  — CodexAppServerClient, ClaudeCodeStatusLine, Keychain, RefreshCoordinator
└── Stores/    — GRDB/SQLite database, stores, legacy importer

AILimitBarClaudeStatusLine (helper)
└── main.swift — Reads statusLine JSON from stdin, writes snapshot to SQLite
```

### Key Patterns

- **Provider adapters** implement `ProviderAdapter` protocol. Each normalizes
  provider data into a `UsageSnapshot`. Adapters never touch UI state directly.
- **`AppModel`** is the main view model, split across `+Accounts`, `+Persistence`,
  `+Refresh` extensions.
- **GRDB/SQLite** stores provider accounts, refresh settings, current normalized
  snapshots, and source diagnostics. It uses WAL mode, foreign keys, and a
  bounded busy timeout. Device-local UI preferences may use `UserDefaults`;
  credentials belong only in Keychain, and browser session data stays in its
  isolated `WKWebsiteDataStore`.
- **AppKit** stays behind narrow platform-integration boundaries such as app and
  window lifecycle, native menus, adaptive colors, and SwiftUI/WebKit bridges.
  Feature state remains in SwiftUI and `AppModel`.
- **Terminal-fieldset dashboard** — the menu bar panel and account details
  use a compact terminal-fieldset composition, not glass cards. See
  `docs/dashboard-design.md`.

## Working Agreement

- Treat live code and `Package.swift` as the source of truth for current
  implementation, `docs/plan.md` for current architecture and settled public
  contracts, and `docs/tasks.md` for completed-history evidence. Active work,
  priorities, dependencies, acceptance, and lifecycle belong in private Linear.
- When Linear is connected and available, use Team `Development` and the
  `Bairometer` product Initiative. Read `Development — Working Guide`, then the
  selected Issue, its relevant finite Project document, and only the linked
  design or provider documents needed for its acceptance. Views are navigation
  aids, not another planning hierarchy.
- New ideas, reports, observations, and agent-discovered concerns enter
  `Triage` cheaply. Search before creating or shaping work. Each shaped Issue
  has exactly one Type: `Bug`, `Gap`, `Feature`, `Improvement`, `Refactor`,
  `Research`, or `Chore`. Use a finite Project for a coherent multi-Issue
  outcome; use `Improvements & Fixes` for ordinary standalone work.
- Follow `Triage` → `Backlog` → `Todo` → `In Progress` → `In Review` → `Done`.
  A status, Project, or plan does not grant execution authority. `Done` requires
  the Issue's observable acceptance and required verification, rather than
  technical implementation or a checklist alone.
- Read the actual evidence and dependencies for any gate before starting its
  blocked scope. Historical Apple Developer Program membership evidence does not
  itself satisfy downstream signing, notarization, protected-CI, clean-Mac, or
  release acceptance requirements.
- Use `change` and `execute-tasks` handoffs proportionally: a small change may
  use an inline approach, while consequential design needs a dated spec and
  resumable ordered work needs a dated plan. Reconcile affected living docs
  with verified implementation; keep tracker acceptance canonical in Linear.
- When Linear is unavailable, use `docs/backlog.md` for intake and necessary
  pending synchronization, explicitly marked pending. Reconcile it with Linear
  after access returns and retire temporary entries; do not run parallel live
  trackers while Linear is available.
- Treat multiple independently authenticated accounts as a first-class
  power-user scenario in provider research and implementation. A source tied to
  one local CLI identity must state that limit, must not be presented as several
  accounts, and must be evaluated alongside safe per-account fallback options.
- Keep private Linear issue identifiers and URLs out of branch names, commits,
  public GitHub issues, and pull requests. Attach a public pull request URL from
  the private Linear issue instead.
- Verify changes in proportion to their scope. Run `swift build` and `swift test`
  for code changes; use the staged `.app` bundle for UI, lifecycle, or provider
  integration checks. Do not mark manual verification complete unless it was
  actually performed.
- **Direct UI automation remains unavailable for the production app.** The
  current Codex Computer Use connection cannot discover or inspect its
  `LSUIElement` menu-bar process. Do not retry it against the production app.
  Use `./script/build_and_run.sh --ui-test-host <scenario>` with explicit
  `AILIMITBAR_DEVELOPMENT_TEAM=YOUR_TEAM_ID` for app-owned dashboard and
  Settings AX/visual checks; see `docs/ui-test-host.md`. The host does not cover
  the production status item, `NSPopover` anchoring,
  `LSUIElement` activation/Spaces, OAuth/WebKit, or real providers. Keep those
  on their existing Swift-test, `--verify`, telemetry, staged-app, and explicit
  manual verification paths.
- Preserve unrelated working-tree changes. Create commits only when the user asks,
  and keep each requested commit scoped to one coherent task.

## Commit Conventions

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(scope): description
docs(scope): description
fix(scope): description
refactor(scope): description
style(scope): description
build(scope): description
```

Common scopes: `storage`, `codex`, `dashboard`, `ollama`, `claude`, `settings`,
`roadmap`, `readme`, `core`, `app`, `ui`, `dev`, `mvp`, `project`.

## Constraints

- **macOS 15+ only.** Do not add compatibility fallbacks for older macOS.
- **SwiftUI-first.** Use system controls before custom components. The
  terminal-fieldset visual system is the product-specific composition.
- **Privacy-first.** Never put credentials, tokens, cookies, browser session
  data, or raw provider responses in SQLite, `UserDefaults`, logs, or
  diagnostics. Persist credentials only in Keychain, keep browser data in its
  isolated per-account `WKWebsiteDataStore`, and do not persist raw responses.
- **Menu-bar-only.** The app uses `LSUIElement` — no Dock icon, no main window.
- **Experimental sources are opt-in.** A successful experimental read is `OK`;
  the `Experimental` label is informational, not a warning.
- **No external dependencies** except GRDB.swift.
- **Don't edit** `.codex/environments/environment.toml` — it is autogenerated.

## Documentation

- `docs/plan.md` — Current architecture, provider evidence, and settled public
  contracts
- `docs/tasks.md` — Completed milestone scope, acceptance criteria, and
  verification history; active and future scope is tracked privately in Linear
- `docs/backlog.md` — Fallback intake and pending synchronization only when
  Linear is unavailable
- `docs/dashboard-design.md` — Terminal-fieldset dashboard design contract
- `docs/settings-design.md` — Settings window lifecycle and visual contract
- `docs/design-qa.md` — Dashboard visual QA findings and fixes
- `docs/providers/` — Per-provider implementation notes
