#!/bin/bash
# Hermes Agent 社区补丁合集 — 一键安装脚本
# 适配版本：v0.14.0+ (v2026.5.16+)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCHES_DIR="$SCRIPT_DIR"
HERMES_DIR="${HERMES_HOME:-$HOME/.hermes/hermes-agent}"

echo "🔧 Hermes 社区补丁合集 v16"
echo "   适配版本：v0.14.0+ (v2026.5.16+) + upstream ca192cfb7"
echo "   补丁目录：$PATCHES_DIR"
echo "   Hermes目录：$HERMES_DIR"
echo ""

# 1. Apply combined patch
PATCH_FILE="$PATCHES_DIR/combined-final-v16.patch"
if [ -f "$PATCH_FILE" ]; then
    echo "📦 应用 combined-final-v16.patch..."
    cd "$HERMES_DIR"
    if git apply --check "$PATCH_FILE" 2>/dev/null; then
        git apply "$PATCH_FILE"
        echo "   ✅ 补丁已应用"
    else
        echo "   ⏭️ 补丁已应用或有冲突，跳过"
    fi
fi

# 2. Copy agent modules
for module in memory_metacognition.py memory_write_pipeline.py shadow_write_logger.py hindsight_access_tracker.py hindsight_reranker.py request_context.py; do
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

# 3. Copy tools
if [ -f "$PATCHES_DIR/tools/memory_graph_tool.py" ]; then
    cp "$PATCHES_DIR/tools/memory_graph_tool.py" "$HERMES_DIR/tools/"
    echo "   ✅ memory_graph_tool.py 已复制"
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

# 7. Register memory_graph tools in toolsets
if ! grep -q "memory_graph_search" "$HERMES_DIR/toolsets.py" 2>/dev/null; then
    echo "   ⚠️ memory_graph tools 未在 toolsets.py 中注册，请手动添加"
fi

echo ""
echo "✅ 补丁安装完成！"
echo "   请重启 gateway: hermes gateway restart"

# 8. Copy memory-graph plugin
if [ -d "$HOME/.hermes/plugins/memory-graph" ]; then
    echo "   ✅ memory-graph plugin 已存在"
else
    echo "   ⚠️ memory-graph plugin 不存在，请手动安装"
fi
