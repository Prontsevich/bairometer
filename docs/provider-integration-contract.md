# Provider Integration Contract

## Status and boundary

This document defines the implementation-level version 1 direction for
Bairometer's internal Provider Integration Contract. It is a design contract for
the application and future portable Core; it is not a public standard, JSON
Schema, SDK, compatibility promise, plugin runtime, or provider registry.

The contract is intentionally transport-independent. Trusted adapter code owns
authentication, endpoint and command selection, requests, process execution,
DOM access, parsing, validation, retry behavior, and normalization. Declarative
metadata never contains executable request rules or credential values.

Version 1 is implemented in `AILimitBarCore` as portable `Codable` domain
models, pure validation rules, and a one-way legacy percentage bridge. That
domain-model implementation has no SQLite, Keychain, URLSession, AppKit, or
SwiftUI dependency. Trusted provider clients may depend on platform transport
while producing these domain values; the strict OpenRouter `URLSession` client
is the first native-monetary example. OpenRouter now persists current native
Contract v1 snapshots while returning a percentage-free `UsageSnapshot` status
projection through the existing adapter API. Native dashboard presentation for
currency and credits remains separate work.

The contract separates six responsibilities:

| Responsibility | Owner |
| --- | --- |
| Provider | Identifies the company or service family. |
| Product Surface | Identifies an independently authenticated and billed offering. |
| Account Context | Identifies the personal, organization, workspace, project, team, or local-identity scope being observed. |
| Data Source | Describes how observations are obtained and their authority, maturity, and freshness behavior. |
| Auth Requirement | Declares the credential category, privilege, scope, and secure storage boundary without implementing credential lifecycle. |
| Capacity Observation | Preserves provider facts in native units with availability, window, provenance, freshness, confidence, and derivation semantics. |

Surfaces from one provider are not merged merely because they share branding.
For example, a personal subscription, API billing account, enterprise tenant,
and local CLI identity can have different authentication, capacity, and
account-scope semantics.

## Contract version

Every serialized account snapshot carries:

```text
ContractVersion
  major: UInt
  minor: UInt
```

Version 1 starts at `1.0`.

- Adding an optional field or a new optional metadata record increments
  `minor`.
- Removing or renaming a field, making an optional field required, changing a
  field's meaning or owner, or changing a required discriminator increments
  `major`.
- A reader accepts its supported major and any minor at or below its supported
  minor. It may accept a newer minor by ignoring unknown object members.
- Unknown object members are ignored; they are not retained or round-tripped.
  There is no arbitrary extension dictionary that could retain raw provider
  data.
- An unknown required metric discriminator rejects that metric, records a
  sanitized diagnostic, and continues with other valid metrics.
- An unknown surface, source, account-context reference, or contract major
  rejects the snapshot. Refresh then preserves the last valid snapshot and
  records a sanitized diagnostic.
- Missing required fields and invalid cross-field invariants follow the same
  fail-closed behavior. Diagnostics identify the contract field or error code,
  never the raw payload or credential material.

The fixture representation uses decimal strings and UTC ISO 8601 timestamps.
The eventual Swift implementation should use `Decimal`, not `Double`, for
native quantities. Decimal strings use ordinary base-10 notation without an
exponent; signed values are preserved rather than clamped or silently rounded.

## Core metadata

### `ProviderSurface`

`ProviderSurface` is declarative registry metadata supplied by trusted app
code. It does not come from downloaded manifests in version 1.

```text
ProviderSurface
  providerID: StableID
  surfaceID: StableID
  displayName: String
  interactionModel: InteractionModel
  regions: [RegionDescriptor]
  accountContextKinds: [AccountContextKind]
  capabilities: [CapabilityID]
```

`providerID` identifies the service family. `surfaceID` is stable within that
provider and identifies the independently authenticated or billed offering.
`InteractionModel` initially supports `subscription`, `api`, `enterprise`,
`local`, and `manual`. New interaction models are additive minor-version work.

