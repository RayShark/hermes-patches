# Claude Code Architecture v2 — Hermes Agent Improvements

Based on analysis of Claude Code's leaked source code (Austin1serb/Anthropic-Leaked-Source-Code), this patch set brings Claude Code's key architectural patterns to Hermes Agent.

## What's Included

### New Modules (8 files)

| Module | Location | Purpose |
|--------|----------|---------|
| `file_state_cache.py` | `tools/` | LRU file content cache (100 entries, 25MB). Returns cached content on dedup hits instead of empty stubs. |
| `micro_compact.py` | `agent/` | Per-turn tool result pruning. Clears old tool outputs (keep recent N) to prevent context bloat. Zero LLM cost. |
| `context_collapse.py` | `agent/` | Folds long tool outputs into head+tail+metadata. Preserves first/last N chars of each result. |
| `tool_prompts.py` | `agent/` | Per-tool prompt system. Each tool has its own behavioral guidance, assembled on demand. |
| `session_memory_compact.py` | `agent/` | Preserves memory authority during compression. Re-injects memory with strong authority markers after compaction. |
| `post_compact_cleanup.py` | `agent/` | Clears stale caches after compression. Also provides time-based micro-compact trigger. |
| `tool_permissions.py` | `agent/` | Per-tool risk classification (SAFE/LOW/MEDIUM/HIGH/BLOCKED) with hardline command blocklist. |
| `loop_middleware.py` | `agent/` | Middleware pattern for the agent loop. Extracts compliance checks into pluggable pre/post hooks. |

### Integration Points (in run_agent.py)

- **Micro-compact + Context collapse**: Run before each API call (lines ~11380-11420)
- **Session memory compact**: Runs in `_compress_context()` before/after compression
- **Post-compact cleanup**: Runs in `_compress_context()` after compression
- **Per-tool prompts**: Assembled in `_build_system_prompt()` alongside existing tool guidance

### Configuration (config.yaml)

```yaml
agent:
  compression:
    microcompact:
      enabled: true        # default true
      keep_recent: 5       # keep N most recent tool results
      min_result_chars: 200  # only compact results larger than this
    context_collapse:
      enabled: true        # default true
      max_chars: 5000      # only collapse results longer than this
      head_chars: 500      # chars to keep from start
      tail_chars: 500      # chars to keep from end
```

## How to Apply After hermes update

```bash
bash /root/hermes-patches/patches/claude-code-v2/apply.sh
```

Then verify:
```bash
cd ~/.hermes/hermes-agent && source venv/bin/activate
python -m pytest tests/tools/test_file_state_cache.py tests/agent/test_micro_compact.py tests/agent/test_context_collapse.py tests/agent/test_tool_permissions.py tests/agent/test_loop_middleware.py tests/agent/test_tool_prompts.py tests/agent/test_session_memory_compact.py tests/agent/test_post_compact_cleanup.py -q
```

## Architecture Notes

### Compression Pipeline (per API call)

```
1. microcompact_messages()     — clear old tool results
2. collapse_messages()         — fold long outputs
3. _sanitize_api_messages()    — existing safety net
4. API call
5. On compression trigger:
   a. extract_memory_before_compact()
   b. context_compressor.compress()
   c. reinject_memory_after_compact()
   d. run_post_compact_cleanup()
```

### Per-Tool Prompt Pattern (Claude Code style)

Each tool has a `@register_tool_prompt("tool_name")` decorator that returns
behavioral guidance. Only assembled when the tool is available. Replaces
monolithic TOOL_USE_ENFORCEMENT_GUIDANCE with tool-specific instructions.

### Tool Risk Classification

```
SAFE:     read_file, search_files, web_search, session_search, skill_view
LOW:      memory, skill_manage, send_message
MEDIUM:   write_file, patch, browser_click, browser_navigate
HIGH:     terminal, execute_code, delegate_task, cronjob
BLOCKED:  rm -rf /, mkfs, dd if=/dev/zero, fork bomb, shutdown
```

## Test Coverage

- 124 tests total across 8 test files
- All tests pass, no regression with existing test suite
- Tests cover: unit tests for each module, integration tests with file_tools, edge cases

## Credits

Architecture patterns extracted from Claude Code's leaked source code
(Austin1serb/Anthropic-Leaked-Source-Code, v2.1.88 source map).
Implemented for Hermes Agent by Cyrene963.
