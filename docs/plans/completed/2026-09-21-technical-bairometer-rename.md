# Technical Bairometer Rename

Date: 2026-09-21

## Outcome

Replace the repository and application technical identity with `Bairometer`
before external adoption. The product already has the public Bairometer name;
this plan removes the temporary former-name compatibility layer instead of
preserving a migration path that is not needed without real users.

## Naming contract

- Swift package, products, targets, modules, source and test directories:
  `Bairometer`.
- Bundle identifier: `io.github.Prontsevich.Bairometer`.
- Application Support data: `Bairometer/Bairometer.sqlite`.
- Keychain service: `io.github.Prontsevich.Bairometer.credentials`.
- Claude Code helper: `BairometerClaudeStatusLine`.
- Build, signing and CI variables: `BAIROMETER_`.
- GitHub repository target: `Prontsevich/bairometer`.

## Scope and non-goals

The work includes every tracked technical reference in source, tests, scripts,
local signing support, GitHub workflows, living documentation, and the local
Git remote. The GitHub repository rename is a separately verified external
unit. No domain purchase, handle reservation, trademark work, public
announcement, release publication, or pre-rename data/Keychain migration is
included.

## Ordered work

- [x] Rename the Swift package family, source/test paths and module imports.
  `swift build` and `swift test` passed.
- [x] Rename local app identities: bundle and Keychain identifiers, storage,
  database, helper, process isolation, test-host names, and diagnostic flags.
  The existing focused test coverage passed under the renamed modules.
- [x] Rename staging, signing, packaging, notarization and workflow contracts,
  including the local signing project and release fixtures. Release-workflow,
  draft-publication and notarization fixtures passed.
- [x] Reconcile living documentation and validate no modifiable tracked former
  technical-name reference remains. GitHub was renamed to
  `Prontsevich/bairometer`; the local remote and redirect were verified.

## Verification

- `swift build`
- `swift test`
- relevant shell-script test suites
- `./script/build_and_run.sh --verify`
- staged-bundle inspection for executable, helper and bundle identifier
- GitHub redirect and updated local remote after the external rename

## Execution note

Linear returned a temporary 502 while this plan was created; after recovery,
the fallback entry was reconciled into the Technical Bairometer rename Project
and removed.

## Execution evidence — 2026-09-21

- `swift build` passed.
- `swift test` passed: 191 XCTest tests, 0 failures.
- `script/test_release_workflow.sh`, `script/test_publish_release_workflow.sh`
  and `script/test_notarize_release.sh` passed.
- `git diff --check` passed; former-name search is clean outside read-only
  Codex harness metadata.
- The GitHub repository rename, old-URL redirect and new `origin` URL were
  verified.

## Completion evidence — 2026-09-22

- Registered the explicit `io.github.Prontsevich.Bairometer` App ID and a macOS
  development profile in Apple Developer.
- `BAIROMETER_DEVELOPMENT_TEAM=... ./script/build_and_run.sh --verify` passed,
  including the deterministic smoke test and Launch Services startup check.
- The staged app has the Bairometer display name and bundle identifier, contains
  `BairometerClaudeStatusLine`, and passed strict code-signature verification.
- The staging validation now correctly accepts a wildcard development profile
  when its signed app entitlement remains the exact Bairometer identifier.
