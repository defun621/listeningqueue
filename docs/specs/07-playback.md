# SP-07 — Playback State and Reliability

Status: Draft

## Objective

Make playback resumable and reliable across podcast enclosures and resolved
video audio while keeping playback history independent of queue order.

## User outcome

A user can stop midway, return later, resume near the saved position, finish an
Item, and receive a useful error when media cannot be played.

## In scope

- Unified playable-media contract
- Podcast and `yt-dlp` resolver selection
- Durable progress updates
- Resume behavior
- Natural completion handling
- Expiring media re-resolution
- Seekability and required request headers
- Playback error states and retry

## Out of scope

- Native mobile players
- CarPlay or Android Auto
- Offline download management
- Mandatory media proxying
- Eager transcoding
- Multi-user playback synchronization
- Recommendations or listening analytics

## Requirements

### PLAY-001 — Playable media

Resolvers return a value equivalent to:

```racket
(struct playable-media
  (uri mime-type expires-at headers seekable?)
  #:transparent)
```

The resolver is selected from Item/media-ref data through an explicit extension
boundary. The core player does not branch on YouTube or Bilibili directly.

### PLAY-002 — On-demand resolution

Resolve media when the user requests playback. Podcast enclosure URLs may be
returned directly. Video Items use SP-06. Resolution must not change queue
order, seen state, or admission state.

### PLAY-003 — Progress updates

Persist position in seconds, known duration, update time, and completion state.
Throttle client updates to avoid a database write on every browser time event,
while sending a final update on pause, navigation, or shutdown when practical.

Reject negative, non-finite, or implausibly out-of-range positions. Handle stale
updates deterministically so an older browser event does not overwrite newer
progress.

### PLAY-004 — Resume

When playback begins, seek to saved progress if the media is seekable and the
saved position is valid. A fresh Item starts at zero. Failure to seek must not
prevent playback from starting at the beginning.

### PLAY-005 — Completion

v0.1 marks an Item completed when the player reports a natural ended event or
the user explicitly marks it complete. Do not introduce an undocumented
percentage heuristic.

Completion may remove the Item from `Next` only through an explicit configured
product behavior. It does not delete Item or seen history.

### PLAY-006 — Expiring media

If playable media is expired or a failure indicates expiry, request one fresh
resolution before reporting final failure. Avoid unbounded retry loops.

### PLAY-007 — Headers and proxy decision

Some media requires request headers that a native browser audio element cannot
send. Start with direct playback where it works. If a resolver requires private
headers, use a narrowly scoped server-side media proxy or return a clear
unsupported condition. Document the chosen behavior and ensure secrets never
reach page markup or logs.

### PLAY-008 — Queue independence

Removing, moving, or completing an Item in `Next` must not accidentally erase
its playback history. Playing an Item must not reorder the queue.

### PLAY-009 — Error model

Distinguish resolution, authorization, expiry, network, unsupported format,
unseekable media, and browser playback failures. Errors should identify the
Item and operation without exposing signed URLs or headers.

## Testing

- Progress validation and persistence round trips
- Stale versus newer progress updates
- Resume from saved position and invalid-position fallback
- Natural and explicit completion
- Queue removal preserving playback state
- Expired media re-resolving exactly once
- Resolver selection without provider checks in core player code
- Required-header secret redaction
- Browser smoke tests for one podcast and one `yt-dlp` Item

## Acceptance criteria

SP-07 is complete when:

1. Podcast playback resumes after page and process restart.
2. A supported video Item resolves and plays audio on demand.
3. Natural completion is persisted.
4. Queue removal does not erase playback history.
5. Expired media receives one bounded re-resolution attempt.
6. Invalid or stale progress cannot corrupt newer state.
7. Playback failures are visible, contextual, and secret-safe.

## Dependencies and follow-ups

Depends on SP-01 podcast playback, SP-02 playback persistence, and SP-06 for
video media. SP-08 provides the complete player controls and user-facing error
presentation. Caching remains deferred until real playback evidence requires it.
