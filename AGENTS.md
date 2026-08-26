# AGENTS.md

This file contains repository-wide guidance for coding agents and contributors.
It applies to every file in this repository unless a more specific `AGENTS.md`
exists in a subdirectory.

## Project

ListenQueue is a self-hosted listening inbox written primarily in Racket. It
periodically pulls podcast and video sources, normalizes discovered entries,
applies admission and initial-placement policies, and maintains exactly one
ordered playback queue named `Next`.

Read `spec.md` before making architectural or product decisions. It is the
source of truth for v0.1 behavior. If code, documentation, and the specification
disagree, call out the mismatch rather than silently changing semantics.

Before implementing a work area, also read its specification under
`docs/specs/`. These documents refine scope, requirements, tests, and acceptance
criteria for each subproject. They never override `spec.md`.

## Non-negotiable invariants

- There is exactly one playback queue: `Next`.
- Automatic placement is insertion-time behavior, never continuous sorting.
- Never reorder existing `Next` entries during a pull or policy evaluation.
- A user's manual queue order is authoritative.
- An item may appear at most once in `Next`.
- Pulling the same external entry repeatedly must not duplicate an item.
- Deleting an item locally must not make it unseen; retain seen/tombstone state
  so upstream entries do not resurrect automatically.
- A failed source pull must not advance persisted source state.
- A source must never be pulled concurrently with itself.
- Provider-specific data belongs at extension boundaries or in namespaced item
  attributes, not in an ever-growing core item structure.
- Extensions add integrations and domain vocabulary. They do not own runtime
  scheduling, enqueue items directly, or introduce arbitrary control flow.
- Do not create a generic pipeline, workflow engine, DAG, or `PipelineStage`
  abstraction.
- Do not hard-code language-specific or provider-specific placement policy into
  the core.
- Normal source refresh is metadata-oriented and must not eagerly download or
  transcode media.

## Runtime model

The incoming lifecycle is fixed:

```text
due source
  -> extension pull
  -> normalize external entries
  -> deduplicate / seen lookup
  -> persist new Item
  -> admission policy
  -> placement policy (accepted items only)
  -> insert into Next
```

The maintenance lifecycle is also fixed:

```text
stored Items
  -> retention predicates
  -> matching retention action
```

Configuration may supply predicates and actions within these slots; it may not
replace the lifecycle with user-defined orchestration.

## Scope and implementation order

Build the smallest vertical slice that proves the current milestone. Follow the
milestone order in `spec.md` unless the task explicitly requires otherwise:

1. An end-to-end podcast slice: RSS to `Next` to audible playback, including
   only the minimal domain and local player needed to prove it.
2. SQLite persistence, including seen history and stable queue order.
3. Podcast subscriptions, scheduling, and broader RSS/Atom polling behavior.
4. `yt-dlp` video-source support.
5. Reusable admission, placement, and retention predicates.
6. Retention and tombstone behavior.
7. Playback progress and playback hardening.
8. Minimal web UI.
9. DSL exploration only after ordinary Racket APIs stabilize.

Do not implement v0.1 non-goals opportunistically. In particular, avoid
multiple queues, playlists, multi-user support, social/discovery features,
distributed infrastructure, AI features, a plugin marketplace, or
`#lang listenqueue`.

## Racket design guidelines

- Prefer idiomatic Racket structs, functions, modules, and contracts or explicit
  validation where useful.
- Prefer ordinary data and functions over classes, macros, or framework-like
  abstractions.
- Do not imitate Java, Scala, Rust, or Haskell architecture mechanically.
- Keep pure domain logic separate from subprocess, network, clock, filesystem,
  and database effects.
- Keep queue operations pure wherever practical.
- Use immutable values by default; introduce mutation only at a clearly owned
  state boundary.
- Use transparent structs for domain values when inspection and testing benefit.
- Validate untrusted data at boundaries before constructing domain values.
- Keep modules focused, with narrow `provide` lists rather than exporting every
  internal definition.
- Explain non-obvious Racket techniques in code comments, but do not narrate
  straightforward code.
- Add macros only when repeated, stable domain syntax demonstrates a real need.

The module layout proposed in `spec.md` is provisional. Preserve conceptual
boundaries, but prefer a simpler layout when implementation evidence supports
it.

## Domain and policy rules

### Items and sources

- Normalize external representations before core policy evaluation.
- Prefer `(source-id, external-id)` as discovered-item identity.
- Keep `media-ref` opaque to core domain logic.
- Store platform-specific metadata in namespaced attributes such as
  `'yt-dlp:extractor` or `'bilibili:bvid`.
