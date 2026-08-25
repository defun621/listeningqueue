# SP-10 — DSL Exploration

Status: Deferred research
Earliest target: After v0.1 ordinary Racket APIs stabilize

## Objective

Determine from real configuration experience whether ListenQueue benefits from
a restricted declarative policy language, and implement only the smallest
syntax justified by evidence.

## User outcome

Maintainers receive either a well-supported recommendation to keep plain Racket
configuration or a small, documented language for sources and policies that
cannot become a generic workflow engine.

## Entry criteria

Do not start implementation until:

1. Podcast and `yt-dlp` sources work through ordinary Racket APIs.
2. Admission, placement, and retention semantics are stable and tested.
3. At least three realistic user configurations exist.
4. Repetition or usability problems are documented with concrete examples.
5. The proposed syntax can translate directly to existing domain APIs.

If these conditions are not met, the correct outcome is to defer the DSL.

## In scope

- Study of real programmatic configurations
- An embedded declarative Racket API
- Macros only where they improve validated domain syntax
- `syntax-parse` validation and useful source errors
- Restricted source, predicate, admission, placement, and retention forms
- Expansion into ordinary, tested Racket domain values
- A written decision on whether `#lang listenqueue` is justified

## Out of scope

- DAGs, task graphs, arbitrary branching, or task dependencies
- User-defined scheduler implementations
- Arbitrary retries or parallel branches
- General-purpose shell/subprocess execution
- Extension-controlled runtime lifecycle
- A plugin marketplace
- Replacing the normal Racket API
- Treating syntax design as a v0.1 requirement

## Language boundary

The language may describe:

- sources/subscriptions
- domain predicates
- admission policy
- initial placement rules
- retention selection and actions

The runtime continues to own:

- when sources are pulled
- normalization and deduplication order
- persistence transactions
- when admission and placement run
- maintenance timing
- error isolation and retries

## Requirements

### DSL-001 — API first

Every DSL form must lower to an existing ordinary Racket API with the same
semantics. Do not create capabilities available only through syntax.

### DSL-002 — Restricted vocabulary

Extensions may contribute validated domain constructors or predicates through
an explicit registry/protocol. They may not contribute arbitrary syntax that
changes runtime control flow.

### DSL-003 — Static validation

Catch unknown source types, predicate arity errors, duplicate names, missing
defaults, invalid durations, and unsupported actions as early as practical.
Errors should point to the user's source form.

### DSL-004 — Deterministic expansion

The same configuration must expand to equivalent domain values independent of
runtime source state. Expansion must not perform network requests, database
writes, source pulls, or media resolution.

### DSL-005 — Escape hatch

Plain Racket configuration remains supported for maintainers and extensions.
The DSL must not require duplicating the runtime or policy implementation.

### DSL-006 — Security

Do not present the DSL as a safe sandbox for untrusted code unless a separate,
reviewed security model proves that claim. A `#lang` alone is not a security
boundary.

### DSL-007 — Evaluation sequence

Explore in this order, stopping when the current level is sufficient:

1. Plain functions and structs.
2. Embedded declarative constructors.
3. Small macros for repeated stable forms.
4. `syntax-parse` for better validation.
5. Restricted `#lang listenqueue` only with demonstrated distribution and
   tooling value.

## Required research artifacts

- Three or more realistic configurations written with the current API
- Identified pain points measured by repetition, ambiguity, or error quality
- Equivalent candidate declarative syntax
- Expansion examples showing generated domain values
- Error-message examples
- Capability matrix proving no workflow features were added
- An architecture decision record recommending implement, defer, or reject

## Testing

If syntax is implemented:

- Expansion tests against ordinary API values
- Syntax-error location and message tests
- Unknown extension/predicate/action tests
- Deterministic rule-order tests
- Proof tests that placement remains insertion-only
- Tests that configuration expansion performs no external effects
- Backward compatibility tests for plain Racket configuration

## Acceptance criteria

SP-10 is complete when:

1. The entry criteria and real configuration evidence are documented.
2. A clear implement/defer/reject decision is recorded.
3. Any implemented syntax lowers to existing APIs without new runtime control
   flow.
4. Extensions can add vocabulary but cannot add scheduling graphs or arbitrary
   execution.
5. Plain Racket remains supported and fully capable.
6. Syntax and error behavior, if implemented, are tested and documented.

## Dependencies and follow-ups

Depends on stable evidence from SP-03 through SP-09. This subproject is allowed
to conclude that no custom DSL or `#lang` should be built.