Each region has a stable `regionID` and display name. A region describes an
authentication, endpoint, policy, or billing boundary visible to account
configuration; it does not contain endpoint URLs. Endpoint selection remains
adapter code.

Capabilities are stable string IDs such as `quota-windows`, `credits`,
`balance`, `spend`, `reset-schedule`, `token-usage`, `requests`, `characters`,
`generations`, `images`, `media-minutes`, `compute-units`, `history`,
`session-usage`, and `per-turn-usage`. A surface or source lists only
capabilities it can actually provide. UI code must not infer unsupported
capabilities from provider identity.

### `SourceDescriptor`

```text
SourceDescriptor
  providerID: StableID
  surfaceID: StableID
  sourceID: StableID
  displayName: String
  kind: SourceKind
  authority: SourceAuthority
  maturity: SourceMaturity
  defaultConfidence: Confidence
  freshnessPolicy: FreshnessPolicy
  capabilities: [CapabilityID]
  authRequirement: AuthRequirement
```

Initial source kinds are `documented-remote-api`,
`documented-local-interface`, `standard-protocol`,
`isolated-authenticated-web`, `local-estimate`, `manual-provider-page`, and
`manual-input`. `SourceAuthority` is `provider-reported`,
`provider-documented`, `locally-observed`, `estimated`, or `manual`.

`SourceMaturity` is `stable` or `experimental`. Maturity is informational and
independent from success or severity: a valid experimental observation can be
`OK` and `live`.

`Confidence` retains the current meanings `live`, `delayed`, `local-estimate`,
`manual`, and `unknown`. A metric may override the source default when the same
source produces facts with different confidence.

`FreshnessPolicy` has one of these forms:

- `maximum-age` with a positive `maxAgeSeconds`;
- `source-expiry`, requiring each observation to supply `validUntil`;
- `manual`, which uses the application's manual-source staleness policy;
- `unknown`, which cannot claim freshness beyond `observedAt`.

Source selection, fallback order, refresh scheduling, and retry policy remain
adapter/application behavior and are observable through existing diagnostics.

### `AuthRequirement`

```text
AuthRequirement
  category: AuthCategory
  privilege: AuthPrivilege
  requiredScopes: [String]
  storageBoundary: CredentialStorageBoundary
```

Initial auth categories are `none`, `api-key`, `subscription-key`, `oauth`,
`external-cli-session`, `isolated-browser-session`, and `other`. Privilege is
`none`, `least-privilege`, or `elevated`. Storage boundaries are `none`,
`keychain`, `provider-managed-cli`, and `isolated-web-data-store`.

`requiredScopes` contains documented scope names or capability labels only. It
never contains a credential, token, cookie, opaque account identifier, or
provider response. Login, refresh, revocation, credential rotation, regional
endpoint selection, and error sanitization remain executable adapter code.
An elevated source is always separate and opt-in; it is never silently selected
as a fallback for a least-privilege source.

## Account snapshot envelope

The future account-level envelope is conceptually:

```text
CapacitySnapshot
  contractVersion: ContractVersion
  providerID: StableID
  surfaceID: StableID
  savedAccountID: StableID
  accountContexts: [AccountContext]
  observedAt: Instant
  metrics: [CapacityMetric]
```

`savedAccountID` is generated and owned by Bairometer. It is not an upstream
account, user, workspace, key, or tenant identifier.

### `AccountContext`

```text
AccountContext
  contextID: StableID
  kind: AccountContextKind
  displayName: String?
  regionID: StableID
  parentContextID: StableID?
```

Initial kinds are `personal`, `organization`, `workspace`, `project`, `team`,
`credential`, and `local-identity`. A context ID is local to the saved account.
Parent links form an acyclic tree, allowing a project, team, or credential
metric to remain distinct from its workspace or organization metric. The root
has no parent.

