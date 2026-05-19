"""Shadow Mode write logger — records proposed writes without executing them."""

import json
import logging
import os
import time
from datetime import datetime, timezone
from typing import Dict, List, Any, Optional

logger = logging.getLogger(__name__)

_SHADOW_LOG_DIR = os.path.expanduser("~/.hermes/logs/shadow_writes")
os.makedirs(_SHADOW_LOG_DIR, exist_ok=True)


def log_shadow_write(
    conversation_id: str,
    user_id: str,
    namespace: str,
    user_message: str,
    assistant_message: str,
    candidates: List[Dict[str, Any]],
    mode: str = "shadow"
) -> Dict[str, Any]:
    """Log a shadow write entry."""
    entry = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "conversation_id": conversation_id,
        "user_id": user_id,
        "namespace": namespace,
        "user_message": user_message[:200],
        "assistant_message": assistant_message[:200],
        "candidate_writes": [],
        "would_write": False,
        "actually_written": False,
        "mode": mode,
    }
    
    for c in candidates:
        write_action = {
            "memory_type": c.get("memory_type", "unknown"),
            "importance_score": c.get("importance", 0),
            "target_store": c.get("target_store", "ignore"),
            "target_path": c.get("target_path", ""),
            "subject": c.get("subject", ""),
            "predicate": c.get("predicate", ""),
            "object": c.get("object_value", "")[:100],
            "requires_review": c.get("requires_review", False),
            "reason": c.get("reason", ""),
        }
        entry["candidate_writes"].append(write_action)
        
        if c.get("target_store") not in ("ignore", None) and c.get("importance", 0) >= 0.40:
            entry["would_write"] = True
    
    # Append to daily log file
    date_str = datetime.now().strftime("%Y-%m-%d")
    log_file = os.path.join(_SHADOW_LOG_DIR, f"shadow_{date_str}.jsonl")
    
    with open(log_file, "a") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    
    logger.debug("Shadow write logged: %d candidates, would_write=%s",
                 len(candidates), entry["would_write"])
    
    return entry


def get_shadow_stats(date_str: Optional[str] = None) -> Dict[str, Any]:
    """Get shadow write statistics for a date."""
    if not date_str:
        date_str = datetime.now().strftime("%Y-%m-%d")
    
    log_file = os.path.join(_SHADOW_LOG_DIR, f"shadow_{date_str}.jsonl")
    if not os.path.exists(log_file):
        return {"date": date_str, "entries": 0}
    
    entries = []
    with open(log_file) as f:
        for line in f:
            line = line.strip()
            if line:
                entries.append(json.loads(line))
    
    total_candidates = sum(len(e.get("candidate_writes", [])) for e in entries)
    would_write = sum(1 for e in entries if e.get("would_write"))
    by_type = {}
    by_target = {}
    
    for e in entries:
        for c in e.get("candidate_writes", []):
            mtype = c.get("memory_type", "unknown")
            target = c.get("target_store", "ignore")
            by_type[mtype] = by_type.get(mtype, 0) + 1
            by_target[target] = by_target.get(target, 0) + 1
    
    return {
        "date": date_str,
        "entries": len(entries),
        "total_candidates": total_candidates,
        "would_write_count": would_write,
        "by_type": by_type,
        "by_target": by_target,
    }
