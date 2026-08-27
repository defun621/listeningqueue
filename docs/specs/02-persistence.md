# SP-02 — SQLite Persistence

Status: Draft

## Objective

Persist the domain state required by ListenQueue while preserving deduplication,
queue ordering, manual-order authority, and deletion tombstones across restarts.

## User outcome

Restarting ListenQueue does not lose known items, subscriptions, `Next` order,
seen history, or playback progress.

## In scope

- SQLite database creation and versioned migrations
- Repositories for sources, items, seen history, `Next`, and playback state
- Stable queue ordering and atomic queue mutations
- Transaction boundaries for multi-record domain operations
- Tombstone/seen behavior
- Temporary-database integration tests

## Out of scope

- An external database
- Event sourcing
- Distributed locks or distributed transactions
- Automatic scheduling
- Retention policy evaluation
- Media file caching
- Database administration UI

## Logical data model

The initial database must represent at least:

```text
sources
items
seen_items
next_items
playback_states
schema_migrations
```

Exact column names and ordering representation remain implementation choices,
but the semantics below are required.

## Requirements

### DB-001 — Database lifecycle

Create the database under one configurable data directory. Apply migrations in
a transaction where SQLite permits it. Refuse to run against a schema newer
than the application understands.

### DB-002 — Item identity

Enforce uniqueness for `(source-id, external-id)` when an external ID exists.
Internal Item IDs must remain stable across reads and restarts.

Attributes and extension-owned state require an explicit, versionable encoding.
The core must not interpret provider-specific values merely to store them.

### DB-003 — Seen history

Persist seen state separately from the presence of the full Item row. A record
must survive local deletion and distinguish at least active versus deliberately
deleted content, whether represented by a disposition field or equivalent
state.

Checking whether an upstream entry is new must consult seen history, not only
the items table.

### DB-004 — Next ordering

Persist a total, stable order for queue entries. Enforce one entry per Item.
Add, insert, remove, and move operations must be atomic and must never lose or
duplicate another entry.

The chosen ordering scheme may use positions, ranks, or another simple model.
Its behavior, including collision and compaction handling, must be covered by
tests.

### DB-005 — Manual order

Repository operations must not expose a routine that re-sorts all of `Next` as
part of automatic placement. If metadata is introduced to record manual
positioning, its semantics must be documented before use.

### DB-006 — Playback state

Playback progress is independent of queue membership. Removing an Item from
`Next` must not automatically remove its playback state.

### DB-007 — Atomic ingestion

Operations that mark an external entry seen and create its Item must commit
together. If admission accepts it, queue insertion must not leave a partially
created or duplicate entry after failure.

The implementation must document whether ingestion uses one transaction per
Item or per pull result. Either choice must preserve retry idempotence.

### DB-008 — Deletion

Deleting an Item must define the behavior of related queue and playback rows and
must preserve seen/tombstone state. Foreign-key behavior must be explicit and
tested rather than relying on SQLite defaults.

### DB-009 — Concurrency

Use SQLite transactions and a documented busy-handling strategy. The design may
assume one ListenQueue process for v0.1, but concurrent runtime tasks inside that
process must not corrupt state.

## Repository boundaries

Repositories should expose domain operations rather than raw SQL to unrelated
modules. Pure queue functions remain separately testable; persistence adapts
those semantics without becoming the owner of placement policy.

## M1 implementation decisions

- The database file is `<data-directory>/listenqueue.sqlite3`.
- Schema migrations and their version records run in one transaction. Version
  1 creates all initial logical tables; newer schema versions are refused.
- Version 1 reserves the `sources` table, but M1 has no Source domain model or
  source repository. Those round trips begin in M2, where `spec.md` assigns
  subscriptions and source state.
- Item ingestion uses one transaction per Item. Discovery atomically writes the
  Item and its seen record but never changes `Next`; explicit queue operations
  are separate transactions.
- Core and extension-owned Item values use a versioned, portable prefab-data
  envelope. Persistence stores provider fields without interpreting them and
  does not embed the checkout path in the database.
- `next_items` uses unique integer positions. Manual insert/move operations
  rewrite compact positions inside one transaction using a collision-free
  temporary range.
- Deleting an Item marks its independent seen row `deleted`. Foreign keys
  explicitly cascade the Item's queue and playback rows.
- SQLite busy handling retries 50 times at 100 milliseconds per retry. v0.1
  assumes one ListenQueue process while permitting its runtime tasks to share
  the repository connection.

## Error handling

Database errors must identify the operation and relevant entity without
including secrets or dumping opaque serialized state. Failed transactions must
roll back completely and leave the connection usable where possible.

## Testing

- Fresh database creation and every migration path
- Item round trips, including optional fields and attributes
- Source round trips when the M2 Source model and repository are introduced
- Duplicate `(source-id, external-id)` insertion
- Seen state surviving Item deletion
- Every queue mutation followed by reload
- Relative order preservation during insertion
- Playback state surviving queue removal
- Transaction rollback at representative failure points
- Foreign-key and deletion behavior
- Restart simulation using a new database connection

Tests must create databases under temporary directories and clean them up.

## Acceptance criteria

SP-02 is complete when:

1. All required logical data survives process restart.
2. Repeated ingestion is idempotent.
3. Every `Next` mutation preserves uniqueness and stable order.
4. A deliberately deleted Item does not become unseen.
5. Playback progress survives removal from `Next`.
6. Partial database failures do not leave broken cross-table state.
7. Migration and repository tests pass against temporary SQLite databases.

## Dependencies and follow-ups

Depends on the minimal domain semantics proven by SP-01. SP-03 uses these
repositories for durable subscriptions and pull state. SP-05 relies on the
deletion and tombstone contracts.
