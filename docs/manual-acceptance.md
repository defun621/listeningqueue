# ListenQueue Manual Acceptance Runbook

Automated harnesses establish repeatable evidence. These procedures establish
that each milestone's user-visible outcome works in a real environment against
a fixed Git revision.

Before presenting a gate, the implementation agent must:

1. run all required automated checks;
2. commit all acceptance-relevant code, scenarios, harnesses, fixtures,
   migrations, examples, and instructions as one scoped candidate;
3. push the candidate to the configured remote;
4. verify the remote contains that commit and the worktree is clean;
5. provide its commit hash with the manual procedure.

No milestone is complete until the user tests that candidate and explicitly
reports a pass. The agent then records the result in a separate commit, pushes
it to the configured remote, and verifies the push before starting the next
milestone. Commands that depend on not-yet-implemented interfaces must be filled
in and verified by the candidate change.

Never commit runtime data, logs, temporary databases, downloads, media, browser
profiles, credentials, cookie files, tokens, or other secrets as acceptance
evidence.

If any acceptance-relevant code or configuration changes, the agent creates a
new candidate hash and the affected manual checks must be repeated.

## Result template

```text
Gate: SP-00 | M0 | M1 | ... | Release
Candidate: full or short Git commit hash
Result: PASS | FAIL
Environment: OS, browser, Racket/container version
Failed step: number, or none
Observed result: what happened
Evidence: output, screenshot, or secret-free log excerpt
```

On failure, turn the observation into a feature scenario and red harness before
changing production code.

## SP-00 — Project foundation

Purpose: confirm that a contributor can test and start the application and that
invalid configuration fails before external work starts.

1. From the repository root, run:

   ```bash
   git status --short
   racket --version
   raco test -x .
   ```

   Save the initial Git status as the comparison baseline. Expected: Racket is
   8.10 or newer and tests pass without internet access.

2. Start the application:

   ```bash
   racket listenqueue/main.rkt
   ```

   Expected: the process stays running on local port 8080.

3. From a second terminal, run:

   ```bash
   curl -i http://127.0.0.1:8080/health
   ```

   Expected: HTTP status `200` and body `ok`.

4. Stop with `Ctrl-C`, then run:

   ```bash
   racket -e '(require "listenqueue/config.rkt") (make-app-config #:port 0)'
   ```

   Expected: the command fails, identifies `port`, and starts no server.

5. Run `git status --short` again and compare it with step 1.

   Expected: starting and stopping added no tracked or unignored runtime data.

Approval response: `Gate SP-00: PASS`, or use the failure template.

## M0 — Podcast listening vertical slice `[SC-POD-005]`

Purpose: confirm the first product outcome—a real public podcast can be heard.

The tested public feed for this gate is BBC Global News Podcast:

```text
https://podcasts.files.bbci.co.uk/p02nq0gn.rss
```

It is live third-party data, so titles and episode count will change.

1. Check out the candidate commit and confirm the worktree is clean:

   ```bash
   git status --short
   git rev-parse HEAD
   ```

   Expected: no status output; `HEAD` is the candidate hash supplied for this
   gate.

2. Launch an isolated instance with a fresh temporary data directory:

   ```bash
   M0_DATA_DIR="$(mktemp -d /tmp/listenqueue-m0-XXXXXX)"
   printf '%s\n' "$M0_DATA_DIR"
   LISTENQUEUE_DATA_DIR="$M0_DATA_DIR" racket listenqueue/main.rkt
   ```

   Expected: the process remains running and reports
   `http://localhost:8080`.

3. Open <http://127.0.0.1:8080/> in a browser. Paste the feed URL above into
   `Podcast RSS URL`, then press `Add podcast`.

   Expected: the page displays titled episodes under `Discovered episodes`,
   each with an `Add to Next` control. `Next` remains empty and has no audio
   controls. Loading may take several seconds.

4. Choose `Add to Next` for the first discovered episode.

   Expected: only that episode appears under `Next` with one native audio
   control. The other discovered episodes remain outside `Next`, and the chosen
   episode's discovery control changes to `In Next`.

5. Press play on the first episode and listen for at least 30 seconds.

   Expected: audio is audible without first downloading or transcoding the full
   episode.

6. Pause playback and inspect the episode list.

   Expected: playback did not change existing queue order.

7. Stop the application with `Ctrl-C`, verify the value of `M0_DATA_DIR` is the
   uniquely generated `/tmp/listenqueue-m0-*` path from step 2, then remove only
   that directory:

   ```bash
   rm -r -- "$M0_DATA_DIR"
   ```

Approval response: `Gate M0: PASS`, or use the failure template.

