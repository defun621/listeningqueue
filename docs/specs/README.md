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
