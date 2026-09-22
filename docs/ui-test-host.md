# Regular-Window UI Test Host

## Purpose

The debug-only UI test host exposes app-owned SwiftUI surfaces through a regular
macOS window that accessibility tooling can inspect. It reuses the production
`Bairometer` executable, `MenuBarPanelView`, `SettingsView`, dashboard keyboard
responder, localization, and resources. It does not alter the production
`LSUIElement` bundle or release workflow.

The host is a presentation test boundary, not a provider-integration emulator.
It creates only scripted synthetic adapters, normalized fixtures, and isolated
local state. It never creates a status item, WebKit controller, real provider
client, executable override, credential, or personal account value.

## Command Contract

Stage and run a scenario through Launch Services:

```zsh
BAIROMETER_DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  ./script/build_and_run.sh --ui-test-host dashboard-healthy \
  --ui-test-language en \
  --ui-test-appearance dark \
  --ui-test-height standard
```

Like every locally staged DEBUG bundle, the host requires an explicit
caller-owned Apple Development Team ID through
`BAIROMETER_DEVELOPMENT_TEAM`; the repository does not store a default.

Supported values:

| Argument | Values | Default |
| --- | --- | --- |
| `--ui-test-host` | `dashboard-empty`, `dashboard-healthy`, `dashboard-mixed`, `dashboard-openrouter`, `dashboard-minimax`, `settings`, `settings-dirty-editor`, `settings-openrouter`, `settings-openrouter-missing-management` | `dashboard-healthy` when the host bundle is opened directly |
| `--ui-test-language` | `en`, `ru` | `en` |
| `--ui-test-appearance` | `light`, `dark` | `dark` |
| `--ui-test-height` | `compact`, `standard`, `tall` | `standard` |

The launcher validates its public arguments. The app also uses a typed parser:
missing or invalid UI-test values fail launch explicitly, while unrelated
system-injected arguments are ignored.

`script/stage_ui_test_host_bundle.sh` stages the debug production app, copies it
to `dist/BairometerUITestHost.app`, changes only the copied bundle metadata, and
ad-hoc signs and validates the result. The host identity is:

- bundle ID: `io.github.Prontsevich.Bairometer.UITestHost`;
- display name: `Bairometer UI Test Host`;
- executable and process: `BairometerTest`;
- `LSUIElement=false`.

The launcher terminates only a previous `BairometerTest` process. A production
`Bairometer` process may remain running alongside it.

## Scenarios

- `dashboard-empty` renders the production empty dashboard state.
- `dashboard-healthy` renders two healthy synthetic accounts with deterministic
  usage windows and supports refresh, meter selection, keyboard navigation, and
  switching the same host window to Settings.
- `dashboard-mixed` covers healthy, warning, stale, failed, manual-only, and
  no-data accounts, a deliberately long synthetic name, details, and scrolling.
- `dashboard-openrouter` renders compact `$` USD account and key amounts with
  up to two localized fraction digits and trimmed trailing zeros
  and three ordinary-key rows. Its existing Info path retains detailed
  native `$` USD usage/BYOK observations, including deterministic zero daily usage
  and zero daily BYOK values that are hidden while collapsed and discoverable
  when expanded. It covers current, stale, unknown, unlimited, and
  authentication-error states. Its scripted Refresh response
  preserves the synthetic native fixture instead of reloading nonexistent
  credential metadata from the isolated database.
- `dashboard-minimax` renders one synthetic MiniMax account with two separate,
  neutral quota categories. Each has independent percentage-based Current and
  Weekly windows, a Used/Remaining meter where a reported percentage is
  present, and reset information. It contains no credential, raw response
  identifier, or callable-model mapping.
- `settings` opens the real Settings surface with healthy synthetic accounts.
- `settings-dirty-editor` opens Accounts with the first synthetic account in
  edit mode so an account-name edit can exercise the discard confirmation flow.
- `settings-openrouter` opens the real compact OpenRouter credential inventory
  with three synthetic ordinary rows and one separately labeled disabled
  management slot. Together with the active management slot in
  `dashboard-openrouter`, it covers default and exception presentation without
  credential values. The fixture contains opaque references only.
- `settings-openrouter-missing-management` opens the same inventory without a
  management slot, exposing the explicit localized empty state and Add
  Management action. It also supplies a synthetic account-level refresh failure
  with no slot diagnostic so the compact exception row is deterministic,
  without provider or Keychain access.

All fixture timestamps derive from one minute-rounded launch instant and remain
away from stale and reset thresholds. Scripted refreshes use one attempt and may
have an explicit deterministic delay. Scheduled refresh is disabled.

## Accessibility Workflow

