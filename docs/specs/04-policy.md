# SP-04 — Policy System

Status: Draft

## Objective

Provide a small, deterministic policy API for deciding whether a newly
discovered Item enters `Next` and where that new Item is inserted, while making
the predicate vocabulary reusable by retention.

## User outcome

A user can express simple rules such as “reject very old episodes” and “put
Chinese items at the front,” without allowing automatic rules to disturb the
existing queue order.

## In scope

- A validated Item evaluation context
- Pure predicate values/functions and boolean composition
- Admission policy
- Ordered placement rules
- Initial `front` and `back` placement actions
- Extension-provided predicates, including a language example
- Deterministic evaluation and focused invariant tests

## Out of scope

- Continuous queue sorting
- Arbitrary user code loaded from untrusted sources
- Extension-provided runtime control flow
- Generic workflow or rule-engine infrastructure
- A custom `#lang`
- Speculative placement actions without a current use case

## Policy context

The runtime constructs an immutable context containing only data needed by
predicates. It may include:

- candidate or existing Item
- source identity and normalized attributes
- a snapshot of `Next` membership/order where required
- playback state where required
- an injected evaluation time

Predicates must not query repositories, call the network, mutate the queue, or
read the wall clock directly. The runtime gathers state before evaluation.

## Requirements

### POL-001 — Predicate contract

A predicate evaluates one context and returns true or false. Core composition
must include `and-p`, `or-p`, and `not-p`. Invalid context or predicate failure
must become a contextual policy error rather than silently evaluating false.

The same predicate representation must be consumable by admission, placement,
and SP-05 retention where its required context is available.

### POL-002 — Admission

Admission evaluates only newly persisted, previously unseen Items. A true
admission predicate accepts the Item for `Next`; false rejects queue admission.
Rejection does not erase the Item or its seen state.

The v0.1 default is accept. Admission does not choose an insertion point.

### POL-003 — Placement rules

Placement is an ordered list of `(predicate, action)` rules followed by a
required default action. v0.1 uses first-match-wins. Rule order is configuration
order and must be preserved exactly.

Placement evaluates only a newly accepted Item. It must never be rerun merely
because Item metadata, policy configuration, or queue contents later change.

### POL-004 — Initial actions

The smallest required action set is:

- `front`: insert before the current first entry
- `back`: insert after the current last entry

Both actions operate correctly on an empty queue. Future actions such as
`before-first-matching` require their own semantics and tests before addition.

The v0.1 default placement is `back`.

### POL-005 — Existing-order preservation

For any existing queue `Q`, inserting a new Item must leave the relative order
of every member of `Q` unchanged. Placement code must return an insertion
decision or updated queue produced by a single insertion operation, never a
sorted replacement queue.

### POL-006 — Manual authority

Manual moves are not policy events. Later automatic insertions may choose a
boundary around the current manually arranged queue but may not move any
existing entry.

### POL-007 — Extension predicates

An extension may register or provide a predicate constructor through an
explicit, validated boundary. Predicate names must not collide silently. The
core must not contain language-specific placement behavior.

The first extension example may expose `(language-is language-code)`. Its
detection strategy and metadata precedence belong to that extension, not to
placement.

### POL-008 — Determinism

The same context, rule order, and predicate definitions must produce the same
result. Time-dependent predicates receive an explicit evaluation instant.

### POL-009 — Failure behavior

Policy failure for one Item must be recorded with Item, policy slot, predicate,
and underlying cause. The runtime must not guess accept/reject after an error.
The Item remains seen and may be inspected or retried through an explicit future
operation.

## Interfaces

The ordinary Racket API should represent concepts equivalent to:

```text
predicate: ItemContext -> boolean
admit: AdmissionPolicy × ItemContext -> accept | reject
place: PlacementPolicy × ItemContext × NextSnapshot -> insertion decision
```

Use structs and functions before macros. Validate rule sets when configuration
loads, not only when the first Item arrives.

## Testing

- Predicate composition truth tables
- Invalid predicate/context behavior
- Admission accept, reject, and error
- First-match-wins and default placement
- Front/back placement on empty and non-empty queues
- Property test: insertion preserves relative order of all existing entries
- Manual reorder followed by repeated automatic insertions
- Extension predicate registration and collision handling
- Injected-time determinism

## Acceptance criteria

SP-04 is complete when:

1. Admission and placement are separate APIs.
2. Ordered placement rules use documented first-match-wins behavior.
3. At least one extension-provided predicate affects placement.
4. No automatic policy operation can reorder existing entries.
5. Rejected Items remain persisted and seen.
6. Predicate vocabulary can be reused by SP-05 without translation to a second
   condition system.
7. All policy and queue-order invariant tests pass.

## Dependencies and follow-ups

Depends on SP-01 domain operations and SP-02 persisted Item/queue snapshots.
SP-03 invokes admission and placement for newly discovered podcast episodes.
SP-05 reuses the predicate model. SP-10 evaluates whether stable policy APIs
justify declarative syntax.
