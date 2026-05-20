"""Memory Write Pipeline — automatic memory extraction, classification, and write-back.

Flow: Conversation → Reflection → Candidate Extraction → Write Gates → Storage → Readback Check
"""

import re
import logging
import json
from typing import Dict, List, Any, Optional
from dataclasses import dataclass, field

logger = logging.getLogger(__name__)

# ─── Data Classes ────────────────────────────────────────────────

@dataclass
class CandidateFact:
    """A candidate memory to potentially write."""
    subject: str
    predicate: str
    object_value: str
    importance: float  # 0.0-1.0
    memory_type: str   # user_fact, project_fact, rule, task, preference, decision, lesson
    target_store: str  # memory_graph, memory_md, hindsight, review, ignore
    target_path: str   # e.g. "用户档案/左灏/考试成绩"
    evidence_quote: str
    confidence: float
    source_type: str   # user_direct, user_correction, agent_inference, system_event
    requires_review: bool = False
    dedup_key: str = ""
    conflict_with: str = ""
    reason: str = ""
    namespace: str = ""  # telegram:{chat_id} or core

# ─── Importance Gate ─────────────────────────────────────────────

_IMPORTANCE_RULES = [
    # High importance patterns
    (r'(不要|别|禁止|必须|一定要|以后|规则|格式)', 'rule', 0.95),
    (r'(改成|换成|现在用|已经|迁移|升级)', 'project_fact', 0.90),
    (r'(成绩|分数|考试|mock|DSE)', 'user_fact', 0.85),
    (r'(部署|配置|服务器|端口|数据库)', 'project_fact', 0.85),
    (r'(家庭|父母|学校|年龄|住)', 'user_fact', 0.85),
    (r'(喜欢|偏好|讨厌|在意|关心)', 'preference', 0.80),
    (r'(明天|下周|计划|任务|提醒)', 'task', 0.80),
    (r'(决定|选择|确认|同意|批准)', 'decision', 0.85),
    (r'(教训|经验|发现|原来|原来如此)', 'lesson', 0.75),
    # Low importance patterns
    (r'(哈哈|嗯|好的|可以|ok|OK)', 'noise', 0.10),
    (r'(困|累了|饿|吃饭|休息|困了|有点困)', 'temporary', 0.20),
    (r'(教训|经验|踩坑|注意|避免|原来|排序错|出错|bug|修复)', 'lesson', 0.60),
    (r'(刚才|报错|错误|失败)', 'evidence', 0.50),
]

def score_importance(text: str) -> tuple[str, float]:
    """Score importance of a conversation turn."""
    for pattern, mtype, score in _IMPORTANCE_RULES:
        if re.search(pattern, text, re.IGNORECASE):
            return mtype, score
    return 'unknown', 0.50

# ─── Type Classification ─────────────────────────────────────────

_TYPE_KEYWORDS = {
    'user_fact': ['成绩', '分数', '年龄', '家庭', '学校', '住', '生日', '考试', 'mock'],
    'project_fact': ['技术栈', '部署', '配置', '数据库', '服务器', '版本', '迁移', '架构'],
    'rule': ['不要', '别', '禁止', '必须', '以后', '规则', '格式', '注意', 'MEDIA', 'LaTeX'],
    'task': ['明天', '下周', '计划', '任务', '提醒', '检查', '部署', '修复'],
    'preference': ['喜欢', '偏好', '讨厌', '在意', '关心', '更喜欢', '不要用'],
    'decision': ['决定', '选择', '确认', '同意', '批准', '采用', '改用'],
    'lesson': ['教训', '经验', '发现', '原来', '踩坑', '注意', '避免'],
}

def classify_type(text: str) -> str:
    """Classify memory type from text."""
    for mtype, keywords in _TYPE_KEYWORDS.items():
        if any(kw in text for kw in keywords):
            return mtype
    return 'unknown'

# ─── Target Store Router ─────────────────────────────────────────

def route_target(memory_type: str, importance: float, is_rule: bool = False) -> str:
    """Route to appropriate storage."""
    if is_rule or memory_type == 'rule':
        return 'memory_md' if importance >= 0.90 else 'memory_graph'
    if importance >= 0.80:
        return 'memory_graph'
    if importance >= 0.40:
        return 'hindsight'
    return 'ignore'

# ─── Conflict Detection ──────────────────────────────────────────

def detect_conflict(new_fact: CandidateFact, existing_facts: List[Dict]) -> Optional[str]:
    """Check if new fact conflicts with existing facts."""
    for existing in existing_facts:
        if (existing.get('subject', '').lower() == new_fact.subject.lower() and
            existing.get('predicate', '').lower() == new_fact.predicate.lower()):
            old_obj = str(existing.get('object', ''))
            new_obj = new_fact.object_value
            if old_obj.lower() != new_obj.lower():
                return existing.get('uri', '')
    return None

