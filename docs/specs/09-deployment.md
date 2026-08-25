# SP-09 — Deployment and Operations

Status: Draft

## Objective

Package ListenQueue as a restart-safe, self-hosted application that runs with
one container/process, one persistent data directory, SQLite, `yt-dlp`, and
`ffmpeg` where needed.

## User outcome

A user can configure the application, run `docker compose up -d`, open it on a
trusted LAN, upgrade it deliberately, and retain all data across restarts.

## In scope

- Reproducible container image
- Docker Compose configuration
- Persistent `/data` layout
- Configurable port and timezone
- Bundled or installed compatible Racket, `yt-dlp`, and `ffmpeg`
- Non-root runtime where practical
- Health check and graceful shutdown
- Secret/cookie file mounting
- Logging, backup, restore, and upgrade documentation

## Out of scope

- Kubernetes, Redis, Kafka, PostgreSQL, or an external scheduler
- Mandatory cloud services
- Horizontal scaling
- Public SaaS deployment
- Built-in TLS certificate management
- Automatic unattended database downgrade

## Runtime layout

The default persistent layout is:

```text
/data/
├── listenqueue.db
├── cache/
├── downloads/
└── secrets/
```

Only directories actually used by v0.1 need to be created. Empty cache/download
features must not be invented merely to match the diagram.

## Requirements

### OPS-001 — Single application unit

The supported deployment is one ListenQueue container/process. SQLite and the
in-process scheduler run inside that unit. Do not add infrastructure services
without changing the product specification.

### OPS-002 — Reproducible image

Pin major runtime/tool versions or otherwise make builds repeatable. Record the
Racket and `yt-dlp` versions in diagnostics. The image build must not rely on
credentials or developer-home state.

### OPS-003 — Persistent data

All durable application state lives below the configured data directory. A
container replacement using the same mounted data directory must preserve
database, seen history, queue order, and playback progress.

### OPS-004 — Configuration

Support documented configuration for data path, listen address/port, timezone,
refresh defaults, maintenance interval, and secret paths actually required by
implemented features. Validate configuration before starting background work.

### OPS-005 — Secrets

Mount cookie files or tokens under protected persistent secret storage or inject
them through an explicitly supported secret mechanism. Do not bake them into
images, Compose files committed to Git, environment dumps, or logs.

### OPS-006 — Network exposure

Document that v0.1 is for a trusted LAN and has no multi-user authentication.
Default to a conservative bind address unless the user explicitly enables LAN
access. Public internet exposure requires an authenticated TLS reverse proxy
outside the v0.1 core.

### OPS-007 — Health and shutdown

Expose a health check that distinguishes process availability from optional
external-source health. On shutdown, stop accepting new work, prevent new
scheduled pulls, finish or cancel bounded work, persist state, and close SQLite
cleanly.

### OPS-008 — Logging

Write structured or consistently formatted logs to stdout/stderr with time,
level, operation, and relevant entity IDs. Redact secrets and signed URLs.
Normal source failures must not cause crash loops.

### OPS-009 — Backup and restore

Document a SQLite-safe backup procedure and a restore procedure. Backups must be
consistent even when the service normally runs continuously. State whether the
service must be stopped or whether SQLite's backup mechanism is used.

### OPS-010 — Upgrade

Document image upgrade steps, database migration behavior, rollback limits, and
the need for a pre-upgrade backup. Refuse schemas newer than the running image.

### OPS-011 — Resource behavior

Set practical timeouts and concurrency bounds for feed requests and `yt-dlp`
processes. The service must not accumulate unbounded subprocesses, responses,
logs, or temporary files.

## Testing

- Container image build
- Container startup with a temporary mounted data directory
- Health check
- Restart and container replacement preserving state
- Config validation failures
- Graceful shutdown during idle and active work
- Executable/version checks for Racket, `yt-dlp`, and `ffmpeg`
- Secret redaction
- Backup and restore smoke test
- Compose configuration validation

## Acceptance criteria

SP-09 is complete when:

1. `docker compose up -d` starts a healthy ListenQueue instance.
2. The configured port and timezone take effect.
3. Container restart/replacement does not lose persistent state.
4. Podcast and supported video playback work from the image.
5. Missing required tools or invalid configuration fail clearly at startup.
6. Secrets do not appear in the image, committed configuration, UI, or logs.
7. Backup, restore, upgrade, and trusted-LAN exposure are documented and tested.

## Dependencies and follow-ups

Depends on the integrated application through SP-08. Deployment feedback may
require bounded operational changes in earlier subprojects, but must not turn
the system into distributed infrastructure.
