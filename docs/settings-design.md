# Settings Window Design

## Status And Scope

This is the approved design and window-lifecycle contract for Milestone 18. It
covers the Settings scene, the Settings entry action, window activation and
placement, and the terminal-adjacent presentation of the existing Settings
workspace.

Implementation status (2026-07-13): the singleton scene, activation boundary,
placement, restoration policy, transient-state reset, visual redesign, and
manual Settings QA are complete. `swift build`, `swift test`, and staged-bundle
`--verify` passed.

Visual correction (2026-07-13): Settings uses one terminal interaction layer
for navigation, choices, selection, and actions. The earlier hybrid of native
blue segmented controls, grouped Form cards, and terminal fieldsets is not an
accepted presentation.

The current Settings information architecture is General, Accounts, and
Providers. General collects the shared, cross-account preferences; Accounts and
Providers keep their current responsibilities. This reorganization does not
change account editing, provider source behavior, usage thresholds,
notifications, theme editing, credentials, or persistence contracts.

General contains the device-local System Default, English, and Russian language
preference, the refresh schedule, and Dashboard height picker with `Compact`
(320 pt), `Standard` (460 pt), and `Tall` (640 pt) viewport presets. The
language preference updates the effective app locale immediately without changing
account, provider, or refresh data. The refresh and dashboard controls preserve
their existing stored values and behavior.

## Outcome

An explicit Settings action should always produce one active, key Settings
window in a predictable location. The window should feel related to the compact
terminal-fieldset dashboard while retaining native macOS editing, focus,
selection, accessibility, and Light/Dark behavior.

## Window Architecture

- Declare Settings as a singleton SwiftUI
  `Window("Bairometer Settings", id: "settings")` scene.
- Open it with `openWindow(id: "settings")`. Calling the action while the window
  is already open brings that window forward instead of creating another one.
- Immediately before opening, call the current `NSApplication.activate()` API
  from one narrow platform helper because the staged app is an `LSUIElement`.
- Keep all Settings content and transient state in SwiftUI. Do not create an
  AppKit-owned `NSWindow`, `NSPanel`, or `NSWindowController`.
- Do not change the app to a regular Dock application and do not keep Settings
  above other apps with a floating window level. The explicit opening action
  brings it forward; normal macOS activation rules apply afterward.
- Keep only the native close control active. Disable minimize, resize, and full
  screen: Settings is a menu-bar utility surface and should be closed, not sent
  to the Dock or expanded into a primary app window.

## Placement And Lifecycle

- Give a newly created Settings window a deterministic default size based on the
  current master-detail layout and center it in the visible area of the display
  that hosts the menu-bar panel. Capture that display before activating the
  `LSUIElement` process; only if no host window is available, use the pointer
  display and then the system default display as fallbacks. After SwiftUI creates
  the window, center its real `NSWindow.frame` in that display's visible area.
- Clamp placement and size to the display's visible bounds so the menu bar and
  Dock do not cover required content.
- Preserve the user's position and size while the same window remains open.
  Reopening an already visible window must not recenter it. A closed or hidden
  SwiftUI window is repositioned using the display that hosts the new Settings
  action.
- Disable unwanted scene restoration. A window that the user closes must not
  return during launch, app activation, or a Spaces change.
- Closing and reopening resets the selected section to Accounts and clears
  editor mode, dirty state, pending navigation, and open confirmations.
- Keep resize constraints large enough for the account list and detail pane but
  do not assume a single display size or arrangement.

## Visual Relationship To The Dashboard

Settings is terminal-adjacent, not a literal terminal and not a clone of the
dashboard cards.

- Reuse compact spacing, thin borders, restrained semantic status colors, and
  clear fieldset labels for product-specific read-only and editor groups.
- Use the monospaced typography hierarchy consistently for Settings navigation,
  account lists, headings, field labels, descriptions, actions, and technical
  values. Native system dialogs may retain their platform typography.
- Use terminal segmented selectors, sidebar selection, toggles, and action
  buttons throughout Settings. They share the same border, selection, hover,
  and pressed states; active controls use the terminal palette, never the system
  blue accent.