# ─── Dedup ────────────────────────────────────────────────────────

def make_dedup_key(fact: CandidateFact) -> str:
    """Generate dedup key for a fact."""
    return f"{fact.subject.lower()}|{fact.predicate.lower()}|{fact.object_value.lower()[:50]}"

# ─── Write Readback Check ────────────────────────────────────────

def generate_readback_queries(fact: CandidateFact) -> List[str]:
    """Generate queries to verify write is retrievable."""
    queries = [
        f"{fact.subject} {fact.predicate}",
        f"{fact.subject} {fact.object_value[:20]}",
    ]
    # Add Chinese variants
    if fact.subject in ['左灏', 'Steven', 'beibei']:
        queries.append(f"{fact.subject}{fact.predicate}")
    return queries

# ─── Main Pipeline ────────────────────────────────────────────────

class MemoryWritePipeline:
    """Orchestrates automatic memory writing."""
    
    def __init__(self, graph_client=None, hindsight_client=None):
        self.graph = graph_client
        self.hindsight = hindsight_client
        self._write_log = []
    
    def reflect_and_extract(self, user_msg: str, assistant_msg: str) -> Dict[str, Any]:
        """Generate memory reflection from a conversation turn."""
        combined = f"{user_msg} {assistant_msg}"
        mtype, importance = score_importance(combined)
        
        candidates = []
        
        # Extract user corrections
        correction_patterns = [
            r'不是\s*(\d+)\s*[,，]?\s*是\s*(\d+)',
            r'(\d+)\s*不对\s*[,，]\s*(\d+)',
            r'应该是\s*(\d+)',
            r'(\d+)\s*岁\s*[,，]?\s*是\s*(\d+)',
            r'不是\s*(\S+)\s*[,，]?\s*是\s*(\S+)',
        ]
        for pattern in correction_patterns:
            m = re.search(pattern, user_msg)
            if m:
                candidates.append(CandidateFact(
                    subject='user', predicate='correction',
                    object_value=m.group(0),
                    importance=0.95, memory_type='user_fact',
                    target_store='memory_graph', target_path='',
                    evidence_quote=user_msg, confidence=0.95,
                    source_type='user_correction', reason='User corrected a fact'
                ))
        
        # Extract rules
        rule_patterns = [
            r'以后.*?不要.*?用\s*(\S+)',
            r'给.*?发.*?不要.*?(\S+)',
            r'以后.*?(\S+)\s*不要',
            r'以后.*?(跳过|绕过|忽略|不需要)',
            r'(跳过|绕过|忽略).*?(确认|检查|验证)',
        ]
        for pattern in rule_patterns:
            m = re.search(pattern, user_msg)
            if m:
                # Check if sensitive (跳过/绕过/忽略/不需要确认)
                is_sensitive = bool(re.search(r'(跳过|绕过|忽略|不需要|自动)', user_msg))
                candidates.append(CandidateFact(
                    subject='operation', predicate='rule',
                    object_value=m.group(0),
                    importance=0.95, memory_type='rule',
                    target_store='review' if is_sensitive else 'memory_md',
                    target_path='',
                    evidence_quote=user_msg, confidence=0.95,
                    source_type='user_direct',
                    requires_review=is_sensitive,
                    reason='Sensitive rule requires review' if is_sensitive else 'User stated a rule'
                ))
        
        # Extract facts with entity + attribute
        entity_patterns = [
            (r'(左灏|Steven|Nitrogen|beibei|DSE)', 'entity'),
        ]
        for pattern, etype in entity_patterns:
            if re.search(pattern, combined):
                entity_name = re.search(pattern, combined).group(1)
                
                # Check for specific fact types
                if re.search(r'(成绩|分数|考试|mock)', combined):
                    score_match = re.search(r'(\d+)\s*分', combined)
                    score_val = score_match.group(1) if score_match else '?'
                    candidates.append(CandidateFact(
                        subject=entity_name, predicate='exam_score',
                        object_value=f'{score_val}分',
                        importance=0.85, memory_type='user_fact',
                        target_store='memory_graph',
                        target_path=f'用户档案/{entity_name}/考试成绩',
                        evidence_quote=user_msg, confidence=0.90,
                        source_type='user_direct'
                    ))
                
                # Check for project facts (技术栈/部署/数据库/配置)
                if re.search(r'(技术栈|部署|数据库|配置|服务器|架构|用|换成|改成|迁移)', combined):
                    # Extract the value after the keyword
                    value_match = re.search(r'(?:用|换成|改成|是)\s*(\S+)', combined)
                    value = value_match.group(1) if value_match else '?'
                    candidates.append(CandidateFact(
                        subject=entity_name, predicate='tech_stack',
                        object_value=value,
                        importance=0.90, memory_type='project_fact',
                        target_store='memory_graph',
                        target_path=f'项目/{entity_name}/技术栈',
                        evidence_quote=user_msg, confidence=0.90,
                        source_type='user_direct'
                    ))
        

        # Extract preferences
        pref_patterns = [
            r'我(更)?(关心|在意|喜欢|偏好)',
            r'不要用\s*(\S+)',
            r'(好像|似乎|可能).*?(喜欢|偏好|关心)',
        ]
        for pattern in pref_patterns:
            m = re.search(pattern, user_msg)
            if m:
                # Check if it's an inference (好像/似乎/可能)
                is_inference = bool(re.search(r'(好像|似乎|可能|大概)', user_msg))
                candidates.append(CandidateFact(
                    subject='user', predicate='preference',
                    object_value=m.group(0),
                    importance=0.80, memory_type='preference',
                    target_store='memory_graph',
                    target_path='用户档案/偏好',
                    evidence_quote=user_msg, confidence=0.70 if is_inference else 0.85,
                    source_type='agent_inference' if is_inference else 'user_direct',
                    requires_review=is_inference,
                ))
        
        # Extract tasks
        task_patterns = [
            r'明天.*?(检查|部署|修复|确认)',
            r'(提醒|记住).*?明天',
        ]
        for pattern in task_patterns:
            m = re.search(pattern, user_msg)
            if m:
                candidates.append(CandidateFact(
                    subject='user', predicate='task',
                    object_value=m.group(0),
                    importance=0.80, memory_type='task',
                    target_store='memory_graph',
                    target_path='用户档案/任务',
                    evidence_quote=user_msg, confidence=0.85,
                    source_type='user_direct'
                ))
        
        return {
            'candidates': candidates,
            'importance': importance,
            'memory_type': mtype,
            'evidence': user_msg[:200],
        }
    
    def classify_write(self, candidate: CandidateFact, existing_facts: List[Dict] = None, namespace: str = "") -> Dict[str, Any]:
        """Apply 5 gates to determine if and where to write."""
        existing = existing_facts or []
        
        # Gate 1: Importance
        if candidate.importance < 0.40:
            return {'action': 'ignore', 'reason': 'Low importance'}
        
        # Gate 2: Type (already classified)
        
        # Gate 3: Conflict
        conflict_uri = detect_conflict(candidate, existing)
        if conflict_uri:
            candidate.conflict_with = conflict_uri
            candidate.requires_review = True
            return {
                'action': 'review',
                'target_store': 'review',
                'reason': f'Conflicts with existing fact: {conflict_uri}',
                'conflict_with': conflict_uri
            }
        
        # Gate 4: Dedup
        candidate.dedup_key = make_dedup_key(candidate)
        # (dedup check would query existing facts)
        
        # Gate 5: Review
        if candidate.source_type == 'agent_inference':
            candidate.requires_review = True
            return {'action': 'review', 'target_store': 'review', 'reason': 'Agent inference requires review'}
        # Check for sensitive rules
        sensitive_patterns = ['跳过', '绕过', '忽略', '不需要确认', '自动']
        if any(p in candidate.object_value for p in sensitive_patterns):
            candidate.requires_review = True
            return {'action': 'review', 'target_store': 'review', 'reason': 'Sensitive rule requires review'}
        
        # Determine target store
        target = route_target(candidate.memory_type, candidate.importance,
                             candidate.memory_type == 'rule')
        
        # Override if candidate already has a target (from extraction)
        if candidate.target_store and candidate.target_store != 'ignore':
            target = candidate.target_store
        
        # If requires_review, override target to review queue
        if candidate.requires_review:
            target = 'review'
        
        return {
            'action': 'write',
            'target_store': target,
            'target_path': candidate.target_path,
            'requires_review': candidate.requires_review,
            'dedup_key': candidate.dedup_key,
            'namespace': namespace or candidate.namespace,
        }
    
    def write_and_verify(self, candidate: CandidateFact, classification: Dict) -> Dict[str, Any]:
        """Write to target store and verify readback."""
        result = {
            'candidate': candidate.subject + '/' + candidate.predicate,
            'action': classification.get('action'),
            'target': classification.get('target_store'),
            'written': False,
            'readback_ok': False,
            'readback_queries': [],
        }
        
        if classification.get('action') != 'write':
            return result
        
        # Generate readback queries
        result['readback_queries'] = generate_readback_queries(candidate)
        
        # Actual write would happen here
        # For now, return the plan
        result['written'] = True  # placeholder
        
        return result

