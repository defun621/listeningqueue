# ListenQueue

ListenQueue is a self-hosted listening inbox with one ordered playback queue:
`Next`. It pulls new episodes and videos from subscribed sources, filters them
through configurable policies, and inserts accepted items without disturbing
the user's existing queue order.

## Status

ListenQueue is in the design and early implementation phase. The target is a
v0.1 Racket application backed by SQLite and deployable as a single container.

## Planned features

- Podcast RSS/Atom subscriptions
- YouTube, Bilibili, and other video sources through `yt-dlp`
- Periodic source refresh and deduplication
- Admission, initial-placement, and retention policies
- Manual queue ordering that always takes precedence
- On-demand media resolution and playback progress persistence
- Minimal web interface for subscriptions, playback, and queue management

ListenQueue deliberately has one queue and is not a general workflow engine.
Extensions add integrations and domain predicates, while the runtime retains
control of scheduling and item lifecycle.

See [spec.md](spec.md) for the full product and architecture specification, and
[the subproject specifications](docs/specs/README.md) for implementation scope
and acceptance criteria by work area. Executable behavior contracts are written
as [Gherkin-style feature scenarios](features/README.md) before implementation.

## Development

Requirements:

- Racket 8.10 or newer

Run the deterministic, offline test suite:

```bash
raco test -x .
```

Start the local application:

```bash
racket listenqueue/main.rkt
```

Check process health from another terminal:

```bash
curl -i http://127.0.0.1:8080/health
```

## Listen to a podcast

With the application running, open <http://127.0.0.1:8080/> and submit this
public RSS 2.0 test feed:

```text
https://podcasts.files.bbci.co.uk/p02nq0gn.rss
```

ListenQueue displays the discovered episodes without automatically putting them
in `Next`. Choose `Add to Next` on the episode you want, then press its native
audio player's play button. Selecting the same episode repeatedly cannot create
duplicate queue entries.

Items, seen history, `Next` order, and playback state are stored in SQLite. Set
the data directory explicitly when developing or self-hosting:

```bash
LISTENQUEUE_DATA_DIR=/path/to/listenqueue-data racket listenqueue/main.rkt
```

The database is created as `listenqueue.sqlite3` under that directory. Without
the environment variable, ListenQueue uses the platform's Racket preferences
directory.

The current slice supports one-shot public HTTP(S) RSS 2.0 loading, direct
podcast enclosures, and durable core listening state. Subscriptions and refresh
scheduling arrive in later milestones. The BBC test feed is a live third-party
resource and may change independently of ListenQueue.

Milestones require explicit human sign-off after automated checks. See the
[manual acceptance runbook](docs/manual-acceptance.md).

## License

See [LICENSE](LICENSE).
