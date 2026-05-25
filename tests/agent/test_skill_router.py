from pathlib import Path

from agent.skill_router import (
    build_autoload_skill_messages,
    classify_task,
    route_skills,
)


AVAILABLE = {
    "deep-work",
    "hermes-agent",
    "memory-management",
    "hermes-memory-os",
    "universal-solutions-for-prs",
    "aegis-lite-completion-gate",
}


def test_long_horizon_hermes_fix_requires_deep_work_and_hermes_skills():
    decision = route_skills(
        "你花一晚上把 Hermes skill 选择失败彻底修好，不要问我是否继续。",
        AVAILABLE,
    )

    assert decision.classification.execution_depth == "deep_work"
    assert decision.classification.autonomy_level == "fully_autonomous_until_done"
    assert decision.classification.continuation_policy == "continue_until_verified"
    assert "deep-work" in decision.mandatory_skills
    assert "hermes-agent" in decision.mandatory_skills
    assert "deep-work" in decision.selected_skills
    assert "hermes-agent" in decision.selected_skills


def test_day_long_research_and_patch_requires_deep_work():
    decision = route_skills(
        "用一天时间 deep work，调研市面类似方案，写出架构改造方案和代码 patch，不完美不准停。",
        AVAILABLE,
    )

    assert decision.classification.deep_work_required is True
    assert decision.classification.duration_expectation == "long_horizon"
    assert "deep-work" in decision.mandatory_skills


def test_sleep_and_merge_prompt_is_long_horizon_autonomous():
    cls = classify_task("我睡觉了，你自己推进到能 merge。")

    assert cls.deep_work_required is True
    assert cls.autonomy_level == "fully_autonomous_until_done"
    assert cls.continuation_policy == "continue_until_verified"


def test_simple_explainer_does_not_trigger_deep_work():
    decision = route_skills("简单解释一下 Hermes skills 是什么。", AVAILABLE)

    assert decision.classification.execution_depth == "quick_answer"
    assert "deep-work" not in decision.mandatory_skills
    assert "hermes-agent" in decision.mandatory_skills


def test_user_reported_missing_skill_becomes_eval_candidate():
    decision = route_skills("你刚才应该加载 deep-work skill，为什么又没用 skill？", AVAILABLE)

    assert decision.classification.routing_failure_report is True
    assert "routing_failure_report" in decision.classification.evidence


def test_missing_mandatory_skill_is_reported():
    decision = route_skills("你花一晚上彻底修复 Hermes Agent skills，不准停。", {"hermes-agent"})

    assert "deep-work" in decision.mandatory_skills
    assert "deep-work" in decision.missing_skills


def test_autoload_builds_skill_messages_without_model_decision(monkeypatch):
    fake_commands = {
        "/deep-work": {"name": "deep-work", "skill_dir": "/tmp/deep-work"},
        "/hermes-agent": {"name": "hermes-agent", "skill_dir": "/tmp/hermes-agent"},
    }

    import agent.skill_router as sr

    monkeypatch.setattr(sr, "_skill_command_map", lambda: fake_commands)

    def fake_build(cmd_key, user_instruction="", task_id=None, runtime_note=""):
        return f"LOADED {cmd_key} :: {runtime_note}"

    import agent.skill_commands as sc

    monkeypatch.setattr(sc, "build_skill_invocation_message", fake_build)

    messages, decision = build_autoload_skill_messages(
        "你花一晚上彻底修复 Hermes skill discovery，不要问我要不要继续。",
        task_id="t1",
    )

    assert "deep-work" in decision.mandatory_skills
    assert "hermes-agent" in decision.mandatory_skills
    assert len(messages) == 3
    assert messages[0]["role"] == "user"
    assert "LOADED" in messages[0]["content"]
    assert "Automatically loaded by Hermes Skill Router" in messages[0]["content"]
    assert "Completion Gate" in messages[-1]["content"]
