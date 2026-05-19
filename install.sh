#!/bin/bash
# Hermes Agent 社区补丁合集 — 一键安装脚本
# 适配版本：v0.14.0 (v2026.5.16)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCHES_DIR="$SCRIPT_DIR"
HERMES_DIR="${HERMES_HOME:-$HOME/.hermes/hermes-agent}"

echo "🔧 Hermes 社区补丁合集 v14"
echo "   适配版本：v0.14.0 (v2026.5.16)"
echo "   补丁目录：$PATCHES_DIR"
echo "   Hermes目录：$HERMES_DIR"
echo ""

# 1. Apply combined patch
PATCH_FILE="$PATCHES_DIR/combined-final-v14.patch"
if [ -f "$PATCH_FILE" ]; then
    echo "📦 应用 combined-final-v14.patch..."
    cd "$HERMES_DIR"
    if git apply --check "$PATCH_FILE" 2>/dev/null; then
        git apply "$PATCH_FILE"
        echo "   ✅ 补丁已应用"
    else
        echo "   ⏭️ 补丁已应用或有冲突，跳过"
    fi
fi

# 2. Copy agent modules
for module in memory_metacognition.py memory_write_pipeline.py shadow_write_logger.py hindsight_access_tracker.py hindsight_reranker.py; do
    if [ -f "$PATCHES_DIR/agent/$module" ]; then
        cp "$PATCHES_DIR/agent/$module" "$HERMES_DIR/agent/"
        echo "   ✅ agent/$module 已复制"
    fi
done

# 3. Copy tools
if [ -f "$PATCHES_DIR/tools/memory_graph_tool.py" ]; then
    cp "$PATCHES_DIR/tools/memory_graph_tool.py" "$HERMES_DIR/tools/"
    echo "   ✅ memory_graph_tool.py 已复制"
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
echo "   ✅ .pyc 缓存已清理"

# 7. Register memory_graph tools in toolsets
if ! grep -q "memory_graph_search" "$HERMES_DIR/toolsets.py" 2>/dev/null; then
    echo "   ⚠️ memory_graph tools 未在 toolsets.py 中注册，请手动添加"
fi

echo ""
echo "✅ 补丁安装完成！"
echo "   请重启 gateway: hermes gateway restart"
