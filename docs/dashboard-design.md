# Menu Bar Dashboard Design

## Status And Scope

This is the approved design brief for the menu bar dashboard and the
account-details popover. It is the implementation contract for Milestone 17.

The scope is limited to `MenuBarPanelView`, dashboard account presentation, and
`AccountDetailsView`. It deliberately excludes Settings redesign, provider
adapters, refresh semantics, persistence, and the `UsageSnapshot` contract,
except for a device-local dashboard-height preference.

## Outcome

The menu bar panel is a fast, all-account status dashboard. A person should be
able to answer these questions without opening a detail view:

- Which account is this?
- How much of each known limit has been used?
- When does that limit reset?
- Is an account refreshing, stale, failed, manual-only, or unavailable?

Technical provenance and timestamps belong in the on-demand details popover.

## Visual System

The dashboard uses a compact terminal-fieldset composition rather than Liquid
Glass cards. The visual references are Codex CLI `/status` for the inspector
typography and outlined usage meter, and lazygit for the dense nested-panel
grid. They guide the visual grammar; the app does not imitate ANSI escape codes
or become a text-mode interface.

- Each account is enclosed by a thin muted-gold bordered panel with a small
  corner radius.
- The account name interrupts the upper border, like a `fieldset` legend. Its
  vertical placement is independent from the right-aligned controls, so a
  refresh spinner cannot move the legend or overlap the border.
- Legend and control masks cover only their intrinsic content, never a reserved
  maximum title width. Account panels leave enough vertical spacing for those
  masks without breaking a neighbouring panel's lower border.
- There are no glass effects, translucent surfaces, gradients, shadows, large
  corner radii, or card hover scaling on these two surfaces.
- Use an adaptive warm paper/charcoal surface, muted-gold structural borders,
  and restrained green, amber, and red semantic status colors. The dark
  screenshots are style references, not a fixed color-mode requirement.
- Use monospaced labels and values, tight vertical rhythm, aligned label/value
  rows, and one-pixel separators associated with a developer status tool.
- Usage windows are full-width, thin rectangular outlined buttons with a
  muted-gold meter fill that matches the structural border; do not use the
  default `ProgressView` track on these surfaces. Their label, value, meter, and
  reset text share one activation target that toggles the Used/Left display
  mode. Hover shows a restrained neutral fill, border, and pointing-hand cursor.
  Pointer activation does not retain focus; keyboard focus starts only with
  keyboard navigation, uses a terminal-colored outline instead of the
  system-blue focus ring, and Escape clears it. Green is reserved for
 warning/stale copy, and red for failure copy.
- Actions remain SwiftUI controls but use flat text or glyph presentation rather
  than prominent system pill buttons. They have a subtle neutral hover fill and
  a pressed state, without card scaling or a pill-shaped hover treatment.

This is an intentional product-specific composition. Standard SwiftUI controls
must still provide pointer, keyboard, focus, accessibility, disabled, and
pressed behavior for all interactive elements.

## Dashboard Layout

### Header

- The panel title is `Bairometer`.
- A glyph-only Refresh All control sits in the upper-right corner and invokes
  the existing global refresh path.
- While the global refresh runs, that control presents progress and cannot be
  invoked again.

### Account Panels

- Render enabled accounts in the user-defined order.
- Use the globally unique account display name as the fieldset legend. Do not
  repeat the provider name in the normal dashboard body.
- Account display names are globally unique. When a legend does not fit beside
  its controls, truncate it with a tail ellipsis and expose the complete name in
  a tooltip and accessibility label.
- Place a glyph-only individual Refresh control and an explicit Info control in
  the upper-right portion of each account border. Center both on the border,
  reserve a visible gap between their hit targets, and preserve the same
  dimensions while Refresh swaps its glyph for progress. Inset the group enough
  to leave the fieldset's top-right corner visible. Both controls use the same
  fixed border slot, borderless idle presentation, and clear hover/pressed
  feedback. Each 24-point target independently paints the fieldset surface
  behind itself so the top border does not pass through its glyph; there is no
  shared control-strip mask. The global Refresh All control follows the
  borderless idle rule but is not on a fieldset border and has no such mask.
- Leave a small top clearance before the first account so its legend cannot
  overlap the dashboard header. Cap the account-list viewport at a compact
  height and use a visible vertical scroll indicator for additional accounts.
  Settings offers `Compact` (320 pt), `Standard` (460 pt), and `Tall` (640 pt)
  viewport presets. The value is a local `UserDefaults` preference, not
  provider or account data. Each preset sets the visible viewport height and
  account lists scroll within it.
