"""Regression tests for Memory Write Pipeline auto-write gating."""

from typing import Any

from agent.memory_write_pipeline import CandidateFact, MemoryWritePipeline


class FakeGraphClient:
    def __init__(self):
        self.calls = []

    def write_candidate(self, candidate, classification, readback_queries):
        self.calls.append((candidate, classification, readback_queries))
        return {
            "written": True,
            "duplicate": False,
            "readback_ok": True,
            "uri": "core://auto-test",
            "node_uuid": "node-auto-test",
        }


def make_candidate(**overrides):
    data: dict[str, Any] = dict(
        subject="Project Alpha",
        predicate="decision",
        object_value="Prefer durable architecture over local hacks",
        importance=0.95,
        memory_type="decision",
        target_store="memory_graph",
        target_path="项目/Project Alpha/决策",
        evidence_quote="Use the durable architecture, not a local hack.",
        confidence=0.95,
        source_type="user_direct",
        namespace="telegram:u1",
    )
    data.update(overrides)
    return CandidateFact(**data)


def test_default_shadow_mode_never_writes_even_high_confidence():
    graph = FakeGraphClient()
    pipeline = MemoryWritePipeline(graph_client=graph, config={"mode": "shadow"})
    candidate = make_candidate()
    classification = pipeline.classify_write(candidate, namespace="telegram:u1")

    result = pipeline.write_and_verify(candidate, classification)

    assert result["auto_write_allowed"] is False
    assert result["written"] is False
    assert graph.calls == []


def test_limited_auto_writes_high_confidence_user_candidate_and_verifies_readback():
    graph = FakeGraphClient()
    pipeline = MemoryWritePipeline(
        graph_client=graph,
        config={
            "mode": "limited_auto",
            "auto_write_threshold": 0.85,
            "allowed_auto_types": ["decision"],
            "never_auto_write_to_core": True,
        },
    )
    candidate = make_candidate()
    classification = pipeline.classify_write(candidate, namespace="telegram:u1")

    result = pipeline.write_and_verify(candidate, classification)

    assert result["auto_write_allowed"] is True
    assert result["written"] is True
    assert result["readback_ok"] is True
    assert result["uri"] == "core://auto-test"
    assert len(graph.calls) == 1
    _, called_classification, readback_queries = graph.calls[0]
    assert called_classification["namespace"] == "telegram:u1"
    assert "Project Alpha decision" in readback_queries


def test_limited_auto_refuses_core_namespace_by_policy():
    graph = FakeGraphClient()
    pipeline = MemoryWritePipeline(
        graph_client=graph,
        config={
            "mode": "limited_auto",
            "auto_write_threshold": 0.85,
            "allowed_auto_types": ["decision"],
            "never_auto_write_to_core": True,
        },
    )
    candidate = make_candidate(namespace="")
    classification = pipeline.classify_write(candidate, namespace="")

    result = pipeline.write_and_verify(candidate, classification)

    assert result["auto_write_allowed"] is False
    assert result["written"] is False
    assert graph.calls == []


def test_user_correction_maps_to_explicit_correction_policy_type():
    graph = FakeGraphClient()
    pipeline = MemoryWritePipeline(
        graph_client=graph,
        config={
            "mode": "limited_auto",
            "auto_write_threshold": 0.85,
            "allowed_auto_types": ["explicit_correction"],
            "never_auto_write_to_core": True,
        },
    )
    candidate = make_candidate(
        source_type="user_correction",
        memory_type="user_fact",
        predicate="correction",
        object_value="Not version 1.2, version 1.3",
    )
    classification = pipeline.classify_write(candidate, namespace="telegram:u1")

    result = pipeline.write_and_verify(candidate, classification)

    assert result["auto_write_allowed"] is True
    assert result["written"] is True
    assert len(graph.calls) == 1
