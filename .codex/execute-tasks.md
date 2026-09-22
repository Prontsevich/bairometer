# Bairometer Execute Tasks Adapter

Use this adapter with the global `execute-tasks` skill in the Bairometer
repository. The global skill owns orchestration; this file defines
repository-specific task sources, task boundaries, lifecycle, review,
verification, and commit policy.

## Task sources

Active strategy, priority, project documents, Issue acceptance, and lifecycle
live in private Linear. `docs/tasks.md` is completed-history evidence, not a
live tracker.

When Linear is connected:

1. Use Team `Development` and the `Bairometer` product Initiative, then read
   `Development — Working Guide`.
2. Read the relevant finite Project document, or confirm that standalone work
   belongs in `Improvements & Fixes`.
3. Read the selected Issue and only the linked design or provider documents
   needed for its acceptance criteria.
4. Do not select work directly from `Triage`, and do not select gated work
   merely because its Project exists.

New ideas, reports, observations, and agent-discovered concerns enter `Triage`
cheaply. Search before creating or shaping work. Each shaped Issue has exactly
one Type: `Bug`, `Gap`, `Feature`, `Improvement`, `Refactor`, `Research`, or
`Chore`. Views are navigation aids, not another planning hierarchy. A finite
Project groups a coherent multi-Issue outcome; `Improvements & Fixes` holds
ordinary standalone work.

When Linear is unavailable, use `docs/backlog.md` for intake and necessary
pending synchronization, explicitly marked pending. Reconcile and retire
temporary entries after access returns; do not maintain a parallel live tracker
while Linear is available.

Accept a Linear issue, an approved repository plan, or an explicit user task
list. Never copy private Linear identifiers or URLs into branches, commits,
public GitHub issues, or pull requests.

## Bound work units

A Linear issue or plan phase is a task source, not automatically one worker
invocation. Before dispatching the first worker, decompose the selected scope
into ordered, independently reviewable work units and show the batch map.

Each work unit must have:

- One coherent outcome and one acceptance-criteria subset.
- An explicit allowed write scope and out-of-scope boundary.
- A verification result that is meaningful before later units start.
- A diff small enough for a complete defect-first review.

Split work that crosses independently shippable storage, provider, app
orchestration, and UI concerns. Keep a tightly coupled vertical slice together
when splitting would create an unverifiable intermediate state. If a worker
discovers materially wider scope, stop that unit and re-bound it before editing
the additional area.

## Execution modes

Support both global execution modes:

- `interactive` is the default. Pause at each verified task's commit gate.
- `autopilot` requires explicit user opt-in. Continue through implementation,
  review, fixes, automated verification, per-task commits, and tracker
  transitions without waiting for approval at each commit.

In `autopilot`, announce every proposed commit message and exact staged paths
before creating the commit, but do not pause for confirmation. Never push,
create a pull request, perform destructive Git operations, claim a manual
check, or broaden product scope without separate authorization.

Manual-only acceptance criteria do not prevent an otherwise verified task from
being committed and moved to `In Review`; they do prevent `Done`. Stop
`autopilot` only when a blocker requires a user decision or new authority, when
task-owned and pre-existing changes overlap unsafely, or when required
verification cannot be completed after a bounded fix cycle.

## Linear lifecycle

The parent orchestrator owns all status transitions:

| Event | Status |
| --- | --- |
| A selected work unit begins implementation | `In Progress` |
| Independent review and automated verification pass, and a durable review artifact exists | `In Review` |
| Review, verification, or commit is incomplete or blocked | keep `In Progress` |
| Every acceptance criterion, including required manual verification, is complete | `Done` only when appropriate for the issue workflow |

A durable review artifact is a task commit or an explicitly user-requested
working-tree review. Never mark an Issue `Done` merely because code was written
or a technical checklist was completed. Confirm its observable acceptance and
required verification.

Read the actual evidence and dependencies for a gate before starting its
blocked scope. Historical Apple Developer Program membership evidence does not
itself satisfy downstream signing, notarization, protected-CI, clean-Mac, or
release acceptance requirements.

## Worker and review visibility

Before every worker or reviewer starts, report:

- Work-unit name and batch position.
- Agent role.
- Requested model and reasoning effort.
- Why that routing matches the risk.
- Allowed scope and expected verification.

After every worker finishes, summarize its outcome, acceptance-criteria
coverage, changed files, commands and real results, deviations, and residual
risks. Do not reduce the worker result to a generic completion sentence.

For every non-trivial Swift code unit, dispatch a fresh read-only reviewer after
the implementation worker. The parent must also inspect the complete diff and
affected call sites. Publish a review verdict of `PASS`, `CHANGES_REQUIRED`, or
`BLOCKED`, followed by actionable findings or the explicit statement that no
task-introduced actionable findings were found. A worker's self-review is not
the independent review.

## Working-tree safety and exploration

Preserve all pre-existing changes. Bairometer frequently has active
uncommitted research or implementation artifacts; do not stage, rewrite, or
delete them unless the selected work unit explicitly owns those paths.

Run targeted `graphify query "<SymbolOrPath>"` calls before broad source reads.
After code changes, run `graphify update` from the repository root when
`graphify-out/` exists.

Treat live code and `Package.swift` as implementation truth, `docs/plan.md` as
the current architecture and settled public-contract record, and linked
provider or design documents as task-specific contracts.

## Verification

For every Swift code change, the parent independently runs:

```zsh
swift build
swift test
```

Add proportionate checks:

- UI, lifecycle, or provider integration: use the staged app bundle through
  `./script/build_and_run.sh` and its relevant `--verify`, `--debug`, `--logs`,
  or `--telemetry` mode.
- App-owned dashboard or Settings accessibility and visual behavior: use
  `./script/build_and_run.sh --ui-test-host <scenario>` and follow
  `docs/ui-test-host.md`.
- Production status item, `NSPopover` anchoring, `LSUIElement`
  activation/Spaces, OAuth/WebKit, and real providers: retain their Swift-test,
  telemetry, staged-app, or explicit manual verification paths.

Direct UI automation cannot inspect the production `LSUIElement` app. Do not
retry it. Never claim a manual check that was not performed.

The task report must list worker checks, parent checks, reviewer verdict, and
manual checks separately so independent verification is visible.

## Architecture and privacy stops

Apply every architecture and product constraint in `AGENTS.md`. In particular,
stop rather than improvise if work would weaken credential isolation, persist
raw provider data, break multi-account boundaries, add an external dependency,
change the menu-bar-only lifecycle, or edit
`.codex/environments/environment.toml`.

## Commits

Use English Conventional Commits and one coherent work unit per commit. Common
scopes include `storage`, `codex`, `dashboard`, `ollama`, `claude`, `settings`,
`roadmap`, `readme`, `core`, `app`, `ui`, `dev`, `mvp`, and `project`.

Stage only explicit task-owned paths. Never include unrelated dirty files,
private Linear identifiers, or private Linear URLs.
