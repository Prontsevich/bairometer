# OpenRouter Provider Research

## Status and decision

OpenRouter has a supported `documented-interface` result for the first MVP. One
saved Bairometer account represents one user-declared OpenRouter billing
account. It contains one or more ordinary API-key credential contexts, each
using `GET /api/v1/key` for its own limits and usage. An optional management key
adds the single account-wide credits metric through `GET /api/v1/credits`.

The management credential is explicitly elevated and opt-in. It is never
selected as a fallback for an ordinary key. The implemented MVP does not call
`GET /api/v1/keys`, auto-import keys, or persist provider labels, hashes, owner
IDs, or workspace IDs.

The strict production HTTP client is implemented in `AILimitBarCore`. Its two
explicit capabilities cannot substitute for each other: an ordinary credential
can request only `GET /api/v1/key`, while an elevated management credential can
request only `GET /api/v1/credits`. Both use fixed trusted HTTPS URLs, a bounded
timeout, streaming response-size enforcement, task cancellation, strict
lossless `Decimal` decoding, and sanitized typed failures. Redirects are
rejected, and the default ephemeral session has no cookie, URL-cache, or URL
credential storage. The client emits native USD Contract v1 metrics.

The registered `openrouter-api` source mode connects that client to the app's
manual, scheduled, and launch refresh paths. Additive GRDB migration v7 stores
the current validated Contract v1 snapshot and normalized metric JSON while
leaving the legacy snapshot columns untouched. Refresh state and sanitized
diagnostics remain per credential slot. The initialized runtime explicitly
starts one idempotent launch refresh after `AppModel` construction. Native
currency and credit presentation is implemented in the dashboard, account
details, and Settings.

## Selected MVP account shape

The dashboard and persistence model use this hierarchy:

```text
OpenRouter billing account
├── shared account credits (optional management source)
├── ordinary API key credential
│   └── per-key usage, BYOK usage, limit and reset metrics
└── ordinary API key credential
    └── per-key usage, BYOK usage, limit and reset metrics
```

An API key is a `credential` account context, not a capacity window. One key can
produce several metrics with different windows. Account credits attach only to
the root context and render once; they are never copied into child-key rows.

Without a management key, ordinary-key metrics continue to work and the shared
balance is unavailable rather than duplicated or inferred. With a management
key, credits are fetched once per account. A failure in one credential context
preserves the other keys and the last valid account metric, with separate
refresh results and diagnostics.

Keys from a genuinely different billing owner belong to another saved AI
Limitbar account. Without management inventory evidence, grouping is an
explicit user choice rather than a provider-verified ownership claim.

## Settings and presentation

Settings creates each ordinary key as a locally named child credential context
and allows rename, replacement, enable/disable, recovery, and secure deletion.
The optional management credential is a separate elevated slot attached to the
account root. It has an explicit disclosure and is never shown as an ordinary
key. Raw values are accepted only by a secure editor, written to Keychain, then
cleared; the app never reads them back into Settings. Replacing an active slot
also recovers a missing Keychain item without changing the local context.
Deleting an OpenRouter account first securely removes all of its credential
items and then removes its local capacity state.

The default dashboard renders only the saved-account balance amount at the
root, with up to two localized fraction digits and trimmed trailing zeros. It
does not show lifetime
credits, derived used credits, percentages, or progress bars. Each ordinary key
has one compact row with its local name, finite key capacity amount, and
relative reset when applicable. A current key with no configured key-level
limit is labeled as such without claiming unlimited account capacity.

The existing account Info inspector remains the single detailed disclosure path
for the full native root summary and every per-key usage, BYOK, limit, reset,
freshness, refresh-state, and fixed diagnostic observation. Unknown,
unavailable, partial, stale, disabled, recovery-required, and credential-error
states remain explicit in the default hierarchy, while healthy status text and
timestamps do not. Presentation uses app-owned metric names and never exposes
provider labels, hashes, opaque IDs, messages, headers, or raw responses.
USD dashboard and Info values use `$`; future non-USD values fall back to their
ISO code. Visual dashboard summaries are amount-only, while accessibility
values retain explicit left/available semantics.