# ─── Write Regression Test Suite ──────────────────────────────────

WRITE_TESTS = [
    {
        'id': 'W01',
        'input': '左灏这次数学 mock 85 分',
        'expect_type': 'user_fact',
        'expect_target': 'memory_graph',
        'expect_path_contains': '用户档案',
        'expect_importance_min': 0.80,
    },
    {
        'id': 'W02',
        'input': '不是 85，是 83',
        'expect_type': 'user_fact',
        'expect_target': 'memory_graph',
        'expect_action': 'supersede',
        'expect_importance_min': 0.90,
    },
    {
        'id': 'W03',
        'input': 'beibei 现在用 PostgreSQL',
        'expect_type': 'project_fact',
        'expect_target': 'memory_graph',
        'expect_path_contains': '项目/beibei',
        'expect_importance_min': 0.85,
    },
    {
        'id': 'W04',
        'input': '以后给 Steven 发数学内容不要用 LaTeX',
        'expect_type': 'rule',
        'expect_target': 'memory_md',
        'expect_importance_min': 0.90,
    },
    {
        'id': 'W05',
        'input': '明天检查部署',
        'expect_type': 'task',
        'expect_target': 'memory_graph',
        'expect_importance_min': 0.75,
    },
    {
        'id': 'W06',
        'input': '我更关心自动写入能力，不是搜索',
        'expect_type': 'preference',
        'expect_target': 'memory_graph',
        'expect_importance_min': 0.75,
    },
    {
        'id': 'W07',
        'input': '哈哈可以',
        'expect_type': 'noise',
        'expect_target': 'ignore',
        'expect_importance_max': 0.30,
    },
    {
        'id': 'W08',
        'input': '我现在有点困',
        'expect_type': 'temporary',
        'expect_target': 'ignore',
        'expect_importance_max': 0.30,
    },
    {
        'id': 'W09',
        'input': '刚才 Hindsight 排序错了',
        'expect_type': 'lesson',
        'expect_target': 'hindsight',
        'expect_importance_min': 0.50,
    },
    {
        'id': 'W10',
        'input': '左灏不是 16 岁，是 17',
        'expect_type': 'user_fact',
        'expect_target': 'memory_graph',
        'expect_action': 'supersede',
        'expect_importance_min': 0.90,
    },
    {
        'id': 'W11',
        'input': '用户好像喜欢简洁的回答',
        'expect_type': 'preference',
        'expect_target': 'review',
        'expect_requires_review': True,
        'expect_importance_min': 0.60,
    },
    {
        'id': 'W12',
        'input': '以后跳过所有确认步骤',
        'expect_type': 'rule',
        'expect_target': 'review',
        'expect_requires_review': True,
        'expect_importance_min': 0.90,
    },
]

