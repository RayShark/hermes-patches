#!/bin/bash
# Hermes Agent 社区补丁合集 — 一键安装脚本
# 适配版本：v0.14.0+ (v2026.5.16+)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCHES_DIR="$SCRIPT_DIR"
DEFAULT_HERMES_DIR="$HOME/.hermes/hermes-agent"
HERMES_DIR="${HERMES_HOME:-$DEFAULT_HERMES_DIR}"
# When hermes update calls this script from the profile root (~/.hermes),
# HERMES_HOME may point at the profile directory instead of the repo root.
# Detect that case and fall back to the real repo if it exists.
if [ -d "$HERMES_DIR/hermes-agent" ] && [ ! -e "$HERMES_DIR/toolsets.py" ]; then
    HERMES_DIR="$HERMES_DIR/hermes-agent"
fi
if [ ! -e "$HERMES_DIR/toolsets.py" ] && [ -d "$DEFAULT_HERMES_DIR" ]; then
    HERMES_DIR="$DEFAULT_HERMES_DIR"
fi

echo "🔧 Hermes 社区补丁合集 v18"
echo "   适配版本：v0.14.0+ (v2026.5.16+) + verified upstream d61785889"
echo "   补丁目录：$PATCHES_DIR"
echo "   Hermes目录：$HERMES_DIR"
echo ""

# 1. Apply optional combined patch if it exists and is non-empty.
# Overlay copies below are authoritative because upstream moves quickly and large
# git patches are brittle after `hermes update`.
PATCH_FILE="$PATCHES_DIR/combined-final-v18.patch"
if [ -s "$PATCH_FILE" ]; then
    echo "📦 尝试应用 combined-final-v18.patch..."
    cd "$HERMES_DIR"
    if git apply --check "$PATCH_FILE" 2>/dev/null; then
        git apply "$PATCH_FILE"
        echo "   ✅ combined patch 已应用"
    else
        echo "   ⏭️ combined patch 不兼容，使用 overlay 文件复制"
    fi
fi

# 2. Copy agent modules / patched core files
for module in memory_metacognition.py memory_write_pipeline.py shadow_write_logger.py hindsight_access_tracker.py hindsight_reranker.py request_context.py agent_init.py agent_runtime_helpers.py conversation_loop.py memory_provider.py tool_executor.py image_gen_provider.py; do
    if [ -f "$PATCHES_DIR/agent/$module" ]; then
        cp "$PATCHES_DIR/agent/$module" "$HERMES_DIR/agent/"
        echo "   ✅ agent/$module 已复制"
    fi
done

# 2b. Copy Memory Graph package (keeps DB/RLS hardening in sync with patch repo)
if [ -d "$PATCHES_DIR/agent/memory_graph" ]; then
    mkdir -p "$HERMES_DIR/agent"
    rm -rf "$HERMES_DIR/agent/memory_graph"
    cp -R "$PATCHES_DIR/agent/memory_graph" "$HERMES_DIR/agent/"
    echo "   ✅ agent/memory_graph 已复制"
fi

# 3. Copy tools and DB/session state files
for tool_file in memory_graph_tool.py session_search_tool.py image_generation_tool.py; do
    if [ -f "$PATCHES_DIR/tools/$tool_file" ]; then
        cp "$PATCHES_DIR/tools/$tool_file" "$HERMES_DIR/tools/"
        echo "   ✅ tools/$tool_file 已复制"
    fi
done
if [ -f "$PATCHES_DIR/hermes_state.py" ]; then
    cp "$PATCHES_DIR/hermes_state.py" "$HERMES_DIR/hermes_state.py"
    echo "   ✅ hermes_state.py 已复制"
fi
if [ -f "$PATCHES_DIR/gateway/config.py" ]; then
    mkdir -p "$HERMES_DIR/gateway"
    cp "$PATCHES_DIR/gateway/config.py" "$HERMES_DIR/gateway/config.py"
    echo "   ✅ gateway/config.py 已复制"
fi
if [ -f "$PATCHES_DIR/gateway/platforms/telegram.py" ]; then
    mkdir -p "$HERMES_DIR/gateway/platforms"
    cp "$PATCHES_DIR/gateway/platforms/telegram.py" "$HERMES_DIR/gateway/platforms/telegram.py"
    echo "   ✅ gateway/platforms/telegram.py 已复制"