Account credits are a two-column `Left`/`Used` table; derivable `Total` is not
rendered or exposed through accessibility. A finite key limit is one compact
`Available` row, for example `$1 / $1`, followed by a thin remaining-capacity
bar. The fraction is clamped and the bar is omitted for zero or unknown totals.
Expanded key
details group Day/Week/Month/Total amounts into Usage and BYOK columns and show
reset identities separately in a Scope/Reset table. Equal standard/BYOK resets
share a short scope row, while different identities retain the necessary
qualifier. Key-limit, lifetime/no-reset, and one freshness line remain explicit.

OpenRouter Settings shows provider identity once in the Accounts sidebar; the
detail header keeps only the saved account name. It uses one compact credential
inventory instead of repeated healthy status, configuration, and refresh
metadata. Active healthy state is implicit. A compact account-level exception
remains visible when refresh fails before a slot diagnostic exists. The active
management row hides only current shared-credit state; stale, unknown, and
unavailable shared-credit states remain visible and accessibility-readable.
Rename, replace/recover, enable/disable, and secure removal live in each row's
native overflow menu. Keychain and elevated-management explanations appear only
inside add/replace flows. User-facing setup says `Add key` and `KEY DETAILS`;
account and key confirmations say Remove because they affect only local app
configuration and Keychain state.

Saved root credits and management diagnostics are visible only while the
current metadata contains one active, enabled management slot. Missing,
disabled, pending-creation, or pending-deletion management metadata makes
shared credits unavailable even if an older root observation or diagnostic
remains in storage. Freshness applies to every known observation, including an
unlimited value: the value may still read `Unlimited`, but an observation older
than the ten-minute source policy is stale and contributes stale account state.

## Documented sources

| Source | Credential | Scope | Useful signals | Confidence |
| --- | --- | --- | --- | --- |
| `GET /api/v1/key` | Ordinary API key | Authenticating key only | Key limit, remaining limit, reset policy, total/daily/weekly/monthly usage, separate BYOK usage, expiry and tier flags | Live |
| `GET /api/v1/credits` | Management key according to the API reference | Current personal or organization billing account | Total credits purchased and total usage | Live |
| `GET /api/v1/keys` | Management key | Administrative key inventory; default workspace or explicit workspace filter | Per-key limits and usage, disabled state and expiry | Live |
| `GET /api/v1/activity` | Management key | Current account; optional key-hash or organization-member filter | Last 30 completed UTC days, grouped by endpoint | Delayed |
| `GET /api/v1/workspaces` | Management key | All workspaces visible to the account-level key | Workspace inventory only | Live |
| `GET /api/v1/workspaces/{id}/budgets` | Organization management key; Enterprise | One selected workspace | Daily, weekly, monthly or lifetime USD limits and reset policy | Live for the configured limit |

The documented workspace-budget response contains the limit and interval but
does not contain current spend. It cannot by itself produce a remaining-budget
value. The activity endpoint is documented as a 30-completed-day account feed
and does not document a workspace field, so it is not a defensible substitute
for exact workspace-period spend. The sanitized management probe returned 31
completed UTC dates and encoded each `date` as `YYYY-MM-DD 00:00:00`, rather
than the documented `YYYY-MM-DD`. A future parser must accept both verified
shapes, normalize them to a completed UTC day, and must not assume exactly 30
rows or dates.

The current-key response also contains a deprecated `rate_limit` object. It is
not a supported capacity signal and must be ignored. Free-model request limits
are plan- and credit-dependent rather than a general account quota exposed by
this endpoint.

Official references:

