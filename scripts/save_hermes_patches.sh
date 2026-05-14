#!/bin/bash
# save_hermes_patches.sh - Save custom commits as patch files
# SMART MODE: only regenerates if there are new commits; preserves existing patches
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

mkdir -p "$PATCHES_DIR"

echo "💾 Saving custom patches..."

# Get commits ahead of origin/main by Nitrogen
AHEAD_COMMITS=$(git log --format="%H" origin/main..HEAD --no-merges --author="Nitrogen" --reverse 2>/dev/null | wc -l)

if [ "$AHEAD_COMMITS" -eq 0 ]; then
    EXISTING=$(ls "$PATCHES_DIR"/*.patch 2>/dev/null | wc -l)
    echo "  ℹ️  No custom commits ahead of origin/main"
    echo "  📦 Preserving $EXISTING existing patches for reapplication"
    exit 0
fi

# Only regenerate if we have commits to save
# DON'T delete existing patches — only add/update
COUNT=0
git log --format="%H" origin/main..HEAD --no-merges --author="Nitrogen" --reverse | while read sha; do
    COUNT=$((COUNT + 1))
    SUBJECT=$(git log -1 --format="%s" "$sha" | tr '/ ' '_-' | tr -cd '[:alnum:]_-' | head -c 60)
    PATCH_FILE="$PATCHES_DIR/${COUNT}_${SUBJECT}.patch"
    if [ ! -f "$PATCH_FILE" ]; then
        git format-patch -1 "$sha" --stdout > "$PATCH_FILE"
        echo "  ✅ Saved: $(basename "$PATCH_FILE")"
    fi
done

TOTAL=$(ls "$PATCHES_DIR"/*.patch 2>/dev/null | wc -l)
echo ""
echo "📦 Total patches: $TOTAL"

# === Save combined-final.patch ===
# Generate a diff from upstream/main to current HEAD as the unified integration patch
COMBINED_DIR="$HOME/.hermes/patches/integration-v1"
COMBINED_FILE="$COMBINED_DIR/combined-final.patch"
mkdir -p "$COMBINED_DIR"
AHEAD=$(git rev-list --count origin/main..HEAD 2>/dev/null || echo 0)
if [ "$AHEAD" -gt 0 ]; then
    git diff origin/main..HEAD > "$COMBINED_FILE"
    echo "📦 Updated combined-final.patch ($(wc -c < "$COMBINED_FILE") bytes)"
fi