- Individual Refresh invokes the existing per-account refresh path. It shows
  progress and is disabled while that account or a global refresh is running.
- Info opens the account-details popover. It must have an accessible label and
  must remain available without relying on hover.

### Usage Windows

For each known limit window, render only:

1. The provider-defined window label, such as `5-hour` or `7-day`.
2. One right-aligned localized Used or Left value. The global display preference
   applies unless that account/window has an explicit override. It preserves a
   provider-supplied fractional percentage to one decimal place (for example,
   `35.4% used`, `64.6% left`, `Ушло 35,4 %`, or `Ещё 64,6 %`) and omits a
   trailing `.0` for whole percentages.
3. One compact rectangular outlined meter with the same displayed percentage.
4. A relative reset label when a reset date is available, such as
   `resets in 2 hours`.

Do not show a second percentage or a normal-state `Updated` timestamp
in an account panel. Use restrained accent colors for progress and reserve
warning/error colors for meaningful thresholds or exceptions. Color must not be
the only indication of state.

`usedPercent` remains canonical. Left is its clamped complement and does not
change severity, thresholds, notifications, analytics, or menu-bar state.

### State Visibility

- Normal or successfully refreshed accounts show no extra status copy.
- A refreshing account communicates progress through its individual Refresh
  control, not a permanent status row.
- Stale data has a compact visible `Stale` label at the start of the account
  body, before its limit windows.
- Failed refreshes have a compact warning indication in the same position; the
  detailed cause is in the Info popover.
- A diagnostic `Warning` is also shown in this position. A warning caused only
  by usage filling a known limit window does not add status text.
- Usage thresholds do not add a dashboard status label. A known limit window
  continues to show only its name, percentage, meter, and reset label; future
  thresholds will change the consumed portion's color only.
- Manual-only, unavailable, and no-data accounts state that condition in the
  account body instead of inventing a progress bar.
- A successful experimental source remains `OK`; its `Experimental` source
  label is informational. Amber warning state is reserved for real usage
  thresholds, stale data, or failed refreshes.

OpenRouter is the native-unit exception to percentage meters. Its default
account fieldset renders only the account-wide balance amount, such as
`$12.2`; lifetime credits, derived used credits, percentages, and progress
fills do not appear there. USD uses `$`; a future non-USD unit falls back to
its ISO code. Currency values use up to two localized fraction digits and trim
trailing zeros (`$1`, `$1.5`, `$1.25`).
Each ordinary key gets one compact row with its local name,
finite key capacity amount, and reset when applicable. A healthy key without
a configured key-level limit says `No key limit` without implying unlimited
account capacity. Normal timestamps, daily/weekly/monthly/lifetime usage, and
BYOK observations stay out of the default dashboard.

The existing Info control is the single disclosure path for all detailed
OpenRouter observations. Partial, stale, unavailable, unknown, disabled,
recovery-required, and credential-error states remain visible in default text
and accessibility values without hiding healthy sibling keys. Healthy native
values use the neutral primary color; semantic green is not a permanent
success-state decoration. OpenRouter dashboard and Info wording is consistently
`left`/`used` in English and `Осталось`/`Использовано` in Russian.

The dashboard should not scroll for common setups of three to five accounts.

## Account Details Popover

The Info control opens a compact technical inspector in the same terminal-
fieldset visual system. It is not a second dashboard and does not repeat the
usage bars. The popover uses one outer inspector fieldset with aligned
monospaced label/value rows, separated by thin rules. Diagnostics are the only
inner bordered block and use a `NOTE`-style label.

It contains:

