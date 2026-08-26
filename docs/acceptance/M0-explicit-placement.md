# M0 Explicit Placement Acceptance Record

Status: Accepted
Candidate: `cf033e7793638d4a901791e20f94a87d695b0d1e`
Accepted on: 2026-08-26

## Reason for re-acceptance

After accepting the original M0 candidate, the user reported that loading a new
RSS feed must not put every discovered episode directly into `Next`. Candidate
`cf033e7` separates feed discovery from explicit user placement. The original
record remains historical evidence for `b2bc265`, but its approval does not
apply to later revisions.

## Automated evidence

- The regression harness failed before implementation because discovery-only
  and explicit-placement operations did not exist
- `raco test -x .`: 26 tests passed after implementation
- `raco make` for the application and harness modules: passed
- `git diff --check`: passed before the candidate commit
- Live BBC RSS smoke: 279 episodes discovered and zero audio controls in `Next`
- Selecting the same live episode twice: one `In Next`, one audio control, and
  278 episodes still offering `Add to Next`
- Candidate and `origin/main` were verified at the same full commit hash

## Human result

The user reported:

```text
Gate: M0
Candidate: cf033e7
Result: PASS
```

No additional environment details were reported. M0 is accepted with explicit
episode placement. Production implementation for M1 may resume after this
record is committed and pushed.
