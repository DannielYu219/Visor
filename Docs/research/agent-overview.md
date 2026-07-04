# Agent 资料与实现方案调研

> Visor iOS 项目 · 2026-07-03 · 与 `security-policy.md` / `open-design-spec.md` 配套

---

## 1. 范式对比

### 1.1 ReAct（Reason + Act）
- **代表**：早期 AutoGPT、BabyAGI
- **循环**：`Thought → Action → Observation` 文本交替
- **优点**：可解释性强，适合长链推理
- **缺点**：依赖模型强 CoT 能力；token 消耗高；不适合移动端弱网

### 1.2 Function Calling / Tool Use
- **代表**：OpenAI Tools、Anthropic Tool Use、Gemini Function Calling
- **协议**：模型输出结构化 `tool_calls` JSON，宿主执行后回填 `tool` 消息
- **优点**：低 token 成本、确定性强、易流式增量
- **缺点**：模型必须支持；调用顺序由模型决定

### 1.3 CLI-style Agent（项目历史范式）
- **代表**：Visor 上一会话的 AgentRunner
- **协议**：模型在文本流中输出 `<visor-cli>WRITE/PATCH/COMMENT/THINK/DONE</visor-cli>` 块
- **优点**：与任意文本生成模型兼容；产物可审计
- **缺点**：解析复杂（holdback 防 `<visor` 漏出）；O(n²) 风险

### 1.4 本项目结论
**采用 Function Calling + CLI 块双协议共存**：
- **主路径**：OpenRouter `tools` 字段（OpenAI 兼容）
- **保留路径**：`<visor-cli>` 块（兼容项目历史，可禁用）

---

## 2. OpenRouter 工具调用规范

### 2.1 请求体（OpenAI 兼容）
```json
{
  "model": "openai/gpt-5.6-pro",
  "messages": [...],
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "calculator",
        "description": "执行四则运算（无副作用）",
        "parameters": {
          "type": "object",
          "properties": {
            "expression": {"type": "string"}
          },
          "required": ["expression"]
        }
      }
    }
  ],
  "tool_choice": "auto",
  "stream": true
}
```

### 2.2 响应（非流式）
```json
{
  "choices": [{
    "finish_reason": "tool_calls",
    "message": {
      "role": "assistant",
      "content": null,
      "tool_calls": [{
        "id": "call_abc123",
        "type": "function",
        "function": {
          "name": "calculator",
          "arguments": "{\"expression\": \"2+2\"}"
        }
      }]
    }
  }]
}
```

### 2.3 流式增量
- `delta.role` / `delta.content` / `delta.tool_calls`
- `tool_calls` 数组分片到达：先给 `id` + `type`，再补 `function.name` + `function.arguments`（增量字符串）
- 客户端需按 `index` 聚合完整后才能 dispatch

### 2.4 多工具并行
- `parallel_tool_calls: true`（OpenRouter 默认）
- 一次响应可包含多个 `tool_calls`，项目内**顺序执行**（避免并发副作用）
- 执行结果依次回填，触发下一轮

### 2.5 必需头部
- `Authorization: Bearer <OR_KEY>`
- `HTTP-Referer: https://visor.app`（OpenRouter 统计需要）
- `X-Title: Visor iOS`
- `Content-Type: application/json`

---

## 3. MCP（Model Context Protocol）定位

### 3.1 角色
- **目标**：标准化"模型 ↔ 工具/数据源"协议
- **发起方**：Anthropic，2024-11 开源
- **现状**：OpenAI / Google 兼容采用

### 3.2 传输
| 传输 | 场景 | iOS 适配 |
|------|------|----------|
| stdio | 本地桌面进程 | ❌ 沙箱限制 |
| HTTP+SSE | 远程/容器化 | ✅ 计划内 |
| Streamable HTTP | 新版（2025） | ✅ 留扩展 |

### 3.3 JSON-RPC 2.0 消息
```json
// Request
{"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}}
// Response
{"jsonrpc": "2.0", "id": 1, "result": {"tools": [...]}}
// Notification (SSE)
{"jsonrpc": "2.0", "method": "notifications/tools/list_changed"}
```

### 3.4 必实现方法
- `initialize` → 握手（协议版本、能力）
- `tools/list` → 列举工具 + JSON Schema
- `tools/call` → 调用工具 + 返回结果
- `notifications/initialized` → 客户端就绪

---

## 4. GPT-5.6 Pro 兼容性策略

### 4.1 风险
- 当前为假设模型（2026-07 未公开）
- OpenRouter 上线时 schema 可能微调

### 4.2 策略
1. **不绑定专有字段**：仅依赖 OpenAI Chat Completions 公共 schema
2. **Tool 描述本地化**：用英文 tool name + 中文 description（双 schema 兜底）
3. **失败降级**：模型不可用时自动切换 `anthropic/claude-sonnet-4.5`
4. **版本探测**：`OpenRouterModels.probe()` 启动时 GET `/api/v1/models` 校验 ID

### 4.3 抽象层
- `ModelProvider` 协议屏蔽具体模型差异
- `OpenRouterClient` 唯一实现

---

## 5. 总结

| 决策 | 选择 | 理由 |
|------|------|------|
| 工具协议 | OpenAI Function Calling | OpenRouter 标准、跨模型 |
| 兼容历史 | 保留 CLI 块 | 项目记忆硬约束 |
| MCP 传输 | HTTP + SSE | iOS 沙箱 |
| 工具执行 | 顺序（非并发） | 避免副作用 |
| 流式聚合 | 按 `tool_calls[].index` 拼装 | OpenRouter 协议 |
| 模型降级 | 多 model 备选 + 启动探测 | 高可用 |

---

## 6. 引用

- OpenRouter API 文档：https://openrouter.ai/docs
- OpenAI Function Calling：https://platform.openai.com/docs/guides/function-calling
- MCP 协议：https://modelcontextprotocol.io
- Anthropic Tool Use：https://docs.anthropic.com/en/docs/agents-and-tools/tool-use/overview
