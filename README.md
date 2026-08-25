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

## License

See [LICENSE](LICENSE).