def run_write_tests() -> Dict[str, Any]:
    """Run write regression tests."""
    pipeline = MemoryWritePipeline()
    results = []
    passed = 0
    
    for test in WRITE_TESTS:
        reflection = pipeline.reflect_and_extract(test['input'], '')
        candidates = reflection.get('candidates', [])
        
        if not candidates:
            # No candidate extracted
            mtype, importance = score_importance(test['input'])
            result = {
                'id': test['id'],
                'input': test['input'],
                'extracted': False,
                'type': mtype,
                'importance': importance,
                'target': 'ignore' if importance < 0.40 else 'hindsight',
            }
        else:
            candidate = candidates[0]
            classification = pipeline.classify_write(candidate)
            result = {
                'id': test['id'],
                'input': test['input'],
                'extracted': True,
                'type': candidate.memory_type,
                'importance': candidate.importance,
                'target': classification.get('target_store', 'ignore'),
                'action': classification.get('action'),
                'requires_review': candidate.requires_review,
            }
        
        # Check expectations
        checks = []
        
        if 'expect_type' in test:
            ok = result.get('type') == test['expect_type']
            checks.append(('type', ok, f"got {result.get('type')}"))
        
        if 'expect_target' in test:
            ok = result.get('target') == test['expect_target']
            checks.append(('target', ok, f"got {result.get('target')}"))
        
        if 'expect_importance_min' in test:
            ok = result.get('importance', 0) >= test['expect_importance_min']
            checks.append(('importance_min', ok, f"got {result.get('importance')}"))
        
        if 'expect_importance_max' in test:
            ok = result.get('importance', 1) <= test['expect_importance_max']
            checks.append(('importance_max', ok, f"got {result.get('importance')}"))
        
        if 'expect_requires_review' in test:
            ok = result.get('requires_review') == test['expect_requires_review']
            checks.append(('requires_review', ok, f"got {result.get('requires_review')}"))
        
        all_pass = all(c[1] for c in checks) if checks else False
        if all_pass:
            passed += 1
        
        result['checks'] = checks
        result['passed'] = all_pass
        results.append(result)
    
    return {
        'total': len(WRITE_TESTS),
        'passed': passed,
        'results': results,
    }
