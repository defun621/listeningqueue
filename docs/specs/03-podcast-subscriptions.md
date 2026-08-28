# SP-03 — Podcast Subscriptions

Status: Draft

## Objective

Turn one-shot podcast feed loading into durable, periodically refreshed
subscriptions that discover new episodes safely and without duplication.

## User outcome

A user adds a podcast once. ListenQueue keeps checking it at the configured
fixed interval and admits newly published episodes without manual refresh.

## In scope

- Durable Source model and enabled/disabled state
- RSS 2.0 and practical Atom feed support
- Fixed refresh intervals
- Runtime scheduling and per-source exclusion
- Conditional HTTP using ETag and Last-Modified where available
- External-entry normalization and deduplication
- Durable extension-owned source state
- Failure isolation and contextual status/error reporting

## Out of scope

- Cron expressions
- User-defined scheduling graphs
- Distributed scheduling or multiple application processes
- Arbitrary retry workflows
- Video-source enumeration
- Authenticated/private podcast feeds unless a concrete v0.1 requirement is
  added

## Source model

A subscription must represent at least:

- internal source ID
- source-extension ID (`rss`)
- feed locator
- fixed refresh interval
- extension-owned refresh state
- enabled/disabled flag
- enough runtime metadata to determine when it is due

The core stores extension state but does not interpret feed-specific fields.

## Requirements

### SUB-001 — Add subscription

Adding a feed validates its HTTP(S) locator and performs enough discovery to
confirm that it is a supported feed. Adding the same normalized locator twice
must have deterministic behavior: either return the existing subscription or a
clear duplicate error.

### SUB-002 — Fixed intervals

Support simple positive intervals such as 30 minutes, one hour, or two hours.
Reject zero, negative, or unreasonably small values according to documented
runtime limits.

### SUB-003 — Due-source scheduling

The runtime determines when a source is due. Disabled sources are skipped. The
scheduler must not rely on a source extension to schedule itself.

### SUB-004 — Per-source exclusion

At most one pull for a given source may be active at a time. A slow source must
not prevent unrelated due sources from running, subject to a small runtime-wide
concurrency limit if one is introduced.

### SUB-005 — Pull contract

The RSS extension consumes a Source and previous opaque state and returns
external entries plus candidate next state. It must not persist Items, evaluate
policies, or enqueue directly.

### SUB-006 — Conditional requests

Persist and send ETag and Last-Modified values when servers provide them. A
not-modified response is a successful pull with no new entries and may update
appropriate refresh timestamps without inventing new content.

### SUB-007 — Ingestion

Normalize provider data before policy evaluation. Check `(source-id,
external-id)` against seen history. Only previously unseen entries enter the
new-Item lifecycle.

Repeated pulls, overlapping feed windows, and feed reordering must not create
duplicates.

### SUB-008 — State advancement

Persist candidate next source state only after the pull and its required
database work succeed. Network, parsing, normalization, policy, or database
failure must not falsely mark a failed pull as fully processed.

Malformed individual entries may be skipped only through explicit,
well-diagnosed validation behavior. They must not crash the scheduler.

### SUB-009 — Failure isolation

One failing source must not stop later sources. Record enough information to
identify source, extension, operation, time, and underlying cause without
exposing credentials.

### SUB-010 — Restart behavior

Source configuration, refresh state, and due-time information survive restart.
Restarting during a pull must result in a safe retry, relying on idempotent seen
and Item persistence.

## Scheduling model

The v0.1 scheduler may be an in-process loop driven by an injectable clock. It
must support clean shutdown and must not start merely because its module is
required by tests or the REPL.

## M2 implementation decisions

- RSS Source IDs use the normalized feed locator. This preserves the Item
  identity established by the earlier one-shot feed form when that feed becomes
  a subscription.
- Adding a subscription performs its first pull before persistence. A failed
  validation or first pull leaves no Source, Item, or seen row.
- Refresh intervals are integer seconds with a minimum of 60 seconds. The Web
  form uses 3600 seconds until interval controls arrive with broader subscription
  management UI.
- Schema migration 2 adds locator, interval, enabled, due-time, attempt,
  success, and error fields to the M1 `sources` table. M1 Items are untouched.
- A successful pull writes Items, seen history, opaque extension state, success
  time, and next due time in one transaction. Discovery never changes `Next`.
- A failed pull records its attempt and a contextual error, and schedules the
  next fixed-interval attempt to prevent a tight retry loop. It does not change
  the last-success time or extension-owned state.
- The RSS extension owns ETag and Last-Modified values and supports practical
  Atom entries with enclosure links. The scheduler never interprets that state.
- Each scheduler tick starts independent threads for due Sources. An in-memory
  per-Source claim prevents overlap; requiring the module starts no thread.
- The application lifecycle polls every 10 seconds by default and cleanly stops
  its scheduler thread when the Web runtime exits.

## Testing

- RSS and Atom fixtures
- First pull, repeated pull, and feed reorder cases
- New episode appearing between pulls
- Conditional GET and not-modified response
- Disabled source
- Two different sources making progress independently
- Attempted overlapping pulls of the same source
- Failure before and after candidate state is produced
- Migration from the accepted M1 schema without losing Items
- Restart and safe retry
- Injectable-clock interval tests without real sleeping

Default tests use fake HTTP and clock boundaries, not the public internet.

## Acceptance criteria

SP-03 is complete when:

1. A durable podcast subscription can be added with a fixed interval.
2. Newly appearing episodes are discovered automatically.
3. Repeated pulls and restarts do not duplicate Items or `Next` entries.
4. A source is never pulled concurrently with itself.
5. One failing source does not stop another source.
6. Failed pulls do not advance source state.
7. Disabled sources remain idle.
8. Scheduler tests run deterministically without wall-clock delays.

## Dependencies and follow-ups

Depends on SP-01 feed semantics and SP-02 persistence. It consumes the admission
and placement defaults until SP-04 makes policy configurable. SP-06 reuses the
same runtime source contract for `yt-dlp` sources.
