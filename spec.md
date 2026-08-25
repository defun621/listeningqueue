# ListenQueue Specification

Status: Draft  
Version: 0.3  
Target: v0.1 implementation  
Primary language: Racket  
Deployment: Self-hosted  
Primary audience: Maintainers, contributors, Codex/coding agents

---

## 1. Summary

ListenQueue is a self-hosted listening inbox with one ordered playback queue named `Next`.

It periodically pulls new content from subscribed sources such as podcast feeds, YouTube channels, Bilibili creators, and other sources supported by `yt-dlp`.

New content is normalized into a common `Item` model, evaluated by domain policies, and—if accepted—inserted into `Next`.

The system is intentionally not a general workflow engine.

The fixed runtime model is:

```text
Sources
   │
   │ periodic pull
   ▼
New external entries
   │
   ▼
Normalize
   │
   ▼
Deduplicate / Seen history
   │
   ▼
Admission Policy
   │
   ├── reject
   └── accept
          │
          ▼
   Placement Policy
          │
          ▼
         Next
          │
          ▼
        Player
```

A second fixed lifecycle manages old content:

```text
Existing Items
     │
     ▼
Retention Policy
     │
     ▼
Retention Action
```

The long-term DSL should extend ListenQueue's **domain vocabulary**, not its control flow.

---

## 2. Core Product Principles

### 2.1 Pull-based

Subscriptions are refreshed automatically.

Users should not need to manually submit every new episode or video.

Each source has a refresh interval controlled by the ListenQueue runtime.

---

### 2.2 Exactly one queue

There is exactly one playback queue:

```text
Next
```

v0.1 has no:

- user-created queues
- playlists
- queue IDs
- commute/weekend queues
- folders

`Next` is an ordered list of items the user intends to listen to.

---

### 2.3 Manual ordering wins

Automatic policy may determine an item's position **only when the item first enters `Next`**.

Once an item is in `Next`, automatic policy must never continuously re-sort the queue.

If the user manually reorders items, that order is authoritative.

Example:

```text
Automatic result:

1. 中文 A
2. 中文 B
3. English A
4. English B
```

The user manually moves `English B` to the top:

```text
1. English B
2. 中文 A
3. 中文 B
4. English A
```

Future pulls must not move `English B` back down.

This is an insertion policy, not a sorting policy.

```text
correct:
insert(new-item, placement-policy)

incorrect:
sort(all-next-items, placement-policy)
```

---

### 2.4 Extension-first

Platform-specific behavior belongs behind extension boundaries.

The core must not contain hard-coded business logic for:

- YouTube
- Bilibili
- Vimeo
- a specific podcast provider

The initial external-source implementations should be:

```text
RSS
yt-dlp
```

`yt-dlp` is the provider layer for YouTube, Bilibili, and other supported video sites.

---

### 2.5 Extensible vocabulary, fixed semantics

Extensions may add domain vocabulary such as:

```racket
(language-is 'zh)
(language-is 'en)
(older-than 90d)
(title-matches #rx"...")
(bilibili-user "...")
(uninteresting?)
```

Extensions must not add arbitrary runtime control flow.

The DSL must not become a mini-Airflow, Temporal, n8n, or generic DAG engine.

The DSL must not expose arbitrary:

- DAGs
- task dependencies
- user-defined scheduling graphs
- arbitrary retries
- arbitrary parallel branches
- generic workflow branching

The runtime lifecycle is fixed by ListenQueue.

---

### 2.6 DSL after semantics

v0.1 must first expose idiomatic Racket APIs built from:

- structs
- functions
- modules
- contracts/validation where useful

A custom `#lang listenqueue` is deferred until the extension and policy semantics are proven.

The DSL should be extracted from real domain needs, not invented in advance.

---

### 2.7 Self-hosted first

The application must work without a required cloud service.

Target deployment:

```text
one ListenQueue process/container
one persistent data directory
SQLite
yt-dlp
ffmpeg when needed
```

No Redis, Kafka, Kubernetes, external scheduler, or mandatory PostgreSQL.

