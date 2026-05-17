#!/bin/bash
# Hermes Agent 社区补丁合集 — 一键安装
# 用法: bash <(curl -sL https://raw.githubusercontent.com/Cyrene963/hermes-patches/main/install.sh)
#
# 安装内容:
#   1. combined-final.patch — 79个文件的核心功能+安全补丁
#   2. agent/disclosure_router.py — 记忆主动注入路由
#   3. memory_policy.default.yaml — 记忆元认知策略配置
#
# 兼容: 上游合并的补丁会被 combined-final 的 git apply --check 自动检测跳过

set -e

REPO_URL="https://github.com/Cyrene963/hermes-patches.git"
HERMES_DIR="${HERMES_HOME:-$HOME/.hermes/hermes-agent}"
TEMP_DIR=$(mktemp -d)
PATCHES_DIR=""

echo "╔══════════════════════════════════════════╗"
echo "║     Hermes Agent 社区补丁合集            ║"
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
    echo "❌ 未找到 Hermes Agent 安装"
    echo "   先安装: pip install hermes-agent"
    echo "   或克隆: git clone https://github.com/NousResearch/hermes-agent.git ~/.hermes/hermes-agent"
    exit 1
fi
echo "✅ Hermes 路径: $HERMES_DIR"

# ── Prepare patches ──
if [ -f "$(dirname "$0")/combined-final.patch" ]; then
    PATCHES_DIR="$(cd "$(dirname "$0")" && pwd)"
    echo "📂 使用本地补丁"
else
    echo "📥 下载补丁..."
    git clone --depth 1 "$REPO_URL" "$TEMP_DIR/hermes-patches" 2>/dev/null
    PATCHES_DIR="$TEMP_DIR/hermes-patches"
fi

cd "$HERMES_DIR"

ORIGINAL_HEAD=$(git rev-parse HEAD)
BRANCH=$(git branch --show-current)
echo "📌 当前: $BRANCH @ ${ORIGINAL_HEAD:0:8}"
echo ""

# ── Apply combined-final.patch ──
COMBINED="$PATCHES_DIR/combined-final.patch"
APPLIED=0

if [ -f "$COMBINED" ]; then
    if git apply --reverse --check "$COMBINED" 2>/dev/null; then
        echo "⏭️  combined-final.patch 已经应用，跳过"
    elif git apply --check "$COMBINED" 2>/dev/null; then
        git apply "$COMBINED"
        git add -A
        git commit -m "Applied: combined-final.patch (社区功能+安全补丁)" --no-verify 2>/dev/null || true
        echo "✅ combined-final.patch 已应用"
        APPLIED=1
    else
        echo "❌ combined-final.patch 冲突!"
        echo "   回滚: cd $HERMES_DIR && git reset --hard $ORIGINAL_HEAD"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
else
    echo "❌ combined-final.patch 未找到"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# ── Apply individual patches (new, not yet in combined-final.patch) ──
if [ -d "$PATCHES_DIR/patches" ]; then
    for pf in "$PATCHES_DIR/patches"/*.patch; do
        [ -f "$pf" ] || continue
        PNAME=$(basename "$pf")
        if git apply --reverse --check "$pf" 2>/dev/null; then
            echo "⏭️  $PNAME 已经应用，跳过"
        elif git apply --check "$pf" 2>/dev/null; then
            git apply "$pf"
            echo "✅ $PNAME 已应用"
            APPLIED=1
        else
            echo "⚠️  $PNAME 跳过（与当前版本不兼容）"
        fi
    done
fi

# ── Install standalone files ──

# Disclosure Router (记忆主动注入)
if [ -f "$PATCHES_DIR/agent/disclosure_router.py" ]; then
    if [ ! -f "$HERMES_DIR/agent/disclosure_router.py" ]; then
        cp "$PATCHES_DIR/agent/disclosure_router.py" "$HERMES_DIR/agent/disclosure_router.py"
        echo "✅ disclosure_router.py 已安装"
        APPLIED=1
    else
        echo "⏭️  disclosure_router.py 已存在"
    fi
fi

# Memory Policy 配置
POLICY_DIR="${HERMES_HOME:-$HOME/.hermes}"
if [ ! -f "$POLICY_DIR/memory_policy.yaml" ]; then
    if [ -f "$PATCHES_DIR/memory_policy.default.yaml" ]; then
        cp "$PATCHES_DIR/memory_policy.default.yaml" "$POLICY_DIR/memory_policy.yaml"
        echo "✅ memory_policy.yaml 已安装 → $POLICY_DIR/memory_policy.yaml"
    fi
else
    echo "⏭️  memory_policy.yaml 已存在"
fi

# ── Done ──
rm -rf "$TEMP_DIR"

echo ""
if [ "$APPLIED" -gt 0 ]; then
    echo "🎉 安装完成！"
    echo ""
    echo "🔄 重启 Gateway..."
    for svc in hermes-gateway hermes-dashboard; do
        if systemctl --user is-active "$svc" >/dev/null 2>&1; then
            systemctl --user restart "$svc"
            echo "  ✅ $svc 已重启"
        fi
    done
else
    echo "✅ 所有补丁已是最新"
fi

echo ""
echo "回滚命令: cd $HERMES_DIR && git reset --hard ${ORIGINAL_HEAD:0:8}"
