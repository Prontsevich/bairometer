# Ollama Cloud Experimental Web Page Source

Ollama Cloud does not currently document an account-usage API. Bairometer uses
the `Experimental web page` source for each Ollama account.

In Settings or the dashboard account details, save the account, then choose
`Connect Ollama…` or `Reconnect`. Bairometer opens a dedicated connection
window so the transient menu-bar panel cannot dismiss the sign-in flow. Sign in
only in the Bairometer-owned WebKit view. Each
account receives its own persistent WebKit data store identified by an opaque
UUID; Bairometer never reads, imports, exports, logs, or stores cookies,
passwords, tokens, browser profile data, raw HTML, or raw bridge payloads.

The source loads `https://ollama.com/settings` and extracts only semantic usage
sections. It supports both page variants Ollama currently serves:

- The legacy variant renders `Session usage` and `Weekly usage` percentage cards,
  resolving each value from its own usage card even when Ollama wraps both cards
  in a shared section.
- The monthly variant renders an `Included usage` block with a spend meter for
  the plan month: an amount line such as `$4.91 of $60 used`, a reset element
  carrying the reset timestamp (`data-time` or `<time datetime>`), and
  per-model request segments. The extracted window is normalized as a
  `Monthly` limit window with a used percentage computed from the amounts, the
  `$X of $Y` amount as its remaining label, and the reset time when exposed.

Either variant may appear; whichever sections are present are extracted, and
both can appear together. During
interactive sign-in, WebKit may follow Ollama's documented authentication
redirect through `api.workos.com`, `signin.ollama.com`, Google, or GitHub;
regional Google Account endpoints such as `accounts.google.by` are allowed for
interactive sign-in. Scheduled refreshes never follow third-party redirects.
Interactive sign-in remains open until it completes or the user cancels it; scheduled refreshes
retain a 20-second load timeout. WebKit cancellation events from an OAuth
redirect or an obsolete navigation after the settings page becomes visible are
ignored; actual failures before the settings page remain actionable. The bridge
is run again after the settings navigation and waits for the usage cards to
render. After login, extraction remains restricted to the settings page.

The values are labeled `Ollama settings web page (Experimental)` with `live`
confidence. The page structure is undocumented and may change, but a successful
read is presented as `OK`; model request counts, per-model meter segments,
extra-usage balance, and billing values are intentionally excluded from the
normalized payload beyond the monthly spend amounts shown on the usage window.

## Appearance

The isolated WebKit session installs a separate visual-only script in its main
frame at document start. The script runs in WebKit's client content world and
adds adaptive Radix and WorkOS page-background color tokens only when the page
origin is exactly `https://ollama.com` or `https://signin.ollama.com`. It follows the effective
macOS Light or Dark appearance through `prefers-color-scheme`, including while
an Ollama-owned page remains open.

The script changes only color scheme, colors, backgrounds, and border contrast.
It does not change layout, visibility, controls, focus, form submission,
navigation, page content, or page event handling. It creates no message handler
and does not inspect or modify the settings-page usage payload. WorkOS, Google,
GitHub, regional Google Account endpoints, and every other third-party OAuth
page receive no stylesheet or DOM mutation.

`Reconnect` is available when the session expires or the page structure
changes. Scheduled refreshes never foreground the login view or attempt
unattended reauthentication. A failed refresh keeps the last valid snapshot and
shows a visible recovery warning.
