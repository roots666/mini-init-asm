# mini-init-asm (PGID-mode)

A tiny **PID 1** for containers, written in **x86-64 NASM** and **ARM64 GAS**.

It spawns your target process as its *own process group*, forwards signals to the whole group,
reaps zombies, and optionally restarts your app on crash. On exit, it returns your app's status
code (with configurable signal→exit mapping).

> **Architectures:** x86-64 Linux (native NASM build) and arm64/AArch64 (cross-build via GNU toolchain).

---

## TL;DR

- **Problem:** many containers still run without a proper PID 1, which breaks signal handling and zombie reaping.
- **Solution:** `mini-init-asm` is a **tiny, auditable init** that:
  - creates a **new session + process group** for your app;
  - forwards signals to the **entire group**;
  - reaps zombies (plus optional **subreaper** mode);
  - supports **graceful shutdown** with configurable timeout and `SIGKILL` escalation;
  - can **restart** the app on crashes (optional, env-driven);
  - is implemented in **pure assembly** using Linux syscalls only (no libc).

It’s a parallel, assembly-focused alternative to tools like [Tini](https://github.com/krallin/tini):
similar semantics for containers, but a different implementation style and feature focus.

---

## When to use mini-init-asm

Use `mini-init-asm` if you:

- Build **minimal or `FROM scratch` images**, and want a tiny, static PID 1.
- Run **multi-process containers** and need robust **process-group** signal fan-out.
- Want a **small, auditable** init written in pure assembly (good for learning & review).
- Need simple **restart-on-crash** behavior without a full-blown supervisor.

If you just want a battle-tested init with wide distro support, you probably still want
[Tini](https://github.com/krallin/tini). This project is intentionally **small and opinionated**, and
targets PGID-mode container entrypoints.

---

## mini-init-asm vs Tini

This project is heavily inspired by the patterns popularized by [Tini](https://github.com/krallin/tini):
spawn one child, forward signals, reap zombies. The difference is mainly in **implementation** and
a few **runtime semantics**.

### High-level comparison

| Aspect                            | **mini-init-asm**                                              | **Tini**                                                                                 |
| --------------------------------- | -------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| Language                          | x86-64 NASM + ARM64 GAS                                        | C                                                                                        |
| Architectures                     | amd64, arm64                                                   | Many (amd64, arm, armhf, i386, etc. – see releases)                                      |
| Binary type                       | Static, **no libc**, pure Linux syscalls                       | Dynamic + static variants; depends on libc                                               |
| Default kill mode                 | Always kills **process group** (`kill(-pgid, sig)`)            | By default kills **child only**, group-kill via `-g` / `TINI_KILL_PROCESS_GROUP`         |
| Session / PGID                    | Always creates **new session + PGID** for child                | Optional group-kill mode; no hard “PGID-mode only” branding                              |
| Signal handling                   | `signalfd(2)` + `epoll(7)` + `timerfd(2)` event loop           | traditional signal handlers + wait / reaping loop                                        |
| Subreaper support                 | `EP_SUBREAPER=1` env (uses `PR_SET_CHILD_SUBREAPER`)           | `-s` flag or `TINI_SUBREAPER` env                                                        |
| Restart-on-crash                  | Yes, via `EP_RESTART_*` env vars (simple supervisor mode)      | No (Tini intentionally does **not** supervise / restart children)                        |
| Exit code mapping                 | `EP_EXIT_CODE_BASE` (base + signal number)                     | `-e` flags to remap specific exit codes to 0                                             |
| Config surface                    | Mostly **env vars** + minimal flags (`-v`, `-V`)               | CLI flags (`-v`, `-s`, `-g`, `-e`, `-p`, …) + env vars                                   |
| Ecosystem integration             | Standalone binary, Dockerfile provided                         | Packaged in many distros; integrated into Docker via `--init`                            |
| Size (qualitative)                | Tiny static binary (pure asm, no libc; tens-of-KB range)       | Tiny dynamic binary (~10KB), static version still <1MB (per upstream docs)               |

> The goal of `mini-init-asm` is **not** to replace Tini everywhere, but to offer:
>
> - a **PGID-first**, assembly-level implementation;
> - an example of a full-featured container init in pure asm;
> - a small init with **restart-mode** for simple setups.

### Feature matrix (plain PID1 vs Tini vs mini-init-asm)

| Feature / Behavior          | Plain app as PID 1          | Tini                          | mini-init-asm (this repo)                       |
|-----------------------------|-----------------------------|-------------------------------|-------------------------------------------------|
| Signal forwarding           | Depends on app              | Yes                           | Yes (group-wide)                                |
| Zombie reaping              | Depends on app              | Yes                           | Yes                                             |
| Process-group kill          | Depends on app              | Optional (`-g` / env)         | Always group-based                              |
| Subreaper mode              | No                          | Yes (`-s` / `TINI_SUBREAPER`) | Yes (`EP_SUBREAPER=1`)                          |
| Restart on crash            | Depends on app              | No                            | Yes (`EP_RESTART_*` envs)                       |
| Pure-syscall implementation | Rare                        | No (libc)                     | Yes                                             |
| Minimal config surface      | N/A                         | CLI + env                     | Primarily env, very small CLI                   |

### Note (why choose this vs tini?)

Most distros already provides well-established init helpers (notably `tini`) and Docker can enable one via `--init`.
`mini-init-asm` is mainly useful when you specifically want:

- A pure-syscall, libc-free implementation (e.g. for very small/static images or audit/learning goals).
- Process-group forwarding as the default behavior (PGID-first “entrypoint init” semantics).
- Optional restart-on-crash behavior (Tini intentionally does not supervise/restart children).

If you just need a battle-tested, widely deployed init with broad architecture coverage and a long track record, prefer `tini`.

---

## Quick Start

### Prerequisites (Debian/Ubuntu)

```bash
sudo apt-get update
sudo apt-get install -y nasm make binutils
````

### Build (x86-64)

```bash
make
```

### Example run (x86-64)

```bash
./build/mini-init-amd64 -- /bin/sh -c 'echo hello && sleep 5'
```

### Cross-build (ARM64 / AArch64)

Install a cross toolchain:

```bash
sudo apt-get install -y gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu
make build-arm64
```

### Native build (ARM64 host)

On an ARM64 machine, you can build natively:

```bash
sudo apt-get install -y make binutils
make build-arm64
```

And you can run the regular test scripts against the ARM64 binary:

```bash
bash scripts/test_harness.sh build/mini-init-arm64
bash scripts/test_ep_signals.sh build/mini-init-arm64
bash scripts/test_edge_cases.sh build/mini-init-arm64
bash scripts/test_exit_code_mapping.sh build/mini-init-arm64
bash scripts/test_restart.sh build/mini-init-arm64
bash scripts/test_diagnostics.sh build/mini-init-arm64
```

### Example run (ARM64 via QEMU on x86 host)

Requires `qemu-user-static` to run an ARM64 binary on x86:

```bash
# Recommended: ensures the second `--` reaches mini-init
qemu-aarch64-static -- ./build/mini-init-arm64 -- /bin/sh -c 'echo hello && sleep 5'

# Alternatively (works in some shells too):
# qemu-aarch64-static ./build/mini-init-arm64 -- /bin/sh -c 'echo hello && sleep 5'
```

If you see a usage message like `usage: mini-init-arm64 ...`, the `--` delimiter was swallowed
by QEMU. Use the extra `--` right after `qemu-aarch64-static`.

> Note: QEMU user-mode emulation can be flaky for the full epoll/signalfd/timerfd loop on some hosts.
> CI therefore uses `EP_ARM64_FALLBACK=1` for a minimal smoke test, and also runs native ARM64 tests
> on GitHub-hosted ARM runners (subject to runner availability). For higher confidence, run tests on
> real ARM64 hardware or use full-system emulation (qemu-system-aarch64) for integration tests.

### Graceful stop demo

```bash
# Run and interrupt with Ctrl+C (TERM to group, grace window, optional KILL)
./build/mini-init-amd64 -- bash -c 'trap "echo got TERM; exit 0" TERM; sleep 1000'
```

---

## Docker

### Single architecture (amd64)

```bash
docker build -t mini-init-asm:dev -f docker/Dockerfile .
docker run --rm -it mini-init-asm:dev -- /bin/sh -c 'sleep 1000'
# In another terminal:
docker kill --signal=TERM <container-id>
```

### Multi-architecture (amd64 + arm64)

```bash
# Build for both platforms
docker buildx build --platform linux/amd64,linux/arm64 \
    -t mini-init-asm:latest -f docker/Dockerfile.multiarch .

# Run on specific platform
docker run --rm --platform linux/amd64 -it mini-init-asm:latest -- /bin/sh -c 'echo hello'
docker run --rm --platform linux/arm64 -it mini-init-asm:latest -- /bin/sh -c 'echo hello'
```

---

## Usage

```bash
mini-init-{amd64|arm64} [--verbose|-v] [--version|-V] -- <command> [args...]
```

### Command-line options

- `-v`, `--verbose` — enable verbose logging (timestamps, fds, signal events).
- `-V`, `--version` — print version string and exit.

### Environment variables

Numeric env vars are parsed as **non-negative decimal**. If a value is invalid/overflows, it is ignored (defaults apply); in verbose mode a warning is logged. Timer-related values (grace/backoff seconds) are clamped to fit in signed 64-bit seconds.

- `EP_GRACE_SECONDS`
  Grace period (in seconds) from the *first* forwarded soft signal to `SIGKILL` escalation.
  Default: `10`.

- `EP_SIGNALS`
  CSV of **additional** signal names to monitor/forward (case-sensitive).
  Supported tokens:
  - Named: `USR1,USR2,PIPE,WINCH,TTIN,TTOU,CONT,ALRM`
  - Numeric: decimal signal numbers `1..64` (SIGKILL and SIGSTOP are ignored)
  - Real-time: `RT1..RT30` (\=`SIGRTMIN+N`), only if `EP_SIGRTMIN` and `EP_SIGRTMAX` are set (see below)
  These **augment** the built-in set: `HUP,INT,QUIT,TERM,CHLD` plus default forwarding
  of `USR1,USR2,PIPE,WINCH,TTIN,TTOU,CONT,ALRM`.
  Unknown tokens are ignored with a warning. In verbose mode we only log
  “EP_SIGNALS parsed” if the variable is present (even if empty).

- `EP_SIGRTMIN`, `EP_SIGRTMAX`
  Decimal runtime values for SIGRTMIN/SIGRTMAX in the target libc environment.
  Required to enable `RT*` tokens in `EP_SIGNALS`.
  This avoids hardcoding RT signal numbers (see `signal(7)`; SIGRTMIN can vary at runtime on glibc with threads).

- `EP_SUBREAPER`
  If set to `1`, enables `PR_SET_CHILD_SUBREAPER` so that `mini-init-asm` adopts orphaned
  grandchildren. Useful when nested processes need proper reaping.
  `mini-init-asm` still exits when the main child exits (it does not wait indefinitely for adopted descendants).
  Default: disabled.

- `EP_EXIT_CODE_BASE`
  Base value for mapping “killed by signal” to exit code:
  `exit_code = EP_EXIT_CODE_BASE + signal_number` (default base `128`, like shells).
  For example, `SIGKILL` (9) with base 200 → exit code 209.
  Valid range: `0..255` (out-of-range values are ignored; default applies).

- `EP_RESTART_ENABLED`
  If set to `1`, enables **restart-on-crash**: when the child is killed by a signal
  (non-zero, non-normal exit), `mini-init-asm` restarts it.
  Restarts are **disabled** during graceful shutdown (after a soft signal like
  `TERM/INT/HUP/QUIT`).
  Default: disabled.

- `EP_MAX_RESTARTS`
  Maximum number of restarts when `EP_RESTART_ENABLED=1`.
  Allows up to `N` restarts (`N+1` total runs: initial + N restarts).
  If the child crashes more than N times, `mini-init-asm` exits with the child’s code.
  Set to `0` for **unlimited** restarts. Default: `0`.

- `EP_RESTART_BACKOFF_SECONDS`
  Delay before restarting a crashed child. Helps avoid tight restart loops.
  `0` = restart immediately. Default: `1`.

- `EP_ARM64_FALLBACK` (ARM64/QEMU only)
  If set to `1`, ARM64 builds skip the epoll/signalfd path and use a simpler
  `wait4` loop. Intended as a workaround for QEMU user-mode flakiness in CI smoke tests.

  **WARNING:** This mode is a CI testing stub and is **NOT suitable for production use**.
  It does **NOT** provide:
  - Signal forwarding to child process group
  - Graceful shutdown with grace period escalation
  - Restart-on-crash functionality
  - Custom signal monitoring (EP_SIGNALS)

  Fallback mode only verifies basic spawn and exit code propagation. Use it **only**
  for CI smoke testing under QEMU user-mode emulation. For production, run the full
  binary on native ARM64 hardware or use full-system emulation.

  In fallback mode, verbose logs may omit timestamps to avoid QEMU-user emulation issues.
  Default: `0` (CI jobs typically set this).

### Examples

```bash
# Default behavior: forward TERM/INT/HUP/QUIT to the group, wait 10s, then KILL if needed
./build/mini-init-amd64 -- ./your-app --flag

# Verbose logs
./build/mini-init-amd64 -v -- ./your-app

# Check version
./build/mini-init-amd64 --version

# Custom grace period
EP_GRACE_SECONDS=5 ./build/mini-init-amd64 -- ./your-app

# Add USR1 forwarding
EP_SIGNALS=USR1 ./build/mini-init-amd64 -- ./your-app

# Add RT signals (RT1 = SIGRTMIN+1, RT5 = SIGRTMIN+5)
# RT tokens are only enabled if you provide runtime SIGRTMIN/SIGRTMAX explicitly:
EP_SIGRTMIN=34 EP_SIGRTMAX=64 EP_SIGNALS=RT1,RT5 ./build/mini-init-amd64 -- ./your-app

# Enable subreaper mode (adopt orphaned grandchildren)
EP_SUBREAPER=1 ./build/mini-init-amd64 -- ./your-app

# Custom exit code base (SIGKILL will yield 200+9=209 instead of 128+9=137)
EP_EXIT_CODE_BASE=200 ./build/mini-init-amd64 -- ./your-app

# Restart on crash (up to 5 restarts, 2s backoff)
EP_RESTART_ENABLED=1 EP_MAX_RESTARTS=5 EP_RESTART_BACKOFF_SECONDS=2 \
  ./build/mini-init-amd64 -- ./your-app

# Unlimited restarts, no backoff
EP_RESTART_ENABLED=1 EP_MAX_RESTARTS=0 EP_RESTART_BACKOFF_SECONDS=0 \
  ./build/mini-init-amd64 -- ./your-app
```

### Best Practices

#### Restart Configuration

When enabling restart-on-crash (`EP_RESTART_ENABLED=1`):

- **Always set a backoff delay** (`EP_RESTART_BACKOFF_SECONDS`) to prevent tight restart loops
  - Recommended minimum: `1` second (default)
  - For flaky apps: `5-10` seconds

- **Set a restart limit** (`EP_MAX_RESTARTS`) to prevent infinite loops on persistent failures
  - Recommended: `3-5` restarts for transient errors
  - Use `0` (unlimited) only for long-running services with rare crashes

**Example - Good configuration:**
```bash
# Bounded restarts with backoff (recommended)
EP_RESTART_ENABLED=1 EP_MAX_RESTARTS=3 EP_RESTART_BACKOFF_SECONDS=5 \
  ./build/mini-init-amd64 -- ./my-app
```

**Example - Dangerous configuration:**
```bash
# Unlimited restarts with no delay (tight loop on immediate crash - avoid!)
EP_RESTART_ENABLED=1 EP_MAX_RESTARTS=0 EP_RESTART_BACKOFF_SECONDS=0 \
  ./build/mini-init-amd64 -- ./my-app
```

### Exit code semantics

- Child exits normally → `mini-init-asm` returns the **child exit code**.
- Child dies by signal → returns `EP_EXIT_CODE_BASE + signal_number`
  (default base: `128`, e.g. `SIGTERM` = 143).
- Child is killed by `SIGKILL` after grace-period expiration → returns `EP_EXIT_CODE_BASE + 9`.

---

## How it works (epoll + signalfd + timerfd)

High-level algorithm:

1. Block all relevant signals in PID 1.
2. Spawn the child under a **new session + process group** (PGID = child PID).
3. Create:

   - a `signalfd` for `HUP,INT,QUIT,TERM,CHLD` plus anything from `EP_SIGNALS`;
   - a `timerfd` for the grace window;
   - an `epoll` instance watching both.
4. Main loop:

   - Wait on `epoll_wait`.
   - On `signalfd` events:

     - For **soft signals** (`HUP/INT/QUIT/TERM`):

       - forward to **process group** via `kill(-pgid, sig)`;
       - arm the grace `timerfd` if this is the *first* soft signal.
     - On `SIGCHLD`:

       - reap children with `waitpid(-1, WNOHANG)`;
       - if the main child exited, propagate its exit code and terminate.
   - On timer expiration:

     - first re-check (reap) the main child so an already-exited child keeps its
       real exit status;
     - if the child is still alive, escalate to `SIGKILL` for the whole group.

Key syscalls: `signalfd(2)`, `epoll(7)`, `timerfd_create(2)`, `timerfd_settime(2)`,
`rt_sigprocmask(2)`, `wait4(2)`, `kill(2)`, `setsid(2)`, `setpgid(2)`.

---

## Repository layout

```text
mini-init-asm/
├─ README.md
├─ ROADMAP.md
├─ LICENSE
├─ Makefile
├─ include/
│  ├─ macros.inc              # x86-64 syscall/log helpers
│  ├─ macros_arm64.inc        # arm64 syscall/log helpers
│  ├─ syscalls_amd64.inc      # syscall numbers for x86-64
│  └─ syscalls_aarch64.inc    # syscall numbers for arm64
├─ src/
│  ├─ amd64/                  # NASM sources (x86-64 ABI)
│  └─ arm64/                  # AArch64 sources (arm64 ABI)
├─ scripts/
│  ├─ test_harness.sh         # e2e tests
│  └─ fixtures/
│     ├─ sleeper.sh
│     └─ trap_exit0.sh
└─ docker/
   └─ Dockerfile              # multi-stage: build -> scratch
```

---

## Build system

```bash
make              # build/mini-init-amd64
make test         # run e2e tests on x86-64 host
make build-arm64  # build/mini-init-arm64 (requires aarch64-linux-gnu toolchain)
make test-arm64   # run ARM64 smoke tests via QEMU (requires qemu-user-static)
make clean
```

Both binaries are linked with `ld -nostdlib`. The code issues syscalls directly:

- x86-64: `rax` + `rdi/rsi/rdx/r10/r8/r9`
- arm64: `x8` + `x0`–`x5`

Signal numbers and ABI differences are factored into the `include/syscalls_*.inc` files.

---

## Testing

### x86-64 (native)

```bash
make test              # Basic e2e tests
make test-all          # e2e + unit + edge cases
# or directly:
bash scripts/test_harness.sh build/mini-init-amd64
bash scripts/test_ep_signals.sh build/mini-init-amd64
bash scripts/test_edge_cases.sh build/mini-init-amd64
bash scripts/test_exit_code_mapping.sh build/mini-init-amd64
bash scripts/test_restart.sh build/mini-init-amd64
```

### ARM64 (via QEMU)

```bash
sudo apt-get install -y qemu-user-static
make test-arm64
# or:
bash scripts/test_harness_arm64.sh build/mini-init-arm64
```

### ARM64 (native)

On an ARM64 host you can run the regular test scripts directly:

```bash
make build-arm64
bash scripts/test_harness.sh build/mini-init-arm64
bash scripts/test_ep_signals.sh build/mini-init-arm64
bash scripts/test_edge_cases.sh build/mini-init-arm64
bash scripts/test_exit_code_mapping.sh build/mini-init-arm64
bash scripts/test_restart.sh build/mini-init-arm64
bash scripts/test_diagnostics.sh build/mini-init-arm64
```

### Test suites

1. **Basic e2e tests** (`test_harness.sh`):

   - group-wide forwarding (TERM) and graceful exit;
   - escalation: app ignores TERM → KILL after grace window;
   - custom `EP_SIGNALS=USR1` and child reaction.

2. **EP_SIGNALS parser tests** (`test_ep_signals.sh`):

   - single/multiple token parsing;
   - unknown tokens (warnings);
   - whitespace handling;
   - empty / edge-case inputs.

3. **Edge-case integration tests** (`test_edge_cases.sh`):

   - rapid signal bursts;
   - orphaned process handling (`EP_SUBREAPER=1`);
   - mixed TERM/INT/HUP;
   - signals during grace period;
   - immediate child exit after signal.

4. **Exit code mapping tests** (`test_exit_code_mapping.sh`):

   - default base (128);
   - custom base;
   - normal exits (unaffected);
   - signal exits with custom base.

5. **Restart functionality tests** (`test_restart.sh`):

   - restart on crash (signal);
   - restart with backoff;
   - max-restart limit;
   - no restart on normal exit;
   - no restart after shutdown signal;
   - unlimited restarts (`EP_MAX_RESTARTS=0`).

> **Note:** ARM64 tests run under QEMU user emulation and may differ slightly in timing or fail on some
> hosts; for full determinism use native ARM64.

---

## Debian Packaging

### Package Information

The Debian package `mini-init-asm` provides a unified binary:
- **Installed at:** `/usr/bin/mini-init-asm`
- **Architecture-specific:** Built for `amd64` and `arm64` only
- **Statically linked:** No runtime dependencies (libc-free)

### Building the Debian Package

```bash
# Install build dependencies
sudo apt-get install debhelper-compat binutils nasm make

# Build binary package
dpkg-buildpackage -us -uc -b

# Install locally
sudo dpkg -i ../mini-init-asm_*.deb
```

### Running Autopkgtest

```bash
# After installing package
autopkgtest . -- null

# Or from source tree with schroot
autopkgtest -B . -- schroot unstable-amd64
```

### Lintian Check

```bash
lintian --fail-on warning --display-info ../mini-init-asm_*.deb
```

### Supported Architectures

Currently supported: **amd64**, **arm64**

Other architectures are not supported due to the assembly implementation.

---

## Security notes

- No privilege dropping, seccomp profiles, or capabilities tuning are implemented here.
- Intended as a **small, auditable entrypoint** that you combine with higher-level policies
  (cgroups, seccomp, AppArmor/SELinux, etc.) at the orchestrator / image level.

---

## Credits

- Inspired by years of using [Tini](https://github.com/krallin/tini) as a tiny init in containers.
- Assembler style: NASM (SysV ABI) and GNU AS (AArch64).