A `credential` context represents a locally configured credential-scoped pool,
such as one API key with its own spending cap and usage counters. Its context
ID and display name are app-owned. The upstream key, hash, owner ID, and other
opaque identifiers are not snapshot fields. A saved account may have several
credential contexts, each with an independent Keychain item, refresh result,
and diagnostic, while account-wide metrics remain attached to their shared
parent context.

Display names are optional, user-visible, and already sanitized or
user-configured. The model does not persist upstream opaque IDs. Every context
has an explicit region selected from its surface so region-specific endpoints,
credentials, and policies cannot become hidden adapter state.

Multiple independently authenticated or billed accounts have independent saved
account IDs, credential or browser-session boundaries, refresh lifecycles,
snapshots, and diagnostics. Several credentials intentionally grouped under one
saved billing account remain separate child contexts rather than pretending to
be several upstream accounts. A source tied to one active local identity
declares that limit and cannot represent several saved accounts.

## `CapacityMetric`

```text
CapacityMetric
  metricID: StableID
  accountContextID: StableID
  sourceID: StableID
  capability: CapabilityID
  displayName: String
  availability: CapacityAvailability
  conditions: [CapacityCondition]
  unit: CapacityUnit
  values: CapacityValues?
  window: CapacityWindow
  freshness: ObservationFreshness
  confidence: Confidence
  derivations: [Derivation]
```

`metricID` is provider-owned and stable within a product surface. It identifies
the semantic metric, not its current position in a response or UI. The tuple of
saved account, context, source, and metric IDs uniquely identifies an
observation.

### Native unit and values

`CapacityUnit.kind` initially supports `percent`, `currency`, `credits`,
`tokens`, `requests`, `characters`, `generations`, `images`, `media-minutes`,
`compute-units`, `time`, and `provider-defined`.

- `currency` requires a `currencyCode` of exactly three ASCII uppercase letters
  (`^[A-Z]{3}$`). This is structural validation only: the contract has no
  runtime or frozen currency registry and no currency-code/version coupling.
  Trusted provider adapters own semantic normalization of their native currency;
  OpenRouter native currency is `USD`.
- `time` requires a fixed duration unit such as `seconds` or `minutes`.
- `provider-defined` requires a stable namespaced `providerUnitID`; it adds a
  unit, not arbitrary fields or semantics.
- Other unit kinds have no qualifier.

`CapacityValues` has optional `consumed`, `remaining`, and `limit` roles. Each
value contains a decimal string and an origin of `reported` or `derived`. All
roles in one metric use the metric's native unit and refer to the same pool and
window.

Values are never clamped. A percentage or consumed quantity may exceed its
nominal limit. Missing is not zero. Currency values with different currency
codes, different provider credit systems, different windows, or different
account contexts are never combined.

### Availability and conditions

`CapacityAvailability` is one of:

- `known`: at least one native quantity is present;
- `unlimited`: no finite limit or remaining quantity is fabricated; a reported
  consumed quantity may still be present;
- `unavailable`: the source explicitly reports that the resource is not
  available for this context;
- `manual`: no machine-readable quantity is available and the user must consult
  or enter provider data;
- `unknown`: the adapter cannot establish the current state.

`unavailable`, `manual`, and `unknown` have no values. `CapacityCondition`
initially supports `overage` and `boost`. An overage remains a known native
value greater than a nominal limit; a boost preserves the provider-reported
expanded capacity. Neither condition changes values or clamps percentages.

### Windows and transitions

`CapacityWindow.kind` is `rolling`, `fixed`, `billing-cycle`, `lifetime`,
`none`, or `unknown`. A window may include `durationSeconds`, `startsAt`, and
`endsAt` when the source reports them.

The optional next transition has a `kind` of `reset`, `renew`, or `expire` and
an exact UTC `at` timestamp. A descriptive reset policy without an exact time
selects the appropriate window kind but does not invent a timestamp. A source
with no meaningful capacity window uses `none`, not an artificial billing
period.

