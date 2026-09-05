#!/usr/bin/env bash
GO="${1:?missing go-file path}"
READY="${GO}.ready"
PIDFILE="${GO}.pid"

got=0
trap 'got=1' TERM INT HUP QUIT

: > "$READY"
printf '%s\n' "$$" > "$PIDFILE"

while :; do
  if [ "$got" = 1 ] && [ -f "$GO" ]; then
    exit 0
  fi
  sleep 0.05
done
