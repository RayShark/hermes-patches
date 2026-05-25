import json
from pathlib import Path

from agent.skill_router import (
    SkillManifest,
    build_autoload_skill_messages,
    classify_task,
    load_skill_manifests,
    maybe_log_routing_failure,
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
    assert decision.gate_status["clarification_gate"] == "enabled"
    assert decision.gate_status["completion_gate"] == "enabled"


def test_day_long_research_and_patch_requires_deep_work():
    decision = route_skills(
        "用一天时间 deep work，调研市面类似方案，写出架构改造方案和代码 patch，不完美不准停。",
        AVAILABLE,
    )

    assert decision.classification.deep_work_required is True
    assert decision.classification.research_required is True
    assert decision.classification.duration_expectation == "long_horizon"
    assert "deep-work" in decision.mandatory_skills
    assert "long_horizon" in decision.bundle_expansion


def test_sleep_and_merge_prompt_is_long_horizon_autonomous():
    cls = classify_task("我睡觉了，你自己推进到能 merge。")

    assert cls.deep_work_required is True
    assert cls.autonomy_level == "fully_autonomous_until_done"
    assert cls.continuation_policy == "continue_until_verified"
    assert cls.test_required is True
    assert cls.verification_required is True


def test_simple_explainer_does_not_trigger_deep_work():
    decision = route_skills("简单解释一下 Hermes skills 是什么。", AVAILABLE)

    assert decision.classification.execution_depth == "quick_answer"
    assert "deep-work" not in decision.mandatory_skills
    assert "hermes-agent" in decision.mandatory_skills


def test_user_reported_missing_skill_becomes_eval_candidate(tmp_path, monkeypatch):
    monkeypatch.setenv("HERMES_HOME", str(tmp_path))
    decision = route_skills("你刚才应该加载 deep-work skill，为什么又没用 skill？", AVAILABLE)
    maybe_log_routing_failure(decision, user_message="你刚才应该加载 deep-work skill", session_id="s1")

    assert decision.classification.routing_failure_report is True
    assert "routing_failure_report" in decision.classification.evidence
    failure_log = tmp_path / "logs" / "skill_routing" / "routing_failures.jsonl"
    assert failure_log.exists()
    record = json.loads(failure_log.read_text(encoding="utf-8").strip().splitlines()[-1])
    assert record["eval_candidate"] is True
    assert record["converted_to_eval_case"] is False
    assert "user_message" not in record


def test_missing_mandatory_skill_is_reported():
    decision = route_skills("你花一晚上彻底修复 Hermes Agent skills，不准停。", {"hermes-agent"})

    assert "deep-work" in decision.mandatory_skills
    assert "deep-work" in decision.missing_skills
    assert decision.gate_status["pre_execution_gate"] == "missing_mandatory"


def test_manifest_required_when_and_dependencies_are_used():
    manifests = {
        "long-runner": SkillManifest(
            name="long-runner",
            required_when=["autonomy_level == fully_autonomous_until_done"],
            dependencies=["verify-skill"],
            load_policy="optional",
        )
    }
    decision = route_skills("拿一整天彻底修，不要问我，自己决定。", {"long-runner", "verify-skill", "deep-work"}, manifests=manifests)

    assert "long-runner" in decision.mandatory_skills
    assert "verify-skill" in decision.selected_skills
    assert decision.dependency_expansion["long-runner"] == ["verify-skill"]


def test_load_skill_manifests_reads_machine_metadata(tmp_path):
    skill_dir = tmp_path / "skills" / "deep-work"
    skill_dir.mkdir(parents=True)
    (skill_dir / "SKILL.md").write_text(
        "---\n"
        "name: deep-work\n"
        "description: Long horizon execution\n"
        "metadata:\n"
        "  hermes:\n"
        "    triggers: [deep work]\n"
        "    required_when:\n"
        "      - user_requested_deep_work == true\n"
        "    dependencies: [aegis-lite-completion-gate]\n"
        "    load_policy: mandatory_if_triggered\n"
        "---\n\nBody\n",
        encoding="utf-8",
    )
    manifests = load_skill_manifests({"/deep-work": {"name": "deep-work", "skill_dir": str(skill_dir)}})

    manifest = manifests["deep-work"]
    assert manifest.triggers == ["deep work"]
    assert "user_requested_deep_work == true" in manifest.required_when
    assert manifest.dependencies == ["aegis-lite-completion-gate"]
    assert manifest.load_policy == "mandatory_if_triggered"


def test_autoload_builds_skill_messages_without_model_decision(monkeypatch):
    fake_commands = {
        "/deep-work": {"name": "deep-work", "skill_dir": "/tmp/deep-work"},
        "/hermes-agent": {"name": "hermes-agent", "skill_dir": "/tmp/hermes-agent"},
    }

    import agent.skill_router as sr

    monkeypatch.setattr(sr, "_skill_command_map", lambda: fake_commands)
    monkeypatch.setattr(sr, "load_skill_manifests", lambda commands=None: {})

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
    assert "deep-work" in decision.loaded_skills
    assert "hermes-agent" in decision.loaded_skills