### Freshness, provenance, and derivation

Every metric references a declared source and carries:

- `observedAt`, the instant the normalized fact was observed;
- optional `validUntil`, required by `source-expiry` freshness;
- actual confidence, which may differ from the source default.

These fields and the source descriptor answer where the fact came from, how
authoritative it is, whether it is experimental, and when it becomes stale.

Derived values are allowed only through explicit adapter-selected rules:

- `percent-complement` derives remaining percent from consumed percent;
- `consumed-from-limit-minus-remaining`;
- `remaining-from-limit-minus-consumed`;
- `utilization-from-consumed-and-limit` derives a separate percent
  presentation only when the adapter declares the native values compatible and
  the limit is non-zero.

Each derivation names its target role or presentation value and its inputs.
Derived outputs are tagged `derived`. The Core performs no implicit derivation
based only on field presence. A derived consumed or remaining quantity must
equal the rule's exact `Decimal` result. Version 1 has no derivation that
targets `limit`, so a limit cannot be tagged `derived`. Utilization may exceed
100 percent and is never persisted as a replacement for native values.

## Compatibility with the current application

The version 1 implementation preserves the current runtime API:

```swift
func fetchSnapshot(account: ProviderAccount) async throws -> UsageSnapshot
```

The OpenRouter transport exposes separate ordinary-current-key and elevated-
management-credits operations and accepts distinct redacted credential
wrappers constructed from a `CredentialSecret` only after validating the
`ProviderCredentialSlot` provider and role. Each wrapper privately retains the
slot's provider, account, context, slot identity, and persisted credential
revision; fetch operations accept no caller-supplied context ID, so normalized
metrics are bound to the credential's validated context. It returns Contract v1 USD metrics plus only
documented safe key metadata. It has fixed HTTPS endpoints, rejects redirects,
uses response/data delegate callbacks for bounded streaming, discards
non-success bodies, and does not provide a configurable URL, generic request
executor, `/api/v1/keys` inventory, or a percentage projection. Null or absent
key limits produce no limit metric; they never produce `unlimited`.

`OpenRouterProviderAdapter` registers the stable `openrouter-api` source mode
and delegates manual, scheduled, and launch refreshes to a hierarchical account
coordinator. The coordinator bounds one account to four concurrent credential
requests across overlapping refresh invocations, cancels superseded account
tasks, performs no same-refresh retries, persists `retryNotBefore` and bounded
backoff per slot, and replaces only the successful source/context metric set.
Different accounts retain independent limiters. Failures and deferrals preserve
the last valid source metrics.
Disable, delete, cancellation, and superseding refreshes suppress late results;
the native store verifies the enabled account, exact credential identity,
credential revision, and refresh generation on transaction entry and
immediately before commit. Its compatibility `UsageSnapshot` contains status
and timestamps only and never fabricates percentage usage. Only current-run
successes count as success: zero successes is an error even when last-valid
native metrics remain, while mixed success and failure is a warning.

Every account refresh ends with a lifecycle-locked conditional management
transaction. It re-reads current slot state rather than relying on the
pre-request source list. A still-enabled active management slot is a benign
no-op, preserving last-valid credits after a request failure. If the slot was
deleted or disabled in flight, the same refresh source-locally removes known
management credits and commits exactly one unavailable root sentinel after a
final generation check.

`CapacitySnapshot` is the portable account-level envelope for contract version,
surface/source references, account contexts, and capacity metrics.
`UsageSnapshot` and `UsageLimitWindow` remain the live compatibility path while
adapters, storage, dashboard presentation, thresholds, and CLI consumers
migrate. `LegacyUsageSnapshotBridge` performs the deterministic one-way
projection into contract v1. There is intentionally no reverse bridge that
could hide native currency, credit, token, request, generation, or media
metrics behind fabricated legacy percentages.