---

## 3. Goals

v0.1 should support:

1. Periodic pulling of subscribed sources.
2. Podcast RSS/Atom feeds.
3. Video sources through `yt-dlp`, including YouTube and Bilibili.
4. Detection of new items.
5. Deduplication and seen-history tracking.
6. A normalized `Item` domain model.
7. Domain predicates contributed by extensions.
8. Admission policy before an item enters `Next`.
9. Initial placement policy for accepted items.
10. One ordered `Next` queue.
11. Manual queue reorder.
12. Removal from `Next`.
13. Playback progress persistence.
14. Audio/media resolution on demand.
15. Retention rules for old content.
16. Filtered retention actions, including deletion of old podcast items.
17. SQLite persistence.
18. Docker-based self-hosting.
19. Programmatic Racket configuration.
20. A design that can later support a Racket DSL.

---

## 4. Non-goals

Out of scope for v0.1:

- Multiple queues
- User-created playlists
- Public recommendation/discovery
- Social features
- Comments/ratings
- Full media-library management
- Native mobile apps
- CarPlay / Android Auto
- Spotify account integration
- Apple Podcasts account integration
- AI/LLM features
- Speech-to-text
- Article text-to-speech
- Multi-user support
- Distributed scheduling
- Event sourcing
- Plugin marketplace
- Generic workflow engine
- User-defined DAG execution
- `#lang listenqueue`

---

## 5. Core Domain

### 5.1 Item

An `Item` is one listenable unit discovered from a source.

Conceptual representation:

```racket
(struct item
  (id
   source-id
   external-id
   title
   description
   published-at
   duration
   canonical-url
   media-ref
   attributes)
  #:transparent)
```

Semantics:

- `id`
  - internal stable identifier
- `source-id`
  - internal source identifier
- `external-id`
  - stable source/provider identity where available
- `title`
- `description`
  - optional
- `published-at`
  - optional
- `duration`
  - optional
- `canonical-url`
- `media-ref`
  - opaque input for media resolution
- `attributes`
  - namespaced extension metadata

Core fields must not grow a provider-specific field for every platform.

Bad:

```text
youtube-video-id
bilibili-bvid
vimeo-id
whisper-transcript
...
```

Provider-specific metadata belongs in namespaced `attributes`.

Example:

```racket
(hash
 'bilibili:bvid "BV1..."
 'yt-dlp:extractor "BiliBili")
```

---

### 5.2 Source

A `Source` is something the runtime can periodically pull.

Examples:

- Podcast feed
- YouTube channel
- Bilibili creator
- Bilibili collection/series
- Any supported `yt-dlp` playlist-like source

Conceptually:

```racket
(struct source
  (id
   extension-id
   locator
   refresh-interval
   state
   enabled?)
  #:transparent)
```

`state` is extension-owned opaque refresh state.

Possible extension-owned state:

- last seen external ID
- ETag
- Last-Modified
- cursor
- timestamp
- extractor-specific state

The core must not interpret provider-specific source state.

---

### 5.3 Next

`Next` is the only playback queue.

Conceptually:

```racket
(struct next-list
  (entries)
  #:transparent)
```

Required pure operations:

```racket
(next-add-first next item-id)
(next-add-last next item-id)
(next-insert-before next item-id target-id)
(next-insert-after next item-id target-id)
(next-remove next item-id)
(next-move-before next item-id target-id)
(next-move-after next item-id target-id)
(next-pop next)
```

Invariants:

1. An item appears at most once in `Next`.
2. Ordering is stable.
3. Reordering never loses or duplicates an item.
4. Manual ordering is authoritative.
5. Automatic placement never reorders an existing entry.
6. A completed item may be removed from `Next`.
7. Queue operations should be pure domain functions where practical.

---

### 5.4 Playback State

Playback state is independent of queue order.

Conceptually:

```racket
(struct playback-state
  (item-id
   position-seconds
   duration-seconds
   updated-at
   completed?)
  #:transparent)
```

Removing an item from `Next` does not necessarily erase playback history.

---

## 6. Extension Model

