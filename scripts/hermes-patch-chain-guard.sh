#!/usr/bin/env bash
# Hermes patch-chain guard: verify that the GitHub/local patch tree, installed Hermes code,
# Memory Graph service, and dashboard API are all present and mutually usable.
set -euo pipefail

HERMES_DIR="${HERMES_DIR:-$HOME/.hermes/hermes-agent}"
PATCHES_DIR="${PATCHES_DIR:-$HOME/.hermes/patches}"
MG_URL="${MG_URL:-http://127.0.0.1:8233}"
MG_PUBLIC_URL="${MG_PUBLIC_URL:-https://mg.bz9.me}"
DASHBOARD_URL="${DASHBOARD_URL:-http://127.0.0.1:9119}"
FAIL=0

ok() { printf '✅ %s\n' "$*"; }
warn() { printf '⚠️ %s\n' "$*"; }
fail() { printf '❌ %s\n' "$*"; FAIL=1; }

require_file() {
  local path="$1" label="$2"
  if [ -f "$path" ]; then ok "$label: $path"; else fail "$label missing: $path"; fi
}
require_dir() {
  local path="$1" label="$2"
  if [ -d "$path" ]; then ok "$label: $path"; else fail "$label missing: $path"; fi
}

require_dir "$HERMES_DIR" "Hermes worktree"
require_dir "$PATCHES_DIR" "Patch worktree"
require_file "$PATCHES_DIR/install.sh" "Patch installer"
require_file "$HERMES_DIR/tools/memory_graph_tool.py" "Installed Memory Graph tool"
require_file "$HERMES_DIR/agent/memory_metacognition.py" "Installed metacognition module"
require_file "$HERMES_DIR/agent/memory_write_pipeline.py" "Installed write pipeline module"
require_file "$HERMES_DIR/agent/shadow_write_logger.py" "Installed shadow logger module"
require_file "$HERMES_DIR/toolsets.py" "Installed toolsets.py"

if [ -f "$HERMES_DIR/toolsets.py" ]; then
  grep -q '"memory_graph"' "$HERMES_DIR/toolsets.py" && ok "memory_graph toolset registered" || fail "memory_graph toolset missing from toolsets.py"
  grep -q 'memory_graph_search' "$HERMES_DIR/toolsets.py" && ok "memory_graph tools included in core/toolsets" || fail "memory_graph_search missing from toolsets.py"
fi

if [ -d "$PATCHES_DIR/.git" ]; then
  git -C "$PATCHES_DIR" remote -v | sed 's/^/patch remote: /'
  git -C "$PATCHES_DIR" status --short | sed 's/^/patch status: /' || true
  ok "Patch repo git metadata readable"
else
  warn "Patch worktree has no .git metadata; cannot compare with GitHub remote"
fi

if [ -d "$HERMES_DIR/.git" ]; then
  git -C "$HERMES_DIR" rev-parse --short HEAD | sed 's/^/hermes head: /'
  git -C "$HERMES_DIR" status --short | sed 's/^/hermes status: /' || true
  ok "Hermes repo git metadata readable"
else
  warn "Hermes worktree has no .git metadata"
fi

if command -v curl >/dev/null 2>&1; then
  if curl -fsS -m 5 "$MG_URL/health" >/tmp/hermes-mg-health.json 2>/tmp/hermes-mg-health.err; then
    ok "Memory Graph health reachable: $(tr -d '\n' </tmp/hermes-mg-health.json)"
  else
    fail "Memory Graph health failed at $MG_URL/health: $(tr -d '\n' </tmp/hermes-mg-health.err 2>/dev/null || true)"
  fi

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$MG_URL" "$MG_PUBLIC_URL" <<'PY' || exit_code=$?
import json, sys, urllib.request
local, public = [x.rstrip('/') for x in sys.argv[1:3]]
for label, base in [('local', local), ('public', public)]:
    req = urllib.request.Request(base + '/openapi.json', headers={'User-Agent': 'Hermes-Patch-Guard/1.0'})
    data = json.load(urllib.request.urlopen(req, timeout=15))
    paths = set(data.get('paths', {}))
    required = {'/api/browse/node', '/api/browse/search', '/api/settings', '/api/review'}
    missing = sorted(p for p in required if p not in paths)
    old_only = any(p.startswith('/api/memory-graph/') for p in paths)
    if missing or old_only:
        print(f'MG_WEBUI_FAIL {label} missing={missing} old_api={old_only}')
        sys.exit(5)
print('MG_WEBUI_OK standalone browse/settings/review API surface reachable')
PY
    rc=${exit_code:-0}
    unset exit_code
    if [ "$rc" -eq 0 ]; then ok "Standalone Memory Graph WebUI API surface reachable"; else fail "Memory Graph WebUI API surface probe failed"; fi
  fi

  # Dashboard protected APIs require the ephemeral token injected into index.html.
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$DASHBOARD_URL" <<'PY' || exit_code=$?
import re, sys, urllib.request, urllib.error
base = sys.argv[1].rstrip('/')
try:
    html = urllib.request.urlopen(base + '/', timeout=10).read().decode('utf-8', 'replace')
    m = re.search(r'__HERMES_SESSION_TOKEN__="([^"]+)"', html)
    if not m:
        print('DASHBOARD_FAIL no session token in index.html')
        sys.exit(2)
    token = m.group(1)
    for ep in ['/api/model/info', '/api/analytics/models?days=30', '/api/model/auxiliary', '/api/sessions?limit=1&offset=0']:
        req = urllib.request.Request(base + ep, headers={'X-Hermes-Session-Token': token})
        with urllib.request.urlopen(req, timeout=20) as r:
            if r.status != 200:
                print(f'DASHBOARD_FAIL {ep} status={r.status}')
                sys.exit(3)
    print('DASHBOARD_OK protected APIs reachable')
except Exception as e:
    print('DASHBOARD_FAIL', type(e).__name__, str(e))
    sys.exit(4)
PY
    rc=${exit_code:-0}
    unset exit_code
    if [ "$rc" -eq 0 ]; then ok "Dashboard protected APIs reachable"; else fail "Dashboard protected API probe failed"; fi
  fi
fi

# Python import smoke: catches copied files that exist but fail at import time.
if [ -x "$HERMES_DIR/venv/bin/python" ]; then
  "$HERMES_DIR/venv/bin/python" - <<'PY' || exit_code=$?
import importlib
mods = [
    'tools.memory_graph_tool',
    'agent.memory_metacognition',
    'agent.memory_write_pipeline',
    'agent.shadow_write_logger',
    'agent.hindsight_reranker',
]
for m in mods:
    importlib.import_module(m)
print('IMPORT_OK', ','.join(mods))
PY
  rc=${exit_code:-0}
  unset exit_code
  if [ "$rc" -eq 0 ]; then ok "Patched Python modules import"; else fail "Patched Python module import smoke failed"; fi
else
  warn "Hermes venv python not executable; skipped import smoke"
fi

if [ "$FAIL" -ne 0 ]; then
  echo ""
  fail "Hermes patch-chain guard FAILED"
  exit 1
fi

echo ""
ok "Hermes patch-chain guard passed"
