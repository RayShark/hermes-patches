# Hermes Agent 社区补丁合集

> 一键安装，补全上游尚未合并的修复和增强。已合并的补丁会自动跳过。
> 
> **适配版本：v0.14.0 (v2026.5.16)**

## 装有什么用？

**🔒 隐私：多用户不再互相泄露**
session_search 和 memory 按用户隔离，中文搜索(CJK trigram)也已修复。
- **微信隔离**: iLink API 的 from_user_id 始终返回 bot 自己的 ID，导致微信对话会串到其他用户。补丁通过 `HINDSIGHT_SKIP_PLATFORMS` 环境变量禁用微信的 Hindsight 自动存储，并在 session_search 中隐藏微信会话。

**🧠 记忆元认知框架**
- session 启动时自动注入记忆库摘要（"我大概记得什么"）
- 查询扩展：用户消息自动扩展为更好的 hindsight 搜索查询
- 预检门控：工具调用前强制检查参数，拦截危险操作

## 适配状态

| 补丁 | v0.14.0 兼容 | 说明 |
|------|-------------|------|
| combined-final-v14.patch | ✅ | 完整补丁（元认知+微信隔离） |
| memory-metacognition-v14.patch | ✅ | 仅元认知框架 |
| weixin-isolation-v14.patch | ✅ | 仅微信隔离 |

## 一行命令安装

```bash
bash <(curl -sL https://raw.githubusercontent.com/Cyrene963/hermes-patches/main/install.sh)
```

## 手动安装

```bash
# 安装完整补丁
cd ~/.hermes/hermes-agent
git apply ~/.hermes/patches/combined-final-v14.patch

# 或分拆安装
git apply ~/.hermes/patches/memory-metacognition-v14.patch
git apply ~/.hermes/patches/weixin-isolation-v14.patch
```

## 补丁内容

### combined-final-v14.patch
- `agent/memory_metacognition.py` — 记忆元认知框架（查询扩展+预检门控+记忆索引）
- `agent/prompt_builder.py` — 添加 expand_recall_queries 和 build_memory_index_block
- `run_agent.py` — 注入记忆索引和预检门控
- `plugins/memory/hindsight/__init__.py` — HINDSIGHT_SKIP_PLATFORMS 环境变量
- `tools/session_search_tool.py` — 微信会话隔离
- `tests/tools/test_session_search.py` — 测试更新

### memory-metacognition-v14.patch
仅包含元认知框架修改（prompt_builder + run_agent）

### weixin-isolation-v14.patch
仅包含微信隔离修改（hindsight + session_search + test）

## 卸载

```bash
cd ~/.hermes/hermes-agent
git checkout -- agent/prompt_builder.py run_agent.py plugins/memory/hindsight/__init__.py tools/session_search_tool.py tests/tools/test_session_search.py
rm agent/memory_metacognition.py
```

## 注意事项

- 补丁默认值策略：上游 PR 默认 OFF，一键补丁默认 ON
- hermes update 后需要重新打补丁
- 所有补丁只修改必要的文件，不做大范围重构