Extensions expand integration behavior and domain vocabulary.

Initial extension categories:

```text
Source Extension
Predicate Extension
Resolver Extension
Retention Action Extension
```

A general `PipelineStage` abstraction should not be introduced in v0.1.

---

### 6.1 Source Extension

A source extension discovers and pulls external content.

Conceptual contract:

```racket
(struct source-extension
  (name
   discover
   pull)
  #:transparent)
```

Semantics:

```text
discover(locator)
  -> extension-owned source state

pull(source, previous-state)
  -> pull-result
```

Conceptual result:

```racket
(struct pull-result
  (external-items
   next-state)
  #:transparent)
```

Requirements:

- A source extension must not enqueue directly.
- A source extension must not control its own scheduler.
- A successful pull may advance source state.
- A failed pull must not advance persisted source state.
- Provider-specific data must be normalized before entering core policy evaluation.

Initial source extensions:

```text
rss
yt-dlp
```

---

### 6.2 Predicate Extension

A predicate answers a domain question about an `Item` or item state.

Conceptual contract:

```text
ItemContext -> boolean
```

The exact context type is not fixed yet, because some predicates require queue/playback state.

Examples:

```racket
(language-is 'zh)
(language-is 'en)
(duration-under 90m)
(older-than 90d)
(title-matches #rx"Racket|OCaml")
(started?)
(completed?)
(in-next?)
(podcast?)
```

Predicates should be pure whenever possible.

The same predicate vocabulary should be reusable across:

- admission
- placement
- retention

This reuse is important: deletion should be filterable using the same domain language rather than inventing a separate delete-specific condition system.

---

### 6.3 Resolver Extension

A resolver converts an item's media reference into playable media.

Conceptually:

```racket
(struct playable-media
  (uri
   mime-type
   expires-at
   headers
   seekable?)
  #:transparent)
```

Resolution happens on demand.

Normal source refresh must not eagerly download or transcode media.

Initial strategy:

- podcast enclosure URL -> direct playable media
- supported video URL -> `yt-dlp` media resolution

---

### 6.4 Retention Action Extension

Retention actions operate on already-known items selected by retention predicates.

Initial conceptual actions:

```text
archive
delete-cache
delete-item
remove-from-next
```

v0.1 only needs actions actually required by implementation.

`delete-item` must not imply that the upstream item becomes "unseen" again.

---

## 7. Policy Model

ListenQueue has fixed runtime lifecycle slots.

Users configure policies inside those slots.

There are three important policy concepts:

```text
Admission
Placement
Retention
```

---

### 7.1 Admission Policy

Admission determines whether a newly discovered item is allowed to enter `Next`.

Conceptually:

```text
ItemContext -> accept | reject
```

Example future Racket API:

```racket
(define admission-policy
  (accept-if
    (not-p (older-than (days 180)))))
```

Admission does not decide queue order.

---

### 7.2 Placement Policy

Placement decides where a **newly accepted** item is inserted into `Next`.

It must not re-sort existing entries.

The placement system is generic:

```text
predicate -> placement action
```

Illustrative future API:

```racket
(define placement-policy
  (placement-rules
    [(predicate-a) prefer-front]
    [(predicate-b) back]
    [else back]))
```

Predicates may come from the core or from extensions. Examples include:

```racket
(language-is 'zh)
(language-is 'en)
(source-is 'podcast)
(duration-under 30m)
(title-matches #rx"...")
```

These are examples of what the DSL can express, not built-in product policy.

Placement actions may likewise be extensible. Examples include:

```text
front
back
prefer-front
before-first-matching
after-last-matching
```

v0.1 should implement only the smallest useful subset.

Required semantics:

- placement rules are evaluated only for newly admitted items;
- policy evaluation is deterministic;
- existing queue items are never automatically re-sorted;
- manual user moves remain authoritative;
- predicates and placement actions can be extended without changing core queue semantics.

Example only:

```racket
(placement-rules
  [(language-is 'zh) prefer-front]
  [(language-is 'en) back]
  [else back])
```

