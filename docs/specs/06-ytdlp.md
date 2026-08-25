# SP-06 — yt-dlp Sources

Status: Draft

## Objective

Add YouTube, Bilibili, and other supported video sources through a safe external
`yt-dlp` process boundary, using the same Source, Item, policy, queue, and media
semantics already proven for podcasts.

## User outcome

A user can subscribe to a supported creator/channel/playlist-like URL, receive
new videos in `Next`, and listen to an audio-capable stream on demand.

## In scope

- `yt-dlp` executable discovery and version diagnostics
- URL inspection/discovery
- Metadata-only source enumeration
- Machine-readable JSON parsing and validation
- Normalization into core Items
- Opaque extension-owned source state
- On-demand playable-media resolution
- Optional cookie-file configuration through a secret-safe boundary
- Fixture and fake-subprocess tests plus opt-in live integration tests

## Out of scope

- Importing `yt-dlp` Python internals
- Eager media download during refresh
- Converting every video to MP3
- Provider-specific queue behavior
- Core fields for YouTube IDs, Bilibili BVIDs, or extractors
- Guaranteeing support for every site accepted by `yt-dlp`
- Automated CAPTCHA or authentication bypass

## Requirements

### YTD-001 — Process boundary

Invoke `yt-dlp` directly with an argument vector, not through shell string
concatenation. Capture exit status, stdout, and bounded stderr. Apply operation
timeouts and terminate abandoned processes cleanly.

### YTD-002 — Machine-readable output

Use documented JSON output appropriate to the operation. Treat every decoded
field as untrusted and validate its type, size, and presence before creating
domain values. Human-oriented output must not be parsed as an API.

### YTD-003 — Discovery

Discovery validates a locator and returns extension-owned initial state plus
display metadata needed by subscription management. It must not add Items to
`Next` or schedule future work.

### YTD-004 — Metadata-only pull

Periodic pulls enumerate entries with the least expensive metadata-only mode
that provides stable identity and required fields. They must not download media
or trigger transcoding.

### YTD-005 — Identity and normalization

Prefer the stable entry ID returned by `yt-dlp` as `external-id`. Normalize at
least title, description, publication time, duration, canonical URL, and an
opaque media reference when available.

Provider-specific data belongs in namespaced attributes, for example:

```racket
(hash 'yt-dlp:extractor "BiliBili"
      'bilibili:bvid "BV1...")
```

Missing required identity or URL data produces a validation error, not a
provider-specific core workaround.

### YTD-006 — Pull state

The extension may use last-seen IDs, timestamps, or other opaque state, but the
runtime persists candidate state only after successful ingestion. Enumeration
order cannot be assumed to be stable unless validated for the extractor.

### YTD-007 — Media resolution

Resolve audio-capable media only when playback is requested. Return a
`playable-media` value containing URI, MIME type when known, expiry when known,
required headers, and seekability. Do not persist short-lived signed URLs as the
Item's permanent identity.

### YTD-008 — Expiry

If resolved media expires, SP-07 may request fresh resolution. Resolution
failures do not delete or mark the Item unseen.

### YTD-009 — Authentication material

Cookie files and tokens are secrets. Accept cookie configuration only through a
documented secret path or protected configuration source. Never include cookie
contents, authorization headers, or signed media URLs in normal logs.

### YTD-010 — Failure isolation

Distinguish executable missing, timeout, nonzero exit, malformed JSON,
unsupported URL, authentication required, entry validation, and media
resolution failures. One bad entry or source must not crash the runtime.

### YTD-011 — Compatibility

Report the detected `yt-dlp` version for diagnostics. Do not silently depend on
undocumented output fields. Live compatibility tests are opt-in because
providers and network conditions change independently of repository code.

## Testing

- Fake subprocess success, nonzero exit, timeout, and oversized output
- Recorded JSON fixtures for at least YouTube and Bilibili
- Missing/wrong-type field validation
- Namespaced attribute preservation
- Repeated enumeration and deduplication
- Source-state failure behavior
- Playable-media resolution and expiry refresh
- Secret redaction tests
- Opt-in live URL inspection test with no media download

## Acceptance criteria

SP-06 is complete when:

1. A supported YouTube source can produce normalized Items.
2. A supported Bilibili source can produce normalized Items.
3. Repeated pulls do not duplicate entries.
4. Source refresh demonstrably performs no eager media download.
5. One Item can resolve to playable audio on demand.
6. `yt-dlp` failures are contextual and isolated.
7. Cookie data and signed URLs do not appear in normal logs.
8. Core domain structs contain no provider-specific fields.

## Dependencies and follow-ups

Depends on SP-02 persistence and the SP-03 Source runtime contract. It uses
SP-04 admission/placement when available and feeds playable media into SP-07.
SP-09 packages compatible `yt-dlp` and `ffmpeg` executables.