Inspect the running app by bundle ID
`io.github.Prontsevich.Bairometer.UITestHost`. Stable language-independent
identifiers include:

- `ui-test-host.root.<scenario>`;
- `dashboard.refresh-all` and `dashboard.open-settings`;
- `details.openrouter.shared`,
  `details.openrouter.key.<context>.summary`,
  `details.openrouter.key.<context>.disclosure`, and
  `details.openrouter.key.<context>.expanded`;
- `dashboard.meter.<provider>.<account>.<window>`;
- `dashboard.openrouter.shared.<account>`;
- `dashboard.minimax.category.<account>.<category>` and
  `dashboard.minimax.window.<account>.<category>.<window>`;
- `details.minimax.category.<account>.<category>` and
  `details.minimax.window.<account>.<category>.<window>`;
- `openrouter.key.<context>` and
  `openrouter.metric.<context>:<source>:<metric>`;
- `settings.navigation.<section>`;
- `settings.general.language.<value>`;
- `settings.general.refresh.<value>`;
- `settings.general.limit-display.<value>`;
- `settings.general.height.<value>`;
- `settings.account-name`, `settings.discard`, and `settings.keep-editing`;
- `settings.openrouter.account-exception`, `settings.openrouter.add-key`,
  `settings.openrouter.add-management`,
  `settings.openrouter.management-missing`,
  `settings.openrouter.credential.<context>`,
  `settings.openrouter.actions.<context>`, `settings.openrouter.key-name`,
  `settings.openrouter.credential-value`, and
  `settings.openrouter.editor-save`.
- `settings.minimax.boundary`, `settings.minimax.subscription-key`,
  `settings.minimax.primary-action`, `settings.minimax.enabled-action`,
  `settings.minimax.remove-action`, `settings.minimax.credential-value`,
  `settings.minimax.editor-save`, and `settings.minimax.editor-error`.

Use the host AX tree and screenshots to verify app-owned layout, labels, values,
focus, keyboard paths, Settings navigation, preference controls, scrolling, and
Light/Dark plus English/Russian presentation. Record only interactions that were
actually performed.

## State Reset

Each launch receives a unique temporary GRDB directory and unique
`UserDefaults` suite. The suite is passed to `AppModel`,
`AppLanguagePreference`, and SwiftUI through `defaultAppStorage`. Normal app
termination removes both. The launcher removes its exact temporary directory as
a fallback after the host exits or is interrupted.

## Coverage Boundary

The host covers app-owned SwiftUI dashboard and Settings behavior, including
OpenRouter's normalized native hierarchy and credential-metadata states. It
does not claim coverage for the production `NSStatusItem`, `NSPopover` anchoring,
`LSUIElement` activation or Spaces behavior, OAuth/WebKit sessions, real provider
processes or network integrations, Keychain, release signing, or notarization.
Those paths retain their existing unit, integration, telemetry, staged-app, and
explicit manual verification requirements.

The host can verify the account-details overlay scroller, compact tables, and
their AX/layout projection. Swift lifecycle tests cover screen-rectangle
capture, stable per-presentation anchor ownership, transient-close cleanup, and
creation of a later anchor without claiming a physical display result. The host
still cannot verify that an arbitrary click on another physical display closes
the production status-item popover without migration. That remains a production
manual gate.

OpenRouter host verification on 2026-07-28 confirmed the static fixtures,
refresh-preservation path, typed parser, and stable identifier/value contracts
through `UITestHostTests`. The fourth correction pass repeated signed Launch
Services startup and exact-process cleanup for `dashboard-openrouter`,
`settings-openrouter`, and the non-OpenRouter `dashboard-healthy` English/Dark
variants; the earlier missing-management and Russian/Light launch coverage
remains valid. No Computer Use attempt was made in this pass. The earlier
post-fix attempt did not return an AX tree or screenshot, so it provides no
interactive or visual evidence. Visual/AX inspection of Info expansion and
scrolling, key overflow and editor actions, Settings alignment, and the
non-OpenRouter regression remains an explicit manual gate. Physical
multi-display status-item behavior remains a separate production-only manual
gate.

MiniMax signed-host verification on 2026-08-24 launched `dashboard-minimax`
in English/Dark and Russian/Light. Screenshots and the AX tree confirmed the
two neutral category rows, independent Current and Weekly values, reset text,
and the Used/Remaining meter toggle. The Account Details overlay opened and
closed, and MiniMax Settings showed the boundary disclosure plus an Add Key
sheet whose secure field exposed only a redacted AX value; no credential was
entered. Keyboard navigation remains an explicit manual follow-up: the desktop
automation's synthetic Tab input did not report a focused element. The host
does not verify real credentials, provider responses, or the production status
item/popover.