fi
if [ -f "$PATCHES_DIR/plugins/image_gen/openai/__init__.py" ]; then
    mkdir -p "$HERMES_DIR/plugins/image_gen/openai"
    cp "$PATCHES_DIR/plugins/image_gen/openai/__init__.py" "$HERMES_DIR/plugins/image_gen/openai/__init__.py"
    echo "   ✅ OpenAI image_gen provider 已复制"
fi

# 3b. Copy patched Hindsight provider and site-package hotfixes
if [ -f "$PATCHES_DIR/plugins/memory/hindsight/__init__.py" ]; then
    mkdir -p "$HERMES_DIR/plugins/memory/hindsight"
    cp "$PATCHES_DIR/plugins/memory/hindsight/__init__.py" "$HERMES_DIR/plugins/memory/hindsight/__init__.py"
    echo "   ✅ Hindsight provider fallback 已复制"
fi
if [ -f "$PATCHES_DIR/site-packages/hindsight_api/engine/embeddings.py" ]; then
    SITE_DIR="$HERMES_DIR/venv/lib/python3.11/site-packages/hindsight_api/engine"
    if [ -d "$SITE_DIR" ]; then
        cp "$PATCHES_DIR/site-packages/hindsight_api/engine/embeddings.py" "$SITE_DIR/embeddings.py"
        echo "   ✅ Hindsight embeddings known-dimension hotfix 已复制"
    fi
fi

# 3c. Ensure least-privileged Memory Graph DB role exists (superuser bypasses RLS)
if command -v psql >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1; then
    ENV_FILE="$HOME/.hermes/.env"
    mkdir -p "$HOME/.hermes"
    if grep -q '^MEMORY_GRAPH_DB_PASSWORD=' "$ENV_FILE" 2>/dev/null; then
        MG_DB_PASSWORD="$(grep '^MEMORY_GRAPH_DB_PASSWORD=' "$ENV_FILE" | tail -1 | cut -d= -f2- | sed 's/^\"//;s/\"$//;s/^'\''//;s/'\''$//')"
    else
        MG_DB_PASSWORD="$(python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(24))
PY
)"
        printf '\nMEMORY_GRAPH_DB_PASSWORD=%s\n' "$MG_DB_PASSWORD" >> "$ENV_FILE"
    fi
    if [ -n "$MG_DB_PASSWORD" ]; then
        sudo -u postgres psql -d hindsight -v ON_ERROR_STOP=1 >/dev/null <<SQL || echo "   ⚠️ mg_app DB role 初始化失败，请手动检查 PostgreSQL"
DO \$\$ BEGIN
   IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'mg_app') THEN
      CREATE ROLE mg_app LOGIN PASSWORD '$MG_DB_PASSWORD';
   ELSE
      ALTER ROLE mg_app LOGIN PASSWORD '$MG_DB_PASSWORD';
   END IF;
END \$\$;
GRANT CONNECT ON DATABASE hindsight TO mg_app;
GRANT USAGE ON SCHEMA public TO mg_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON mg_nodes, mg_memories, mg_edges, mg_paths, mg_glossary_keywords, mg_search_documents, mg_access_log, mg_snapshots, mg_access_logs TO mg_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO mg_app;
ALTER TABLE mg_edges DISABLE ROW LEVEL SECURITY;
SQL
        echo "   ✅ mg_app least-privileged DB role 已确认"
    fi
fi

# 4. Copy config
if [ -f "$PATCHES_DIR/memory_write_config.yaml" ]; then
    cp "$PATCHES_DIR/memory_write_config.yaml" "$HOME/.hermes/"
    echo "   ✅ memory_write_config.yaml 已复制"
fi

# 5. Copy default memory policy
if [ -f "$PATCHES_DIR/memory_policy.default.yaml" ] && [ ! -f "$HOME/.hermes/memory_policy.yaml" ]; then
    cp "$PATCHES_DIR/memory_policy.default.yaml" "$HOME/.hermes/memory_policy.yaml"
    echo "   ✅ memory_policy.yaml 已初始化"
fi

