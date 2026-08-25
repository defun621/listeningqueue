# SP-08 — Minimal Web UI

Status: Draft

## Objective

Provide a small, understandable browser interface for subscriptions, `Next`,
manual ordering, removal, playback, and operational feedback.

## User outcome

A self-hosted user can perform the complete v0.1 workflow from a browser without
editing the database or using the Racket REPL.

## In scope

- Subscription list, add, enable/disable, refresh, and remove operations
- `Next` list and manual move/remove operations
- Native browser audio controls backed by SP-07
- Playback progress and completion display
- Source refresh status and actionable errors
- Basic responsive layout and keyboard-accessible controls
- Safe same-origin mutation endpoints

## Out of scope

- Multiple users or roles
- Public registration
- Social, discovery, rating, or recommendation pages
- Playlist or multiple-queue UI
- Native mobile application
- A general administration console
- Visual workflow or policy builders

## Information architecture

The UI requires three primary views or clearly separated regions:

1. `Next`: ordered queue and current playback.
2. Subscriptions: source configuration and refresh status.
3. Settings/status: minimal runtime information needed for self-hosting.

Policy configuration may begin as programmatic Racket configuration. A policy
editor is not required for v0.1.

## Requirements

### WEB-001 — Next display

Display Items in authoritative queue order with title, source, useful duration
or publication metadata, progress, and current state. Empty and loading states
must be clear.

### WEB-002 — Manual ordering

Expose explicit move operations such as before/after or up/down. Drag-and-drop
may be added but cannot be the only accessible mechanism.

Send semantic move operations to the server rather than replacing the entire
queue from an old client snapshot. The server validates Item membership and
target membership atomically.

### WEB-003 — Remove

Removing from `Next` requires a clear action distinct from deleting the stored
Item. The UI must not imply that queue removal erases playback history.

### WEB-004 — Playback

The current player shows Item title, native or equivalent audio controls,
loading/resolution state, saved progress, completion, and retryable errors.
Starting playback does not change queue order.

### WEB-005 — Subscription management

Users can add a supported locator, choose a valid fixed refresh interval,
enable/disable the source, request a refresh, and remove the subscription
according to documented Item-retention behavior.

Display last successful pull, current/last error, and whether a pull is active.

### WEB-006 — Error presentation

Show plain-language errors with enough context to act, while keeping detailed
diagnostics in logs. Never render cookie paths, tokens, authorization headers,
or signed media URLs.

### WEB-007 — Concurrency

The server is authoritative. Stale browser actions must fail clearly or apply as
validated semantic operations; they must not overwrite newer queue order.

### WEB-008 — Security baseline

Use POST or another non-GET method for mutations, same-origin protections, CSRF
defense, safe output escaping, and bounded request bodies. Validate all source
URLs and numeric inputs server-side.

v0.1 has no account system. Default binding and deployment documentation must
not imply safe exposure to the public internet; SP-09 targets a trusted LAN or a
user-provided authenticated reverse proxy.

### WEB-009 — Accessibility

All core actions must be keyboard reachable, controls must have accessible
names, focus must remain understandable after queue changes, and status/errors
must not rely on color alone.

### WEB-010 — Simplicity

Prefer server-rendered HTML and small amounts of JavaScript unless a concrete UI
requirement proves a client framework necessary. Do not duplicate domain or
policy rules in browser code.

## HTTP/API boundary

Routes and payloads are implementation choices, but handlers must call domain
and repository operations rather than issuing ad hoc SQL. Mutation responses
must make the resulting authoritative state or redirect explicit.

## Testing

- Handler tests for every read and mutation path
- Output escaping and invalid-input tests
- Queue move/remove integration tests
- Stale move request behavior
- CSRF and wrong-method rejection
- Subscription validation and status display
- Playback progress/error rendering
- Keyboard/manual accessibility smoke test
- End-to-end browser smoke test for add feed, enqueue, reorder, and play

## Acceptance criteria

SP-08 is complete when:

1. A user can add and manage podcast, YouTube, and Bilibili subscriptions.
2. `Next` displays the persisted authoritative order.
3. Manual moves survive refresh and later automatic pulls.
4. A user can remove an entry without deleting playback history.
5. A user can play, pause, resume, and observe completion/progress.
6. Source and playback failures are understandable and secret-safe.
7. Core actions work with keyboard controls.
8. The UI does not expose a second queue or playlist concept.

## Dependencies and follow-ups

Builds on SP-01's minimal player and depends on SP-02 through SP-07 for durable
behavior. SP-09 packages and exposes the UI for self-hosting.