## M1 — SQLite persistence `[SC-DB-009]`

Purpose: confirm state survives restart and database operations preserve domain
invariants.

From the checked-out M1 candidate, run the complete acceptance script once:

```bash
racket tools/m1-acceptance.rkt
```

The script creates its own isolated temporary database, closes and reopens it
between checks, verifies queue order and playback progress, removes one Item
from `Next`, deletes another Item, retries that upstream Item, and cleans the
temporary database even if a check fails. It retains a separate evidence
directory containing these screenshots:

```text
01-restart-and-order.png
02-queue-removal-and-progress.png
03-deletion-and-tombstone.png
```

It also creates `index.html`, which displays all three screenshots together.
Open the printed review-page path in a browser and review every image. Each
image must show the candidate hash, the relevant requirements, actual observed
state, and a green `PASS` badge. The images respectively demonstrate:

1. manual `Next` order, Items, and playback progress survived a new connection;
2. removing Episode 42 from `Next` retained its 37.5-second progress;
3. deleting Episode 41 left it tombstoned and an upstream retry inserted zero.

Expected final output:

```text
Restart and order: PASS
Queue removal and progress: PASS
Deletion and tombstone: PASS
Cleanup: PASS
Screenshots: <absolute evidence directory>
Review page: <absolute path to index.html>
Gate: M1
  Result: PASS
```

Any failed check exits nonzero and does not print `Gate: M1 ... PASS`.
Do not approve the human gate until all three retained screenshots have been
visually reviewed; terminal `PASS` output alone is insufficient.

Approval response:

```text
Gate: M1
  Candidate: <tested commit>
  Evidence: <printed evidence directory>
  Screenshots-reviewed: 3/3
  Result: PASS
```

Use the failure template if any screenshot or observed state is wrong.

## M2 — Podcast subscriptions `[SC-SUB-012]`

Purpose: confirm durable subscription, scheduling, deduplication, conditional
HTTP, failure isolation, restart, and per-Source exclusion.

From the checked-out M2 candidate, run the complete acceptance script once:

```bash
racket tools/m2-acceptance.rkt
```

The script uses deterministic RSS fixtures, an injected clock, controlled
failure/concurrency boundaries, and a temporary SQLite database. It deletes the
database even on failure but retains this evidence directory:

```text
01-subscription-created.png
02-atom-feed-supported.png
03-scheduled-refresh.png
04-discovery-keeps-next-empty.png
05-conditional-http.png
06-disabled-source-idle.png
07-failure-isolation.png
08-restart-retains-source.png
09-source-exclusion.png
index.html
```

Open the printed `index.html` path and review all nine images. Every image must
show the tested candidate hash, requirement IDs, actual observed state, and a
green `PASS` badge. In order, they demonstrate:

1. one durable enabled subscription with two discoveries and empty `Next`;
2. a practical Atom entry becomes one playable podcast Item;
3. one due tick discovers exactly one new Item without real waiting;
4. reordered/repeated discovery creates no duplicates and leaves `Next` empty;
5. ETag and Last-Modified are sent and HTTP 304 returns no Items;
6. a disabled due Source performs no pull and keeps its state unchanged;
7. one Source fails without advancing its state or stopping another Source;
8. configuration, ETag, success time, and due time survive a new connection;
9. a second pull of an already-running Source is rejected.

Expected terminal summary:

```text
Subscription created: PASS
Atom feed supported: PASS
Scheduled refresh: PASS
Discovery keeps Next empty: PASS
Conditional HTTP: PASS
Disabled Source idle: PASS
Failure isolation: PASS
Restart retains Source: PASS
Source exclusion: PASS
Cleanup: PASS
Screenshots: <absolute evidence directory>
Review page: <absolute path to index.html>
Screenshots-reviewed: 9 required
Gate: M2
  Result: PASS
```

Any failed check exits nonzero and does not print `Gate: M2 ... PASS`. Terminal
PASS output alone is insufficient; do not approve until every image is reviewed.

Approval response:

```text
Gate: M2
  Candidate: <tested commit>
  Evidence: <printed evidence directory>
  Screenshots-reviewed: 9/9
  Result: PASS
```

Use the failure template if any screenshot or observed state is wrong.

## M3 — yt-dlp sources

Purpose: confirm YouTube and Bilibili ingestion and on-demand audio resolution.

1. Record `yt-dlp --version` and use the documented public YouTube and Bilibili
   acceptance URLs.
2. Add both sources and request refresh.

   Expected: both produce titled normalized Items without duplicates.

3. Inspect the data directory before and after refresh.

   Expected: refresh downloaded or transcoded no complete media files.

4. Play one Item from each provider.

   Expected: audio resolves on demand and is audible.

