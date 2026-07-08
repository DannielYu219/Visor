# Visor

AI 驱动的 iPad 设计工作室。用自然语言描述你的想法，AI 实时生成 HTML 设计稿并在画布中渲染预览。

> 基于 [Open Design](https://github.com/manalkaff/opendesign) 的理念进行 iOS 端实现。

---

## 功能

- **自然语言生成设计** — 描述你的需求（登录页、pitch deck、线框图等），AI 自动生成完整 HTML
- **实时画布预览** — WebKit 画布即时渲染，支持自定义尺寸与圆角
- **多文件管理** — session 内支持 HTML/CSS/JS 多文件，画布内切换预览
- **流式对话** — SSE 流式输出，Markdown 渲染，思考过程折叠，工具调用可视化
- **22 个模型可选** — 通过 OpenRouter 接入，涵盖旗舰 / Pro / 快速三档
- **费用控制** — 三段预算熔断（会话 $5 / 日 $20 / 月 $200），实时费用显示
- **多模态输入** — 支持图片附件，自动检测模型 vision 能力
- **全链路诊断** — 内置终端 / Token / 错误日志三标签调试面板
- **金融级安全** — API Key 存入 Keychain，AES-GCM-256 加密，审计日志只追加

---

## 架构

```
+--------------+--------------------+------------------+
|   侧边栏     |      对话区        |     画布         |
|  会话列表    |  消息流 + 输入栏   |  WKWebView 渲染  |
+--------------+--------------------+------------------+
```

用户输入 → SkillRouter 路由 → OpenRouter SSE 流式请求 → AgentRuntime 处理 delta / tool_call → 消息持久化 — 画布通知刷新

---

## 技术栈

| 维度 | 选型 |
|------|------|
| UI | SwiftUI (iOS 26+, iPad) |
| 持久化 | SwiftData |
| Web 渲染 | WKWebView |
| LLM 接入 | OpenRouter API (SSE) |
| 安全 | Keychain + CryptoKit AES-GCM-256 |
| 设计 | Liquid Glass + 自定义 DesignTokens |
| 并发 | Swift Concurrency (`async/await`, `AsyncStream`) |

零第三方 SDK，纯 Apple 原生框架。

---

## 运行

1. `git clone` 并 Xcode 打开 `Visor.xcodeproj`
2. 在设置页填入你的 [OpenRouter API Key](https://openrouter.ai/keys)
3. 选择目标设备（iPad，iOS 27.0+），Build & Run

---

## 安全

- API Key 存储在系统 Keychain，永不写入 UserDefaults 或日志
- 文件操作沙盒化，拒绝路径越权
- 预算三段熔断（预估 → 流式 → 完成），防止意外费用
- 401 自动清理 Keychain
- 审计日志只追加不可篡改

---

## 致谢

- [Open Design](https://github.com/manalkaff/opendesign) — 最初的设计理念参考
- [OpenRouter](https://openrouter.ai) — 统一模型接入服务
- iOS 26 [Liquid Glass](https://developer.apple.com/design) — 视觉设计语言