The example above must not be hard-coded as ListenQueue default behavior.

---

### 7.3 Retention Policy

Retention applies to existing stored items.

It answers:

> Which old items should receive a retention action?

Example future API:

```racket
(define old-podcast-cleanup
  (delete-if
    (and-p
      (podcast?)
      (older-than (days 90))
      (not-p (in-next?))
      (not-p (started?)))))
```

This is important: **the delete action is filterable**.

The system should not provide a special hard-coded rule like "delete podcasts older than N days."

Instead:

```text
predicate composition
        +
retention action
```

defines the policy.

Examples:

```racket
(delete-if
  (and-p
    (podcast?)
    (older-than (days 90))))
```

```racket
(delete-cache-if
  (and-p
    (completed?)
    (older-than (days 7))))
```

```racket
(remove-from-next-if
  (and-p
    (older-than (days 60))
    (not-p (started?))))
```

Retention execution timing belongs to the runtime, not to the DSL.

---

## 8. Fixed Runtime Semantics

### 8.1 Incoming lifecycle

```text
source becomes due
       ↓
source extension pull
       ↓
normalize external entries
       ↓
deduplicate / seen lookup
       ↓
persist new Item
       ↓
admission policy
       ↓
if accepted:
placement policy
       ↓
insert into Next
```

---

### 8.2 Maintenance lifecycle

```text
runtime maintenance cycle
       ↓
existing stored Items
       ↓
retention predicates
       ↓
matching action
```

The user may configure predicates/actions, but not replace this lifecycle with a DAG.

---

## 9. Scheduling

Scheduling is a runtime responsibility.

Each subscription has a refresh interval.

v0.1 only needs fixed intervals:

```text
30 minutes
1 hour
2 hours
...
```

Cron syntax is not required.

Required behavior:

- a source is never pulled concurrently with itself;
- one failing source does not stop other sources;
- failed pulls do not advance source state;
- disabled sources are skipped;
- source state survives restart.

A maintenance interval for retention is runtime configuration, not a user-defined workflow.

---

## 10. Deduplication and Tombstones

Preferred discovered-item identity:

```text
(source-id, external-id)
```

Repeated pulling must not duplicate items or `Next` entries.

Retention introduces an important invariant:

```text
deleted locally
!=
never seen
```

Example problem:

```text
Podcast episode is 120 days old
      ↓
retention deletes it
      ↓
RSS feed still contains it
      ↓
next pull sees "not in items table"
      ↓
episode gets recreated forever
```

Therefore the system must persist seen-history/tombstone state.

Conceptual table:

```text
seen_items
----------
source_id
external_id
first_seen_at
disposition
```

Possible dispositions:

```text
active
archived
deleted
```

Exact schema is not fixed.

A deliberately deleted item must not automatically resurrect merely because it still exists upstream.

---

## 11. Example Predicate Extension: Language

Language is an example of extension-provided policy vocabulary.

The core must not require language detection for placement to work.

A language extension may provide predicates such as:

```racket
(language-is 'zh)
(language-is 'en)
(language-in '(zh en))
```

Possible language sources include provider metadata, podcast metadata, title/description detection, or a richer language-detection extension.

The exact detection strategy is outside core semantics.

The general requirement is that admission, placement, and retention policies can consume predicates contributed by extensions.

---

## 12. Podcast Support

Minimum podcast feed support:

- RSS 2.0
- Atom where practical
- GUID or deterministic identity
- enclosure URL
- title
- publication date
- duration when available
- description when available

ETag and Last-Modified support are desirable.

---

## 13. yt-dlp Integration

`yt-dlp` is an external process boundary.

```text
Racket
   │
   └── subprocess
          │
          ▼
       yt-dlp
```

Do not depend on internal Python APIs.

Use machine-readable JSON output.

Responsibilities:

- inspect supported URLs
- enumerate channel/creator/playlist-like sources
- obtain stable external IDs
- obtain metadata
- resolve audio-capable media

The application must treat `yt-dlp` output as untrusted external data.

For periodic pulls, prefer metadata-only enumeration where possible.