5. Run the documented unsupported-URL and missing-authentication checks.

   Expected: errors identify source and operation without exposing secrets or
   signed URLs.

Approval response: `Gate M3: PASS`, or use the failure template.

## M4 — Policy

Purpose: confirm admission and placement without re-sorting existing entries.

1. Load the documented accepted, rejected, and extension-predicate fixtures.
2. Arrange existing `Next` manually as `C, A, B`.
3. Admit `N` with `front` placement.

   Expected: `N, C, A, B`; existing relative order stays `C, A, B`.

4. Admit another Item with `back` placement.

   Expected: it appears after `B` without moving existing entries.

5. Process a rejected Item.

   Expected: it stays out of `Next` but remains stored and seen.

6. Exercise the documented extension-provided predicate.

   Expected: it affects placement without provider/language behavior being
   hard-coded into core queue operations.

Approval response: `Gate M4: PASS`, or use the failure template.

## M5 — Retention

Purpose: confirm filtered cleanup, preview, retry safety, and tombstones.

1. Load the documented old/new, started/unstarted, and in/out-of-`Next` fixtures.
2. Preview the documented retention rule.

   Expected: only matching Items appear and no state changes.

3. Execute the rule.

   Expected: previewed Items receive the action; unrelated Items do not change.

4. Pull an upstream feed that still contains a deleted episode.

   Expected: the deliberately deleted episode does not return.

5. Re-run retention and the pull.

   Expected: both are idempotent and `Next` remains valid.

6. Remove from `Next` an Item with playback progress.

   Expected: queue membership is removed while Item and progress remain.

Approval response: `Gate M5: PASS`, or use the failure template.

## M6 — Playback

Purpose: confirm resume, completion, expiry recovery, and useful failures.

1. Play a podcast for 30 seconds, pause, reload, and restart the service.

   Expected: playback resumes near the saved position.

2. Let a short acceptance Item end naturally.

   Expected: completion persists without deleting Item or seen history.

3. Remove a partially played Item from `Next`, then open it again.

   Expected: saved progress still exists.

4. Run the documented expiring-media acceptance harness.

   Expected: media resolves again once and does not retry forever.

5. Run the documented unplayable-media case.

   Expected: the UI shows a useful, secret-safe error and remains available.

Approval response: `Gate M6: PASS`, or use the failure template.

## M7 — Minimal Web UI

Purpose: confirm the complete browser workflow and manual-order authority.

1. Add, disable, refresh, and remove a subscription.
2. Add several Items to `Next`; reorder with pointer and keyboard controls.

   Expected: both methods persist the same order and focus remains clear.

3. Open two tabs, reorder in the first, then attempt a stale move in the second.

   Expected: the newer order is not silently overwritten.

4. Remove an Item from `Next` and confirm this is visibly different from
   deleting the Item.
5. Play, pause, resume, and complete an Item.
6. Trigger documented source and playback errors.

   Expected: messages are understandable and contain no credentials or signed
   URLs.

7. Confirm no page offers multiple queues, playlists, users, or workflow
   editing.

Approval response: `Gate M7: PASS`, or use the failure template.

## M8 — DSL exploration

Purpose: make a human design decision from evidence; implementing a DSL is not
automatically the passing outcome.

1. Review three real plain-Racket configurations and documented pain points.
2. Compare candidate declarative forms and expansion examples.
3. Review error examples and the capability matrix.
4. Confirm the candidate cannot express scheduling graphs, arbitrary branches,
   shell execution, or replacement runtime control flow.
5. Choose `IMPLEMENT`, `DEFER`, or `REJECT`.
6. If syntax exists, load valid and representative invalid configurations.

   Expected: valid syntax lowers to existing APIs, errors identify source forms,
   and plain Racket remains fully supported.

Approval response: `Gate M8: PASS — decision IMPLEMENT|DEFER|REJECT`, or use the
failure template.

## Release — Deployment and operations

Purpose: confirm the self-hosted delivery promised by v0.1.

1. On a clean Docker Compose host, run:

   ```bash
   docker compose up -d
   ```

2. Confirm health and open ListenQueue from the trusted-LAN client.
3. Subscribe, play an Item, save progress, and arrange `Next`.
4. Replace/restart the container with the same `/data` mount.

   Expected: subscriptions, seen history, queue order, and progress survive.

5. Inspect image configuration and logs with the documented secret test.

   Expected: secrets and signed URLs are absent.

6. Perform the documented backup, change state, restore, and verify the restored
   state.
7. Follow the documented upgrade procedure using a pre-upgrade backup.

Approval response: `Gate Release: PASS`, or use the failure template.
