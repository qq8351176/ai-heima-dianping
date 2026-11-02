#!/bin/sh
set -eu
ROOT=/mnt/e/java_learn/ai-dianping
BIN=/mnt/e/DevTools/Redis/redis-7.4.12/usr/bin
export REDISCLI_AUTH="$(sed -n 's/^requirepass //p' "$ROOT/runtime/redis/redis.conf" | tr -d '\r')"
case "${1:-status}" in
  start)
    if ! "$BIN/redis-cli" -h 127.0.0.1 -p 6380 ping >/dev/null 2>&1; then
      "$BIN/redis-server" "$ROOT/runtime/redis/redis.conf"
    fi
    attempt=0
    until "$BIN/redis-cli" -h 127.0.0.1 -p 6380 ping 2>/dev/null; do
      attempt=$((attempt + 1))
      [ "$attempt" -lt 30 ] || exit 1
      sleep 0.1
    done
    ;;
  stop)
    if "$BIN/redis-cli" -h 127.0.0.1 -p 6380 ping >/dev/null 2>&1; then
      "$BIN/redis-cli" -h 127.0.0.1 -p 6380 shutdown save
    fi
    ;;
  status) "$BIN/redis-cli" -h 127.0.0.1 -p 6380 ping ;;
  *) echo "Usage: redis-control.sh start|stop|status" >&2; exit 2 ;;
esac
