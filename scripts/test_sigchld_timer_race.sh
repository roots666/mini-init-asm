#!/usr/bin/env bash
set -euo pipefail
# Regression: grace timerfd vs pending SIGCHLD during graceful shutdown.
#
# A main child that has already exited (waitable) while SIGCHLD is still queued
# on the signalfd must keep its real exit status: grace-timer expiration must
# not convert that child into a forced SIGKILL / 137.
#
# Sequence:
#   1. child fixture is ready (and publishes its PID)
#   2. TERM -> mini-init forwards it and arms the grace timer
#   3. wait until timer armed AND timerfd registered in epoll
#   4. SIGSTOP mini-init
#   5. let the non-zero grace timer expire
#   6. release the fixture (touch go)
#   7. poll until the main child is observably zombie/waitable
#   8. SIGCONT mini-init
#   9. timerfd and signalfd are both ready; real status must win
#
# Every wait/poll is bounded. Cleanup releases the child process group first so
# no fixture/sleep descendant is orphaned.

BIN="${1:-./build/mini-init-amd64}"
GRACE="${EP_GRACE_SECONDS:-1}"

tmpdir="$(mktemp -d)"
log="$tmpdir/init.log"
go="$tmpdir/go"
child_pid=""
init_pid=""

# is_zombie <pid>
is_zombie() {
  [ -r "/proc/$1/stat" ] || return 0
  [ "$(awk '{print $3}' "/proc/$1/stat" 2>/dev/null)" = "Z" ]
}

# wait_exited <pid> <tries> -> 0 on zombie/gone, 1 on timeout
wait_exited() {
  local pid="$1" tries="$2"
  local i state
  i=0
  while [ "$i" -lt "$tries" ]; do
    if [ ! -r "/proc/$pid/stat" ]; then return 0; fi
    state="$(awk '{print $3}' "/proc/$pid/stat" 2>/dev/null || true)"
    [ "$state" = "Z" ] && return 0
    i=$((i + 1))
    sleep 0.05
  done
  return 1
}

cleanup() {
  # Release the fixture first, then stop the child process group by PID.
  if [ -n "$child_pid" ] && kill -0 "$child_pid" 2>/dev/null; then
    touch "$go" 2>/dev/null || true
    kill -TERM -- "-$child_pid" 2>/dev/null || true
    sleep 0.1
    kill -KILL -- "-$child_pid" 2>/dev/null || true
  fi
  if [ -n "$init_pid" ]; then
    kill -CONT "$init_pid" 2>/dev/null || true
    kill -KILL "$init_pid" 2>/dev/null || true
  fi
  rm -rf "$tmpdir"
}
trap cleanup EXIT

EP_GRACE_SECONDS="$GRACE" "$BIN" -v -- /bin/bash scripts/fixtures/trap_exit_after_go.sh "$go" 2>"$log" &
init_pid=$!

# 1. child ready
ready=0
for _ in $(seq 1 200); do
  if [ -f "$go.ready" ]; then ready=1; break; fi
  sleep 0.05
done
[ "$ready" = 1 ] || { echo "FAIL: child did not become ready"; cat "$log" >&2; exit 1; }

# child PID (== process group id; do_spawn does setsid+setpgid(0,0))
child_pid="$(cat "$go.pid" 2>/dev/null || true)"
if [ -z "$child_pid" ] || [ "$child_pid" -le 1 ]; then
  echo "FAIL: bad child pid '$child_pid'"; cat "$log" >&2; exit 1
fi

# 2. start graceful shutdown
kill -TERM "$init_pid"

# 3a. timerfd created
tfd=""
for _ in $(seq 1 200); do
  tfd="$(grep -m1 -o 'timerfd created fd=[0-9]*' "$log" | sed 's/.*=//' || true)"
  [ -n "$tfd" ] && break
  sleep 0.05
done
[ -n "$tfd" ] || { echo "FAIL: timerfd created log missing"; cat "$log" >&2; exit 1; }

# 3b. timer armed
armed=0
for _ in $(seq 1 200); do
  grep -q "grace timer armed" "$log" && { armed=1; break; }
  sleep 0.05
done
[ "$armed" = 1 ] || { echo "FAIL: grace timer armed log missing"; cat "$log" >&2; exit 1; }

# 3c. timerfd registered in epoll
registered=0
for _ in $(seq 1 200); do
  grep -q "added FD to epoll fd=$tfd" "$log" && { registered=1; break; }
  sleep 0.05
done
[ "$registered" = 1 ] || { echo "FAIL: timerfd fd=$tfd not registered"; cat "$log" >&2; exit 1; }

# 4-6. stop init; let timer expire; release fixture
kill -STOP "$init_pid"
sleep 2
touch "$go"

# 7. wait for the main child to be truly waitable (zombie) while init is stopped
if ! wait_exited "$child_pid" 200; then
  echo "FAIL: child did not become waitable while init stopped"
  ps -o pid,ppid,stat,cmd -p "$child_pid" 2>/dev/null || true
  cat "$log" >&2
  exit 1
fi

# 8. resume; both timerfd and signalfd are now ready
kill -CONT "$init_pid"

# 9. init must exit (zombie-detect, bounded) and then we collect its status
if ! wait_exited "$init_pid" 200; then
  echo "FAIL: init did not exit after SIGCONT"
  cat "$log" >&2
  exit 1
fi

set +e
wait "$init_pid"
rc=$?
set -e

echo "[test] rc=$rc"
if grep -q "escalating to SIGKILL" "$log"; then
  echo "FAIL: falsely escalated to SIGKILL"
  cat "$log" >&2
  exit 1
fi
if [ "$rc" -ne 0 ]; then
  echo "FAIL: expected child status 0, got $rc"
  cat "$log" >&2
  exit 1
fi

echo "[test] OK (real child status preserved)"