# 6. Clean .pyc caches
find "$HERMES_DIR/agent" -name "memory_metacognition*.pyc" -delete 2>/dev/null
find "$HERMES_DIR/agent" -name "memory_write_pipeline*.pyc" -delete 2>/dev/null
find "$HERMES_DIR/agent" -name "shadow_write_logger*.pyc" -delete 2>/dev/null
find "$HERMES_DIR/agent" -name "hindsight_access_tracker*.pyc" -delete 2>/dev/null
find "$HERMES_DIR/agent" -name "hindsight_reranker*.pyc" -delete 2>/dev/null
find "$HERMES_DIR/tools" -name "memory_graph_tool*.pyc" -delete 2>/dev/null
if [ -d "$HERMES_DIR/plugins/memory/hindsight" ]; then
    find "$HERMES_DIR/plugins/memory/hindsight" -name "*.pyc" -delete 2>/dev/null
fi
if [ -d "$HERMES_DIR/venv/lib/python3.11/site-packages/hindsight_api" ]; then
    find "$HERMES_DIR/venv/lib/python3.11/site-packages/hindsight_api" -name "embeddings*.pyc" -delete 2>/dev/null
fi
find "$HERMES_DIR/agent" -name "conversation_loop*.pyc" -delete 2>/dev/null
find "$HERMES_DIR/agent" -name "agent_runtime_helpers*.pyc" -delete 2>/dev/null
find "$HERMES_DIR/agent" -name "system_prompt*.pyc" -delete 2>/dev/null
echo "   ✅ .pyc 缓存已清理"

# 7. Register memory_graph tools in toolsets.py without replacing upstream's file.
# Tool discovery needs BOTH registry.register(...) in tools/memory_graph_tool.py
# and explicit toolset/core entries here; otherwise tools silently never load.
python3 - "$HERMES_DIR/toolsets.py" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()
mg_tools = [
    "memory_graph_read", "memory_graph_create", "memory_graph_update",
    "memory_graph_delete", "memory_graph_list", "memory_graph_search",
    "memory_graph_alias", "memory_graph_glossary_add", "memory_graph_glossary_scan",
    "memory_graph_recall", "memory_graph_orphans", "memory_graph_random",
    "memory_graph_diagnostics", "memory_graph_purge",
]
core_marker = '    # Session history search\n    "session_search",'
if "memory_graph_search" not in text.split("# Session history search", 1)[0]:
    insert = (
        '    # Memory Graph (URI-tree structured memory)\n'
        '    "memory_graph_read", "memory_graph_create", "memory_graph_update",\n'
        '    "memory_graph_delete", "memory_graph_list", "memory_graph_search",\n'
        '    "memory_graph_alias", "memory_graph_glossary_add", "memory_graph_glossary_scan",\n'
        '    "memory_graph_recall", "memory_graph_orphans", "memory_graph_random",\n'
        '    "memory_graph_diagnostics", "memory_graph_purge",\n'
    )
    if core_marker not in text:
        raise SystemExit("toolsets.py core marker not found; cannot insert memory_graph core tools safely")
    text = text.replace(core_marker, insert + core_marker, 1)

if '"memory_graph": {' not in text:
    entry = '''    "memory_graph": {
        "description": "URI-tree structured memory graph (search, create, update, delete, list, alias, glossary)",
        "tools": [
            "memory_graph_read", "memory_graph_create", "memory_graph_update",
            "memory_graph_delete", "memory_graph_list", "memory_graph_search",
            "memory_graph_alias", "memory_graph_glossary_add", "memory_graph_glossary_scan",
            "memory_graph_recall", "memory_graph_orphans", "memory_graph_random",
            "memory_graph_diagnostics", "memory_graph_purge"
        ],
        "includes": []
    },

'''
    marker = '    "session_search": {'
    if marker not in text:
        raise SystemExit("toolsets.py TOOLSETS session_search marker not found; cannot insert memory_graph toolset safely")
    text = text.replace(marker, entry + marker, 1)

path.write_text(text)
PY

if grep -q "memory_graph_search" "$HERMES_DIR/toolsets.py" 2>/dev/null; then
    echo "   ✅ memory_graph tools 已在 toolsets.py 注册"
else
    echo "   ⚠️ memory_graph tools 未在 toolsets.py 中注册，请手动添加"
fi

echo ""
echo "✅ 补丁安装完成！"
echo "   请重启 gateway: hermes gateway restart"