- Account identity and current refresh state.
- For OpenRouter, the root-credit and ordinary-key hierarchy in a roomier
  read-only layout. Each key starts as one collapsed summary row showing its
  name, capacity left or truthful exception state, and reset when
  applicable. At most one key is expanded at a time. Expanding it reveals every
  native usage, BYOK, limit, unknown, unavailable, and unlimited observation,
  including zero values; the collapsed state intentionally suppresses zero
  usage noise. Expanded usage is a compact Day/Week/Month/Total table with
  Usage and BYOK columns. Reset schedule is a separate Scope/Reset table with
  one row per exact native reset identity. A shared standard/BYOK reset uses its
  short scope once; differing resets retain the Usage or BYOK qualifier.
  Key-limit and lifetime/no-reset identities remain distinct. It emits at most
  one update line per key. VoiceOver follows that same compact projection
  instead of announcing hidden per-metric timestamps or reset copy. Shared
  credits are not flattened into every key.
  The complete header row is the disclosure target, with a fixed leading
  chevron slot that does not move when details appear. Metric labels, values,
  and grouped resets adapt from two columns to vertically stacked rows at the
  360-point inspector width, in both English and Russian, rather than truncating
  or collapsing reset values into character columns. Account credits use a
  compact two-column `Left`/`Used` table. Derivable `Total` is omitted from both
  visual and accessibility presentation. A finite key limit uses one
  `Available` row with `$available / $total` and a thin available-capacity bar.
  The bar is shown only for a positive total, clamps its remaining fraction to
  `0...1`, and is explicitly labeled as available in accessibility output.
- The precise last-updated date and time.
- Source and confidence.
- A Use global / Used / Left control for every percentage-based limit window.
- Exact reset dates when available.
- Warning, stale, and failed-refresh context in a clearly labeled bordered
  message block.
- Secondary account actions such as Test Connection and Open Usage. Do not
  duplicate the normal individual Refresh action here. These actions and the
  dashboard footer Settings, About, and Quit actions have subtle visible idle
  outlines plus stronger hover/pressed feedback.

The popover may scroll only when diagnostic content genuinely exceeds the
compact inspector height. Its vertical scroller is a narrow autohiding overlay
over the right padding; it does not reserve a gutter or paint a background
strip.

## Accessibility And Interaction

- Glyph-only Refresh and Info controls require visible keyboard focus, tooltips,
  and descriptive accessibility labels.
- Each fieldset header control paints an idle fieldset-surface mask clipped to
  its own fixed hit target. Hover and pressed fills remain visible over that
  mask. No shared plate or slot may erase the border between controls, a
  neighboring panel border, or the fieldset's top-right corner.
- Meters are keyboard-focusable buttons. Their help, accessibility value, and
  fill agree with the current Used or Left value; their accessibility hint
  explains the toggle action. From the neutral panel, Tab enters the first
  meter and Shift-Tab enters the last; both keys wrap across the meter list.
  Space or Return toggles the focused meter. Escape clears meter focus, or
  closes the dashboard when no meter is focused.
- Disabled refresh controls explain why they are unavailable through their
  accessibility state and tooltip where appropriate.
- The details popover remains reachable by pointer and keyboard; hover is only
  an optional convenience.
- Dashboard popovers and their add/replace sheets inherit the selected app
  language explicitly. Their titles, labels, placeholders, buttons, metrics,
  reset copy, and update copy never fall back independently to the system
  locale.
- SwiftUI `MenuBarExtra` does not expose the clicked per-display status-item
  representation or the pre-close event ordering needed for deterministic
  multi-display anchoring. The existing narrow `NSStatusItem`/`NSPopover`
  boundary therefore converts the clicked button bounds to a screen rectangle
  once and owns a transparent, nonactivating, mouse-ignoring AppKit anchor host
  only for that presentation. The transient popover follows this stable host,
  not a mirrored status-item view that may migrate between displays, and an
  ordinary outside click closes it. A status-item click while the dashboard is
  visible is close-only, including on another display; a local pre-dismiss
  left-mouse-down latch preserves that decision if AppKit closes the transient
  popover before target-action dispatch. The host is released on every close or
  failed presentation. The latch expires after the event and is consumed once,
  so only a later explicit status-item click may create a new anchor on the
  newly clicked display. Production multi-display behavior remains an explicit
  manual verification gate.

## Non-Goals

- Redesigning Settings.
- Changing refresh coordination or provider behavior.
- Changing the normalized snapshot model.
- Adding history, charts, notifications, or a WidgetKit surface.
- Recreating terminal escape codes, text-mode controls, or literal ASCII art.

## Validation

- Build and run the staged menu-bar app.
- Verify global refresh, individual refresh, Info popover, and disabled states.
- Verify global Used/Left selection, per-window overrides, meter pointer and
  keyboard activation, persistence, and reset to Use global.
- Manually check normal, refreshing, stale, failed, manual-only, and no-data
  accounts in both Light and Dark appearance.
- Confirm that account ordering, progress accessibility values, and all existing
  details actions remain functional.
