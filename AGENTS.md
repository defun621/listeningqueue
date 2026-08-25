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

1. Domain values and pure `Next` operations.
2. `yt-dlp` subprocess/JSON vertical slice.
3. SQLite persistence, including seen history and stable queue order.
4. Pull subscriptions and scheduling.
5. RSS/podcast support.
6. Reusable admission, placement, and retention predicates.
7. Retention and tombstone behavior.
8. Media resolution and playback progress.
9. Minimal web UI.
10. DSL exploration only after ordinary Racket APIs stabilize.

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

The repository has not established final commands yet. Once the package and
test layout exist, prefer standard Racket tooling and keep this section updated.
Typical checks are:

```bash
raco fmt --check <changed-racket-files>
raco test <test-paths>
raco test -x .
```

Do not claim a check passed unless it was actually run. If a required executable
such as Racket, `yt-dlp`, or `ffmpeg` is unavailable, report that limitation and
run all remaining checks.

## Working practices

1. Inspect the relevant code, tests, and `spec.md` section before editing.
2. Keep changes scoped to the requested behavior and current milestone.
3. Preserve unrelated user changes in a dirty worktree.
4. Add or update tests alongside implementation changes.
5. Run the formatter and the narrowest relevant tests, then broader tests when
   practical.
6. Update documentation when public configuration or behavior changes.
7. In the handoff, summarize behavior changed, checks run, and any known gaps or
   decisions still open in `spec.md`.

Do not silently resolve an open product question from `spec.md` by creating a
large abstraction. Choose the smallest reversible behavior needed for the task,
document the assumption, and keep the design easy to change.

## Definition of done

A change is complete when it:

- satisfies the requested behavior and relevant acceptance criteria;
- preserves every applicable invariant above;
- keeps external effects behind explicit boundaries;
- includes focused tests for new behavior and regressions;
- passes applicable formatting and test checks;
- introduces no unnecessary provider coupling or workflow machinery; and
- leaves configuration and documentation consistent with the implementation.
