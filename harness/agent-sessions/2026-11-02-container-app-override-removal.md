# Session: Remove runtime app-fetch overrides

## Summary
- Removed `scripts/fetch-apps.sh` and its documented setup/handoff steps.
- App resolution now accepts binaries baked into the SIF: `/apps` first, with `/opt` as a SIF-only fallback for the already-built image; no per-user app override remains.
- Removed state app candidates and the legacy fetch workflow; updated README/HPC handoff guidance. Node runtime keeps a transitional state-mounted Node path for the existing image, which will go away when a new SIF is validated.

## Validation
- Shell syntax checks passed for affected scripts.
- Initial Node tests passed: 25. On continuation, the worktree showed a separate uncommitted router edit plus an untracked watcher script. I left both untouched; with that router edit present, 1 of 25 tests now fails because a test expects no task-intent heuristic while the edit escalates `no-tool-call` and wide prompts.
- `git diff --check` passed.
- Inspected the existing SIF with `singularity sif` and `unsquashfs` (data offset 49152). It contains executable IDE, App 2.0, CLI, and Obsidian binaries under `/opt`, not `/apps`; the SIF-embedded definition also identifies the older `/opt` layout. Binary executable modes confirmed.
- Added a SIF-only `/opt` compatibility fallback after confirming the path mismatch; no per-user override was restored.
- Runtime smoke test remains blocked: the installed Singularity build has no setuid installation; `--userns` and `--fakeroot` both attempted conversion but failed on the setuid requirement. Using `~/ss/tmp` removed the disk-capacity issue. No SIF rebuild attempted.

## Follow-up
- Build a new SIF using the current `/apps` definition when a suitable runtime/temp location is available; do not overwrite current 839 MB image without explicit confirmation.
- Run app resolution smoke tests and SSM package validation against that rebuilt SIF.
