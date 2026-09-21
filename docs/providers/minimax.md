# MiniMax Token Plan Provider

## Supported boundary

Bairometer implements the experimental MiniMax Global Token Plan source with
the documented `GET /v1/token_plan/remains` endpoint. A saved MiniMax account
is a local context for one Global personal Default Team and exactly one
Subscription Key. It is not a MiniMax profile and must not merge Teams, regions,
or credentials.

Several saved MiniMax accounts are isolated locally: every account has its own
Keychain item, saved-account ID, contexts, refresh state, snapshots, and
diagnostics. Credential changes invalidate only that account's in-flight
generation, so a late result for it is discarded without cancelling or
overwriting another account's refresh.

The source deliberately does not support regular Teams, Mainland China,
purchased Credits, pay-as-you-go API keys, CLI credentials, web sessions, or
cross-region fallback.

## Subscription Key setup

The MiniMax account detail in Settings has a single Subscription Key slot.
The user can add, replace, disable, enable, recover, or remove that key. The
secret is written only to Keychain; the Settings presentation uses stored
credential metadata and never displays or reads the secret merely to render
the screen. Removing or replacing a key invalidates pending work for that
account before its persisted credential metadata changes.

The configured boundary is displayed as Global / personal Default Team / local
configuration. Those labels describe the product boundary; the remains
response does not establish an upstream owner or Team identity.

## API and quota-category semantics

The provider response uses engineering field names including `base_resp`,
`model_remains`, and `model_name`. They are retained in parser and API-contract
discussion because they are part of the observed wire shape. A successful
business response requires `base_resp.status_code == 0` before the app decodes
the capacity entries.

## Failure diagnostics

A Token Plan response classified as an unavailable subscription is persisted as
a distinct sanitized credential diagnostic. Dashboard, Account Details, and
MiniMax Settings present fixed localized copy that the Token Plan subscription
is unavailable or expired; they do not display upstream response text, key
material, account or plan identifiers, or usage values. Invalid authentication,
throttling, transient failures, and last-valid snapshot preservation remain
separate behaviors.