Do not download media during source refresh.

---

## 14. Media Strategy

Default:

```text
Item persisted
    ↓
user plays item
    ↓
resolve media
    ↓
play
```

Preferred order:

1. direct podcast enclosure when available;
2. existing audio-only stream;
3. remux/transcode only if needed;
4. caching/download only when explicitly introduced.

Do not convert every video to MP3 in advance.

---

## 15. Persistence

Use SQLite.

All persistent data should live under one data directory.

Example:

```text
/data/
├── listenqueue.db
├── cache/
├── downloads/
└── secrets/
```

Initial logical tables:

```text
sources
items
seen_items
next_items
playback_states
```

`next_items` must preserve stable order.

If manual placement metadata is needed to preserve placement invariants, it may be added to `next_items`.

No external database is required.

---

## 16. DSL Direction

The future DSL is a **ListenQueue policy language**, not a workflow language.

Its job is to express:

- sources/subscriptions
- domain predicates
- admission
- initial placement
- retention selection/actions

It must not express arbitrary task graphs.

Possible future evolution:

```text
plain Racket API
      ↓
embedded declarative API
      ↓
macros where useful
      ↓
syntax-parse
      ↓
restricted #lang listenqueue
```

Illustrative syntax only:

```racket
#lang listenqueue

(source tech
  (bilibili-user "123456"))

(next
  #:admit
  (not-p (older-than 180d))

  #:placement
  (rules
    [(language-is 'zh) prefer-front]
    [(language-is 'en) back]
    [else back]))

(retention
  (delete
    (and-p
      (podcast?)
      (older-than 90d)
      (not-p (in-next?))
      (not-p (started?)))))
```

The key rule is:

```text
extensions extend vocabulary
runtime owns control flow
```

---

## 17. Extension Composition

Extensions do not directly orchestrate each other.

Wrong:

```text
Bilibili extension
   ↓ calls
language extension
   ↓ calls
Next
```

Correct:

```text
Bilibili source extension
   ↓
normalized Item
   ↓
runtime admission slot
   ↓
language predicate
   ↓
runtime placement slot
   ↓
Next
```

Retention:

```text
Stored Item
   ↓
runtime retention slot
   ↓
predicates
   ↓
retention action
```

Core owns semantics.

Extensions own vocabulary and integrations.

---

## 18. Error Handling

Expected failures include:

- source unavailable
- authentication required
- malformed feed
- invalid external metadata
- `yt-dlp` failure
- temporary network failure
- media resolution failure
- database failure
- extension failure

One failing source/item must not crash the long-running runtime.

Errors should include enough context to identify:

- source
- extension
- operation
- underlying error

Straightforward explicit error handling is preferred for v0.1.

---

## 19. Authentication and Secrets

Public sources should work without credentials.

Future extensions may use cookie files or tokens.

Secrets:

- must not be committed;
- must not appear in logs;
- should live under persistent secrets storage or environment/config;
- must be treated as credentials.

`yt-dlp` cookie files are sensitive authentication material.

---

## 20. Deployment

Target user experience:

```bash
docker compose up -d
```

Conceptual container:

```text
listenqueue
├── Racket application
├── yt-dlp
├── ffmpeg
└── /data
```

Requirements:

- one app container/process;
- persistent `/data`;
- configurable port;
- configurable timezone;
- restart-safe;
- works on LAN;
- no mandatory cloud service.

---

## 21. Proposed Racket Modules

Provisional layout:

```text
listenqueue/
├── main.rkt
├── config.rkt
│
├── domain/
│   ├── item.rkt
│   ├── source.rkt
│   ├── next.rkt
│   └── playback.rkt
│
├── extension/
│   ├── protocol.rkt
│   ├── rss.rkt
│   ├── ytdlp.rkt
│   └── language.rkt
│
├── policy/
│   ├── predicate.rkt
│   ├── admission.rkt
│   ├── placement.rkt
│   └── retention.rkt
│
├── scheduler/
│   └── scheduler.rkt
│
├── persistence/
│   ├── database.rkt
│   ├── source-repository.rkt
│   ├── item-repository.rkt
│   ├── seen-repository.rkt
│   ├── next-repository.rkt
│   └── playback-repository.rkt
│
├── media/
│   └── resolver.rkt
│
├── web/
│   └── server.rkt
│
└── tests/
```