- Use a terminal provider selector with a scrollable list, full keyboard focus,
  and arrow-key navigation, plus terminal text-field focus borders in the
  account editor. Keep the file importer, `Menu`, alert, sheet, and keyboard
  behavior native where macOS platform integration is the user-facing benefit.
- Use system-adaptive foregrounds and backgrounds in Light and Dark appearance.
  Do not make the dark dashboard reference a fixed Settings color scheme.
- Remove opaque list/sidebar backgrounds and decorative Liquid Glass treatments
  that compete with the thin fieldset composition.
- Do not introduce configurable dashboard theme tokens in this milestone.
  Milestone 26 owns custom palettes and app appearance preferences.

## Layout

The segmented top-level navigation contains General, Accounts, and Provider
Setup. Accounts continues to use a local master-detail workspace and remains
the selected section when Settings opens or reopens.

```text
┌─ Bairometer Settings ──────────────────────────────────────┐
│        [ General ]  [ Accounts ]  [ Providers ]            │
├──────────────────┬─────────────────────────────────────────┤
│ ACCOUNTS         │ claude-main                    [Enabled]│
│                  │                                         │
│ > claude-main    │ ┌─ STATUS ────────────────────────────┐ │
│   ollama-work    │ │ Source       Managed statusLine     │ │
│   codex-main     │ │ Last update  08:14                  │ │
│                  │ │ State        Ready                  │ │
│                  │ └─────────────────────────────────────┘ │
│                  │                                         │
│                  │ ┌─ CONFIGURATION ─────────────────────┐ │
│                  │ │ Provider     Claude Code            │ │
│                  │ │ Snapshot     ~/.local/...           │ │
│                  │ └─────────────────────────────────────┘ │
│ [+] [−]      [↻] │             [Edit] [Test] [Open Usage] │
└──────────────────┴─────────────────────────────────────────┘
```

The read-only account detail uses bordered Status and Configuration groups.
Create and Edit use top-aligned `ACCOUNT` and `SOURCE` fieldsets instead of a
column `Form`, so custom source selectors cannot distort native form alignment.
Provider selection uses one compact terminal selector with a scrollable,
square-cornered terminal overlay with no decorative title. Space and Return open
the list; arrows move its focus, Tab enters the list and then moves through its
items, Space/Return select, and Escape closes it. The selector lists only
providers that can accept another account, so an already-configured
single-account Codex source is not selectable. Text fields have terminal focus
borders rather than system-blue rings. File importer, validation, Save, Cancel,
Return, and Escape behavior remain intact inside those groups.

Providers lists each provider's current source summary and an action to open its
limits page. It does not show a disabled Credentials placeholder; credential UI
appears only when a verified provider integration has an actionable requirement.

Accounts without a configurable source, such as the built-in Mock provider, do
not show a redundant source fieldset. Ollama Cloud and OpenAI Codex keep their
single current sources. Claude Code exposes a compact terminal selector for
Manual, managed `statusLine`, and experimental `/usage` CLI; source-specific
controls appear below it without changing the surrounding fieldset layout.

OpenRouter is a deliberate read-only-detail exception to the generic Status and
Configuration groups. Its provider identity appears once in the Accounts
sidebar; the detail header keeps only the saved account name. The healthy
default omits the repeated provider/source group and last-refresh row. A compact
account-level exception appears when the refresh fails before any key slot can
provide a diagnostic. One terminal `KEYS` inventory contains compact ordinary
API-key rows and the separately labeled optional shared-credits management key.
Healthy active state is implicit. Disabled, missing,
stale, unknown, unavailable, failed, recovery, and deletion-pending states
remain visible in text and accessibility values. An active management row hides
only a current shared-credit state; every non-current shared-credit state is
projected into that row.

