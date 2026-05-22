#!/bin/bash
# Hermes Memory Stack watchdog.
# Checks resident Memory OS dependencies and restarts failed services when possible.

set -u

LOG_PREFIX="[hermes-memory-watchdog]"
MG_URL="${MEMORY_GRAPH_HEALTH_URL:-http://127.0.0.1:8900/health}"
HINDSIGHT_URL="${HINDSIGHT_HEALTH_URL:-http://127.0.0.1:9177/health}"

log() { echo "$LOG_PREFIX $*"; }

is_root() { [ "$(id -u)" -eq 0 ]; }

restart_system_service() {
    local svc="$1"
    if command -v systemctl >/dev/null 2>&1; then
        log "restarting $svc"
        systemctl restart "$svc" || log "restart failed: $svc"
    fi
}

restart_user_service() {
    local svc="$1"
    if command -v systemctl >/dev/null 2>&1; then
        log "restarting user $svc"
        systemctl --user restart "$svc" || log "user restart failed: $svc"
    fi
}

check_http() {
    local name="$1"
    local url="$2"
    curl -fsS -m 5 "$url" >/dev/null 2>&1
}

check_postgres() {
    if ! command -v pg_isready >/dev/null 2>&1; then
        log "pg_isready not available; skipping PostgreSQL check"
        return 0
    fi
    pg_isready -q
}

postgres_failed=0
hindsight_failed=0
mg_failed=0

if ! check_postgres; then
    postgres_failed=1
    log "PostgreSQL unhealthy"
    if is_root; then
        restart_system_service postgresql@15-main.service
    else
        log "not root; cannot restart PostgreSQL"
    fi
fi

if ! check_http hindsight "$HINDSIGHT_URL"; then
    hindsight_failed=1
    log "Hindsight unhealthy: $HINDSIGHT_URL"
    if is_root; then
        restart_system_service hindsight.service
    else
        log "not root; cannot restart system Hindsight"
    fi
fi

if ! check_http memory-graph "$MG_URL"; then
    mg_failed=1
    log "Memory Graph unhealthy: $MG_URL"
    if is_root; then
        restart_system_service hermes-memory-graph.service
    else
        restart_user_service hermes-memory-graph.service
    fi
fi

# Re-check Memory Graph after restart because it is the service most often
# affected by patch/update drift. Give uvicorn/imports time to bind the port.
mg_ok=0
for _i in $(seq 1 20); do
    if check_http memory-graph "$MG_URL"; then
        mg_ok=1
        break
    fi
    sleep 1
done
if [ "$mg_ok" -ne 1 ]; then
    log "Memory Graph still unhealthy after remediation"
    mg_failed=1
else
    mg_failed=0
fi

# Re-check other services if they were unhealthy and restart was attempted.
if [ "$postgres_failed" -eq 1 ] && check_postgres; then
    postgres_failed=0
fi
if [ "$hindsight_failed" -eq 1 ] && check_http hindsight "$HINDSIGHT_URL"; then
    hindsight_failed=0
fi

failed=0
if [ "$postgres_failed" -ne 0 ] || [ "$hindsight_failed" -ne 0 ] || [ "$mg_failed" -ne 0 ]; then
    failed=1
fi

if [ "$failed" -eq 0 ]; then
    log "healthy"
fi

exit "$failed"