Do not preserve this shape if implementation evidence suggests a simpler boundary.

---

## 22. Development Principles

1. Prefer data and ordinary functions before macros.
2. Keep core queue operations pure.
3. Normalize external data early.
4. Keep provider-specific metadata at extension boundaries.
5. Treat placement as insertion, never repeated sorting.
6. Preserve manual queue ordering.
7. Reuse predicate vocabulary across admission, placement, and retention.
8. Do not create a generic workflow abstraction.
9. Do not introduce speculative extension categories.
10. Keep the system easy to inspect from the Racket REPL.
11. Add tests for every architectural invariant.
12. Prefer boring implementation over clever abstraction until a real requirement appears.

---

## 23. First Vertical Slice

The first product slice must prove that a user can actually listen to a podcast.

Input:

```text
one public podcast RSS or Atom URL
```

Flow:

```text
feed URL
 ↓
fetch and parse feed
 ↓
normalize episodes to Items
 ↓
simple admission decision
 ↓
insert into Next
 ↓
select an episode
 ↓
resolve its enclosure URL
 ↓
play audio
```

The slice may use a deliberately small local web page with the browser's native
audio player. It does not need the full v0.1 Web UI.

No:

- SQLite
- scheduler
- `yt-dlp`
- custom DSL
- media download or transcoding
- production-ready subscription management

This validates:

1. feed fetching and parsing;
2. external-data normalization;
3. pure `Next` operations;
4. direct podcast media resolution;
5. an end-to-end path that produces audible playback.

---

## 24. Milestones

### M0 — Podcast listening vertical slice

Implement only the domain and delivery pieces needed to listen end to end:

- minimal `Item`
- minimal pure `Next` operations and invariant tests
- RSS 2.0 feed fetching and parsing
- podcast episode normalization
- enclosure URL resolution
- a minimal local browser audio player
- one end-to-end podcast playback smoke test

### M1 — Persistence

Implement:

- SQLite
- items
- seen/tombstones
- Next ordering
- playback state

### M2 — Podcast subscriptions

Implement:

- Source model
- source state
- scheduler
- deduplication
- podcast polling
- Atom support where practical
- ETag and Last-Modified where practical

### M3 — yt-dlp sources

Implement:

- subprocess invocation
- machine-readable JSON parsing
- video-source normalization
- YouTube and Bilibili creator/channel enumeration
- `yt-dlp` media resolution

### M4 — Policy

Implement:

- reusable predicates
- admission policy
- language predicate
- placement policy
- manual-order invariants

### M5 — Retention

Implement:

- runtime maintenance cycle
- old-item predicates
- filtered delete
- tombstone behavior

### M6 — Playback

Implement:

- progress persistence
- completion behavior
- playback error handling
- expiring-media refresh where needed

### M7 — Minimal Web UI

Implement:

- subscriptions
- Next
- reorder
- remove
- play

### M8 — DSL exploration

Only after normal Racket APIs stabilize:

- embedded declarative policy API
- macros where justified
- `syntax-parse` evaluation
- possible `#lang listenqueue`

---

## 25. v0.1 Acceptance Criteria

A self-hosted user can:

1. Start ListenQueue.
2. Subscribe to a podcast source.
3. Subscribe to a YouTube source.
4. Subscribe to a Bilibili source.
5. Configure pull intervals.
6. Leave the service running and receive new items automatically.
7. Avoid duplicates across repeated pulls.
8. Evaluate new items through admission predicates.
9. Evaluate configurable placement rules expressed as `predicate -> placement action`.
10. Use at least one extension-provided predicate as a placement input.
11. Support language-based placement as an example configuration without hard-coding language policy into the core.
12. Manually reorder `Next`.
13. Preserve manual ordering across all later automatic pulls.
14. Remove items from `Next`.
15. Apply a filtered retention rule to old podcasts.
16. Delete old items without causing them to resurrect on the next source pull.
17. Play audio.
18. Persist playback progress.
19. Restart without losing:
    - subscriptions
    - source state
    - seen history/tombstones
    - items
    - Next order
    - playback progress
