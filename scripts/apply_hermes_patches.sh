#!/bin/bash
# apply_hermes_patches.sh - hermes update 后重新应用补丁
# 用法: bash ~/.hermes/patches/scripts/apply_hermes_patches.sh
# 幂等: 多次运行安全，已应用的补丁自动跳过

set -e

HERMES_DIR="${HERMES_HOME:-$HOME/.hermes/hermes-agent}"
COMBINED_PATCH="${HERMES_HOME:-$HOME/.hermes}/patches/combined-final.patch"

# Auto-detect hermes-agent source
detect_hermes_dir() {
    if [ -d "$HERMES_DIR/.git" ]; then return 0; fi
    for alt in "$HOME/hermes-agent" "/usr/local/lib/hermes-agent" "/opt/hermes-agent"; do
        if [ -d "$alt/.git" ] && [ -f "$alt/run_agent.py" ]; then
            HERMES_DIR="$alt"
            return 0
        fi
    done
    return 1
}

if ! detect_hermes_dir; then
    echo "❌ Cannot find hermes-agent source directory"
    exit 1
fi

echo "📂 hermes-agent: $HERMES_DIR"
cd "$HERMES_DIR" || exit 1

# ── Apply combined-final.patch ──
if [ ! -f "$COMBINED_PATCH" ]; then
    echo "❌ combined-final.patch not found at $COMBINED_PATCH"
    exit 1
fi

if git apply --reverse --check "$COMBINED_PATCH" 2>/dev/null; then
    echo "⏭️  combined-final.patch 已经应用"
elif git apply --check "$COMBINED_PATCH" 2>/dev/null; then
    git apply "$COMBINED_PATCH"
    git add -A
    git commit -m "Applied: combined-final.patch (re-apply after update)" --no-verify 2>/dev/null || true
    echo "✅ combined-final.patch 已应用"
else
    echo "⚠️  combined-final.patch 冲突 — 可能需要手动解决"
    echo "   尝试: cd $HERMES_DIR && git apply --3way $COMBINED_PATCH"
    exit 1
fi

# ── Ensure standalone files exist ──
PATCHES_BASE="${HERMES_HOME:-$HOME/.hermes}/patches"

if [ -f "$PATCHES_BASE/agent/disclosure_router.py" ] && [ ! -f "$HERMES_DIR/agent/disclosure_router.py" ]; then
    cp "$PATCHES_BASE/agent/disclosure_router.py" "$HERMES_DIR/agent/disclosure_router.py"
    echo "✅ disclosure_router.py 已安装"
fi

# ── Restart gateway if running ──
for svc in hermes-gateway hermes-dashboard; do
    if systemctl --user is-active "$svc" >/dev/null 2>&1; then
        echo "🔄 重启 $svc..."
        systemctl --user restart "$svc"
    fi
done

echo "✅ 补丁应用完成"
