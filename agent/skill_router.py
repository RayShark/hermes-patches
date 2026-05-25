"""Skill routing and enforcement helpers for Hermes Agent.

This module is intentionally small and dependency-light: it runs before the
first model token of a turn, so it cannot depend on the model deciding to call
``skill_view`` by itself.  The router produces an auditable route decision and
can synthesize skill-invocation messages that load mandatory skills before the
user's actual request reaches the model.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
import hashlib
import json
import logging
import os
import re
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence

from hermes_constants import get_hermes_home

logger = logging.getLogger(__name__)


@dataclass
class TaskClassification:
    task_domain: str = "other"
    execution_depth: str = "standard_task"
    autonomy_level: str = "proceed_until_blocked"
    duration_expectation: str = "minutes"
    continuation_policy: str = "stop_after_answer"
    completion_contract: str = "answer_only"
    deep_work_required: bool = False
    hermes_agent_task: bool = False
    memory_task: bool = False
    patch_or_pr_task: bool = False
    routing_failure_report: bool = False
    confidence: float = 0.5
    evidence: list[str] = field(default_factory=list)


@dataclass
class SkillRouteDecision:
    classification: TaskClassification
    candidate_skills: list[str] = field(default_factory=list)
    mandatory_skills: list[str] = field(default_factory=list)
    selected_skills: list[str] = field(default_factory=list)
    rejected_skills: dict[str, str] = field(default_factory=dict)
    missing_skills: list[str] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        data = asdict(self)
        return data


_LONG_HORIZON_PATTERNS = [
    r"deep[-\s]?work|深度工作",
    r"花\s*(一|1)?\s*(晚上|晚|夜|整晚|一天|1天|一周|1周|week|day|night)",
    r"一整天|整晚|通宵|overnight|all\s+night|all\s+day",
    r"不准停|不要停|直到完成|不完美不准停|自己推进|一直推进",
    r"不要问.*(继续|要不要)|别问.*(继续|要不要)",
    r"能查就查|能改就改|能测就测|端到端|彻底修复|production[-\s]?ready|能\s*merge",
]

_HERMES_PATTERNS = [
    r"hermes\s*agent|Hermes\s*Agent|Hermes|技能|skill|skills|gateway|toolsets?|工具集|插件|plugin|patch[-\s]?chain|补丁|四端同步",
]

_MEMORY_PATTERNS = [
    r"memory\s*graph|hindsight|memory\s*os|记忆|Memory\s*OS|外置大脑|数字替身|召回|写入管道",
]

_PR_PATTERNS = [
    r"\bPR\b|pull\s+request|upstream|官方仓库|开源|提交|merge|补丁仓库|patch[-\s]?repo",
]

_ROUTING_FAILURE_PATTERNS = [
    r"没(有)?用.*skill|没(有)?加载.*skill|应该加载|不知道.*skill|skills?.*用(不)?上",
    r"又偷懒|又停了|没继续|要不要继续|实际使用.*垃圾|测试.*通过.*实际",
]

_SIMPLE_EXPLAIN_PATTERNS = [
    r"^(简单|简要| briefly|quickly|一句话|解释一下|说下|介绍一下)",
]


def _matches_any(text: str, patterns: Sequence[str]) -> list[str]:
    hits: list[str] = []
    for pat in patterns:
        try:
            if re.search(pat, text, re.IGNORECASE):
                hits.append(pat)
        except re.error:
            continue
    return hits


def classify_task(user_message: str) -> TaskClassification:
    """Classify a turn for skill-routing purposes.

    This is a deterministic pre-model safety layer, not the only intelligence in
    the system.  It catches high-cost failure modes before the model can skip the
    skill check on its first token.
    """
    text = user_message or ""
    cls = TaskClassification()

    long_hits = _matches_any(text, _LONG_HORIZON_PATTERNS)
    hermes_hits = _matches_any(text, _HERMES_PATTERNS)
    memory_hits = _matches_any(text, _MEMORY_PATTERNS)
    pr_hits = _matches_any(text, _PR_PATTERNS)
    failure_hits = _matches_any(text, _ROUTING_FAILURE_PATTERNS)
    simple_hits = _matches_any(text.strip(), _SIMPLE_EXPLAIN_PATTERNS)

    if hermes_hits:
        cls.hermes_agent_task = True
        cls.task_domain = "hermes_config"
        cls.evidence.append("hermes_agent_terms")
    if memory_hits:
        cls.memory_task = True
        if cls.task_domain == "other":
            cls.task_domain = "memory"
        cls.evidence.append("memory_terms")
    if pr_hits:
        cls.patch_or_pr_task = True
        cls.evidence.append("patch_or_pr_terms")
    if failure_hits:
        cls.routing_failure_report = True
        cls.evidence.append("routing_failure_report")

    if long_hits:
        cls.deep_work_required = True
        cls.execution_depth = "deep_work"
        cls.autonomy_level = "fully_autonomous_until_done"
        cls.duration_expectation = "long_horizon"
        cls.continuation_policy = "continue_until_verified"
        cls.completion_contract = "modify_code_and_verify" if cls.hermes_agent_task else "verify"
        cls.confidence = 0.95
        cls.evidence.append("long_horizon_terms")
    elif simple_hits and not failure_hits:
        cls.execution_depth = "quick_answer"
        cls.autonomy_level = "proceed_until_blocked"
        cls.duration_expectation = "minutes"
        cls.continuation_policy = "stop_after_answer"
        cls.confidence = 0.75
        cls.evidence.append("simple_answer_terms")
    elif failure_hits:
        cls.execution_depth = "standard_task"
        cls.continuation_policy = "continue_until_verified"
        cls.confidence = 0.85

    if cls.hermes_agent_task and (cls.routing_failure_report or cls.deep_work_required):
        cls.completion_contract = "modify_code_and_verify"

    return cls


def _available_lookup(available_skill_names: Iterable[str] | None) -> set[str]:
    names = set()
    for name in available_skill_names or []:
        if not name:
            continue
        raw = str(name).strip()
        names.add(raw)
        names.add(raw.lower())
        names.add(raw.lower().replace("_", "-"))
    return names


def _skill_available(name: str, lookup: set[str]) -> bool:
    return name in lookup or name.lower() in lookup or name.lower().replace("_", "-") in lookup


def route_skills(
    user_message: str,
    available_skill_names: Iterable[str] | None = None,
) -> SkillRouteDecision:
    """Return the skills that must/should be loaded for this user turn."""
    cls = classify_task(user_message)
    lookup = _available_lookup(available_skill_names)
    mandatory: list[str] = []
    candidates: list[str] = []
    notes: list[str] = []

    def add(name: str, *, must: bool = False) -> None:
        if name not in candidates:
            candidates.append(name)
        if must and name not in mandatory:
            mandatory.append(name)

    if cls.hermes_agent_task:
        add("hermes-agent", must=True)
    if cls.memory_task:
        add("memory-management", must=True)
    if cls.deep_work_required:
        add("deep-work", must=True)
        notes.append("long-horizon/autonomous request: deep-work bundle is mandatory")
        # Bundle dependencies that exist in this installation are selected.  They
        # are not all mandatory because installations differ, but they are visible
        # in trace for debugging missed context.
        for dep in ("aegis-lite-completion-gate", "deep-work", "memory-management"):
            add(dep, must=(dep == "deep-work"))
    if cls.patch_or_pr_task:
        add("universal-solutions-for-prs", must=cls.hermes_agent_task)
        add("hermes-memory-os", must=cls.hermes_agent_task)

    if cls.routing_failure_report:
        add("deep-work", must=cls.deep_work_required)
        notes.append("user reported prior skill-routing failure; trace this turn")

    # For a simple explainer, avoid loading deep-work merely because the user
    # mentions the words while asking what a skill is.
    if cls.execution_depth == "quick_answer" and "deep-work" in mandatory:
        mandatory.remove("deep-work")
        notes.append("quick-answer request: deep-work not mandatory")

    selected = [s for s in candidates if not lookup or _skill_available(s, lookup)]
    missing = [s for s in mandatory if lookup and not _skill_available(s, lookup)]

    return SkillRouteDecision(
        classification=cls,
        candidate_skills=candidates,
        mandatory_skills=mandatory,
        selected_skills=selected,
        missing_skills=missing,
        notes=notes,
    )


def _skill_command_map() -> Mapping[str, Mapping[str, Any]]:
    try:
        from agent.skill_commands import get_skill_commands
        return get_skill_commands()
    except Exception:
        return {}


def available_skill_names_from_commands(commands: Mapping[str, Mapping[str, Any]] | None = None) -> set[str]:
    commands = commands if commands is not None else _skill_command_map()
    out: set[str] = set()
    for cmd, info in commands.items():
        slug = str(cmd).lstrip("/")
        out.add(slug)
        name = str((info or {}).get("name") or "")
        if name:
            out.add(name)
    return out


def _command_for_skill(skill_name: str, commands: Mapping[str, Mapping[str, Any]]) -> str | None:
    target = skill_name.lower().replace("_", "-")
    for cmd, info in commands.items():
        slug = str(cmd).lstrip("/").lower().replace("_", "-")
        name = str((info or {}).get("name") or "").lower().replace("_", "-")
        if target in {slug, name}:
            return str(cmd)
    return None


def build_autoload_skill_messages(
    user_message: str,
    *,
    task_id: str | None = None,
) -> tuple[list[dict[str, str]], SkillRouteDecision]:
    """Build synthetic user messages that load mandatory skills before the turn.

    Returns ``(messages, decision)``.  The caller should insert the messages
    before the real user message so the final user request remains the most
    recent instruction.
    """
    commands = _skill_command_map()
    names = available_skill_names_from_commands(commands)
    decision = route_skills(user_message, names)

    messages: list[dict[str, str]] = []
    if not decision.mandatory_skills:
        return messages, decision

    try:
        from agent.skill_commands import build_skill_invocation_message
    except Exception:
        decision.notes.append("skill invocation helper unavailable")
        return messages, decision

    for skill_name in decision.mandatory_skills:
        cmd = _command_for_skill(skill_name, commands)
        if not cmd:
            if skill_name not in decision.missing_skills:
                decision.missing_skills.append(skill_name)
            continue
        runtime_note = (
            "Automatically loaded by Hermes Skill Router before the first model token. "
            "This skill is mandatory for the current task classification; follow it unless the user explicitly overrides it."
        )
        payload = build_skill_invocation_message(
            cmd,
            user_instruction="Auto-loaded because the current user request requires this skill.",
            task_id=task_id,
            runtime_note=runtime_note,
        )
        if payload:
            messages.append({"role": "user", "content": payload})
        else:
            if skill_name not in decision.missing_skills:
                decision.missing_skills.append(skill_name)

    if decision.classification.deep_work_required:
        messages.append({
            "role": "user",
            "content": (
                "[Hermes Skill Router Execution Gate]\n"
                "This turn was classified as long-horizon/autonomous/deep-work. "
                "Before answering, build a todo/state plan and start executing with tools. "
                "Clarification Gate: do not ask non-blocking 'whether to continue' questions; "
                "use reasonable defaults and retrieve missing context with tools. Ask only for "
                "credentials, safety/permission boundaries, or irreversible choices. "
                "Completion Gate: do not final while there is a concrete tool-backed next step; "
                "final is allowed only after the task is verified, a real blocker is proven, "
                "or an explicit resource/permission limit is reached. "
                "If you are about to stop with a plan, continue executing instead.]"
            ),
        })

    return messages, decision


def log_skill_route_decision(
    decision: SkillRouteDecision,
    *,
    user_message: str,
    session_id: str | None = None,
    platform: str | None = None,
) -> None:
    """Append a JSONL route trace.  Never stores the full user message."""
    try:
        log_dir = Path(get_hermes_home()) / "logs" / "skill_routing"
        log_dir.mkdir(parents=True, exist_ok=True)
        path = log_dir / f"skill_routing_{datetime.now(timezone.utc).strftime('%Y-%m-%d')}.jsonl"
        digest = hashlib.sha256((user_message or "").encode("utf-8", "ignore")).hexdigest()[:16]
        record = {
            "ts": datetime.now(timezone.utc).isoformat(),
            "session_id": session_id or "",
            "platform": platform or "",
            "user_message_sha256_16": digest,
            "decision": decision.to_dict(),
        }
        with path.open("a", encoding="utf-8") as f:
            f.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")
    except Exception as exc:
        logger.debug("failed to write skill route trace: %s", exc)


def maybe_log_routing_failure(
    decision: SkillRouteDecision,
    *,
    user_message: str,
    session_id: str | None = None,
) -> None:
    """Record user-reported routing failures as regression candidates."""
    if not decision.classification.routing_failure_report:
        return
    try:
        base = Path(get_hermes_home()) / "logs" / "skill_routing"
        base.mkdir(parents=True, exist_ok=True)
        path = base / "routing_failures.jsonl"
        record = {
            "ts": datetime.now(timezone.utc).isoformat(),
            "session_id": session_id or "",
            "user_message_sha256_16": hashlib.sha256((user_message or "").encode("utf-8", "ignore")).hexdigest()[:16],
            "failure_type": "user_reported_skill_routing_failure",
            "expected_skills": decision.mandatory_skills or decision.candidate_skills,
            "actual_selected_skills": decision.selected_skills,
            "missing_skills": decision.missing_skills,
            "eval_candidate": True,
            "classification": asdict(decision.classification),
        }
        with path.open("a", encoding="utf-8") as f:
            f.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")
    except Exception as exc:
        logger.debug("failed to write routing failure record: %s", exc)
