# SP-05 — Retention

Status: Draft

## Objective

Apply filterable maintenance actions to existing Items without creating a
delete-specific condition language or allowing deleted upstream content to
resurrect.

## User outcome

A user can express rules such as “delete podcast episodes older than 90 days
that are not in `Next`,” and the deleted episodes stay deleted on later pulls.

## In scope

- Runtime-owned maintenance interval
- Reuse of SP-04 predicates for existing Items
- Ordered retention rules
- `remove-from-next` and `delete-item` actions
- Tombstone behavior
- Dry evaluation/planning support for tests and diagnostics
- Failure isolation and audit-friendly results

`delete-cache` may be added when a real cache exists. `archive` is deferred until
its product semantics are defined.

## Out of scope

- User-defined maintenance schedules or cron
- Arbitrary scripts as retention actions
- Making deleted content unseen
- A separate retention query language
- Bulk media-library management
- Automatic upstream deletion

## Requirements

### RET-001 — Runtime ownership

The ListenQueue runtime starts retention at a configured fixed maintenance
interval. Retention rules do not schedule themselves and extensions cannot
replace the maintenance lifecycle.

### RET-002 — Context snapshot

Build an immutable context for each existing Item using normalized Item data,
queue membership, playback state, source data, and one injected evaluation
time. Predicate evaluation must not perform database or network effects.

### RET-003 — Ordered rules

v0.1 retention is an ordered list of `(predicate, action)` rules. The first
matching rule for an Item wins, so at most one action is planned per Item in one
maintenance cycle. This keeps destructive behavior deterministic and
inspectable.

If future requirements need action composition, define it explicitly rather
than running multiple destructive actions accidentally.

### RET-004 — Remove from Next

`remove-from-next` removes queue membership without deleting the Item, seen
state, or playback history. Applying it to an Item not in `Next` is an
idempotent no-op.

### RET-005 — Delete Item

`delete-item` removes the stored Item and any queue membership according to the
SP-02 deletion transaction. It must retain a seen record with a deleted
disposition. Playback-state handling follows the documented SP-02 foreign-key
contract and must not be accidental.

### RET-006 — Filterability

No action may contain a hard-coded “podcast older than N days” condition. The
selection is always predicate composition plus an action. Initial useful
predicates include `older-than`, `podcast?`, `in-next?`, `started?`, and
`completed?` as their data becomes available.

### RET-007 — Planning before effects

Separate selection from execution. The evaluator should be able to produce a
plan of Item/action pairs without mutating state. Execution validates that each
target is still eligible or safely handles state changes since the snapshot.

### RET-008 — Idempotence

Re-running a maintenance cycle after partial failure must not resurrect Items,
duplicate tombstones, or corrupt `Next`. Applying an already completed action
must either be a no-op or return a clear already-applied result.

### RET-009 — Failure isolation

Failure on one Item must not prevent unrelated planned actions. Record rule,
action, Item, operation, and cause. Database transactions remain per action or
small documented batch so failures are attributable.

### RET-010 — Safety defaults

No destructive retention rule is enabled implicitly. Configuration validation
must reject missing actions and invalid durations. A diagnostic preview should
show what a rule would target before users enable destructive cleanup.

## Testing

- Predicate reuse from SP-04
- First-match-wins across overlapping rules
- Stable evaluation time for `older-than`
- `remove-from-next` preserving Item and playback data
- `delete-item` preserving seen/tombstone state
- Deleted Item still present upstream on next pull
- Repeated and partially failed maintenance cycles
- Preview producing the same targets as execution under unchanged state
- One action failure not blocking another Item

## Acceptance criteria

SP-05 is complete when:

1. A composed predicate can select old podcast Items.
2. Selection and action are separate and inspectable.
3. A filtered delete removes the Item and preserves its tombstone.
4. The next source pull does not recreate a deliberately deleted Item.
5. Removing from `Next` does not erase Item or playback history.
6. No destructive rule is enabled by default.
7. Retention tests cover retry and partial-failure behavior.

## Dependencies and follow-ups

Depends on SP-02 deletion/tombstone semantics and SP-04 predicates. SP-07 adds
richer started/completed state. SP-09 decides whether maintenance status belongs
in operational health reporting.