20. Run from documented self-hosted deployment configuration.

---

## 26. Architectural Invariants

### INV-1
There is exactly one playback queue named `Next`.

### INV-2
Sources are pull-based.

### INV-3
Scheduling belongs to the runtime, not source extensions.

### INV-4
Source extensions never enqueue directly.

### INV-5
Provider-specific metadata does not become a core field without a demonstrated cross-provider need.

### INV-6
`yt-dlp` is an external process boundary.

### INV-7
Normal source refresh does not eagerly download/transcode media.

### INV-8
SQLite is the default persistent store.

### INV-9
The DSL is not a workflow/DAG language.

### INV-10
Extensions extend domain vocabulary, not arbitrary control flow.

### INV-11
Admission decides whether a new item may enter `Next`.

### INV-12
Placement decides only the initial insertion of a newly admitted item.

### INV-13
Placement semantics are generic and must not hard-code language-, source-, or provider-specific ordering rules.

### INV-14
Placement rules compose predicates with placement actions; both may be extension-provided where appropriate.

### INV-15
Automatic policy never reorders an item already present in `Next`.

### INV-16
Manual user ordering is authoritative.

### INV-17
Predicate vocabulary is reusable across admission, placement, and retention.

### INV-18
Retention actions can be filtered through domain predicates.

### INV-19
Deleting an item does not erase seen-history; intentionally deleted upstream items must not automatically resurrect.

### INV-20
A custom DSL must emerge from stable domain APIs; core runtime semantics must not depend on DSL syntax.

---

## 27. Open Questions

1. Is `Inbox` a first-class persisted domain concept, or simply discovered items not yet dispositioned?
2. Should every new item be evaluated exactly once by admission policy?
3. Can an archived/deleted item ever be explicitly restored by a user?
4. What is the precise playback completion threshold?
5. Should media be proxied through ListenQueue or redirected directly?
6. When should media caching be introduced?
7. How should authenticated `yt-dlp` sources expose cookie configuration safely?
8. What exact semantics should placement actions such as `prefer-front`, `before-first-matching`, and `after-last-matching` have?
9. After manual queue reordering, how should a new item be inserted automatically without disturbing manual order?
10. Should queue entries record whether their current position was manually established?
11. Should placement use first-match-wins, explicit priorities, or another deterministic rule model?
12. How are extension-provided placement actions registered and validated?
13. Should language come from provider metadata first, an extension detector first, or a precedence chain?
14. When does plain Racket configuration become insufficient enough to justify macros?
15. What real extension requirement would justify `#lang listenqueue`?

These questions should not block M0–M2 unless required by implementation.

---

## 28. Codex / Agent Guidance

When implementing this specification:

- Prefer idiomatic Racket.
- Do not mechanically imitate Scala, Java, Rust, or Haskell architectures.
- Begin with structs, modules, and functions.
- Do not add macros merely because Racket supports them.
- Keep external representations separate from domain values.
- Keep queue logic pure.
- Treat automatic placement as insertion, never repeated sorting.
- Preserve manual `Next` order.
- Keep placement generic: `predicate -> placement action`.
- Do not hard-code Chinese/English or any other specific placement policy into core behavior.
- Reuse predicates instead of inventing separate condition systems.
- Keep source effects behind source-extension boundaries.
- Do not introduce a generic `PipelineStage` or workflow DAG abstraction.
- Extensions may add vocabulary, not arbitrary runtime control flow.
- Add focused tests for architectural invariants.
- Keep early milestones easy to drive from the REPL.
- Explain non-obvious Racket-specific techniques.
- Run formatter and tests after changes.

The project should be both a useful self-hosted application and a vehicle for learning idiomatic Racket and language-oriented design without forcing a DSL prematurely.
