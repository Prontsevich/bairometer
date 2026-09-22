# Contributing to Bairometer

Bairometer is both the public product name and the technical identity for the
package, executables, app bundle, archive names, storage, signing, and
repository. Keep those names aligned when changing a related contract.

## Build & Test

**Requirements:** macOS 15+, Xcode 26+ (Swift 6.2)

```zsh
swift build                                           # Build all targets
swift test                                            # Run full test suite
BAIROMETER_DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  ./script/build_and_run.sh                           # Stage DEBUG .app and launch
```

### Run Modes

| Mode | Description |
| --- | --- |
| `--verify` | Deterministic integration smoke + staged Launch Services startup check |
| `--debug` | Attach LLDB to the staged bundle |
| `--logs` | Show live app logs |
| `--telemetry` | Enable telemetry output |

The run script builds the SwiftPM product and stages the DEBUG `.app` bundle in
`dist/`. DEBUG staging requires the caller's explicit
`BAIROMETER_DEVELOPMENT_TEAM`; Xcode automatic signing selects an installed
Apple Development identity and an Xcode-managed provisioning profile that
authorizes the restricted application-identifier and default Keychain-group
entitlements. `--verify` first runs the deterministic app-layer integration
test, then launches the staged bundle through Launch Services with disposable
storage, verifies startup stability, and terminates only the process created by
that check. The staged bundle remains in `dist/` for manual QA. Interactive
menu-bar, Settings, focus, and pointer checks are not inferred from the process
check and must be performed manually.

## Release Packaging

Create locally validated architecture-specific release archives:

```zsh
export BAIROMETER_DEVELOPMENT_TEAM=YOUR_TEAM_ID
export BAIROMETER_DEVELOPER_IDENTITY="Developer ID Application: YOUR_NAME (YOUR_TEAM_ID)"
export BAIROMETER_PROVISIONING_PROFILE=/private/path/Bairometer.provisionprofile
./script/package_release.sh 0.2.0 20260813.1 arm64
./script/package_release.sh 0.2.0 20260813.1 x86_64
```

Release staging fails closed unless the selected Developer ID identity matches
the single certificate in the supplied Developer ID provisioning profile. It
signs the bundled helper and outer app with Hardened Runtime and secure
timestamps, embeds the profile that authorizes the app's default Keychain
group, and revalidates the signature after the ZIP round trip. The identity,
profile, private key, and Team ID stay outside the repository. These direct
`package_release.sh` outputs are signing-only artifacts and must not be
distributed without notarization.

For a local notarized release, first create a private `notarytool` Keychain
profile outside the repository, then provide its caller-owned name. If the
profile lives in an isolated file-based Keychain, also provide that Keychain's
path:

```zsh
export BAIROMETER_NOTARYTOOL_PROFILE=YOUR_NOTARYTOOL_PROFILE
# Optional for an isolated file-based Keychain:
export BAIROMETER_NOTARYTOOL_KEYCHAIN=/private/path/release.keychain-db
./script/notarize_release.sh 0.2.0 20260813.1 arm64
./script/notarize_release.sh 0.2.0 20260813.1 x86_64
```

The wrapper creates `Bairometer-<version>-<architecture>-signed.zip` for the
Apple submission, waits for an `Accepted` result, staples the app extracted
from that exact submitted ZIP, and only then creates the final
`Bairometer-<version>-<architecture>.zip`. Both the stapled app and a fresh
extraction of the final ZIP must pass exact bundle, architecture, entitlement,
signature, stapler-ticket, and Gatekeeper validation. On failure, the command
prints only the submission ID/status and a private temporary path plus a safe
`notarytool log` command; it does not dump Apple's full log. Keychain profile
values, Apple credentials, app-specific passwords, API keys, and notarization
logs remain outside Git and public logs.

The `Release` GitHub Actions workflow is manual-only and produces workflow
artifacts; it does not respond to tags or create a GitHub Release. Before using
it, repository administrators must configure the `protected-release` GitHub
Environment with required reviewers, restrict deployment branches to `main`,
and prevent unreviewed access to its secrets. The `main` branch itself must be
protected because the workflow rejects any other or unprotected ref before the
credential jobs start.

The Environment supplies these required secrets without storing values in the
repository:

- `DEVELOPER_ID_P12_BASE64`
- `DEVELOPER_ID_P12_PASSWORD`
- `DEVELOPER_ID_PROVISIONING_PROFILE_BASE64`
- `NOTARYTOOL_APPLE_ID`
- `NOTARYTOOL_TEAM_ID`
- `NOTARYTOOL_PASSWORD`

Each architecture job checks the complete secret set before decoding or
building, imports the P12 into an ephemeral file-based Keychain, derives the
matching Developer ID identity from the provisioning profile certificate, and
creates a temporary validated `notarytool` profile in that exact Keychain. The
existing notarization pipeline runs on `macos-15` for `arm64` and
`macos-15-intel` for `x86_64`. A separate extraction and trust-validation pass
must succeed before the architecture-specific ZIP is uploaded for three days.
An invocation-specific ownership marker prevents collision failures from
removing pre-existing paths. Success and failure paths delete only their owned
temporary Keychain, decoded material, and private diagnostics, and cleanup must
succeed before upload. Workflow artifacts remain protected validation outputs.

After a successful validation run, dispatch `Publish Draft Release` from the
protected `main` branch with the same version, build number, and validation run
ID. It verifies that exact successful validation, creates an annotated tag, and
attaches both validated archives to a GitHub draft with bilingual notes and
SHA-256 checksums. Review the draft, its notes, and its assets before manually
publishing it. Tag-triggered publication remains disabled.

## Architecture

See [`AGENTS.md`](AGENTS.md) for the full architecture guide: target layout,
layer responsibilities, key patterns, and working agreements.

## Documentation

- [`docs/plan.md`](docs/plan.md) — Product plan, provider research, architecture decisions
- [`docs/tasks.md`](docs/tasks.md) — Completed milestone scope, acceptance, and
  verification history; active work lives in Linear
- [`docs/backlog.md`](docs/backlog.md) — Fallback intake and pending
  synchronization only when Linear is unavailable
- [`docs/dashboard-design.md`](docs/dashboard-design.md) — Terminal-fieldset dashboard design contract
- [`docs/settings-design.md`](docs/settings-design.md) — Settings window lifecycle and visual contract
- [`docs/design-qa.md`](docs/design-qa.md) — Dashboard visual QA findings and fixes
- [`docs/providers/`](docs/providers/) — Per-provider implementation notes

## Commit Conventions

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(scope): description
docs(scope): description
fix(scope): description
refactor(scope): description
style(scope): description
build(scope): description
```

Common scopes: `storage`, `codex`, `dashboard`, `ollama`, `claude`, `settings`,
`roadmap`, `readme`, `core`, `app`, `ui`, `dev`, `mvp`, `project`.
