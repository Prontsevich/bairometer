# Bairometer Roadmap

## Work Tracking

Active work, status, priority, dependencies, and acceptance are tracked in
private Linear under Team `Development` for the `Bairometer` product. This
document preserves milestone goals, scope, acceptance criteria, and
completed-history evidence; it is not a second live task tracker. Closed
checkboxes are historical. Remaining plain bullets describe scope whose live
state belongs to the corresponding Linear Issue.

The public GitHub issue links below are legacy references for completed manual
QA. New private implementation work belongs in Linear. Do not copy private
Linear issue descriptions or identifiers into public GitHub content.

Bairometer is the public product identity. Historical entries retain
`AILimitBar` only for technical compatibility artifacts such as executables,
bundle paths, storage, and identifiers.

| Roadmap scope | GitHub issue |
| --- | --- |
| Milestone 12 manual Settings QA | [#1](https://github.com/Prontsevich/ai-limitbar/issues/1) |
| Milestone 17 manual dashboard QA | [#2](https://github.com/Prontsevich/ai-limitbar/issues/2) |
| Milestone 22.1 manual status-indicator QA | [#4](https://github.com/Prontsevich/ai-limitbar/issues/4) |
| Milestone 22.3 manual Ollama WebKit QA | [#5](https://github.com/Prontsevich/ai-limitbar/issues/5) |

## Milestone 0: Project Foundation

- [x] Create project directory.
- [x] Initialize git repository.
- [x] Draft MVP plan.
- [x] Create initial macOS project scaffold.
- [x] Add basic build/run script for local development.
- [x] Add project README.

## Milestone 1: App Skeleton

Goal: produce a runnable macOS menu bar app with mock data and no real provider
credentials.

- [x] Create SwiftUI macOS app target.
- [x] Add `MenuBarExtra` as the primary app surface.
- [x] Add settings scene placeholder.
- [x] Add `UsageSnapshot` model.
- [x] Add `ProviderAdapter` protocol.
- [x] Add mock provider adapter.
- [x] Add app-level snapshot state.
- [x] Render provider rows in the menu bar panel.
- [x] Add manual refresh action.
- [x] Show last updated state.
- [x] Show confidence/source labels.

Acceptance:

- The app launches.
- The menu bar item appears.
- Mock provider snapshots render.
- Manual refresh changes or reloads mock data.
- No real credentials are required.

## Milestone 2: Persistence

Goal: persist normalized snapshots locally without storing secrets.

- [x] Add application support directory resolver.
- [x] Add JSON snapshot store.
- [x] Load snapshots on app launch.
- [x] Save snapshots after refresh.
- [x] Handle missing/corrupt snapshot files gracefully.
- [x] Add lightweight error state for failed loads or saves.

Acceptance:

- Closing and reopening the app preserves the last mock snapshot.
- Snapshot JSON contains no credentials or raw provider responses.

## Milestone 3: Provider Configuration

Goal: let users enable providers and prepare for real credentials.

- [x] Add provider registry.
- [x] Add provider enabled/disabled state.
- [x] Add settings UI for provider toggles.
- [x] Add placeholder connection test action.
- [x] Add provider usage URL action.
- [x] Add Keychain service interface.
- [x] Keep credential entry disabled until real provider requirements are known.

Acceptance:

- The settings window controls which providers appear in the menu bar list.
- Provider state survives app restart.
- The app has a clear place to add credentials later.

## Milestone 4: Provider Research Spikes

Goal: determine what each provider can support reliably before implementation.

- [x] OpenAI Codex: identify supported usage sources by account type.
- [x] OpenAI Codex: decide MVP source mode and confidence level.
- [x] Claude Code: identify CLI/local usage source and output format.
- [x] Claude Code: decide whether usage can be parsed reliably.
- [x] Ollama Cloud: determine whether a documented usage API exists.
- [x] Ollama Cloud: decide MVP source mode and confidence level.
- [x] Document unsupported or manual-only cases in the plan.

Acceptance:

- Each provider has a documented source strategy.
- Each provider has a selected initial confidence level.
- No provider implementation starts from an unverified assumption.

## Milestone 5: First Real Provider

Goal: add one real provider end to end.

- [x] Pick first provider based on research results.
- [x] Implement configuration requirements.
- [x] Implement adapter fetch logic.
- [x] Normalize provider result into `UsageSnapshot`.
- [x] Add structured error handling.
- [x] Add connection test.
- [x] Add manual refresh.
- [x] Verify no secrets are logged or persisted outside Keychain.

Acceptance:

- One real provider returns a useful snapshot.
- Errors are visible and actionable.
- The mock provider still works.

Decision:

- Claude Code is the first real provider target.
- Initial mode is opt-in `local-estimate` from a Bairometer-owned JSON
  snapshot file.
- The provider must not parse Claude's interactive `/usage` screen,
  undocumented local session files, browser pages, or private provider state.
- The settings `Test` action uses the configured adapter fetch path and surfaces
  structured adapter errors as snapshot warnings.
- Manual refresh uses the same configured adapter fetch path for every enabled
  provider and persists the resulting normalized snapshot.
- The Claude Code local snapshot schema excludes credentials, cookies, tokens,
  raw provider responses, and free-form provider warnings; the app persists only
  normalized snapshot fields and app-generated warnings.

## Milestone 6: Refresh Coordination

Goal: make refresh behavior predictable and respectful of provider limits.

- [x] Add refresh coordinator.
- [x] Add per-provider refresh status.
- [x] Prevent overlapping refreshes.
- [x] Add configurable refresh interval.
- [x] Add stale snapshot detection.
- [x] Add retry/backoff policy for transient failures.

Acceptance:

- Manual refresh remains immediate.
- Scheduled refreshes do not overlap.
- Stale data is clearly labeled.

## Milestone 7: Widget Readiness

Goal: prepare snapshots for WidgetKit without adding the widget yet.

- [x] Move snapshot storage behind a container abstraction.
- [x] Decide App Group identifier.
- [x] Add shared snapshot format version.
- [x] Keep storage location switch explicit for pre-release builds.
- [x] Document widget constraints.

Acceptance:

- The app can switch storage locations without changing provider adapters.
- Widget work can start without redesigning snapshot storage.

Decision:

- Provisional App Group identifier: `group.com.lestroy.ai-limitbar`.
- The identifier must be verified against the final Apple Developer Team and
  bundle identifiers before signing a WidgetKit build.

Widget constraints:

- The widget must be passive and read only versioned normalized snapshots from
  the App Group container.
- The widget must not fetch providers, authenticate, read Keychain credentials,
  parse local provider state, or write provider configuration.
- Widget UI must handle stale, unavailable, and missing snapshots without
  inventing usage values.
- Timeline reload policy should be derived from stored snapshot freshness and
  the app's configured refresh interval.

## Milestone 8: Account Model

Goal: make the menu bar app model provider accounts explicitly before adding
more real data sources.

- [x] Add `ProviderAccount` model.
- [x] Add stable account identifiers scoped by provider.
- [x] Add account display name and enabled state.
- [x] Allow providers to have zero, one, or many configured accounts.
- [x] Add account identity to stored snapshots.
- [x] Group menu bar rows by provider and account.
- [x] Update settings to configure accounts instead of only providers.
- [x] Keep existing single-provider mock and Claude local snapshot behavior
  working through configured accounts.

Acceptance:

- A provider can have more than one configured account.
- Providers can be left with no configured accounts.
- Menu bar rows clearly identify both provider and account.
- No provider credentials are introduced outside Keychain.

## Milestone 9: Account Details Panel

Goal: make the menu bar item open a useful compact window with details for each
account.

- [x] Add account row selection.
- [x] Add account details view.
- [x] Show usage, source, confidence, warnings, reset time, stale state, and
  last refresh state.
- [x] Add per-account refresh action.
- [x] Add per-account connection test action.
- [x] Add per-account open usage page action.
- [x] Add empty, unavailable, stale, and error states.
- [x] Keep the panel compact enough for repeated menu bar use.

Acceptance:

- Clicking an account row reveals detailed account state.
- Account actions affect only the selected account.
- Errors and stale data are visible without hiding the last known snapshot.

## Milestone 10: Dashboard Panel Redesign

Goal: make the menu bar panel a glanceable dashboard for all enabled accounts,
not a list with a permanently visible inspector.

- [x] Replace the selected-detail-first layout with compact dashboard rows.
- [x] Show every enabled account in user-defined order without grouping by
  provider.
- [x] Add account ordering controls in Settings with move up/down actions.
- [x] Add normalized limit-window rows for provider-defined windows such as
  weekly limits and 3-hour, 4-hour, 5-hour, or other rolling windows.
- [x] Render one compact progress bar per known limit window.
- [x] Keep unavailable, manual, stale, warning, and error states visible in the
  account row without hiding other accounts.
- [x] Move source, confidence, warnings, last refresh state, reset details, and
  account actions into an explicit details popover.
- [x] Use a `?` or info button for details; hover may preview or highlight but
  must not be the only way to access details.
- [x] Avoid scrolling for common small setups and keep 3-5 accounts readable at
  a glance.

Acceptance:

- Opening the menu bar panel gives a fast account-wide status overview.
- Accounts are not grouped by provider unless the user later chooses that sort.
- Each known limit window has its own label, progress bar, and reset/remaining
  text when available.
- Details are available on demand without occupying the main dashboard surface.

Decision:

- Milestone 9 remains the technical foundation for per-account selection,
  actions, and details. Milestone 10 replaces its visible panel layout with a
  dashboard-first design before adding more data-source work.
- Limit windows are provider-defined and must not be hardcoded to only hourly or
  weekly categories. A provider may expose weekly plus 3-hour, 4-hour, 5-hour,
  or other rolling windows.

## Milestone 11: Settings Window Redesign

Goal: replace the system SwiftUI `Settings` scene with a controlled settings
window and make account configuration clear enough for daily use.

Superseded by Milestone 12: Settings now uses SwiftUI's native `Settings`
scene again. The controlled AppKit settings window was removed in favor of the
current system windowing path.

- [x] Remove the system SwiftUI `Settings` scene.
- [x] Add a narrow settings window controller that owns one settings window.
- [x] Open Settings from the menu bar panel through the controlled window path.
- [x] Focus the existing Settings window when it is already open instead of
  creating duplicates.
- [x] Ensure closing Settings destroys/hides that window and does not reopen it
  during Spaces changes.
- [x] Redesign Settings around clear sections for Accounts, Refresh, and
  Provider Setup.
- [x] Make Accounts the primary Settings section.
- [x] Render each account as a readable block with name, provider, enabled
  state, source, optional local snapshot path, ordering controls, and actions.
- [x] Keep account cards read-first, with rename behind an explicit edit
  button instead of a permanently focused text field.
- [x] Use an inline add-account form instead of a modal sheet.
- [x] Require confirmation before deleting an account.
- [x] Keep add account, enable/disable, rename, move up/down, test connection,
  open usage page, delete account, Claude Code source mode, local snapshot path,
  and refresh interval working.
- [x] Keep the existing provider account and snapshot storage contracts
  unchanged.

Historical acceptance for the superseded controlled-window path:

- Settings opens as an app-controlled window from the menu bar panel.
- Pressing Settings while the window is open focuses the existing window.
- Closing Settings prevents it from reappearing on its own during Spaces changes.
- Account ordering and provider/source state are easy to understand.
- The redesign remains an MVP settings surface, not a large enterprise
  administration system.

## Milestone 12: Modern macOS And Liquid Glass Baseline

Historical note: this milestone records the earlier Liquid Glass exploration.
Its deployment and visual baseline were later superseded; the current decision
is macOS 15+ with the terminal-fieldset visual system documented in
`docs/plan.md`.

Goal: move Bairometer to a modern-only macOS baseline and redesign the visible
app surfaces around the current system design language instead of legacy
compatibility patterns.

- [x] Raise the deployment target to the current Liquid Glass-capable macOS
  baseline.
- [x] Remove macOS 14 compatibility as a product constraint.
- [x] Audit Settings and the menu bar panel for custom chrome, custom
  backgrounds, `.plain` button styles, and hand-built hover/selection states
  that replace standard system behavior.
- [x] Redesign Settings around standard SwiftUI structures and controls first:
  system sidebars, toolbar items, sheets, forms, pickers, toggles, and buttons
  where they fit the workflow, because those controls already carry the current
  Liquid Glass appearance and interaction model.
- [x] Treat Liquid Glass as the visual baseline for custom app-specific
  surfaces, not as a hand-built replacement for system buttons, sidebars,
  toolbars, sheets, forms, or pickers.
- [x] Prefer native hover, pressed, focus, keyboard, and accessibility behavior
  over custom visual effects.
- [x] Remove Settings window AppKit interop and use SwiftUI scene/windowing.
- [x] Remove or justify custom `GroupBox`-style account cards, opaque fills,
  manual sidebar selection backgrounds, and decorative materials that fight the
  system visual language.
- [x] Revisit Settings window strategy after the redesign: use the native
  SwiftUI `Settings` scene even if the old Spaces workaround is no longer
  preserved.
- [x] Verify hover, click, focus ring, resize, close/reopen, and Settings
  state-reset behavior in a foreground `.app` bundle.
- [x] Update screenshots or documentation notes after the modern UI direction
  is implemented.

Acceptance:

- The app intentionally targets modern macOS technology instead of preserving
  old OS compatibility.
- Settings and menu bar controls feel like current macOS controls, including
  pointer, pressed, focus, and keyboard behavior.
- Standard SwiftUI controls and system structures are used before custom
  components.
- Custom Liquid Glass surfaces are used for product-specific compositions,
  such as account status clusters or dashboard summaries, and do not duplicate
  standard system controls.
- Settings UI and windowing use SwiftUI-native scene and control APIs.
- Modern visual behavior does not regress the account workflows, refresh
  controls, source configuration, or Settings close/reopen behavior.

Decision:

- Bairometer is a modern-only macOS app. Do not optimize UI architecture for
  macOS 14-era compatibility unless that decision is explicitly reopened.
- Liquid Glass and current SwiftUI macOS patterns are the default design
  baseline.
- The project should honor Apple's current controls and interaction work
  instead of recreating hover, click, focus, toolbar, sidebar, or glass behavior
  by hand.
- Originally implemented with macOS 26 as the deployment baseline, a SwiftPM
  6.2 manifest, Swift 6 language mode, SwiftUI's native `Settings` scene, a system
  `NavigationSplitView` sidebar, and grouped `Form` sections for account
  settings.
- Removed the controlled AppKit settings window, close observer, text-field
  prewarm, and other Settings window lifecycle bridges.
- URL opening now goes through SwiftUI's `openURL`, and Settings opens through
  `openSettings`. AppKit is limited to the application termination boundary.
- Removed custom hover tint/scale effects; interaction feedback now comes from
  system controls and SwiftUI glass/button behavior.
- Foreground `.app` launch verification passed with `./script/build_and_run.sh --verify`.
  Interactive hover/click/focus smoke also passed manual QA on 2026-07-15.

Historical note: Milestone 18 plans to supersede the native `Settings` scene
decision after daily use exposed unresolved activation, key-window, placement,
and Spaces behavior in the menu-bar-only `LSUIElement` app. The replacement
remains SwiftUI-owned and adds only a narrow application-activation boundary.

## Milestone 12.1: Quality Stabilization Gate

Goal: make the current modern macOS baseline reliable, testable, and maintainable
before starting another provider or product feature milestone.

- [x] Bound the menu bar dashboard and account-details popover by available
  screen space regardless of account or limit-window count.
- [x] Own and cancel account refresh tasks so deleting an account cannot restore
  orphan runtime state or persisted snapshots.
- [x] Validate every adapter result against the requested provider and account
  identity before it reaches app state.
- [x] Preserve unsupported or malformed snapshot documents before writing a new
  current-format document.
- [x] Make refresh retry cancellation cooperative and test it.
- [x] Add a dedicated app test target and cover orchestration for
  refresh, deletion, persistence, ordering, and menu bar summary behavior.
- [x] Remove unused inspector, grouping, selection, and row code left behind by
  the dashboard redesign.
- [x] Restore normal macOS termination behavior through a narrow lifecycle edge.
- [x] Make debug, run, logs, telemetry, and verify modes use the same staged app
  bundle.
- [x] Add explicit accessibility semantics for the menu bar status item and
  icon-only account actions.
- [x] Keep Settings compact and complete the expected Return/Escape keyboard
  flows.
- [x] Align README and architecture documentation with the implemented account,
  snapshot-format, launch, and storage behavior.
- [x] Pass debug and release builds, warnings-as-errors, the full test suite,
  script validation, code-sign validation, and a foreground app smoke test.

Acceptance:

- Valid provider data cannot make primary menu bar actions unreachable.
- Deleting an account while work is in flight leaves no account snapshot,
  refresh status, or persistence residue after the task completes.
- Malformed or newer snapshot formats are preserved before replacement.
- App-facing orchestration has deterministic automated coverage instead of
  relying only on `AILimitBarCore` tests.
- Every development mode exercises the same menu-bar-only `.app` bundle shape.
- The working tree contains no obsolete dashboard predecessor code.
- Documentation describes the live implementation and current quality gate.

Decision:

- Settings behavior across macOS Spaces is explicitly deferred and is not a
  blocker for this stabilization gate.
- The native SwiftUI `Settings` scene and the modern macOS/Liquid Glass direction
  remain in place for this stabilization gate. Milestone 18 later revisits the
  scene choice without returning Settings ownership to AppKit.
- AppKit may be used only at a narrow platform lifecycle boundary where SwiftUI
  does not expose an equivalent application-termination action.

## Milestone 12.2: Settings Account Master-Detail Redesign

Goal: make Settings feel like a compact native macOS preference window, with
account management modeled after the Accounts pane in system apps.

- [x] Replace the top-level Settings sidebar and tile bar with a compact native
  segmented control for Accounts, Refresh, and Provider Setup; render each
  section below it so the Accounts master-detail sidebar remains local.
- [x] Rebuild Accounts as a master-detail layout: a compact account list on the
  left and selected-account configuration on the right.
- [x] Show account name first and provider name second in the list.
- [x] Add native drag-and-drop reordering; keep Move Up/Down in the row context
  menu as an accessibility fallback.
- [x] Put add/delete controls in the list footer and keep delete confirmation.
- [x] Add a read-only detail state with immediate Enabled control, visible
  Refresh action, Edit button, and overflow menu for Test Connection/Open Usage.
- [x] Add create and edit forms in the detail pane with Save/Cancel behavior.
- [x] Make multi-field account edits persist atomically without changing the
  existing configuration storage format.
- [x] Guard account and section navigation with one discard confirmation that
  appears only after meaningful draft changes.
- [x] Reset the editor session and return to Accounts when Settings closes;
  reopening Settings must not restore an active draft.
- [x] Normalize draft values using the same trimming/default rules as account
  persistence before deciding whether a draft is dirty.
- [x] Add app-model coverage for atomic account edits and multi-row reordering.
- [x] Use system glass icon buttons for account actions, move Refresh All into
  the account-list footer, and keep all Settings pane content on a consistent
  readable width.
- [x] Keep the overflow trigger as a matching glass button while presenting
  its actions through a narrow native `NSMenu` bridge, because the SwiftUI
  Settings toolbar renderer does not expose the Notes-style menu affordance.

Acceptance:

- Settings opens directly to Accounts with a compact segmented section control,
  without a permanent top tile bar.
- Account rows remain compact and preserve the user-defined dashboard order.
- Frequent refresh actions are discoverable; less frequent actions do not crowd
  the account detail header.
- Entering Edit without changing a field does not trigger a discard prompt.
- Closing and reopening Settings shows a clean Accounts state.
- Edit, create, delete, enable/disable, reorder, refresh, connection test, and
  usage-page workflows remain available.

## Milestone 13: Claude Code Data Source

Goal: make Claude Code useful without relying on hand-edited JSON files.

- [x] Define the first supported Claude Code local data source contract.
- [x] Add a helper/import path that writes Bairometer local snapshot JSON.
- [x] Validate helper output before storing snapshots.
- [x] Add source diagnostics for missing file, invalid schema, stale helper
  output, and invalid percentage values.
- [x] Document how to configure Claude Code local snapshot updates.
- [x] Avoid parsing Claude interactive screens, private local state, or browser
  pages.

Acceptance:

- [x] Claude Code can produce useful local-estimate data without manually editing
  JSON.
- [x] The source remains clearly labeled as local-estimate, not account-authoritative
  live usage.
- [x] Invalid helper output does not corrupt stored snapshots.

## Milestone 14: Ollama Cloud Web Page Data Source

Goal: add an explicit opt-in, experimental Ollama Cloud source that reads the
authenticated usage page without accessing, copying, or persisting browser
credentials.

- [x] Add an `ollama-web-page` source mode; keep `manual` as the default and
  fallback mode for Ollama Cloud accounts.
- [x] Add a compact `Connect Ollama…` / `Reconnect` flow backed by an
  Bairometer-owned `WKWebView`; the user completes sign-in directly with
  Ollama in that view.
- [x] Keep the WebKit session isolated from other browsers and apps. Do not
  read, export, import, log, or write cookies, tokens, passwords, profile data,
  or any browser storage outside WebKit's own managed session.
- [x] Load only `https://ollama.com/settings` after a successful connection and
  add a narrowly scoped user script for that exact origin and path.
- [x] Parse the current server-rendered usage page through semantic text
  anchors, not CSS utility-class names: `Session usage`, `Weekly usage`, their
  used percentages, and reset timestamps.
- [x] Validate the extracted payload in Swift before creating a snapshot:
  required windows must be present, percentages must be in `0...100`, and
  reset values must be valid future dates when supplied.
- [x] Normalize session and weekly values into provider-defined
  `UsageLimitWindow` entries; do not assume the session window has a fixed
  duration or that either page section is permanently available.
- [x] Keep per-model request counts and extra-usage balance out of the initial
  snapshot contract; they are not required to represent the two primary limits.
- [x] Label the source as `Experimental web page` in Settings and details,
  including the risk that Ollama may change its authenticated page structure
  without notice; a successful experimental read remains `OK`.
- [x] Run refreshes only through the configured schedule or explicit user
  action. A refresh must never foreground the login UI, submit account changes,
  or attempt an unattended reauthentication.
- [x] Add clear recovery states for a missing connection, expired session,
  changed page structure, incomplete usage data, load failure, and timeout;
  preserve the last valid snapshot when a refresh fails.
- [x] Discard raw HTML and JavaScript bridge payloads after validation. Do not
  write them to snapshots, diagnostics, logs, tests, or export bundles.
- [x] Add fixture-based parser and adapter tests for both windows, a missing
  window, invalid percentages, stale/expired connection, parser drift, and a
  refresh failure that preserves the prior snapshot.
- [x] Document connection, reconnect, privacy, experimental compatibility, and
  manual-fallback behavior in the README and provider plan.

Acceptance:

- [x] An explicitly connected Ollama account supplies current session and weekly
  limit windows from its settings page without any Bairometer-managed
  credential storage.
- [x] The settings and dashboard clearly distinguish this source from an official
  machine-readable usage API and make reconnection actionable.
- [x] A page or session change produces a recoverable warning and retains the last
  valid snapshot instead of inventing or clearing limit values.
- [x] The initial implementation neither parses another browser's session nor
  stores raw page content, cookies, tokens, profile data, model request counts,
  or billing balance.

Decision:

- The current Ollama settings page is account-authenticated and server-rendered;
  no separate usage JSON response was observed during the research check.
- This source is intentionally an experimental DOM integration. Re-evaluate it
  if Ollama publishes a supported account-usage API.
- The user must sign in again through Bairometer's own WebKit view. The app
  must never reuse or extract a session from Codex, Safari, Chrome, or another
  browser.

## Milestone 15: Codex App-Server Data Source

Goal: add an opt-in, experimental OpenAI Codex source that reads structured
current CLI rate-limit data without scraping an interactive terminal, browser,
or local session history.

- [x] Add an `app-server` source mode for OpenAI Codex; keep `manual` as the
  default and fallback mode.
- [x] Locate an installed `codex` executable without storing authentication
  material, cookies, tokens, or account files.
- [x] Start `codex app-server --listen stdio://` for one refresh, complete the
  JSON-RPC initialization handshake, and request `account/rateLimits/read`.
- [x] Normalize `primary` and optional `secondary` rate-limit windows into
  provider-defined `UsageLimitWindow` values; do not assume a weekly window is
  always present.
- [x] Handle multi-bucket responses defensively and select the Codex limit
  bucket only when it is explicitly identified.
- [x] Discard raw app-server responses and unneeded account fields, including
  credit balance strings, reset-credit identifiers, and opaque account data.
- [x] Add diagnostics for a missing CLI, unauthenticated CLI, unsupported or
  changed app-server schema, malformed JSON-RPC responses, timeouts, and
  process-launch failures.
- [x] Use the configured refresh schedule rather than high-frequency polling;
  terminate the short-lived app-server process after each request.
- [x] Label the source as experimental in Settings and snapshots, with clear
  compatibility and data-coverage context; a successful experimental read
  remains `OK`.
- [x] Add fixture-based tests for current, missing-secondary, multi-bucket,
  malformed, and timeout/error responses without depending on a real account.
- [x] Document setup, the experimental compatibility boundary, privacy rules,
  and the manual fallback.

Acceptance:

- An authenticated local Codex CLI can supply normalized rate-limit windows to
  an explicitly opted-in OpenAI Codex account.
- Missing windows or unsupported response fields degrade to a useful warning,
  never a fabricated quota value.
- The app never drives `/status` through a PTY and never reads browser content,
  raw Codex session files, or Codex authentication state.
- No credentials, raw app-server payloads, or opaque account identifiers are
  written to Bairometer storage or diagnostics.
- A Codex CLI update or unavailable experimental interface leaves the account
  in a clear recoverable state and preserves the manual usage-page workflow.

## Milestone 16: Local Database Migration

Goal: replace the app's JSON persistence and Claude Code snapshot file with one
app-owned SQLite database accessed through GRDB, without losing existing local
state or weakening the current privacy boundary.

- [x] Add GRDB through Swift Package Manager and make it available to both
  `AILimitBar` and `AILimitBarClaudeStatusLine` through `AILimitBarCore`.
- [x] Create one non-user-configurable database at
  `~/Library/Application Support/AI Limitbar/AI Limitbar.sqlite` (a retained
  technical path) and enable
  WAL mode, foreign-key enforcement, and a bounded busy timeout.
- [x] Define versioned GRDB migrations for provider accounts, current
  normalized snapshots, refresh settings, and persisted source diagnostics.
  Preserve the current app behavior; history/chart retention is a separate
  feature, not an implicit migration requirement.
- [x] Enforce one globally unique account display name across all persisted
  accounts, including disabled accounts. Trim leading/trailing whitespace and
  compare names case-insensitively before save; back the rule with a normalized
  database column and a unique constraint rather than UI validation alone.
- [x] Replace `JSONSnapshotStore`, `ProviderConfigurationStore`, and
  `RefreshSettingsStore` behind focused store protocols so `AppModel` keeps its
  existing account and refresh behavior.
- [x] Replace Claude Code's generic `local-snapshot` path with an
  Bairometer-managed `statusLine` database source. The helper must validate
  and write only the normalized snapshot in a short transaction, even when the
  app is not running.
- [x] Remove the user-editable local snapshot path from Settings after the
  managed source is available. Existing custom paths must not be silently
  followed forever: import the last valid value once, retain a clear migration
  warning, and guide the user to configure the bundled helper.
- [x] On first launch, import valid legacy `providers.json`, `snapshots.json`,
  refresh settings, and the managed Claude `statusline.json` into one atomic
  database migration. Preserve the original files as backups and make the
  migration idempotent. If legacy accounts collide after name normalization,
  retain every account by assigning deterministic display-name suffixes such as
  ` (2)` and record an actionable migration warning.
- [x] Keep malformed, unsupported, or partially importable legacy data from
  replacing valid database rows; surface actionable diagnostics instead.
- [x] Keep credentials, cookies, WebKit browser data, raw provider responses,
  and opaque account/authentication fields out of the database.
- [x] Add tests for schema creation/upgrades, concurrent app/helper writes,
  legacy import, idempotency, rollback on failed migration, custom-path
  migration warnings, display-name uniqueness, deterministic legacy-name
  conflict resolution, and preservation of the last valid snapshot.
- [x] Document the database location, backup/recovery behavior, migration
  result, and the new Claude Code setup flow.

Acceptance:

- A fresh install runs entirely from the GRDB-managed SQLite database and
  requires no user-provided snapshot path.
- Updating Claude Code through the bundled `statusLine` helper remains safe
  while Bairometer is closed or reading the same database.
- Existing supported JSON-based installations retain their accounts, refresh
  settings, and latest valid snapshots after one restart; their legacy files
  remain available as backups.
- A failed or malformed legacy import leaves the database usable and never
  destroys a prior valid state.
- The database contains normalized product data only, never credentials or raw
  provider/session material.
- All saved accounts have globally unique display names after migration; a
  legacy naming collision does not discard an account or silently overwrite it.

## Milestone 17: Terminal Dashboard And Details Redesign

Goal: replace the Liquid Glass dashboard cards and account-details presentation
with the approved terminal-fieldset status dashboard, without changing provider,
refresh, or persistence behavior.

Design contract: [`docs/dashboard-design.md`](dashboard-design.md).

- [x] Replace dashboard glass cards with fieldset-style account panels whose
  border is interrupted by the account name.
- [x] Truncate a long account legend with a tail ellipsis without displacing
  Refresh or Info controls, and expose the complete name in a tooltip and its
  accessibility label.
- [x] Render one `NN% used` value, one compact outlined usage meter, and a relative reset label
  per known limit window; do not show normal-state update timestamps or a
  duplicate remaining percentage.
- [x] Move Refresh All to a glyph control in the menu-panel header and show its
  in-progress/disabled state.
- [x] Add glyph-only individual Refresh and explicit Info controls to every
  account panel, using the existing per-account refresh and details paths.
- [x] Keep stale, failed, manual-only, unavailable, and no-data states visible
  inline without inventing usage values or permanently occupying normal cards.
- [x] Redesign `AccountDetailsView` as the matching technical inspector with
  precise timestamps, source, confidence, resets, diagnostics, and secondary
  actions.
- [x] Remove dashboard and account-details Liquid Glass treatments, including
  glass buttons and glass/card hover behavior, while preserving accessible
  system control semantics.
- [x] Apply the approved Codex `/status` and lazygit visual grammar: adaptive
  terminal palette, monospaced hierarchy, thin outlined custom usage meters,
  flat actions, and one label/value details inspector with a nested diagnostics
  note.
- [x] Add or update focused tests for refresh action availability and preserve
  existing refresh/account ordering behavior.
- [x] Add persisted device-local Compact (320 pt), Standard (460 pt), and Tall
  (640 pt) dashboard-height presets; retain a scrolling viewport for overflow.
- [x] Manually verify normal, refreshing, stale, failed, manual-only, and
  no-data examples in Light and Dark appearance.

Acceptance:

- The main menu panel is readable as an all-account usage dashboard without
  opening details.
- Normal cards show only account identity, usage, reset information, and
  necessary exception states.
- Refresh All, individual Refresh, and Info are discoverable and do not overlap
  or lose keyboard/accessibility support.
- The details popover holds timestamps and diagnostics without duplicating the
  dashboard or individual Refresh action.
- The selected dashboard-height preset persists between launches, changes the
  scroll viewport immediately, and leaves short account lists naturally sized.
- No provider, refresh, snapshot, or persistence contract changes are required
  solely for the visual redesign.

## Milestone 18: Settings Window Lifecycle And Terminal-Adjacent Redesign

Goal: replace the system-managed Settings presentation with a predictable
singleton SwiftUI window, then align the Settings workspace with the approved
terminal-fieldset product language and one consistent interactive control layer.

Design contract: [`docs/settings-design.md`](settings-design.md).

- [x] Replace the SwiftUI `Settings` scene and `SettingsLink` entry point with a
  singleton `Window("Bairometer Settings", id: "settings")` scene opened through
  `openWindow(id:)`.
- [x] Add one narrow application-activation boundary that calls the current
  `NSApplication.activate()` API in direct response to the Settings action before
  opening the SwiftUI window. Do not restore an AppKit-owned `NSWindowController`
  or use deprecated focus-stealing APIs.
- [x] Keep the staged app `LSUIElement` and menu-bar-only. Opening Settings must
  make the app active and the Settings window key without adding a Dock icon,
  changing the normal activation policy, or making the window float above other
  apps.
- [x] Disable the native minimize, resize, and full-screen controls while
  preserving close. A menu-bar utility Settings window is closed to dismiss it
  rather than minimized to the Dock or expanded into a primary app window.
- [x] Make the Settings scene singleton: reopening an existing window brings it
  forward instead of creating a duplicate or repositioning it. A closed or
  hidden window is centered again on the display hosting the new Settings action.
- [x] Define a deterministic default size and center new Settings windows on the
  display that hosts the menu-bar panel when the Settings action is invoked,
  using the pointer display and then the active/default visible display only as
  fallbacks. After creation, use the real window frame to center it in that
  display's visible bounds.
  Respect the user's move and resize choices while that window remains open,
  including multi-display setups.
- [x] Disable unwanted restoration for the Settings scene so a closed window does
  not reappear during launch or Spaces changes. Closing and reopening must reset
  transient editor, pending-navigation, alert, and section-selection state.
- [x] Preserve the current Accounts, Refresh, and Provider Setup information
  architecture for this milestone. Leave the planned General-section
  reorganization to Milestone 23 so lifecycle and visual work do not absorb
  localization or preference-model changes.
- [x] Restyle Settings as terminal-adjacent rather than as a literal terminal:
  reuse compact spacing, thin fieldset borders, restrained semantic status color,
  and a monospaced text hierarchy. Terminal selectors, sidebar selection,
  toggles, and actions share visible hover/pressed feedback; native editing,
  dialogs, menus, and focus behavior remain intact.
- [x] Remove opaque sidebar/list backgrounds and decorative glass treatments that
  fight the new composition. Keep system-adaptive Light and Dark appearances and
  do not introduce the custom theme-token model planned for Milestone 26.
- [x] Hide the non-actionable Credentials placeholder from Provider Setup until a
  verified provider integration needs an actual credential workflow.
- [x] Replace the account create/edit `Form` column layout with top-aligned
  `ACCOUNT` and `SOURCE` terminal fieldsets while preserving text editing, file
  import, validation, Save/Cancel, Return, and Escape.
- [x] Replace the account editor's system Provider popup and text-field focus
  ring with a keyboard-accessible terminal provider selector, a terminal focus
  border, and a square-cornered, scrollable provider overlay without a decorative
  title. Space/Return opens the selector, arrows move its list focus, Tab enters
  and traverses its items, and Escape closes it. Hide a provider that cannot
  accept another account, and hide the redundant source fieldset for providers
  with no configurable source.
- [x] Remove `Manual` as a real-provider Create/Edit source. New and saved real
  accounts use the provider's single current source; `Manual` remains only for
  the built-in Mock provider.
- [x] Preserve add, edit, delete, enable/disable, reorder, refresh, connection,
  usage-page, configured-source, helper-install, Save/Cancel, and dirty-draft
  workflows without changing refresh, persistence, or snapshot contracts.
- [x] Manually verify opening from behind another app, repeated open, close/reopen,
  active selection accent, keyboard focus, dirty drafts, Light/Dark appearance,
  multiple Spaces, and multiple displays in the staged `.app` bundle.

Acceptance:

- Every explicit Settings action opens one active, key Settings window in a
  predictable location; an already open window comes forward without duplication.
- Closing Settings prevents spontaneous reappearance and reopening starts from a
  clean Accounts state without stale editor or confirmation UI.
- Active selectors, selection, toggles, and actions use the terminal palette with
  visible hover/pressed feedback; the implementation does not use system-blue
  selection or a mixed control style.
- Every selector segment has a compact fixed height and responds across its full
  bordered cell, not only over its label.
- Account creation and editing remain top-aligned and readable at the normal
  Settings window size; labels, source selectors, and validation do not clip or
  overlap one another.
- Provider choices, text-field focus, and action hover feedback use the terminal
  palette without system-blue popup or focus styling.
- Settings is recognizably related to the terminal-fieldset dashboard while still
  behaving like a native macOS configuration workspace in Light and Dark modes.
- The redesign changes windowing and presentation only; existing account and
  provider workflows and their storage contracts remain intact.

## Milestone 19: Claude Code `/usage` CLI Data Source

Goal: add an explicit opt-in experimental Claude Code source that actively
reads current subscription plan limits through the local non-interactive CLI,
including model-specific weekly limits such as Fable, without driving a PTY,
running a model turn, or replacing the existing managed `statusLine` source.

- [x] Add a `claude-usage-cli` provider source mode for Claude Code. Keep
  `manual` and `claude-status-line` available, preserve the current default,
  and label `/usage` CLI as informational `Experimental` rather than a warning
  after a successful read.
- [x] Allow only one saved Claude Code account to use `/usage` CLI at a time,
  because the launched process reads the identity currently authenticated in
  that CLI environment. Keep managed `statusLine` available for explicitly
  configured multi-account snapshots.
- [x] Add automatic Claude executable discovery plus an optional saved
  executable override. Reuse a provider-neutral executable-path model instead
  of placing Claude paths in the existing Codex-specific field; migrate the
  current Codex value without changing Codex behavior.
- [x] Add a bounded, cancellable process client that launches the selected
  executable with `--safe-mode`, `-p "/usage"`, `--output-format json`,
  `--tools ""`, and `--no-session-persistence`, while forcing UTC and an English
  POSIX-compatible locale. Apply a short timeout and stdout size limit,
  terminate the child on cancellation, and do not expose stderr or raw command
  output through logs or diagnostics.
- [x] Decode the CLI JSON result envelope before parsing usage text. Accept
  only a successful built-in command response with zero model turns, zero
  model-token usage, and zero reported model cost; reject unsupported versions,
  authentication failures, inference activity, malformed envelopes, and
  oversized responses.
- [x] Parse only recognized plan-limit lines from the in-memory `result` text:
  `Current session`, `Current week (all models)`, and generic
  `Current week (<model>)` entries. Ignore session-cost details, activity
  attribution, skills, subagents, MCP servers, request counts, and every other
  local-history breakdown.
- [x] Normalize the recognized values into stable `UsageLimitWindow` entries:
  `session`, `weekly-all`, and provider-derived model IDs such as
  `weekly-fable`. Preserve provider display labels while keeping stored IDs
  locale-independent and collision-safe.
- [x] Parse UTC weekly reset timestamps with and without minutes and across year
  boundaries. Preserve the verified `Current session` value with no fabricated
  reset when Claude Code omits it. Reject percentages outside `0...100`,
  unparseable supplied reset values, duplicate required windows, and responses
  with no usable plan limits.
- [x] Produce a normalized live snapshot with the experimental Claude Code
  `/usage` source label. A successful read remains `OK` unless normal usage
  thresholds require another status; parser compatibility is represented by
  the source-mode label and diagnostics, not by forcing every valid snapshot
  into Warning.
- [x] Preserve the last valid snapshot when the executable is missing, the CLI
  is unauthenticated, `/usage` is unavailable, the text format changes, reset
  parsing fails, the process times out, or cancellation occurs. Surface a
  sanitized actionable recovery message and keep Manual and managed
  `statusLine` as selectable fallbacks.
- [x] Add compact Settings support for the new source: optional Claude
  executable path, automatic-location help, Browse, source conflict feedback,
  and connection testing. Do not show the statusLine helper installer when
  `/usage` CLI is selected.
- [x] Add fixture-based parser and process-client tests for the verified Claude
  Code `2.1.207` result, no-minute reset times, year rollover, generic
  model-specific windows, absent Fable, API-key/session-only output, malformed
  JSON, non-zero inference metadata, unsupported CLI output, timeout,
  cancellation, response limits, executable discovery, account conflicts, and
  last-valid-snapshot preservation.
- [x] Document setup, the authenticated-CLI identity boundary, the distinction
  between account-wide plan bars and machine-local activity attribution, the
  experimental text-compatibility boundary, privacy rules, diagnostics, and
  fallback behavior in `docs/plan.md`, the provider docs, and README.
- [x] Manually verify the staged app against an authenticated Claude Code CLI:
  confirm session, all-model weekly, and Fable weekly windows; confirm reset
  times where supplied, the verified session-without-reset behavior, refresh
  scheduling, connection testing, relaunch persistence, format failure recovery,
  zero model turns/cost/tokens, and no raw payloads in SQLite or logs.

Acceptance:

- An explicitly opted-in Claude Code account can refresh current session,
  all-model weekly, and available model-specific weekly plan limits through the
  authenticated local CLI without opening an interactive terminal.
- A successful refresh performs no model turn, exposes no tools, creates no
  persisted Claude session, and stores only the normalized `UsageSnapshot` in
  Bairometer's database.
- Machine-local activity attribution from `/usage` is never presented as an
  account-wide quota value or retained in storage or diagnostics.
- A Claude CLI or text-format change fails closed, preserves the last valid
  snapshot, and leaves Manual and managed `statusLine` immediately available.
- The experimental source is `OK` after a valid read, while its compatibility
  boundary remains visible without turning the informational Experimental label
  into a false health warning.
- Only one `/usage` CLI account can claim the active local CLI identity; other
  Claude accounts remain configurable through Manual or managed `statusLine`.

## Milestone 20: GitHub Release Distribution

Goal: let people download and run a tested Bairometer `.app` from GitHub
Releases without building from source, while keeping the initial ad-hoc-signed,
non-notarized distribution path honest about macOS Gatekeeper warnings.

Implementation status (2026-07-15): the original Apple Silicon packaging,
archive round-trip validation, staged-app smoke verification, the manual GitHub
Actions run, the first published release, and outside-build artifact
verification are complete. The current follow-up lowers the deployment target
to macOS 15 and extends release packaging with separate Apple Silicon and Intel
archives.

- [x] Add one reproducible release-packaging script that builds the SwiftPM
  products, stages the complete `AILimitBar.app` bundle (including the bundled
  Claude Code helper, selected AppIcon asset, and localized resources), signs
  the bundle ad-hoc, and creates an architecture-specific
  `AILimitBar-<version>-<arch>.zip` with `ditto --keepParent`.
- [x] Give the staged bundle explicit `CFBundleShortVersionString` and
  `CFBundleVersion` values without changing the existing local build-and-run
  workflow. The former is the release's `MAJOR.MINOR.PATCH` version; the latter
  is `YYYYMMDD.<commit-count>`, derived from the UTC creation date of an
  annotated release tag and its target commit.
- [x] Add a GitHub Actions release workflow with a manual package-validation
  path and a version-tag publication path. Use the `macos-26` runner, run
  `swift test`, build `arm64` and `x86_64`, create both architecture-specific
  release ZIPs, and verify each app bundle before publication.
- [x] Configure only the publication job with the required `contents: write`
  permission to create a GitHub Release and upload both ZIPs. Keep the workflow
  free of Apple-signing credentials, tokens, and other secrets in this first
  distribution milestone.
- [x] Publish both archives as `AILimitBar-<version>-arm64.zip` and
  `AILimitBar-<version>-x86_64.zip` on the matching GitHub Release, with
  generated or maintained release notes that state the version and macOS 15+
  requirement plus the architecture mapping.
- [x] Document the tag-to-release procedure and installation path: download the
  ZIP, unpack it, move `AILimitBar.app` to Applications, and use the standard
  macOS Gatekeeper recovery action on first launch when required.
- [x] State plainly in release documentation that ad-hoc signing is not
  Developer ID signing or Apple notarization; do not describe this first path
  as trusted, notarized, or warning-free.
- [x] Add the promised MIT license before the first tagged release.
- [x] Verify one published release artifact by downloading it outside the build
  directory, inspecting the archive contents and bundle version, checking the
  ad-hoc code signature, and manually launching the original macOS 26 build.

Acceptance:

- Pushing one version tag creates a GitHub Release with exactly two custom
  application archives, `AILimitBar-<version>-arm64.zip` and
  `AILimitBar-<version>-x86_64.zip`; no source build is needed by the downloader.
- The archive expands directly to `AILimitBar.app`, whose main executable,
  bundled helper, resources, and version metadata are present and valid.
- The workflow fails before publication when tests, staging, archive creation,
  or code-sign verification fails.
- The documented first-run Gatekeeper behavior and the absence of notarization
  are clear to a downloader.

## Milestone 21: Provider And Account Readiness

Goal: prepare the app for more providers, multi-account identity mappings, and
clear account/source readiness diagnostics.

- [x] Add provider/account source diagnostics model.
- [x] Track last successful refresh separately from failed refresh attempts.
- [x] Improve error copy for missing connections, unsupported source modes, and
  unavailable provider APIs.
- [x] Add provider capability metadata for manual, local snapshot, live, and
  delayed modes.

Implementation status (2026-07-15): the diagnostics and provider-capability
foundation is complete. Authenticated provider research is tracked as separate
private Linear work and is intentionally absent from this completed-history
document.

Acceptance:

- The app can explain why each account is or is not refreshable.
- Provider adapters can advertise supported source modes.
- Diagnostics retain only sanitized, non-secret information.

## Milestone 22.1: Menu Bar Status Indicator

Goal: make warning and error state recognizable at the real menu-bar icon size
without adding visible text or encoding state in tiny gauge-needle variants.

- [x] Keep one neutral image-only base icon for the `NSStatusItem`. Do not
  add a visible title, percentage, account name, or other status text to the
  menu bar.
- [x] Overlay one small circular badge in the icon's upper-right corner: red
  when any enabled account has a refresh failure or error snapshot, yellow when
  there is no error and at least one enabled account has a warning snapshot,
  and no badge otherwise. Red takes precedence over yellow.
- [x] Ignore disabled accounts when resolving the badge. Refreshing, stale,
  unavailable, no-data, and ordinary Mock state do not create a badge unless
  the account also has an explicit warning or error.
- [x] Keep explicit accessibility label and value text for the image-only status
  item so badge color is not the sole representation of warning or error state.
- [x] Add focused tests for normal, warning, error, mixed-state priority, and
  disabled-account cases.
- [x] Manually verify the staged app at the real menu-bar size in Light and Dark
  appearance, including inactive menu-bar presentation.

Implementation status (2026-07-14): the `NSStatusItem` uses one composite,
non-template image with a neutral gauge base and a state badge. Enabled-account
state aggregation, accessibility text, and focused AppModel/renderer tests are
complete. Staged-app visual verification passed manual QA on 2026-07-15.

Acceptance:

- The neutral base icon remains recognizable and does not change its gauge
  needle to communicate state.
- A warning produces one clearly visible yellow badge, an error produces one
  clearly visible red badge, and red wins when both states exist.
- Normal state has no badge, and the menu-bar panel itself is unchanged.
- VoiceOver exposes the same state without depending on badge color.

## Milestone 22.2: Daily-Use Smoke Verification

Goal: provide one repeatable verification command for app launch, refresh, and
the persistence paths needed for normal daily use.

- [x] Add one deterministic app-layer integration smoke test that uses a fake
  provider and disposable storage to create an account, change the refresh
  schedule, perform a refresh, persist a normalized snapshot, recreate
  `AppModel`, and verify that the account, settings, and snapshot reload.
- [x] Keep `./script/build_and_run.sh --verify` as the public smoke entrypoint.
  It runs the deterministic integration check, stages the normal debug `.app`
  bundle, launches it through Launch Services, waits for the `AILimitBar`
  process, and fails when the process cannot start or exits immediately.
- [x] Give the automated smoke path disposable storage. It must not read or
  write the user's normal Application Support database, Keychain, WebKit data,
  provider CLIs, or network sources.
- [x] Terminate only the smoke-launched process after verification and leave the
  staged bundle available for manual QA. Keep interactive menu-bar, Settings,
  focus, and pointer checks documented as manual verification rather than
  claiming that process launch proves them.

Implementation status (2026-07-15): the app-layer test uses a fixed fake
provider snapshot and disposable GRDB storage. `--verify` runs that test before
staging, launches the staged bundle through Launch Services with a disposable
storage-directory argument, verifies a new process remains alive, and cleans up
only that process and its temporary storage. Full automated verification passed;
interactive menu-bar, Settings, focus, and pointer checks remain manual.

Acceptance:

- One documented command verifies deterministic refresh, account and refresh
  settings persistence,
  snapshot persistence, bundle staging, and foreground app launch.
- The command is repeatable and leaves no account, snapshot, refresh status,
  process, or persistence residue in the user's real app data.
- A successful process launch is reported separately from manual UI verification.

## Milestone 22.3: Ollama-Owned Web Appearance

Goal: make Ollama-owned settings and sign-in pages follow the effective macOS
appearance without changing authentication, navigation, or usage extraction.

- [x] Add a separate visual-only `WKUserScript` for the isolated Ollama WebKit
  session. It may change only colors, backgrounds, borders, text contrast, and
  the page `color-scheme`; it must not alter layout, visibility, controls,
  focus, submission, navigation, or page content.
- [x] Apply the visual stylesheet only when the exact HTTPS host is
  `ollama.com` or `signin.ollama.com`. WorkOS, Google, GitHub, and every other
  third-party OAuth page remain provider-controlled.
- [x] Keep the visual script independent from the existing usage-extraction
  script and normalized bridge payload. Appearance changes must not trigger,
  suppress, or rewrite usage extraction.
- [x] Apply the current effective Light or Dark appearance when an Ollama-owned
  page loads and when the effective appearance changes while the page remains
  open.
- [x] Add focused tests for host allowlisting and visual/extraction separation.
- [x] Manually verify settings, Ollama sign-in, third-party OAuth redirects,
  keyboard focus, form controls, navigation, and usage parsing in Light and
  Dark appearance.

Implementation status (2026-07-15): a main-frame, document-start visual script
uses an isolated WebKit client content world and an exact-origin guard for
`https://ollama.com` and `https://signin.ollama.com`. Its adaptive Radix color
tokens follow `prefers-color-scheme`; the separate settings-only usage bridge is
unchanged. `swift build`, `swift test`, and `./script/build_and_run.sh --verify`
passed. Authenticated interactive visual verification passed on 2026-07-15.

Acceptance:

- Ollama-owned settings and sign-in pages remain readable in the active Light
  or Dark appearance.
- No visual stylesheet reaches WorkOS, Google, GitHub, or another third-party
  page.
- Sign-in, navigation, keyboard focus, form submission, and normalized usage
  parsing behave exactly as before the visual adaptation.

## Milestone 22.4: About Bairometer

Goal: provide a compact, discoverable source of app identity, build metadata,
and project-support links without expanding Settings or touching provider data.

- [x] Add an `About` text action beside `Settings` in the menu-bar panel footer.
  Keep the existing compact terminal text-action style, `Quit` alignment, and an
  explicit `About Bairometer` help/accessibility label.
- [x] Present one fixed-size, non-restoring `About Bairometer` utility window.
  It activates the `LSUIElement` app, reuses and foregrounds an open window,
  centers a newly reopened window on the display that received the menu-bar
  action, and leaves only the native Close control available.
- [x] Show the bundled app icon, app name, and `Version <version> (build
  <build>)` from `CFBundleShortVersionString` / `CFBundleVersion`. If either
  release value is absent, show `Development build` rather than an empty or
  misleading version.
- [x] Add static, accessible external links to the GitHub project and the
  existing Boosty support page. Keep the README Boosty badge unchanged.
- [x] Keep About independent of `AppModel`, provider state, SQLite, Keychain,
  diagnostics, and persisted preferences.
- [x] Add unit coverage for release/development build text and both link URLs.
- [x] Manually verify the staged app: footer layout, accessibility, first open,
  repeated open, close/reopen, version fallback, and both external links.

Implementation status (2026-07-15): `swift build`, 133-test `swift test`, the
staged-app `--verify` smoke check, local release-package metadata validation,
and manual About UI verification passed.

Acceptance:

- A user can open About directly from the menu-bar panel without opening
  Settings, and repeated activation never produces duplicate About windows.
- The window reliably identifies a release build or the local development
  fallback, contains no account or provider information, and does not return at
  app launch after it is closed.
- GitHub and Boosty open through the system link handler; no support or release
  URL is persisted with user data.

## Milestone 22.5: Feedback And Contact Channels

Goal: make direct feedback and bug reporting discoverable from the About window
without adding user data, in-app messaging, or a provider-facing support flow.

- [x] Add static accessible links for GitHub issue reporting, direct e-mail, and
  Telegram beside the existing repository and Boosty links.
- [x] Keep all contact destinations public and app-owned; opening a link uses
  the system handler and never stores a message, recipient, or contact state.
- [x] Increase the fixed About window only enough to keep every feedback and
  support action visible without scrolling.
- [x] Document the three feedback paths in README and add URL regression tests.
- [x] Manually verify all feedback/support links from a staged app and confirm
  the About layout remains readable in Light and Dark appearance.

Implementation status (2026-07-15): `swift build`, 133-test `swift test`, the
staged-app `--verify` smoke check, and manual feedback/support UI verification
passed.

Acceptance:

- A person can report an issue, compose an e-mail, or start a Telegram message
  directly from About, with no account or app-state dependency.
- The feedback links remain readable and reachable without scrolling or clipping
  in both system appearances.

## Milestone 23: English/Russian Localization And v0.3 Release

Goal: verify and publish the localized v0.3 app through the existing ad-hoc
GitHub Release flow without implying trusted or notarized distribution.

- [x] Run `swift build` and the full `swift test` suite.
- [x] Verify the deterministic staged-app smoke path and localization regression
  coverage.
- [x] Build and validate architecture-specific `arm64` and `x86_64` archives,
  including bundle metadata, resources, ad-hoc signatures, and ZIP round trips.
- [x] Update public documentation to describe shipped English/Russian
  localization, General Settings, and locale-aware formatting.
- [x] Publish public-safe GitHub Release notes with the ad-hoc signing and
  non-notarization disclaimer.

Implementation status (2026-07-20): `swift build` passed; `swift test` passed
with 154 tests and no failures; `./script/build_and_run.sh --verify` passed;
and both release archives passed local packaging validation. The app remains a
menu-bar-only `LSUIElement`; interactive visual verification of every menu-bar
surface requires a macOS GUI session and is not inferred from process or test
checks.

## Milestone 23.1: Regular-Window UI Verification Host

Goal: make app-owned dashboard and Settings UI directly inspectable without
changing the production menu-bar bundle or using real provider integrations.

- [x] Add a debug-only runtime and regular-window host that reuse the production
  executable, `MenuBarPanelView`, `SettingsView`, localization, and dashboard
  keyboard responder.
- [x] Add deterministic empty, healthy, mixed-state, Settings, and dirty-editor
  scenarios backed only by scripted synthetic adapters and isolated GRDB and
  `UserDefaults` state.
- [x] Stage `AILimitBarUITestHost.app` with a distinct bundle ID,
  `AILimitBarTest` process, `LSUIElement=false`, copied resources, and an ad-hoc
  signature. Preserve production bundle metadata and release staging.
- [x] Add typed launch configuration, stable language-independent AX
  identifiers, a public launcher command, lifecycle cleanup, unit coverage, and
  the command/coverage contract in `docs/ui-test-host.md`.
- [x] Verify the host through Computer Use without extending its claims to the
  production status item, popover anchoring, `LSUIElement` behavior, WebKit, or
  real providers.

Implementation verification (2026-07-21): `swift build` passed and the full
167-test `swift test` suite passed with no failures. The existing
`./script/build_and_run.sh --verify` app-layer and Launch Services smoke path
passed. Host and production bundle metadata, resources, signatures, distinct
process names, concurrent launch, host-only termination, normal launcher wait,
and temporary-state cleanup were checked directly.

Computer Use obtained complete AX trees and screenshots from the host bundle ID.
It verified `dashboard-empty` in EN/Light; `dashboard-healthy` in EN/Dark,
including meter value toggle, `Tab`/`Return`/`Escape`, and dashboard-to-Settings
switching; and `dashboard-mixed` in RU/Light/Compact, including healthy, warning,
stale, failed, manual, no-data, long-name, Info popover, and scrolling states.
It verified `settings` in EN/Light/Tall across Accounts, General, Providers, and
a limit-display preference change. It verified `settings-dirty-editor` in
RU/Dark by changing the account name, attempting section navigation, reading the
discard alert and its stable action identifiers, and discarding the edit. Direct
bundle launch also resolved to the documented EN/Dark/Standard healthy defaults.

Acceptance:

- App-owned dashboard and Settings behavior can be exercised through a regular
  AX-inspectable window with deterministic, privacy-safe state.
- The production `AILimitBar.app`, status item lifecycle, provider clients, and
  release workflow remain unchanged.
- Host data and preferences are unique per launch and removed after normal exit;
  the launcher removes its exact temporary directory as a fallback.

## Future Directions And Execution Boundary

Detailed unfinished scope is maintained privately in Linear. Public high-level
directions include localization, additional provider research, per-limit
thresholds, usage notifications, dashboard appearance, trusted direct
distribution, automatic updates, and a passive WidgetKit extension.

Work that requires Developer ID signing, notarization, App Group registration,
or production WidgetKit distribution is gated by an active Apple Developer
Program membership. The current ad-hoc GitHub Release flow remains usable but
must not be described as trusted or notarized distribution.

Linear is the active private execution tracker. GitHub remains the public code
and release surface: pull requests, tags, releases, and explicitly public
feedback. Derive release notes from completed Linear issues and merged pull
requests when preparing a release; do not use Linear as a second changelog.

## MVP Verification

- [x] `swift build`
- [x] `swift test`
- [x] `./script/build_and_run.sh --verify`