Contract decoding ignores additive unknown object members. An unknown required
metric discriminator drops only that metric and records a sanitized local
diagnostic containing an error code and field path; malformed required fields
still reject the snapshot. `ProviderContractValidator` checks version
compatibility, registry references, source capabilities, native-unit
invariants, freshness, derivations, and the locally identified acyclic
account-context tree without retaining rejected input.

Legacy projection rules are deterministic:

1. Each `UsageLimitWindow` with `usedPercent` becomes a `quota-windows` metric
   with unit `percent`, availability `known`, reported `consumed`, and optional
   `percent-complement` derivation. Its window ID becomes the stable metric ID.
2. If `limitWindows` is empty, the legacy top-level percentage fields produce a
   `primary` metric.
3. `resetAt` becomes the next `reset` transition. A duration or start time is
   not invented.
4. Snapshot confidence and source map to the matching source descriptor and
   metric confidence.
5. A legacy manual or unavailable snapshot maps to the matching availability
   without a numeric value. Free-form `remainingLabel` and warnings stay in the
   legacy presentation during the transition; they do not become native
   quantities.

The current dashboard continues to render only the compatible status
projection for OpenRouter. Native currency, credits, tokens, requests,
generations, and media metrics require a separate UI implementation decision;
they are never hidden behind fabricated progress meters.

## Persistence migration direction

Credential-context configuration and secret storage now have a platform-owned
foundation. Additive GRDB migration v6 stores account contexts, credential
slots, per-slot refresh state, and sanitized typed diagnostics. Each ordinary
slot attaches to one `credential` child context; the optional management slot
attaches to the account root and is constrained to one per saved account.
Contexts and slots use app-owned stable IDs. SQLite stores only display
configuration, role, enabled state, lifecycle state, and an opaque local
Keychain reference.

Every credential is a separate local, non-synchronizing generic password in the
macOS Data Protection Keychain. Every `SecItem` CRUD query sets
`kSecUseDataProtectionKeychain = true` and selects non-synchronizing items;
creation additionally uses
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Item queries omit an
explicit access group and use the provisioned application identifier as the
app's default private Keychain group. The raw value is represented by a
redacted wrapper and is returned only to trusted executable adapter code. It is
never part of context metadata, SQLite, `UserDefaults`, diagnostics, logs,
error text, or string descriptions. Disabled, missing, pending-creation, and
pending-deletion credentials fail with fixed typed errors.

Local DEBUG verification uses an Apple Development-signed app with an embedded
Xcode-managed Mac development provisioning profile that authorizes the exact
application identifier and default Keychain group. Personal Team profiles are
valid for seven days and are refreshed through Xcode automatic signing. The
caller supplies its team explicitly through `AILIMITBAR_DEVELOPMENT_TEAM`; no
developer Team ID is stored in the repository. Release staging requires a
caller-supplied Developer ID Application identity and matching Developer ID
provisioning profile, then validates the exact application identifier and
default Keychain group before signing with Hardened Runtime and a secure
timestamp. Notarization and stapling remain required before distribution.

SQLite and Keychain cannot participate in one atomic transaction, so lifecycle
states make their partial-failure boundary explicit. All operations for one
provider account are serialized by a process-wide per-account coordinator,
including when callers hold separate store instances:

1. Creation first inserts inaccessible `pending-creation` metadata, then creates
   the Keychain item, then activates the slot. A failure leaves the opaque
   reference in a row that can be retried or securely deleted.
2. Replacement increments the persisted credential revision, then uses
   `SecItemUpdate` on the existing item without changing its local reference.
   A request carrying the previous revision cannot commit after this boundary.
3. Deletion first marks the slot disabled and `pending-deletion`, then removes
   the Keychain item idempotently, then removes the metadata. A failure leaves a
   retryable inaccessible tombstone rather than an untracked item.
4. Account deletion marks every child slot pending before touching Keychain,
   removes each item, and deletes account metadata only after all items are
   absent. A retry treats an already missing item as cleaned. Generic account
   deletion rejects accounts that still own credential slots.