Each key row exposes a keyboard-accessible native overflow menu for
rename where applicable, replace/recover, enable/disable, and secure removal.
The add-key and add-management-key actions remain directly visible. Their
32-point header slots and the overflow menu stay aligned as glyphs change.
These and all other Settings glyph controls remain borderless at idle. The key
overflow menu uses the same reusable full native-menu bridge, 32-point hit
target, hover, and pointer-press feedback as the provider-level overflow menu;
enabled state, destructive role, keyboard behavior, and accessibility remain
native. The KEYS header Add slot is inset from the fieldset's right border as a
whole control rather than offsetting only its glyph. Its own 32-point target
paints the fieldset surface behind the glyph so the border cannot pass through
it, without introducing a shared header plate or masking the adjacent border.
The management-section Add action is inside the fieldset body and does not gain
that idle mask;
ordinary text actions do not gain boxes. Persistent
Keychain, endpoint, and elevated-management prose is absent from the inventory
and appears in the add/replace secure editor instead. Key editors use
`SecureField`, clear submitted input on success or failure, support Return and
Escape, and never read an existing Keychain value back into the UI. Account
deletion explicitly warns that all associated OpenRouter credentials and native
capacity data are securely removed. User-facing English and Russian consistently
say Key/Keys and Ключ/Ключи; internal credential model and accessibility
identifiers remain unchanged. Sheets explicitly inherit the selected app locale
rather than the system locale. The ordinary-key action and sheet use the
user-facing title `Add key`; its editor fieldset is `KEY DETAILS`, and the copy
does not expose the internal ordinary-key role merely to explain `/api/v1/key`.
Account confirmations use `Remove account`, matching `Remove key`, because
these actions remove local configuration rather than remote OpenRouter objects.

## Interaction And Accessibility

- Opening Settings from behind another application activates Bairometer and
  makes the Settings window key.
- Terminal selection and segmented controls use the same active/inactive palette
  as the dashboard fieldsets, with visible hover and pressed feedback. Each
  segment's full bordered cell is its pointer target; the control keeps a compact,
  fixed intrinsic height instead of stretching into unused window space.
- Every compact icon and text action has a visible hover target and preserves its
  descriptive accessibility label and help text.
- OpenRouter key rows, overflow menus, add actions, secure editor fields,
  save actions, account-level exceptions, and the missing-management state
  retain stable language-independent accessibility identifiers.
- Add, delete, reorder, enable/disable, refresh, test connection, open usage,
  source selection, helper installation, Edit, Save, and Cancel remain reachable
  by their existing pointer and keyboard paths.
- Glyph-only actions retain descriptive accessibility labels and help text.
- Dirty drafts continue to use one discard confirmation when changing account or
  section. Closing and reopening must not resurrect the draft or dialog.
- Color supplements text and control state; it is never the only status signal.

## Non-Goals

- Changing provider, refresh, snapshot, or persistence contracts.
- Adding a Dock icon or converting Bairometer into a conventional main-window
  app.
- Using an always-on-top Settings panel.
- Recreating general text-editing controls, file panels, or dialogs. Terminal
  selectors and action buttons are intentional product-specific controls.
- Implementing a literal terminal, ASCII controls, or terminal escape colors.
- Changing refresh, dashboard-height, language-preference, provider, or account
  persistence contracts.
- Adding custom theme import, export, editing, or palette persistence.

## Validation

- Build and run the staged `LSUIElement` `.app` bundle.
- Open Settings while Finder and another regular application are active.
- Verify first open, repeated open, close/reopen, and no duplicate windows.
- Verify the initial position and resizing on the primary and a secondary display.
- Move between Spaces and confirm a closed Settings window does not reappear.
- Confirm active selection accent, keyboard focus, Return/Escape, and dirty-draft
  confirmation behavior.
- Verify General exposes language, refresh schedule, and Dashboard height; each
  selection survives close/reopen and app relaunch without changing provider or
  account values.
- Exercise every existing account and provider action in Light and Dark
  appearance.
- Exercise OpenRouter's active, disabled, and missing management states plus a
  top-level refresh failure in English and Russian at supported Settings
  widths. Confirm the provider name appears only in the sidebar, healthy state
  is implicit, exception text precedes credential actions in accessibility
  order, and long labels wrap instead of truncating.