Although the array is named `model_remains`, the reviewed identifiers observed
there are quota-category identifiers, not callable MiniMax model names. The
official [Token Plan overview](https://platform.minimax.io/docs/token-plan/intro)
describes a shared text, image, speech, and music quota alongside a distinct
video-generation quota. Bairometer therefore applies this closed,
code-reviewed mapping:

- Wire identifier `general` → stable ID `quota-category-a` → local label
  “Shared text & multimodal Token Plan quota”.
- Wire identifier `video` → stable ID `quota-category-b` → local label
  “Video generation Token Plan quota”.

The raw identifiers are neither displayed, persisted as presentation data, nor
placed in diagnostics or accessibility labels. They are never mapped to a
callable model name. Unrecognized entries are ignored with a fixed local
diagnostic, and the two known categories are never aggregated.

Each category retains two independent provider-defined windows:

- Current — the provider's rolling window.
- Weekly — the provider's weekly window.

For every category/window pair, a usable documented remaining percentage
(`0...100`) is the sole quota value projected into the normalized contract. It
uses the `percent` unit, with reported remaining percentage, reported `100`
percentage-scale limit, and consumed percentage derived as the complement.
The count and opaque status fields are decoded only for the strict wire shape;
they do not determine quota availability, percentage, meter, or presentation.
In particular, status `3` does not mean unlimited. A missing or unusable
percentage produces the non-claiming `unknown` capacity state with no meter.
The app presents reset information only from a validated provider window
transition. It does not call any values requests, characters, images,
generations, or tokens.

## HTTP, errors, and privacy

The production client requests the canonical Global endpoint
`https://api.minimax.io/v1/token_plan/remains` with Bearer authentication and
an ephemeral, no-cookie `URLSession`. It limits successful response bytes while
they are received, so an oversized body is cancelled before it is fully
buffered. Non-200 responses are classified from HTTP status before body-size
handling, preserving authentication, throttling, and service-unavailable
classification and any applicable `Retry-After` value.

The client decodes the base business envelope before capacity entries. Known
business errors therefore remain correctly classified even when a capacity
array is absent, null, or malformed. The implementation has fixed local
categories for authentication, throttling, unavailable subscription, exhausted
usage, insufficient resource, temporary service failure, and unsupported
responses. It does not persist or log Subscription Keys, response bodies,
provider messages, opaque identifiers, or unrecognized response fields.

## Presentation

Dashboard and Account Details use the same privacy-safe projection. The
Dashboard uses compact local labels: “Text & multimedia” and “Video generation”
in English, or “Текст и мультимедиа” and “Генерация видео” in Russian. Account
Details and accessibility labels use the expanded descriptions: the shared text
& multimodal Token Plan quota and video generation Token Plan quota; in Russian,
“Общая квота Token Plan для текста и мультимодальных задач” and “Квота Token
Plan на генерацию видео”. Both surfaces retain independent Current and Weekly
rows, a used/left percentage toggle where the provider reported a usable
percentage, and reset information when available. No raw count values, response
identifier, model name, status, or combined total is shown.

The debug-only UI test host provides the `dashboard-minimax` scenario. It uses
synthetic normalized capacity data only and is not a real-provider or Keychain
test. Its stable MiniMax accessibility identifiers are:

- `ui-test-host.root.dashboard-minimax`
- `dashboard.minimax.category.<account>.<category>`
- `dashboard.minimax.window.<account>.<category>.<window>`
- `details.minimax.category.<account>.<category>`
- `details.minimax.window.<account>.<category>.<window>`
- `settings.minimax.boundary`, `settings.minimax.subscription-key`,
  `settings.minimax.primary-action`, `settings.minimax.enabled-action`, and
  `settings.minimax.remove-action`
- `settings.minimax.credential-value`, `settings.minimax.editor-save`, and
  `settings.minimax.editor-error`

## Automated verification

The MiniMax Core and app tests cover:

- accepted and rejected HTTP/business responses, including status validation
  before decoding capacity entries;
- incremental response-size enforcement and HTTP error classification;
- closed category mapping, unknown-category diagnostics, independent current
  and weekly percentage windows, status-`3` presentation without an unlimited
  inference, and no raw identifier/model-name projection;
- Keychain-only single-slot lifecycle, recovery and deletion behavior, and
  metadata-only Settings presentation;
- account isolation, including concurrent refreshes and late results after a
  credential mutation;
- Dashboard, Account Details, English/Russian presentation, and the synthetic
  `dashboard-minimax` host fixture.

`swift build` and the full `swift test` suite passed for the implemented
provider changes. Signed UI-host verification on 2026-08-24 covered
`dashboard-minimax` in English/Dark and Russian/Light: screenshots and the AX
tree showed both neutral categories, independent windows, reset text, and the
Used/Remaining meter toggle. Account Details opened and closed; MiniMax Settings
showed the boundary disclosure and an Add Key sheet whose secure field exposed
only a redacted AX value, with no credential entered. Keyboard navigation is
still an explicit manual follow-up because synthetic Tab input did not report a
focused element. Real credentials, provider responses, and the production
status item/popover remain outside the host's verified boundary.

## References

- [MiniMax Token Plan overview](https://platform.minimax.io/docs/token-plan/intro)
- [MiniMax Token Plan FAQ](https://platform.minimax.io/docs/token-plan/faq)
- [MiniMax Models guide](https://platform.minimax.io/docs/guides/models-intro)
- [MiniMax API error codes](https://platform.minimax.io/docs/api-reference/errorcode)
- [MiniMax API rate limits](https://platform.minimax.io/docs/guides/rate-limits)
- [Official MiniMax CLI quota types](https://github.com/MiniMax-AI/cli/blob/3615170a2e26ec6003c4550cd1324b55ec8ad677/src/types/api.ts)
