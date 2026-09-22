# Design QA

## Source Visual Truth

- Codex CLI `/status` reference screenshot (temporary clipboard capture, no longer available).
- lazygit reference screenshot (temporary clipboard capture, no longer available).

## Implementation Screenshots

All screenshots below were temporary clipboard captures that are no longer
available. The findings and fixes remain valid.

- Dashboard before the current fix.
- Details popover before the current fix.
- Dashboard before the current controls and status-policy fix.

## Comparison State

- Menu-bar popover at its 390-point width in Dark appearance.
- Source screenshots: six enabled accounts, two accounts with limit windows,
  and visible warning copy.
- Source details screenshot: Ollama account with a successful refresh and a
  compatibility diagnostic; the current policy no longer promotes that
  diagnostic to a visible warning state.

## Findings

- [P1] Fieldset legends sit in the main panel area rather than centered in the
  top-border gap, and they move when Refresh changes to a spinner.
  Fix applied: legend and controls are independent overlays; the spinner now
  occupies the same fixed 14-point frame as the refresh glyph.
- [P1] Account controls are too low and too close together.
  Fix applied: controls are independently centered on the border, use 22-point
  hit targets, and have a seven-point gap.
- [P2] The meter fill reads as an amber warning even for normal usage.
  Fix applied: every normal usage meter now uses the same muted-gold color as
  its structural border. Green is used for successful refresh status, amber for
  warning or stale copy, and red for failures.
- [P2] Flat controls have no hover affordance.
  Fix applied: terminal text and glyph controls now show a subtle neutral hover
  fill and a stronger pressed fill without becoming pill buttons.
- [P1] The account-list viewport grows instead of scrolling, and the first
  account legend is clipped beneath the dashboard header.
  Fix applied: the list has a visible vertical scroll indicator and a 10-point
  legend clearance above its first panel. Its device-local viewport preset is
  Compact (320 pt), Standard (460 pt), or Tall (640 pt), so long account lists
  can show more rows without growing the popover indefinitely.
- [P1] The fieldset breaks are much wider than their legends, and close panels
  let a following legend mask the previous panel's lower border.
  Fix applied: the legend background now wraps its intrinsic text width rather
  than the title's maximum layout width, and inter-panel spacing is 14 points.
- [P2] The controls mask the top-right fieldset corner.
  Fix applied: the controls are shifted 12 points left while preserving their
  hit targets and the visible gap between Refresh and Info.
- [P1] A successful experimental source is elevated to a visible warning solely
  because of its compatibility note.
  Fix applied: a successful `.appServer` or `.ollamaWebPage` snapshot remains
  `OK`; only real usage thresholds, stale data, or failures produce warning
  state. The experimental label remains visible as source context.

## Full-View Comparison Evidence

The two implementation screenshots made the P1 and P2 findings above visible.
Post-fix staged-app verification was completed manually on 2026-07-15. The
temporary comparison captures were not retained in the repository.

## Focused Region Comparison Evidence

The account legend and control strip, the outlined meter, and the details
refresh row were inspected in the supplied screenshots and in the staged app.
The code addresses their geometry and semantic color mapping; the final native
captures were temporary and are not available in the repository.

## Comparison History

1. The first rounded-card dashboard was rejected as visually unlike the target.
2. The terminal-fieldset redesign established the status-inspector direction.
3. The supplied native screenshots revealed legend/control geometry, meter-color,
   success-color, and hover-state mismatches; the fixes above were implemented.
4. A second supplied dashboard screenshot revealed a growing viewport, clipped
   first legend, oversized fieldset breaks, and damaged adjacent borders; the
   corresponding layout fixes were implemented.
5. A later supplied dashboard screenshot confirmed the structural fixes and
   revealed the obscured fieldset corner and experimental-source warning state;
   the corresponding layout and status-policy fixes were implemented.
6. A later product decision added persisted Compact, Standard, and Tall
   dashboard viewport presets; code, Settings copy, the design contract, and
   staged-app manual verification were completed on 2026-07-15.
7. Computer Use still cannot inspect `Bairometer`, its bundle identifier, or
   `SystemUIServer`; every attempt ends with
   `Computer Use server error -10005: timeoutReached`.
