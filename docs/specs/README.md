# ListenQueue Subproject Specifications

These documents split the ListenQueue product into independently testable work
areas. They are implementation specifications, not separate services or
repositories. ListenQueue remains one Racket application with one SQLite
database and one playback queue named `Next`.

The SP numbers identify work areas; they do not create a rigid release sequence.
Section 24 of [`spec.md`](../../spec.md) defines milestone order. SP-00 is a
small prerequisite and SP-09 is a cross-cutting release concern.

## Precedence

The repository-level [`spec.md`](../../spec.md) defines product semantics and is
the final authority. These subproject specifications refine it. If a subproject
specification conflicts with `spec.md`, stop and resolve the conflict instead of
silently choosing one interpretation.

## Specifications

| ID | Subproject | Primary outcome |
| --- | --- | --- |
| SP-00 | [Project foundation](00-project-foundation.md) | A small Racket application that can be run and tested |
| SP-01 | [Podcast listening slice](01-podcast-listening.md) | A public podcast episode can be heard end to end |
| SP-02 | [SQLite persistence](02-persistence.md) | Items, seen history, queue order, and progress survive restart |
| SP-03 | [Podcast subscriptions](03-podcast-subscriptions.md) | Feeds refresh automatically without duplicates |
| SP-04 | [Policy system](04-policy.md) | Admission and insertion policies are deterministic and extensible |
| SP-05 | [Retention](05-retention.md) | Old content can be filtered and removed without resurrection |
| SP-06 | [`yt-dlp` sources](06-ytdlp.md) | YouTube, Bilibili, and similar sources produce playable Items |
| SP-07 | [Playback state](07-playback.md) | Progress, completion, and media failures are handled reliably |
| SP-08 | [Web UI](08-web-ui.md) | Users can manage subscriptions, `Next`, and playback |
| SP-09 | [Deployment and operations](09-deployment.md) | The application runs as a restart-safe self-hosted container |
| SP-10 | [DSL exploration](10-dsl-exploration.md) | Evidence determines whether a restricted policy DSL is justified |

## Shared invariants

Every subproject must preserve these rules:

1. There is exactly one queue, `Next`.
2. Automatic placement inserts a new item; it never re-sorts existing entries.
3. Manual queue order is authoritative.
4. Repeated pulls do not duplicate items or queue entries.
5. Local deletion does not erase seen history.
6. Provider-specific behavior stays behind extension boundaries.
7. Extensions add integrations and vocabulary, not arbitrary runtime control
   flow.
8. Source refresh does not eagerly download or transcode media.
9. A failed pull does not advance persisted source state.
10. One source is never pulled concurrently with itself.

## Delivery rule

Finish and demonstrate SP-01 before expanding the product surface. Later
subprojects may establish small prerequisites early, but they must not delay the
first outcome: supplying a public podcast feed and hearing an episode.

## Behavior-contract and harness-first rule

No production implementation starts until:

1. A Gherkin-style scenario under [`features/`](../../features/README.md)
   describes the observable behavior.
2. The scenario carries a unique scenario ID plus matching subproject and
   requirement tags.
3. Its smallest useful harness exists and has been run.
4. The harness demonstrates that it detects the missing or incorrect behavior.

The harness must drive the intended boundary and remains in the repository as a
regression test or documented smoke harness. Harness test names or registered
metadata must reference the same scenario ID as the feature scenario.

Choose the harness to match the subproject:

| Subproject area | Minimum harness |
| --- | --- |
| Foundation | Module-load, test-command, and health-handler smoke harness |
| Podcast listening | Feed fixture through normalization and `Next`, plus documented audio smoke harness |
| Persistence | Temporary SQLite database and restart/rollback harness |
| Subscriptions | Fake HTTP and injectable-clock scheduler harness |
| Policy | Pure context/rule/queue invariant harness |
| Retention | Temporary-database plan, execute, retry, and resurrection harness |
| `yt-dlp` | Fake subprocess with recorded JSON and failure fixtures |
| Playback | Fake resolver/progress harness plus opt-in browser playback smoke harness |
| Web UI | Handler harness plus focused browser journey |
| Deployment | Container/Compose startup, health, restart, and persistence harness |
| DSL exploration | Expansion and syntax-error harness, only after entry criteria pass |

Default harnesses must be deterministic and offline. Live-network, browser, or
container checks may be opt-in, but they supplement rather than replace the
default harness.

## Human milestone gate

Each milestone ends with the applicable procedure in
[`docs/manual-acceptance.md`](../manual-acceptance.md). Automated checks do not
complete a milestone by themselves. First commit and push a clean, scoped
milestone candidate; then the user performs the observable checks against that
remote commit and explicitly approves it. Record and push the approval in a
separate commit before production work begins on the next milestone.