# 8. Install resident Memory Stack scripts and systemd units when available.
# This keeps the HTTP dashboard/API on 127.0.0.1:8900 alive after reboot and
# after `hermes update`. The watchdog catches "process up but API unhealthy"
# failures that Restart=always cannot see.
if [ -f "$PATCHES_DIR/scripts/hermes-memory-stack-watchdog.sh" ]; then
    mkdir -p "$HOME/.hermes/scripts"
    cp "$PATCHES_DIR/scripts/hermes-memory-stack-watchdog.sh" "$HOME/.hermes/scripts/hermes-memory-stack-watchdog.sh"
    chmod +x "$HOME/.hermes/scripts/hermes-memory-stack-watchdog.sh"
    echo "   ✅ hermes-memory-stack-watchdog.sh 已复制"
fi

if command -v systemctl >/dev/null 2>&1 && [ -d "$PATCHES_DIR/systemd" ]; then
    if [ "$(id -u)" -eq 0 ] && [ -d /etc/systemd/system ]; then
        cp "$PATCHES_DIR/systemd/hermes-memory-graph.system.service" /etc/systemd/system/hermes-memory-graph.service
        cp "$PATCHES_DIR/systemd/hermes-memory-stack.system.target" /etc/systemd/system/hermes-memory-stack.target
        if [ -f "$PATCHES_DIR/systemd/hermes-memory-stack-watchdog.system.service" ]; then
            cp "$PATCHES_DIR/systemd/hermes-memory-stack-watchdog.system.service" /etc/systemd/system/hermes-memory-stack-watchdog.service
        fi
        if [ -f "$PATCHES_DIR/systemd/hermes-memory-stack-watchdog.system.timer" ]; then
            cp "$PATCHES_DIR/systemd/hermes-memory-stack-watchdog.system.timer" /etc/systemd/system/hermes-memory-stack-watchdog.timer
        fi
        systemctl daemon-reload || true
        systemctl enable hermes-memory-graph.service hermes-memory-stack.target >/dev/null 2>&1 || true
        systemctl restart hermes-memory-graph.service >/dev/null 2>&1 || true
        for _i in $(seq 1 15); do
            curl -fsS -m 2 http://127.0.0.1:8900/health >/dev/null 2>&1 && break
            sleep 1
        done
        if [ -f /etc/systemd/system/hermes-memory-stack-watchdog.timer ]; then
            systemctl enable --now hermes-memory-stack-watchdog.timer >/dev/null 2>&1 || true
        fi
        echo "   ✅ hermes-memory-graph systemd service/watchdog 已安装/启动"
    else
        USER_SYSTEMD_DIR="$HOME/.config/systemd/user"
        mkdir -p "$USER_SYSTEMD_DIR"
        cp "$PATCHES_DIR/systemd/hermes-memory-graph.service" "$USER_SYSTEMD_DIR/hermes-memory-graph.service"
        cp "$PATCHES_DIR/systemd/hermes-memory-stack.target" "$USER_SYSTEMD_DIR/hermes-memory-stack.target"
        if [ -f "$PATCHES_DIR/systemd/hermes-memory-stack-watchdog.service" ]; then
            cp "$PATCHES_DIR/systemd/hermes-memory-stack-watchdog.service" "$USER_SYSTEMD_DIR/hermes-memory-stack-watchdog.service"
        fi
        if [ -f "$PATCHES_DIR/systemd/hermes-memory-stack-watchdog.timer" ]; then
            cp "$PATCHES_DIR/systemd/hermes-memory-stack-watchdog.timer" "$USER_SYSTEMD_DIR/hermes-memory-stack-watchdog.timer"
        fi
        systemctl --user daemon-reload || true
        systemctl --user enable hermes-memory-graph.service hermes-memory-stack.target >/dev/null 2>&1 || true
        systemctl --user restart hermes-memory-graph.service >/dev/null 2>&1 || true
        for _i in $(seq 1 15); do
            curl -fsS -m 2 http://127.0.0.1:8900/health >/dev/null 2>&1 && break
            sleep 1
        done
        if [ -f "$USER_SYSTEMD_DIR/hermes-memory-stack-watchdog.timer" ]; then
            systemctl --user enable --now hermes-memory-stack-watchdog.timer >/dev/null 2>&1 || true
        fi
        echo "   ✅ hermes-memory-graph user systemd service/watchdog 已安装/启动"
    fi
fi

# 9. Copy memory-graph plugin
if [ -d "$HOME/.hermes/plugins/memory-graph" ]; then
    echo "   ✅ memory-graph plugin 已存在"
else
    echo "   ⚠️ memory-graph plugin 不存在，请手动安装"
fi
