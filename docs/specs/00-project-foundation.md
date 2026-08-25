# SP-00 — Project Foundation

Status: Draft

## Objective

Create the smallest idiomatic Racket project that supports incremental
development, automated tests, and a local HTTP entry point. This subproject is a
prerequisite, not a product milestone of its own.

## User outcome

A contributor can clone the repository, run the test suite, start the local
application, and understand where pure domain code and effectful integrations
belong.

## In scope

- Racket package metadata and module entry points
- A small source and test layout
- One documented test command
- A minimal configuration representation
- A minimal local HTTP server or handler needed by SP-01
- Explicit boundaries for domain, feed/network, media, and web effects
- Development documentation for prerequisites and commands

## Out of scope

- Product-complete configuration
- SQLite schema
- Background scheduling
- Authentication
- A framework-like dependency injection system
- Macros, custom languages, plugin registries, or generic pipelines
- Production container images

## Requirements

### FND-001 — Package structure

The repository must be recognizable to standard Racket tooling. Modules should
have narrow `provide` lists and should not expose internal helpers by default.

The exact directory layout is allowed to evolve. Conceptual boundaries matter
more than matching the provisional tree in `spec.md`.

### FND-002 — Entry points

Provide a clear application entry point and a clear test entry point. Starting
the application must not execute network pulls or mutate persistent user data
merely because a module was required from the REPL or a test.

### FND-003 — Configuration

Initial configuration may be a transparent struct or ordinary function
arguments. Validate values at the boundary. Do not design the future policy DSL
in this subproject.

### FND-004 — Effect boundaries

Network, clock, filesystem, subprocess, and HTTP-server effects must be callable
through small functions or interfaces that tests can replace with fixtures or
fakes. Pure domain modules must not depend on the web server.

### FND-005 — Diagnostics

Startup failures must identify the failing operation without printing secrets.
The application should have a simple health response suitable for local smoke
testing, but production observability belongs to SP-09.

### FND-006 — Tooling

Document the exact commands that work in this repository. At minimum, the
default test suite must run through `raco test`. Do not document commands that
have not been verified.

### FND-007 — Behavior traceability

Provide a lightweight check that validates behavior contracts under `features/`:

- every Scenario has one globally unique `@SC-*` ID;
- every Scenario has a subproject tag, requirement tag, and execution tag;
- duplicate scenario IDs fail;
- every implemented `@automated` scenario maps to a RackUnit harness carrying
  the same scenario ID;
- harness references to unknown scenario IDs fail.

This check may scan the limited repository conventions directly. It must not
grow into a complete Gherkin parser or step-definition runtime.

## Testing

- A smoke test requires the main module without starting background work.
- A handler or server test confirms the local health response.
- Configuration tests cover valid input and representative invalid values.
- Behavior-contract tests cover missing, duplicate, and unknown scenario IDs.
- The default suite must not require network access, `yt-dlp`, `ffmpeg`, or a
  persistent database.

## Acceptance criteria

SP-00 is complete when:

1. `raco test` runs the repository tests successfully.
2. The application starts locally with a documented command.
3. A health request returns a successful response.
4. Requiring core modules has no hidden external side effects.
5. The README contains accurate development prerequisites and commands.
6. Behavior contracts and RackUnit harnesses have mechanically checked scenario
   ID traceability.

## Dependencies and follow-ups

SP-00 has no product dependency. It must remain deliberately small and expand
only when a later subproject demonstrates a concrete need.
