#!/bin/bash
# apply_hermes_patches.sh - Apply custom PR patches after hermes update
# Idempotent: safe to run multiple times. Skips already-applied patches.
# Supports both legacy (~/.hermes/hermes-agent) and FHS (/usr/local/lib/hermes-agent) layouts.

set -e

PATCHES_DIR="$HOME/.hermes/patches/individual"

# Auto-detect hermes-agent source directory
detect_hermes_dir() {
    # 1. Explicit override
    if [ -n "${HERMES_AGENT_DIR:-}" ] && [ -d "$HERMES_AGENT_DIR/.git" ]; then
        echo "$HERMES_AGENT_DIR"
        return 0
    fi

    # 2. Legacy layout (non-root or existing install)
    if [ -d "$HOME/.hermes/hermes-agent/.git" ]; then
        echo "$HOME/.hermes/hermes-agent"
        return 0
    fi

    # 3. FHS layout (root on Linux)
    if [ -d "/usr/local/lib/hermes-agent/.git" ]; then
        echo "/usr/local/lib/hermes-agent"
        return 0
    fi

    # 4. Try to find via hermes executable
    local hermes_bin
    hermes_bin=$(command -v hermes 2>/dev/null || true)
    if [ -n "$hermes_bin" ]; then
        # Resolve symlinks
        hermes_bin=$(readlink -f "$hermes_bin" 2>/dev/null || echo "$hermes_bin")
        # hermes is usually at <venv>/bin/hermes, source is 2 levels up
        local candidate
        candidate=$(dirname "$(dirname "$hermes_bin")")
        if [ -d "$candidate/.git" ]; then
            echo "$candidate"
            return 0
        fi
    fi

    # 5. Search common locations
    for dir in \
        "$HOME/.hermes/hermes-agent" \
        "/usr/local/lib/hermes-agent" \
        "/opt/hermes-agent"; do
        if [ -d "$dir/.git" ]; then
            echo "$dir"
            return 0
        fi
    done

    return 1
}

HERMES_DIR=$(detect_hermes_dir) || {
    echo "❌ Cannot find hermes-agent source directory"
    echo "   Searched: ~/.hermes/hermes-agent, /usr/local/lib/hermes-agent"
    echo "   Set HERMES_AGENT_DIR to override"
    exit 1
}

echo "📂 Using hermes-agent at: $HERMES_DIR"
cd "$HERMES_DIR" || exit 1

PATCH_COUNT=$(ls "$PATCHES_DIR"/*.patch 2>/dev/null | wc -l)
if [ "$PATCH_COUNT" -eq 0 ]; then
    echo "ℹ️  No patches to apply"
    exit 0
fi

echo "🔍 Checking $PATCH_COUNT patches..."

APPLIED=0
SKIPPED=0
FAILED=0

for patch_file in "$PATCHES_DIR"/*.patch; do
    [ -f "$patch_file" ] || continue
    patch_name=$(basename "$patch_file" .patch)

    # Extract subject from patch file
    subject=$(sed -n 's/^Subject: \[PATCH[^]]*\] //p' "$patch_file" 2>/dev/null | head -1)

    if [ -z "$subject" ]; then
        # No subject found, try to apply anyway
        subject="$patch_name"
    fi

    # Check if already in history (match first 50 chars of subject)
    short_subject=$(echo "$subject" | head -c 50)
    if git log --oneline -30 HEAD 2>/dev/null | grep -qi "$short_subject"; then
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # Apply
    if git am --3way "$patch_file" 2>/dev/null; then
        echo "  ✅ $patch_name"
        APPLIED=$((APPLIED + 1))
    else
        git am --abort 2>/dev/null || true
        if git apply --check "$patch_file" 2>/dev/null; then
            git apply "$patch_file"
            git add -A
            git commit -m "Applied: $patch_name" --no-verify 2>/dev/null || true
            echo "  ✅ $patch_name (fallback)"
            APPLIED=$((APPLIED + 1))
        else
            # git apply --check failed - determine if already applied or real conflict
            already_applied=false

            # Strategy 1: Match full subject against recent git log (deeper search, 100 commits)
            if [ -n "$subject" ]; then
                if git log --oneline -100 HEAD 2>/dev/null | grep -qi "$subject"; then
                    already_applied=true
                fi
            fi

            # Strategy 2: Match patch name against recent git log
            if [ "$already_applied" = false ]; then
                if git log --oneline -100 HEAD 2>/dev/null | grep -qi "$patch_name"; then
                    already_applied=true
                fi
            fi

            # Strategy 3: Try reverse-apply check - if the patch can be cleanly
            # reversed, its changes are already in the codebase
            if [ "$already_applied" = false ]; then
                if git apply --reverse --check "$patch_file" 2>/dev/null; then
                    already_applied=true
                fi
            fi

            if [ "$already_applied" = true ]; then
                echo "  ⏭️  $patch_name (already applied)"
                SKIPPED=$((SKIPPED + 1))
            else
                echo "  ❌ $patch_name (conflict)"
                FAILED=$((FAILED + 1))
            fi
        fi
    fi
done

# === Apply combined-final.patch (integration patch) ===
COMBINED_PATCH="$HOME/.hermes/patches/integration-v1/combined-final.patch"
if [ -f "$COMBINED_PATCH" ]; then
    # Check if already applied by testing for a key feature
    if grep -q "DisclosureRouter" "$HERMES_DIR/agent/disclosure_router.py" 2>/dev/null && \
       grep -q "_detect_time_budget" "$HERMES_DIR/run_agent.py" 2>/dev/null; then
        echo "⏭️  combined-final.patch (already applied)"
        SKIPPED=$((SKIPPED + 1))
    else
        echo "📦 Applying combined-final.patch (integration)..."
        if git apply --check "$COMBINED_PATCH" 2>/dev/null; then
            git apply "$COMBINED_PATCH"
            git add -A
            git commit -m "Applied: combined-final.patch (integration)" --no-verify 2>/dev/null || true
            echo "  ✅ combined-final.patch"
            APPLIED=$((APPLIED + 1))
        else
            echo "  ⚠️  combined-final.patch (conflict — may need manual fix)"
            FAILED=$((FAILED + 1))
        fi
    fi
fi

echo ""
if [ "$APPLIED" -gt 0 ]; then
    echo "✅ Applied $APPLIED patches"
    # Restart gateway if running
    for svc in hermes-gateway hermes-dashboard; do
        if systemctl --user is-active "$svc" >/dev/null 2>&1; then
            echo "🔄 Restarting $svc..."
            systemctl --user restart "$svc"
        fi
    done
fi
[ "$SKIPPED" -gt 0 ] && echo "⏭️  $SKIPPED already applied"
[ "$FAILED" -gt 0 ] && echo "⚠️  $FAILED failed (may need manual fix)"
[ "$APPLIED" -eq 0 ] && [ "$SKIPPED" -gt 0 ] && echo "✅ All patches already applied"
