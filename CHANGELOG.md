<!-- markdownlint-disable MD024 -->
# Changelog

## 0.3.2 - 2026-09-05

### Fixed

- Fix graceful-shutdown race: before the grace timer escalates to `SIGKILL`, reconcile the main child state with a non-blocking reap. A child that already exited while `SIGCHLD` was still pending on the signalfd now keeps its real exit status instead of being reported as a forced `SIGKILL`/137. Applies equally to the timer-unavailable immediate-escalation path and to both amd64 and arm64.

### Tests

- Add a deterministic stop/release regression (`scripts/test_sigchld_timer_race.sh`) that arms the grace timer, registers its timerfd in epoll, stops init, lets the timer fire and the child exit, then resumes init; verified RED before the fix and GREEN after on native ARM64, with the amd64 runner quirk detected and skipped.

## 0.3.1 - 2026-01-11

### Fixed

- Fix `debian/control` Architecture field: changed from `any` to `amd64 arm64` to prevent FTBFS on unsupported architectures.
- Add explicit `make` to Build-Depends for reproducible builds across all environments.

### Improved

- Implement VERSION single source of truth: version now controlled by `VERSION` file at repository root.
- Auto-generate arch-specific version include files (`include/version_amd64.inc`, `include/version_arm64.inc`) during build.
- Version string length now calculated dynamically (no hardcoded lengths).
- Version bumps now require changing only 1 file instead of 4 separate locations.

### Tests/Docs

- Add restart-on-crash test to `debian/tests/smoke`: validates `EP_RESTART_ENABLED` and `EP_MAX_RESTARTS` functionality.
- Add PGID signal fan-out test to `debian/tests/smoke`: verifies signals reach both child and grandchild processes.
- Autopkgtest now validates 5 critical behaviors (was 3).
- Document that `EP_ARM64_FALLBACK` mode is NOT suitable for production (CI testing stub only).
- List features NOT available in fallback mode: signal forwarding, graceful shutdown, restart, custom EP_SIGNALS.
- Add restart configuration best practices: guidance on backoff delays and restart limits to prevent tight CPU loops.
- Add Debian packaging guide section with build instructions, autopkgtest usage, lintian checks, and supported architectures.
- Update man page date and version metadata to match VERSION file.
- Document that ARM64 native tests run on every PR (validates full epoll/signalfd path).

## 0.3.0 - 2026-01-06

- Real-time signals: `EP_SIGNALS=RT*` now requires explicit `EP_SIGRTMIN`/`EP_SIGRTMAX` (avoids hardcoded SIGRTMIN/SIGRTMAX assumptions).
- `EP_SIGNALS` now supports numeric signal tokens (`1..64`, excluding SIGKILL/SIGSTOP).
- Logging and fd I/O: add `write_all` handling partial writes and `EINTR`; harden `signalfd`/`timerfd` reads.
- ARM64 correctness: fix AArch64 call/return ABI issues (preserve `x30` where required), ensure `do_spawn` is instruction-aligned (avoid native SIGILL), and fix `EP_SIGNALS` parsing crash (token parsing no longer relies on a clobbered register).
- Correctness: avoid forwarding signals after the main child has exited while restart backoff is pending (prevents accidental signaling of a reused PGID).
- Debian readiness: add `mini-init-asm(1)` and an initial `debian/` packaging skeleton with autopkgtest and CI lintian build.

## 0.2.0 - 2025-12-13

### Fixed

- Fix critical PID1 hang: main-child exit could be missed during SIGCHLD storms (now reliably detected/reported on both amd64 and arm64).
- Fix amd64 restart-mode stack safety when max restarts are reached.
- Prevent `epoll` fd leakage into the exec’ed child (`epoll_create1(EPOLL_CLOEXEC)`).
- Avoid SIGKILL escalation to a reused/nonexistent PGID (`kill(-pgid, 0)` probe before escalation).
- Fix verbose logging writing a NUL byte in timestamps.

### Improved

- More actionable verbose logs: signal number, grace seconds, restart backoff seconds, and restart count.
- Harden `EP_SIGNALS` parsing:
  - Trim trailing whitespace per token.
  - Real-time signals are now bounded to the kernel max (`RT1..RT30`).
- Numeric env vars are now parsed strictly as decimal digits; invalid/overflow values are ignored (warnings in verbose mode).
- Timer-related seconds (grace/backoff) are clamped to fit signed 64-bit seconds.
- `EP_EXIT_CODE_BASE` is now validated as `0..255` (out-of-range values are ignored; default applies).
- ARM64/QEMU: remove `msub` usage in hot paths; in `EP_ARM64_FALLBACK=1` mode timestamps are omitted to reduce QEMU-user flakiness.

### Tests/Docs

- Add an edge-case test covering “main child exits while many other children are reaped”.
- Update docs to reflect RT signal bounds and ARM64 fallback timestamp behavior.
- ARM64/QEMU: in fallback mode, smoke tests now exercise `--version` and the wait4-only path (helper exit propagation) instead of skipping entirely.
- Clean up `scripts/*` quoting to avoid common ShellCheck warnings (SC2016/SC2086).