Existing provider accounts and snapshots are not rewritten or removed by v6.
They continue to load with no context rows until a credential-backed provider
configuration explicitly creates a validated local tree.

Additive GRDB migration v7 adds current native-capacity snapshot metadata and
normalized metric rows plus a defaulted credential revision on every existing
slot. The snapshot row stores Contract v1 version, surface, observation, and
completion metadata; each metric row is keyed by provider, saved account,
context, source, and metric ID. Its validated Contract model is encoded as
normalized JSON, which preserves `Decimal` values as canonical plain base-10
strings. A successful source commits its matching `(contextID, sourceID)` rows,
refresh state, and diagnostic clearing in one short transaction. A failed
source commits only failed refresh state, retry boundary, and sanitized
diagnostic in one transaction; deferred sources perform a validated read and
no mutation. Each outcome shares the credential lifecycle lock and revalidates
identity and generation before commit.

Migration v7 also extends each credential refresh state with completion time,
`retryNotBefore`, and consecutive failure count. It does not backfill legacy
percentage windows, add history, persist raw responses or credentials, or
remove legacy tables and columns. Existing legacy snapshots remain available
to all existing adapters. A failed, deferred, cancelled, stale-generation, or
invalid native refresh leaves the last valid native metric rows unchanged.
Backfilling legacy snapshots, native presentation for other providers, history,
and legacy-column removal require separate decisions.

## Portable Core and CLI mapping

`ProviderSurface`, `SourceDescriptor`, `AuthRequirement`, `AccountContext`,
`CapacityMetric`, version compatibility, and pure validation/derivation rules
belong to the future portable domain. Platform adapters own SQLite, Keychain,
process execution, filesystem locations, browser sessions, and provider
transport.

The future CLI reads normalized persisted snapshots through a repository
interface. It does not force provider refresh and does not silently degrade a
platform-specific source. A future stable `status --json` document may reuse
these semantics, but its wire format and public compatibility policy remain a
separate CLI/public-contract decision.

## Validation fixtures

Sanitized internal examples live in
[`docs/providers/contract-fixtures`](providers/contract-fixtures/README.md).
They validate the shared model against Codex, Claude, MiniMax Token Plan, and
OpenRouter without copying raw provider responses or adding provider-specific
shared fields. Passing a fixture demonstrates expressiveness only; it does not
approve or implement a source.

## Public-contract evidence gate

A public JSON Schema, SDK, conformance validator, fixture suite, provider
registry, or compatibility promise may be considered only in a new architecture
decision after all of these conditions hold:

1. The Codex, Claude, MiniMax, and OpenRouter research tracks are complete,
   including negative or limited decisions and multi-account constraints.
2. Every positively selected production adapter is implemented, persisted,
   rendered, privacy-reviewed, and verified with sanitized fixtures and
   integration coverage.
3. At least the percentage-window, native currency/credit, regional or
   multimodal, unavailable/unlimited, overage/boost, and privilege-separated
   authentication cases have passed without provider-specific fields in the
   shared model.
4. The legacy snapshot migration and portable Core/repository mapping are
   implemented and verified.
5. Contract diagnostics, fixtures, logs, and storage contain no credentials,
   tokens, cookies, browser data, raw responses, opaque account identifiers, or
   unredacted captures.

Meeting the gate only permits evaluation. It does not publish the internal
contract, freeze version 1, or create backward-compatibility obligations.

## Explicit non-goals

- A universal authentication or credential lifecycle engine.
- Declarative HTTP, endpoint selection, DOM scraping, parsing, or credential
  exchange.
- Arbitrary downloaded executable provider code.
- A universal percentage or exchange rate between incompatible native units.
- A public provider marketplace, registry, SDK, schema, or conformance program.
- Snapshot history, analytics, or a cross-platform GUI.
