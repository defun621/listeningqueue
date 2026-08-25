# ListenQueue Behavior Contracts

Files in this directory are Gherkin-style behavior contracts. They connect the
product rules in `spec.md` and `docs/specs/` to executable harnesses.

They are not a new ListenQueue DSL and do not control runtime behavior.

## Required workflow

For every feature or bug fix:

```text
write/update scenario
  -> add harness mapped to scenario tags
  -> run harness and observe the expected failure
  -> implement production behavior
  -> run harness and observe success
  -> keep scenario and harness for regression
```

## Format

Use ordinary Gherkin structure:

```gherkin
@SP-01
Feature: Stable podcast episode identity

  Rule: Repeated feed entries represent the same Item

    @SC-POD-001 @POD-002 @automated
    Scenario: An episode with a GUID is loaded twice
      Given an RSS fixture containing an episode with GUID "episode-42"
      When the feed is loaded twice
      Then exactly one Item has external ID "episode-42"
      And exactly one entry for that Item exists in Next
```

Use English keywords and descriptions for consistency with the repository's
technical specifications. Keep wording understandable to a product reader.

## Tags and traceability

Every scenario carries:

- one globally unique scenario ID, such as `@SC-POD-001`;
- one subproject tag, such as `@SP-01`;
- at least one requirement tag, such as `@POD-002`;
- one execution tag:
  - `@automated`: deterministic default-suite harness;
  - `@manual`: unavoidable human observation;
  - `@live`: real external network/service;
  - `@slow`: excluded from the fast feedback loop;
  - `@container`: requires a built container runtime.

Scenario IDs use `SC-<AREA>-<NUMBER>`, remain stable after publication, and are
never reused for different behavior. Wording may improve without changing the
ID; materially different behavior gets a new ID.

Harness test names or registered metadata must repeat the scenario ID. A
reviewer and the traceability check must be able to move in both directions:

```text
requirement <-> feature scenario <-> harness/test
```

## Racket implementation

Use plain RackUnit for the initial harness layer. Map a scenario to a named test:

```racket
#lang racket/base

(require rackunit)

(module+ test
  (test-case
   "[SC-POD-001] loading the same GUID episode twice creates one item"

   ;; Given
   (define feed (load-fixture "episode-42.xml"))

   ;; When
   (define result (load-feed-twice feed))

   ;; Then
   (check-equal?
    (count-items-with-external-id result "episode-42")
    1)
   (check-equal?
    (count-next-entries result "episode-42")
    1)))
```

Recommended repository layout:

```text
features/                    behavior contracts
tests/harness/               RackUnit scenario harnesses
tests/fixtures/              RSS, JSON, and other controlled inputs
tests/integration/           opt-in live/browser/container harnesses
```

SP-00 must add a small traceability check that scans the repository conventions
and verifies unique scenario IDs and their RackUnit mappings. It does not need
to understand every Gherkin sentence or execute Given/When/Then steps.

The optional `rackunit/spec` package provides `describe`, `context`, and `it`
BDD forms, but it does not execute `.feature` files and is not required. Adopt
it only if it materially improves harness readability.

## Writing rules

- `Given` describes only necessary state and controlled dependencies.
- `When` contains one primary user or runtime action.
- `Then` describes observable output, state, or side effects.
- Prefer concrete examples over vague words such as “correctly” or “properly.”
- Do not mention private helper functions or chosen SQL layout unless those are
  the actual specified boundary.
- Keep scenarios independent and repeatable.
- Give each scenario exactly one primary `When`; split workflows with distinct
  actions into separate scenarios.
- Use fixture files, fake clocks, fake subprocesses, and temporary databases for
  `@automated` scenarios.
- Do not make the default suite depend on the public internet.

## Relationship to harnesses

A `.feature` file is the behavior contract; it is not executable evidence by
itself. A harness supplies controlled inputs and dependencies, drives the public
boundary, observes results, and produces an unambiguous pass/fail result.

No Gherkin parser or Cucumber-style framework is required initially. RackUnit
tests and smoke runners implement scenarios directly. Add parsing or
step-definition machinery only if repeated real usage justifies it.

## Precedence

`spec.md` remains authoritative. Subproject specifications refine it, feature
scenarios provide concrete examples, and harnesses provide executable evidence.
If any layer conflicts, fix the documents before implementation.
