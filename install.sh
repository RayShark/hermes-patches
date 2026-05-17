#!/bin/bash
# Hermes Agent 社区补丁合集 — 一键安装
# 用法: bash <(curl -sL https://raw.githubusercontent.com/Cyrene963/hermes-patches/main/install.sh)
#
# 安装内容:

# ── Memory Graph 模块 ──
echo ""
echo "📦 安装 Memory Graph 模块..."
MG_FILES=(
    "agent/memory_graph/__init__.py"
    "agent/memory_graph/auth.py"
    "agent/memory_graph/db/__init__.py"
    "agent/memory_graph/db/models.py"
    "agent/memory_graph/db/init.sql"
    "agent/memory_graph/migration.py"
    "agent/memory_graph/server.py"
    "agent/memory_graph/services/__init__.py"
    "agent/memory_graph/services/graph.py"
    "agent/memory_graph/services/search.py"
    "agent/memory_graph/services/glossary.py"
    "agent/memory_graph/services/disclosure.py"
    "agent/memory_graph/services/namespace.py"
    "agent/memory_graph/services/snapshot.py"
    "agent/memory_graph/services/system_views.py"
    "agent/memory_graph/services/text_patch.py"
    "agent/memory_graph/services/search_terms.py"
    "agent/memory_graph/web/__init__.py"
    "agent/memory_graph/web/dashboard.py"
    "tools/memory_graph_tool.py"
)
for f in "${MG_FILES[@]}"; do
    src="$PATCHES_DIR/$f"
    dst="$HERMES_DIR/$f"
    if [ -f "$src" ]; then
        mkdir -p "$(dirname "$dst")"
        if [ ! -f "$dst" ] || ! diff -q "$src" "$dst" > /dev/null 2>&1; then
            cp "$src" "$dst"
            echo "✅ $f"
        else
            echo "⏭️  $f 已是最新"
        fi
    fi
done
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

# ── Install auto-reapply hook in hermes update command ──
MAIN_PY="$HERMES_DIR/hermes_cli/main.py"
if [ -f "$MAIN_PY" ] && ! grep -q "_reapply_community_patches" "$MAIN_PY" 2>/dev/null; then
    echo ""
    echo "🔧 安装 hermes update 自动打补丁钩子..."
    "$HERMES_DIR/venv/bin/python3" -c "
import sys
path = sys.argv[1]
with open(path) as f:
    c = f.read()
if '_reapply_community_patches' in c:
    print('  ⏭️  钩子已存在')
    sys.exit(0)
func = '''
def _reapply_community_patches() -> None:
    \"\"\"Reapply community patches after hermes update. Idempotent.\"\"\"
    import subprocess as _sp
    patches_dir = Path.home() / \".hermes\" / \"patches\"
    install_sh = patches_dir / \"install.sh\"
    if not install_sh.exists():
        return
    print()
    print(\"📦 Reapplying community patches...\")
    try:
        result = _sp.run([\"bash\", str(install_sh)], cwd=str(patches_dir),
                         capture_output=True, text=True, timeout=120)
        for line in result.stdout.splitlines():
            if line.strip() and not line.startswith((\"╔\", \"║\", \"╚\")):
                print(f\"  {line}\")
        if result.returncode != 0:
            print(f\"  ⚠️  Patch reapplication had issues (exit {result.returncode})\")
    except Exception:
        pass

'''
if 'def _cmd_update_impl' in c:
    c = c.replace('def _cmd_update_impl(args, gateway_mode: bool):', func + 'def _cmd_update_impl(args, gateway_mode: bool):')
    c = c.replace('        print(\"Tip: You can now select a provider and model:\")', '        _reapply_community_patches()\\n\\n        print(\"Tip: You can now select a provider and model:\")')
    with open(path, 'w') as f:
        f.write(c)
    print('  ✅ 钩子已安装')
else:
    print('  ⚠️  未找到 _cmd_update_impl，跳过')
" "$MAIN_PY"
fi