- Treat extension-owned source state as opaque in the core.

### Next

Implement and test queue changes as explicit operations such as add, insert,
remove, move, and pop. Placement of a new item may inspect the current queue to
choose an insertion point, but it must preserve the relative order of all
existing entries.

Never implement placement as:

```text
sort(all-next-items, placement-policy)
```

### Policies

- Admission decides accept or reject; it does not determine queue order.
- Placement runs exactly once when a newly accepted item enters `Next`.
- Retention selects already-known items and applies an explicit action.
- Make evaluation deterministic and document rule precedence.
- Reuse predicate vocabulary across admission, placement, and retention instead
  of creating separate condition systems.
- Keep extension-provided predicates pure whenever possible.
- Implement only the smallest useful set of placement and retention actions.

## Effects and integrations

### `yt-dlp`

- Invoke `yt-dlp` as an external subprocess; do not import its Python internals.
- Request and parse machine-readable JSON.
- Treat exit status, stdout, stderr, and decoded JSON as untrusted input.
- Avoid logging cookies, tokens, request headers, or other credentials.
- Prefer metadata-only enumeration during pulls and resolve playable media on
  demand.

### Persistence

- Use SQLite; do not introduce an external database or service.
- Keep all persistent state under one configurable data directory.
- Make writes that combine item creation, seen state, and queue insertion
  transactional where partial state would violate invariants.
- Preserve `Next` order explicitly and stably across restarts.
- Keep playback history independent of queue membership.
- Test migrations and repository behavior against a temporary database.

### Scheduling and errors

- Use simple fixed refresh intervals for v0.1; cron is unnecessary.
- Isolate failures so one bad source or item does not crash the long-running
  runtime or block unrelated sources.
- Include source, extension, operation, and underlying cause in errors.
- Prefer explicit, inspectable error handling over speculative retry systems.
- Never expose secrets in errors or logs.

## Testing

### Behavior contract and harness first

Before writing production implementation for any behavior, first create or
update its Gherkin-style behavior contract under `features/`, then create and run
a small harness for that behavior. The required sequence is:

```text
feature scenario -> harness -> observed failure -> implementation -> passing harness
```

Feature scenarios are normative examples that refine the relevant subproject
specification. They do not override `spec.md` or `docs/specs/`. If these layers
conflict, stop and resolve the specification instead of encoding the conflict in
a test.

Each scenario must:

- use `Feature`, optional `Rule`, `Scenario` or `Scenario Outline`, and
  `Given`/`When`/`Then` structure;
- describe externally observable behavior rather than private functions, SQL,
  or control flow, unless that implementation boundary is itself the specified
  subject;
- carry one globally unique scenario ID such as `@SC-POD-001`;
- carry tags for its subproject and requirement, such as `@SP-01 @POD-002`;
- use one primary action in `When` and concrete, verifiable outcomes in `Then`;
- state enough preconditions to run deterministically;
- carry exactly one automation tag: `@automated` by default or `@manual` when
  human observation is unavoidable;
- use `@live`, `@slow`, or `@container` as additional environment tags when
  needed;
- carry `@pending` while behavior is specified but implementation work has not
  started; remove `@pending` when its harness is created, before production
  implementation.

The corresponding harness must reference the scenario ID in its test name or
registered metadata so reviewers and the traceability check can connect contract
to executable evidence. Include requirement tags nearby when useful. One
harness may cover multiple closely related scenarios, but every implemented
scenario needs evidence.

Use plain RackUnit as the default Racket harness runner. A test should be named
like `[SC-POD-001] loading the same GUID episode twice creates one item`.
`.feature` files are not executed directly at first. A lightweight repository
check validates scenario tags, uniqueness, and harness mappings; do not build a
full Gherkin parser, step registry, or Cucumber clone without demonstrated need.

A harness is an executable feedback loop that drives the intended public
boundary and makes missing or incorrect behavior visible. It may be a focused
RackUnit test module, a fixture-driven integration test, a temporary-database
runner, a fake-clock scheduler test, a fake-subprocess driver, or a
browser/container smoke test, depending on the boundary.

The harness must:

- exist before the implementation it drives;
- encode the relevant acceptance criterion or architectural invariant;
- fail, report missing behavior, or otherwise demonstrate that it can detect the
  unimplemented/broken state before implementation begins;
- be deterministic and offline by default, using fixtures or fakes for network,
  clock, subprocess, and similar effects;
