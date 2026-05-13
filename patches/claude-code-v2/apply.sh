#!/bin/bash
# Claude Code Architecture v2 — Apply Script
# Restores all new modules and patches after hermes update
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HERMES_DIR="$HOME/.hermes/hermes-agent"

echo "=== Applying Claude Code Architecture v2 ==="

# Copy new modules
for f in file_state_cache.py micro_compact.py context_collapse.py tool_permissions.py loop_middleware.py tool_prompts.py session_memory_compact.py post_compact_cleanup.py; do
    if [ -f "$SCRIPT_DIR/$f" ]; then
        if echo "$f" | grep -q "file_state_cache"; then
            cp "$SCRIPT_DIR/$f" "$HERMES_DIR/tools/$f"
            echo "  + tools/$f"
        else
            cp "$SCRIPT_DIR/$f" "$HERMES_DIR/agent/$f"
            echo "  + agent/$f"
        fi
    fi
done

# Copy test files
for f in test_file_state_cache.py test_micro_compact.py test_context_collapse.py test_tool_permissions.py test_loop_middleware.py test_tool_prompts.py test_session_memory_compact.py test_post_compact_cleanup.py; do
    if [ -f "$SCRIPT_DIR/$f" ]; then
        if echo "$f" | grep -q "file_state_cache"; then
            cp "$SCRIPT_DIR/$f" "$HERMES_DIR/tests/tools/$f"
            echo "  + tests/tools/$f"
        else
            cp "$SCRIPT_DIR/$f" "$HERMES_DIR/tests/agent/$f"
            echo "  + tests/agent/$f"
        fi
    fi
done

# Apply patches for modified files
for patch in "$SCRIPT_DIR"/*.patch; do
    if [ -f "$patch" ] && [ -s "$patch" ]; then
        cd "$HERMES_DIR"
        if git apply --check "$patch" 2>/dev/null; then
            git apply "$patch"
            echo "  + Applied $(basename $patch)"
        else
            echo "  ! SKIP $(basename $patch) (conflict — apply manually)"
        fi
    fi
done

echo ""
echo "=== Done. Run tests: ==="
echo "cd $HERMES_DIR && source venv/bin/activate && python -m pytest tests/tools/test_file_state_cache.py tests/agent/test_micro_compact.py tests/agent/test_context_collapse.py tests/agent/test_tool_permissions.py tests/agent/test_loop_middleware.py tests/agent/test_tool_prompts.py tests/agent/test_session_memory_compact.py tests/agent/test_post_compact_cleanup.py -q"