- [Current API key](https://openrouter.ai/docs/api/api-reference/api-keys/get-current-key)
- [Credits](https://openrouter.ai/docs/api/api-reference/credits/get-credits)
- [Management API keys](https://openrouter.ai/docs/guides/overview/auth/management-api-keys)
- [API-key inventory](https://openrouter.ai/docs/api/api-reference/api-keys/list)
- [Activity](https://openrouter.ai/docs/api/api-reference/analytics/get-user-activity)
- [Workspaces](https://openrouter.ai/docs/guides/features/workspaces/overview)
- [Workspace budgets](https://openrouter.ai/docs/guides/features/workspaces/workspace-budgets)
- [Errors and retry behavior](https://openrouter.ai/docs/api/reference/errors-and-debugging)

## Signal semantics

All documented monetary values are represented as native USD currency values;
they are not converted to a percentage or mixed with token, request or BYOK
quantities.

For an ordinary key:

- `usage`, `usage_daily`, `usage_weekly` and `usage_monthly` are distinct spend
  observations and remain separate metrics.
- `byok_usage` and its daily/weekly/monthly variants remain separate from
  OpenRouter-billed usage. `include_byok_in_limit` controls only whether those
  values participate in the key limit.
- A finite `limit` with `daily`, `weekly` or `monthly` `limit_reset` maps to the
  matching fixed UTC window. Daily resets are at midnight UTC, weekly resets
  are Monday at midnight UTC, and monthly resets are on the first day at
  midnight UTC.
- A finite limit with no reset is a lifetime key limit.
- `limit_remaining` is provider-reported. It is not recomputed unless a future
  adapter records an explicit derivation, and negative or over-limit values
  must not be clamped.
- `limit == null`, `limit_remaining == null` and `limit_reset == null` mean that
  this key has no configured key-level limit. They do not prove unlimited
  account credits, model availability or provider capacity. The adapter omits
  the limit metric and still reports the available usage metrics.
- `is_free_tier` and `is_management_key` are required booleans. The first maps
  to the safe key tier; an ordinary-current-key read rejects
  `is_management_key == true` instead of silently accepting an elevated
  credential shape.
- Missing is not zero. Unknown fields are ignored, while a missing required
  observation fails only the affected metric.

For a management key, `total_credits` and `total_usage` describe the current
billing account, not a workspace. Remaining credits may be derived explicitly
as total credits minus total usage. Activity is historical and delayed because
the endpoint contains only completed UTC days. Workspace budgets are distinct
workspace metrics and must not be combined with account-wide credits.

## Credential and account boundaries

Ordinary and management keys are separate Keychain credential slots. The raw
key is used only in the HTTPS Authorization header and is never written to
SQLite, `UserDefaults`, logs, fixtures or diagnostics.

The transport API accepts role-specific redacted wrappers rather than a bare
secret. Constructing an ordinary or management wrapper validates both the
`openrouter` provider ID and the exact `ProviderCredentialSlot.role`, so a
management slot cannot compile as the argument to the ordinary operation and
runtime slot mismatches fail before a request is created. Each wrapper also
retains its validated provider, account, context, and slot identity privately.
The public fetch operations accept no independent context ID; every emitted
metric receives the wrapper's slot context, preventing one credential from
labelling observations as another context.

Each slot is a device-local, non-synchronizing generic password in the macOS
Data Protection Keychain. All CRUD queries explicitly target that Keychain;
creation uses after-first-unlock, this-device-only accessibility. Access stays
inside the app's provisioned default Keychain group, so local staged
verification requires Apple Development signing and an embedded authorized
profile. The local developer supplies its Team ID explicitly through
`AILIMITBAR_DEVELOPMENT_TEAM`; the repository stores no team-specific value.
Release staging accepts the Developer ID identity and matching provisioning
profile only through explicit caller-owned inputs, validates the exact default
Keychain group, and signs with Hardened Runtime and a secure timestamp.
Notarization and stapling remain required before distribution.

Each ordinary slot attaches to one app-owned `credential` child context. The
optional management slot attaches to the saved billing-account root, so its
future credits metric remains root-scoped rather than becoming a child-key
metric. SQLite enforces one slot per context and at most one management slot per
saved account; all reads and writes include the provider, saved-account, and
slot IDs so identical local child names in two accounts cannot cross their
credential boundary.

Credential creation, replacement, disabling, and deletion are lifecycle-aware.
A disabled or incomplete slot cannot be read. Create and delete partial failures
retain an opaque Keychain reference in an inaccessible retryable SQLite row;
account removal cannot bypass credential cleanup. Per-account serialization
keeps create and recovery from racing delete across separate store instances,
while the persisted lifecycle row remains the crash-recovery boundary. No
recovery path returns an existing raw key to Settings or diagnostics. Each slot
also has a persisted `credentialRevision`. Replacement or credential-bearing
creation recovery increments that revision before changing Keychain material,
so a request started with an older secret cannot commit metrics, refresh state,
or diagnostics after the replacement.

An ordinary key is the narrowest reliable credential boundary:

- every OpenRouter API key belongs to a workspace, but `/api/v1/key` does not
  return a workspace identifier;
- organization keys draw from the organization's shared credit pool, but the
  current-key response does not identify the organization;
- therefore Bairometer can truthfully label the source as one configured API
  key, but cannot infer an upstream personal account, organization or workspace
  from it;
- keys grouped by the user under one billing account retain separate local
  credential-context IDs, Keychain items, refresh results and diagnostics,
  while account-wide credits remain a single root metric.

Management keys are account-level administrative credentials. OpenRouter
documents that they operate across workspaces and cannot call completion
endpoints. In the implemented MVP they provide shared credits only. Key
inventory is outside the runtime scope. A management source represents one
explicitly selected billing account and does not create multiple saved
accounts.

OpenRouter organizations are separate from personal accounts, can share one
credit pool, and can contain members in several workspaces. A user may belong
to multiple organizations. The completed live matrix covers two ordinary keys,
one management key, a populated default workspace and a second empty workspace
in one personal billing context. It verifies management visibility and empty
workspace key filtering, but does not establish organization behavior or a
workspace containing an independently scoped key.

## Sanitized probe evidence

An ordinary-key probe on 2026-07-23 decoded the response only in memory and
emitted field names, JSON types, null flags, credential-class booleans and HTTP
status codes. It did not emit or retain the key, label, creator ID, monetary
values, raw response or error messages.

Observed results:

- `/api/v1/key` returned the documented `data` envelope and ordinary,
  non-provisioning credential classification.
- Usage and BYOK total/daily/weekly/monthly fields were numeric.
- `limit`, `limit_remaining`, `limit_reset` and `expires_at` were present and
  null, proving the no-key-limit variant without treating it as unlimited.
- Missing and deliberately invalid authentication both returned HTTP 401.
- The ordinary key returned HTTP 403 for `/activity` and HTTP 401 for `/keys`
  and `/workspaces`, confirming that those administrative paths cannot be an
  ordinary-key fallback.
- The same ordinary key unexpectedly returned HTTP 200 and the documented
  numeric schema from `/credits`, despite the current API reference requiring a
  management key. This is an undocumented authorization mismatch. Bairometer
  must not rely on it; `/credits` remains management-only in the source
  contract until OpenRouter changes its documentation.
- The management credential identified itself as both management and
  provisioning, and returned the documented numeric credits schema, key
  inventory, activity feed and workspace inventory.
- Two distinct ordinary keys had the same creator context. One exercised the
  all-null key-limit variant; the other exercised a finite monthly key limit.
  Both were visible in the management inventory and all enumerated keys shared
  the same workspace.
- `/credits` returned equal account totals for both ordinary keys and the
  management key. This confirms that per-key usage and limits remain separate
  while the probed keys share one account-wide credit pool. The ordinary-key
  access remains undocumented and unsupported despite this observed equality.
- Management activity was non-empty and contained endpoint, model and provider
  metadata that must be discarded. Filtering by the primary key hash returned
  only that key's rows; filtering by a second key with no matching activity
  returned an empty successful result.
- The organization-only `user_id` activity filter returned HTTP 400 in the
  probed personal context.
- Workspace-scoped key filtering returned the full populated inventory for the
  original workspace and every returned item matched that filter.
- Workspace-budget reads returned HTTP 404 by both workspace ID and slug. This
  is a missing personal/default-workspace capability, not an empty known
  budget.
- After a second empty workspace was added, management workspace inventory
  returned both contexts and workspace-filtered key inventory returned an empty
  successful result for the new workspace. Account credits remained identical
  through the ordinary and management credentials, confirming that credits are
  account-wide rather than workspace-scoped. The new workspace budget endpoint
  also returned HTTP 404.

Deferred expansion scope:

- organization identities, member-created keys, and workspaces containing
  independently scoped keys;
- automatic management-key discovery and synchronization of key inventory;
- management activity/history and workspace-aware analytics;
- daily, weekly and lifetime finite key-limit variants, including zero and
  over-limit observations where they can be created without paid inference;
- an available Enterprise workspace-budget variant if workspace budgets are to
  become supported;
- HTTP 429 evidence when naturally encountered. Research must not manufacture
  load to force rate limiting.

## Refresh, failure and privacy behavior

The endpoints are ordinary HTTPS JSON reads and are compatible with the current
macOS architecture through a trusted `URLSession` adapter. No browser session,
CLI, helper process or additional dependency is needed.

The provider does not document an observation expiry for these reads. The
source descriptor therefore applies a ten-minute maximum age, and the client
marks successful metrics with their fetch completion time. The account
coordinator runs at most four credential requests concurrently across all
overlapping refresh invocations for that saved account. Starting a newer
refresh cancels the prior account's network tasks; requests that do not
cooperate with cancellation retain their shared permits until they actually
finish, so overlap cannot exceed the bound. Different saved accounts have
independent limiters. Each source performs one request per eligible refresh;
there are no hidden retry loops or sleeping tasks.

The client parses standard `Retry-After` values on HTTP 429 and 503 and returns
that semantic value to the coordinator without retrying or busy waiting. The
coordinator persists `retryNotBefore` and bounded exponential backoff per slot;
a later manual, scheduled, or launch refresh retries only when that timestamp
is eligible. Delta-seconds accept only nonempty ASCII digits within `UInt`;
signs, embedded whitespace, Unicode digits, and overflow fail closed. Dates
accept only the three canonical HTTP-date forms, with literal `GMT` on the two
zoned forms; arbitrary `PST`, `UTC`, or other `z`-parsed zones are rejected.
Outer HTTP optional whitespace remains allowed.

Responses are consumed by a per-request `URLSessionDataDelegate`. Its response
callback cancels a declared `Content-Length` above the configured bound before
app-owned body collection and cancels non-200 bodies without collecting them.
For an unbounded or chunked response, data callbacks append only while the
configured bound can hold the complete callback and cancel as soon as the next
data would cross it. The lossless JSON-number transformation has its own
bounded output. These limits prevent either app-owned transport storage or the
exact-decimal preprocessing step from becoming an unbounded raw-response
retention path.

Errors map to fixed diagnostics by HTTP class: authentication for 401,
insufficient privilege for 403, insufficient credits for 402, throttled for
429, service unavailable for 503, and sanitized server failure for other 5xx.
Timeout, cancellation, transport, response-size and decoding failures remain
distinct. Provider messages, metadata, headers and response bodies are never
returned, logged or persisted.

A successful source replaces only its own `(contextID, sourceID)` metric set.
Its metric replacement, successful refresh state, and diagnostic clearing are
one GRDB transaction under the same account lifecycle lock. A failure preserves
last-valid metrics while committing its failed refresh state, retry boundary,
and fixed diagnostic in one transaction. A deferred source performs no
mutation, but revalidates the account, slot identity, credential revision, and
refresh generation before being counted. Ordinary sibling keys and the
root-scoped management metric therefore survive an unrelated child failure.
When no enabled management slot exists, the root credits metric is explicitly
unavailable instead of inferred or copied. At the end of every account refresh,
a lifecycle-locked conditional transaction re-reads the current management
slot: an enabled active slot is a benign no-op, while an absent or disabled slot
source-locally replaces any known credits with exactly one unavailable
sentinel. Disable, delete, cancellation, and a newer account refresh invalidate
older generations; SQLite revalidates the account, exact slot identity,
credential revision, and generation both on transaction entry and immediately
before commit.

The compatibility result counts only sources that succeeded during the current
refresh. Last-valid native observations remain available separately and the
synthetic unavailable-management sentinel is never counted as usable
freshness. Zero current successes is therefore an error, including first
failure, total failure after earlier success, all-deferred, and
management-absent-only outcomes. `AppModel` preserves the prior compatibility
snapshot and its last-success timestamp on those errors. A mixed current
success/failure result is a warning.

## Fixture and test strategy

Production client fixtures are hand-authored from the documented schema and
sanitized probe shapes, never copied from real responses. Deterministic parser
and `URLProtocol`-style client coverage now includes:

- bounded ordinary keys with daily, weekly, monthly and lifetime resets;
- null and absent key-limit variants;
- zero, decimal, negative remaining and over-limit values without clamping;
- BYOK included in and excluded from a key limit;
- missing optional fields, unknown fields, malformed numbers and wrong JSON
  types, including exponent boundaries that must fail without trapping;
- exact management credit derivation separated from per-key usage;
- fixed endpoint, provider/credential-role capability separation, direct
  redirect rejection, private slot-identity binding, and ephemeral
  default-session privacy policy;
- 401, 402, 403, 429 and 503 with `Retry-After` delay/date variants, other 5xx,
  transport failure, cancellation, timeout, declared and streamed
  response-size failure, and bounded JSON transformation;
- accepted and rejected `Retry-After` delta/date syntax, including overflow,
  Unicode digits, and non-GMT zones;
- deterministic `127.0.0.1` loopback coverage of the real delegate transport,
  proving early connection closure for oversized declared, chunked, and
  non-success responses with one request and no provider traffic;
- error rendering that excludes credentials, raw bodies, headers and monetary
  values, plus recursive and pattern-based fixture privacy scans.

Deferred activity and workspace coverage still includes:

- empty and populated management activity with completed-day freshness;
- both documented date-only and observed UTC-midnight timestamp activity dates,
  including a variable number of returned completed days;
- account-wide credits separated from workspace budgets and per-key usage;
- two genuinely separate billing accounts when that expansion is researched;
- absence of credentials, labels, hashes, upstream user/workspace IDs, model
  names and raw errors from persistence, logs and diagnostics.

The existing synthetic contract fixture continues to demonstrate native
currency, privilege-separated sources, null limits and account/workspace
separation. Neither the contract fixture nor the client fixtures count as
authentication or live provider verification.

On 2026-07-24, the user launched the Apple Development-signed DEBUG app through
`./script/build_and_run.sh`, added their own OpenRouter keys in Settings, and
successfully received the expected OpenRouter data. This verifies real Keychain
credential input and creation plus provider refresh and data retrieval; it does
not verify credential replacement, deletion, recovery, visual or AX behavior,
or any specific management-versus-ordinary credential path.

Debug UI-host scenarios `dashboard-openrouter`, `settings-openrouter`, and
`settings-openrouter-missing-management` render the real dashboard and Settings
views with synthetic normalized capacity, active/disabled/missing management
metadata, per-slot freshness, fixed diagnostics, and an account failure before
slot diagnostics. They contain no credential values and perform no provider or
Keychain access.

A DEBUG-only deterministic end-to-end seam exercises the registered adapter,
hierarchical coordinator, partial child failure, Contract v1 validation,
per-slot diagnostics, and native SQLite persistence without provider traffic
or real credentials:

```zsh
verification_dir="${TMPDIR%/}/ailimitbar-openrouter-verification-$(uuidgen | tr -d '-').disposable"
AILIMITBAR_DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  ./script/stage_app_bundle.sh --configuration debug
dist/AILimitBar.app/Contents/MacOS/AILimitBar \
  --ai-limitbar-openrouter-verification \
  --ai-limitbar-storage-directory "$verification_dir"
```

The command accepts only a non-existing direct child of the canonical system
temporary directory whose basename matches the verification prefix and
`.disposable` sentinel. It rejects existing paths, symlink parents, production
storage, the workspace, home, and broad filesystem roots. The command itself
creates the directory and removes it after both success and failure. It writes
synthetic secrets to an in-memory test Keychain implementation, never to the
real Keychain or SQLite.