8. Supplied OpenRouter dashboard, Info, Settings, overflow-menu, and key-editor
   screenshots revealed inconsistent icon geometry, invisible idle targets,
   right-aligned reset copy, eager metric expansion with repeated timestamps,
   system-locale leakage, and mixed key/credential terminology.
   Fix applied: dashboard and Settings icon controls share fixed borderless-idle
   geometry with hover/pressed feedback; only dashboard footer and Info text
   actions retain subtle idle outlines. Reset copy sits below the key name; Info
   uses full-row, one-at-a-time disclosures closed by default and vertically
   stacks long values and reset groups at narrow width. Locale propagation is
   explicit; English capacity uses `left`; and user-facing English/Russian use
   Key/Keys and Ключ/Ключи consistently. Add-key and local-removal terminology
   now matches the actions. Automated presentation, localization, rendering,
   and fixture tests cover the contracts. Signed English/Dark UI-host startup
   and exact-process cleanup probes on 2026-07-28 covered
   `dashboard-openrouter`, `settings-openrouter`, and the non-OpenRouter
   `dashboard-healthy` regression scenario. The post-fix visual and AX pass did
   not complete and remains an explicit manual gate alongside production
   status-item and popover anchoring.
9. A third supplied production pass found the remaining refresh/info optical
   mismatch, a wide Info scroller gutter, verbose money/key-limit copy, dense
   expanded usage/reset rows, Settings trailing-control drift, and a
   multi-display popover relocation on the close click. The correction keeps
   equal fixed icon containers while raising only the refresh glyph optically;
   configures the enclosing SwiftUI `NSScrollView` as a narrow autohiding
   overlay across recreation; trims amounts to two optional fraction digits;
   presents credits as Left/Used, usage as Usage/BYOK, and resets as
   Scope/Reset; aligns Settings controls on the shared overflow surface; and
   makes a visible status-item activation close-only before a later click can
   open on the new display. Production multi-display behavior remains a manual
   gate because the UI host does not own or automate `NSStatusItem` copies.
   Post-fix host visual and AX inspection also remains open; automated
   presentation, lifecycle, localization, and recreation tests do not substitute
   for that evidence.
10. A fourth supplied production pass showed that AppKit could dismiss the
    visible popover before the status-item action, idle header-control masks
    could erase nearby fieldset borders, OpenRouter money and key-limit copy
    remained verbose, and the Settings key menu did not share the provider
    menu's full interaction path. The correction adds an event-scoped
    pre-dismiss visibility latch, transparent idle control containers, `$` USD
    amounts with semantic accessibility copy, a compact Available capacity bar,
    stronger Info hierarchy, a left-inset Add slot, and one reusable native
    overflow implementation. Automated tests cover event ordering, expiry,
    input filtering, capacity safety, localization, presentation, and menu
    action state. Physical multi-display behavior and transient visual/AX
    inspection remain manual gates.
11. The final supplied production pass clarified that the multi-display defect
    occurs for an ordinary click anywhere on the second display, without a
    status-item action, and showed fieldset borders passing directly behind the
    dashboard Refresh/Info glyphs and the Settings KEYS Add glyph. The status
    action latch could not cover that path: AppKit continued to anchor the
    popover to a mirrored status-item view that can move. The correction
    captures the clicked button's screen rectangle once, presents the transient
    popover from a per-presentation transparent nonactivating mouse-ignoring
    host, and releases that host on close or failure. Each affected glyph now
    has its own 24- or 32-point fieldset-surface mask, with no shared plate;
    accepted global, footer, provider-header, management Add, and overflow
    controls are unchanged. Automated lifecycle and configuration tests cover
    the frozen anchor, outside-close teardown, next explicit anchor, failure
    cleanup, and individual mask policy. There is no post-fix screenshot or AX
    claim. Physical any-click-on-the-second-display behavior remains the final
    production manual gate.

## Final Result

passed — manual Light/Dark staged-app verification completed on 2026-07-15;
the public QA record is [GitHub issue #2](https://github.com/Prontsevich/bairometer/issues/2).
