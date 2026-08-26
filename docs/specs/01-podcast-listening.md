# SP-01 — Podcast Listening Slice

Status: Draft
Priority: First product outcome

## Objective

Prove the complete user path from one public podcast feed URL to audible
playback. This slice must be usable before persistence, scheduling, video
sources, or the full Web UI are built.

## User outcome

A user enters a public podcast RSS URL, sees its episodes, adds or selects an
episode in `Next`, presses play, and hears audio in the browser.

## In scope

- Fetching one public HTTP(S) RSS 2.0 feed
- Parsing channel and episode metadata
- Normalizing episodes into minimal `Item` values
- A minimal in-memory `Next`
- Simple admission that accepts valid episodes
- Simple placement that appends new episodes
- Direct resolution of podcast enclosure URLs
- A deliberately small local page using the browser's native audio player
- Fixture-based unit tests and one documented manual playback smoke test

Atom support may be accepted if it comes naturally from the parser, but it is
not required until SP-03.

## Out of scope

- SQLite and restart persistence
- Periodic refresh and subscription management
- `yt-dlp`, downloads, caching, remuxing, or transcoding
- Playback progress persistence
- Complete queue reordering controls
- Authentication or remote deployment
- General policy configuration

## Domain requirements

### POD-001 — Minimal Item

Each valid episode must normalize to an Item containing at least:

- a stable in-process ID
- source identity
- external identity
- title
- canonical episode URL when available
- publication date when available
- duration when available
- description when available
- an enclosure-based `media-ref`
- namespaced feed-specific attributes when needed

Provider data must not create podcast-specific fields in the long-term core Item
without a demonstrated cross-provider need.

### POD-002 — Episode identity

Prefer the RSS GUID as `external-id`. If it is absent, derive a deterministic
fallback from stable feed data such as enclosure URL or canonical episode URL.
Document the fallback order and test it. A title alone is not a safe identity.

M0 uses this exact order: a nonblank RSS GUID, then the HTTP(S) enclosure URL.
An episode without either is not playable and is skipped. The title and
publication date never participate in identity.

### POD-003 — Feed parsing

The parser must tolerate optional fields while rejecting entries that cannot be
played or identified. It must handle XML namespaces used for common podcast
metadata without coupling core domain code to raw XML.

Malformed individual entries may be skipped with contextual diagnostics. A
malformed feed must produce a clear source-level error instead of partial,
unexplained output.

### POD-004 — Minimal Next semantics

The in-memory queue must preserve insertion order and uniqueness. Adding the
same episode twice must not create two queue entries. Operations must be pure
where practical.

### POD-005 — Media resolution

For a podcast episode, resolution returns its enclosure URL and available MIME
type as playable media. Follow ordinary HTTP redirects. Do not download the
entire media file during feed parsing or resolution.

### POD-006 — Minimal player

The local page must expose enough information to choose an episode and play it
with a native HTML audio control. The first slice may keep all state in memory.
It must display a useful error when the enclosure is absent or playback cannot
be started.

### POD-007 — Network safety

Accept only HTTP(S) feed and media URLs. Apply finite connection/read timeouts
and a bounded feed response size. Do not log embedded credentials or sensitive
query parameters.

## Interfaces

The implementation should expose separable operations equivalent to:

```text
fetch-feed(url) -> bytes + response metadata
parse-feed(bytes, source) -> external episodes
normalize-episode(source, external episode) -> Item or validation error
resolve-podcast-media(Item) -> playable media or resolution error
```

Names and exact Racket signatures are implementation decisions. Tests must be
able to exercise parsing and normalization without live network access.

## Error handling

Errors must distinguish:

- invalid or unsupported feed URL
- network or timeout failure
- non-successful HTTP response
- oversized response
- malformed XML/feed structure
- invalid episode identity
- missing or invalid enclosure
- browser/media playback failure

One bad episode must not crash the local server.

## Testing

- RSS fixture with complete episode metadata
- Fixture with missing optional fields
- Fixture using a GUID and fixture using the documented fallback identity
- Duplicate episode insertion
- Malformed XML and malformed episode cases
- Redirecting enclosure resolution using a fake HTTP boundary
- Queue order and uniqueness properties
- A manual smoke test against a documented public test feed

The default automated suite must not depend on the public internet.

## Acceptance criteria

SP-01 is complete when:

1. The user can submit a public RSS 2.0 podcast URL locally.
2. At least one valid episode is normalized and displayed.
3. Selecting or enqueuing the episode places it in `Next` exactly once.
4. Pressing play produces audible audio through the browser.
5. Feed refresh does not eagerly download the audio file.
6. Automated tests cover parsing, normalization, identity, and queue invariants.
7. The playback smoke-test procedure and known limitations are documented.

## Dependencies and follow-ups

Depends only on SP-00. SP-02 replaces in-memory state with SQLite. SP-03 turns a
one-shot feed into a periodically refreshed subscription. SP-07 adds durable
progress and completion behavior.
