#!/bin/bash
# Hermes Agent 社区补丁合集 — 一键安装
# 用法: bash <(curl -sL https://raw.githubusercontent.com/Cyrene963/hermes-patches/main/install.sh)
#
# 安装内容:
#   1. combined-final-v14.patch — 元认知框架+微信隔离
#   2. memory_metacognition.py — 记忆元认知框架源码
#   3. memory_policy.default.yaml — 记忆元认知策略配置
#
# 兼容版本: v0.14.0 (v2026.5.16)

set -e

REPO_URL="https://github.com/Cyrene963/hermes-patches.git"
HERMES_DIR="${HERMES_HOME:-$HOME/.hermes/hermes-agent}"
TEMP_DIR=$(mktemp -d)
PATCHES_DIR=""

echo "╔══════════════════════════════════════════╗"
echo "║     Hermes Agent 社区补丁合集            ║"
echo "║     适配版本: v0.14.0 (v2026.5.16)       ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── Find hermes-agent source ──
find_hermes_source() {
    if [ -d "$HERMES_DIR/.git" ]; then return 0; fi
    for alt in "$HOME/hermes-agent" "/usr/local/lib/hermes-agent" "/opt/hermes-agent"; do
        if [ -d "$alt/.git" ] && [ -f "$alt/run_agent.py" ]; then
            HERMES_DIR="$alt"
            return 0
        fi
    done
    return 1
}

if ! find_hermes_source; then
    echo "❌ 找不到 hermes-agent 源码目录"
    echo "   请设置 HERMES_HOME 环境变量或确认安装路径"
    exit 1
fi

echo "📁 hermes-agent: $HERMES_DIR"

# ── Clone patch repo ──
echo "📥 下载补丁..."
git clone --depth 1 "$REPO_URL" "$TEMP_DIR/patches" 2>/dev/null
PATCHES_DIR="$TEMP_DIR/patches"

# ── Apply patches ──
cd "$HERMES_DIR"

echo "🔧 应用补丁..."

# 检查版本兼容性
UPSTREAM_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "unknown")
echo "   当前版本: $UPSTREAM_TAG"

# Apply combined patch
PATCH_FILE="$PATCHES_DIR/combined-final-v14.patch"
if [ -f "$PATCH_FILE" ]; then
    if git apply --check "$PATCH_FILE" 2>/dev/null; then
        git apply "$PATCH_FILE"
        echo "   ✅ combined-final-v14.patch 已应用"
    else
        echo "   ⚠️ combined-final-v14.patch 已应用或有冲突，尝试 --3way"
        git apply --3way "$PATCH_FILE" 2>/dev/null || echo "   ⚠️ 部分修改已存在"
    fi
else
    echo "   ❌ 找不到 $PATCH_FILE"
fi

# Copy memory_metacognition.py
if [ -f "$PATCHES_DIR/agent/memory_metacognition.py" ]; then
    cp "$PATCHES_DIR/agent/memory_metacognition.py" "$HERMES_DIR/agent/"
    echo "   ✅ memory_metacognition.py 已复制"
fi

# Copy memory_policy.default.yaml
if [ -f "$PATCHES_DIR/memory_policy.default.yaml" ]; then
    cp "$PATCHES_DIR/memory_policy.default.yaml" "$HERMES_DIR/"
    echo "   ✅ memory_policy.default.yaml 已复制"
fi

# ── Cleanup ──
rm -rf "$TEMP_DIR"

echo ""
echo "✅ 补丁安装完成！"
echo ""
echo "已安装:"
echo "  - 记忆元认知框架（查询扩展+预检门控+记忆索引）"
echo "  - 微信会话隔离（HINDSIGHT_SKIP_PLATFORMS）"
echo "  - session_search 微信隐藏"
echo ""
echo "配置: ~/.hermes/memory_policy.yaml"
echo "文档: https://github.com/Cyrene963/hermes-patches"