- exercise public/domain boundaries rather than duplicate the implementation;
- remain in the repository as a regression test or documented smoke harness;
- have an exact, verified command for running it.

Live-network, real-browser, and container harnesses may be opt-in, but they do
not replace the default deterministic harness. For a bug fix, first add or
extend a feature scenario, then make its harness reproduce the bug, then
implement the fix.

### Human milestone gate

Automated success is necessary but not sufficient to complete a milestone.
Before asking for human acceptance, create a scoped milestone-candidate commit
and ensure the worktree is clean. The candidate commit includes production code,
feature scenarios, harnesses, fixtures, migrations, configuration examples, and
the exact acceptance instructions needed to test that revision. It never
includes runtime data, logs, temporary databases, downloaded media, or secrets.

Then follow `docs/manual-acceptance.md` and stop at the milestone boundary.
Provide the user with the candidate commit hash, exact verified commands,
setup/cleanup instructions, expected observable results, known limitations, and
a short result template. The user must test that revision and explicitly
approve it.

After approval, create a separate acceptance-record commit that names the tested
candidate hash and reported environment/evidence. Only then may production work
begin on the next milestone. If code or acceptance-relevant configuration
changes after testing, create a new candidate; previous approval does not apply
to the new revision.

Until that approval arrives:

- do not mark the milestone complete;
- do not claim its user outcome is accepted;
- do not begin production implementation for the next milestone;
- keep later feature scenarios `@pending`.

Reported failures become new or updated feature scenarios before fixes are
implemented.

Every behavior change must include focused tests at the lowest useful layer.
Architectural invariants deserve direct tests, especially:

- add/insert/remove/move/pop preserve uniqueness and do not lose items;
- manual ordering survives later automatic insertions;
- placement preserves the relative order of existing entries;
- repeated pulls are idempotent;
- deleted items remain seen and do not resurrect;
- failed pulls do not persist advanced source state;
- source pulls cannot overlap for the same source;
- policy evaluation is deterministic;
- malformed feeds and `yt-dlp` output fail safely;
- queue order and playback state survive persistence round trips.

Use deterministic fixtures and injected clocks where time affects behavior.
Avoid live-network tests in the default suite. Wrap subprocess and network
boundaries so unit tests can use fixtures or fakes; keep a smaller opt-in
integration suite for real tools.

The established test commands are:

```bash
raco test <test-paths>
raco test -x .
```

No formatter command is established yet. Add and verify one before documenting
it as required tooling.

Do not claim a check passed unless it was actually run. If a required executable
such as Racket, `yt-dlp`, or `ffmpeg` is unavailable, report that limitation and
run all remaining checks.

## Working practices

1. Inspect the relevant code, tests, `spec.md`, and subproject spec before
   editing.
2. Write or update the Gherkin-style feature scenario for the behavior.
3. Write and run the smallest useful harness before production implementation.
4. Confirm the harness detects the missing or broken behavior for the expected
   reason.
5. Keep changes scoped to the requested behavior and current milestone.
6. Preserve unrelated user changes in a dirty worktree.
7. Implement only enough behavior to satisfy the scenario, harness, and
   specification.
8. Run the formatter and the narrowest relevant tests, then broader tests when
   practical.
9. Update documentation when public configuration or behavior changes.
10. At a milestone boundary, create and verify a scoped candidate commit with a
    clean worktree.
11. Give the user that commit hash and the manual acceptance procedure; wait for
    explicit approval.
12. Record approval in a separate commit before starting the next milestone.
13. In the handoff, summarize scenarios, harnesses, behavior changed, checks
    run, manual acceptance status, and any known gaps or decisions still open in
    `spec.md`.

Do not silently resolve an open product question from `spec.md` by creating a
large abstraction. Choose the smallest reversible behavior needed for the task,
document the assumption, and keep the design easy to change.

## Definition of done

A change is complete when it:

- satisfies the requested behavior and relevant acceptance criteria;
- has traceable Gherkin-style scenarios under `features/`;
- was driven by a runnable harness that remains available for regression use;
- preserves every applicable invariant above;
- keeps external effects behind explicit boundaries;
- includes focused tests for new behavior and regressions;
- passes applicable formatting and test checks;
- introduces no unnecessary provider coupling or workflow machinery; and
- leaves configuration and documentation consistent with the implementation.

A milestone additionally requires explicit user confirmation that its manual
acceptance procedure passed against a named candidate commit, followed by a
separate acceptance-record commit.
