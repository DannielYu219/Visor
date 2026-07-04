# 安全策略与风险评估

> Visor iOS 项目 · 2026-07-03 · 配套 `agent-overview.md` / `open-design-spec.md`
> 基线：**金融级**。所有红线必须通过验收。

---

## 1. 威胁模型

### 1.1 密钥泄露（Key Disclosure）
- **场景 A**：API Key 写 UserDefaults，被备份/越狱读取
- **场景 B**：Key 出现在 `print()` / `os_log` 输出
- **场景 C**：URL Query 携带（`?api_key=xxx`），进入网络代理日志
- **场景 D**：崩溃 dump 文件残留

### 1.2 费用失控（Cost Runaway）
- **场景 A**：模型异常输出超大 token 循环
- **场景 B**：MCP 工具被诱导递归调用
- **场景 C**：月度无上限 → 500 美元模型单日烧光
- **场景 D**：网络重试未限流

### 1.3 提示注入（Prompt Injection）
- **场景 A**：用户输入中嵌入"忽略之前指令"
- **场景 B**：MCP 工具返回值含恶意指令
- **场景 C**：网页搜索结果含隐藏 prompt
- **场景 D**：`<visor-cli>` 块伪装

### 1.4 工具滥用（Tool Abuse）
- **场景 A**：调用未授权 shell
- **场景 B**：写入敏感路径（`/etc`、`~/Library/Keychains`）
- **场景 C**：网络外发（HTTP/HTTPS 到非 allowlist 域名）

### 1.5 数据外泄（Data Exfiltration）
- **场景 A**：用户消息上传到非 OpenRouter 域
- **场景 B**：Analytics SDK 默认开启
- **场景 C**：崩溃报告含消息内容

---

## 2. 缓解矩阵

| 威胁 | 缓解措施 | 落地模块 | 验证 |
|------|----------|----------|------|
| 密钥 UserDefaults | Keychain `kSecAttrAccessibleAfterFirstUnlock` | `KeychainStore` | 静态扫描 UserDefaults 写入 |
| 密钥 日志 | `print` 过滤 + URL 剥离 + 自定义 `OSLog` 签名 | 全局 | grep Key 前缀 |
| 密钥 URL | URLQueryItem 黑名单 + URLSessionConfiguration 钩子 | `OpenRouterClient` | 单元测试 |
| 密钥 dump | 关闭 `applicationSupportsHandoff` | `Info.plist` | 配置检查 |
| 费用异常 | `BudgetGuard` 三段熔断（预估/流式/完成） | `BudgetGuard` | 模拟超支 |
| 费用 MCP | 工具沙箱（输入/输出长度上限） | `ToolSandbox` | 单元测试 |
| 注入 A/B | `PromptInjectionGuard` 关键词黑名单 + 工具输出包裹 | `PromptInjectionGuard` | 测试集 ≥ 95% |
| 注入 C | 工具结果 `stripDangerousPatterns()` | 同上 | 同上 |
| 注入 D | `CommandRunner` holdback + schema 校验 | `CommandRunner` | 单元测试 |
| 工具 shell | `ConfirmationPolicy` 黑名单 + 用户确认 | `ConfirmationPolicy` | 配置默认拒绝 |
| 工具 fs | 同上 + 沙盒路径限制 | 同上 | 同上 |
| 数据外发 | URL allowlist（仅 `openrouter.ai`） | `URLSessionDelegate` | DNS 解析测试 |
| Analytics | 关闭所有第三方 SDK | `Info.plist` | 配置检查 |
| 崩溃报告 | 不接入 Crashlytics；仅本地 `os_log` | 工程配置 | 配置检查 |

---

## 3. Keychain 设计

### 3.1 Item
```swift
// KeychainStore.swift
let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "com.lyrastudio.Visor",
    kSecAttrAccount as String: "openrouter_api_key",
    kSecValueData as String: keyData,
    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
]
```

### 3.2 约束
- 永远 `kSecAttrAccessibleAfterFirstUnlock`（不备份到 iCloud）
- 不存明文到 `UserDefaults` / `FileManager`
- 读取失败 → 弹窗引导重新输入，不抛崩溃

---

## 4. CryptoBox 设计

### 4.1 用途
- 加密 SwiftData 中敏感字段（如未来扩展 `EncryptedNote`）
- 默认**不**加密 Keychain 已有数据（Keychain 本身已加密）

### 4.2 算法
- AES-GCM-256（CryptoKit）
- 密钥派生：设备 + 用户绑定（PBKDF2 100k iterations）
- 临时密钥：内存中，进程结束即失效

---

## 5. BudgetGuard 设计

### 5.1 三段熔断
| 阶段 | 触发 | 行为 |
|------|------|------|
| 预估 | 请求前 | 估算 cost + 当前 spent；超限直接拒绝 |
| 流式 | 每 80ms 批 | 累计 `delta.usage`；超限 cancel + 标记 |
| 完成 | 响应结束 | 实际 cost 累加；超限熔断 + 写审计 |

### 5.2 周期
- `session`：单次会话
- `daily`：自然日（按用户时区）
- `monthly`：自然月

### 5.3 默认值
| 周期 | 默认 USD | 0 元警告 | 100% 熔断 |
|------|---------|----------|-----------|
| session | 5.00 | 80% | 100% |
| daily | 20.00 | 80% | 100% |
| monthly | 200.00 | 80% | 100% |

---

## 6. PromptInjectionGuard 设计

### 6.1 黑名单关键词
- 英文：`"ignore previous instructions"`、`"disregard the system prompt"`、`"act as"`、`"you are now"`
- 中文：`"忽略之前的指令"`、`"无视系统提示"`、`"扮演"`

### 6.2 工具输出包裹
```swift
"<<<tool_result_untrusted>>>\n{original}\n<<<end_tool_result>>>"
```
模型侧被提示工具内容不可信。

### 6.3 行为
- 检测到 → 标记 `risk=high` + 写入 `AuditLogEntity`
- 不阻断对话（避免误伤），但 UI 显示 ⚠️ 标记
- 连续 3 次触发 → 弹窗警告用户

### 6.4 测试集
- `Docs/research/security-policy.md` 附录
- 至少 20 条样本（注入 / 非注入各半）
- 拦截率目标 ≥ 95%

---

## 7. ConfirmationPolicy 设计

### 7.1 风险等级
| 等级 | 工具 | 默认 |
|------|------|------|
| low | `calculator` | 自动执行 |
| medium | `web_search`, `artifact_writer` | 弹确认（首次可记忆） |
| high | `shell_exec`, `file_system` | **默认禁止** |
| forbidden | — | 拒绝 |

### 7.2 状态机
```
[Created] → [Auto-Execute] → [Done]
              ↓ (medium)
            [Pending Confirmation] → [Confirmed] → [Done]
                                  → [Denied] → [Cancelled]
```

### 7.3 存储
- 用户决策（deny once / deny always / allow once / allow always）持久化到 `BudgetEntity` 旁边的 `PolicyEntity`

---

## 8. AuditLogger 设计

### 8.1 Schema
```swift
@Model class AuditLogEntity {
    var id: UUID
    var timestamp: Date
    var actor: String         // user / runtime
    var action: String        // tool_call / api_request / budget_block / injection_detected / policy_decision
    var detail: String        // JSON
    var riskLevel: String     // low / medium / high
}
```

### 8.2 写入规则
- **只追加**：禁止 `update` / `delete`
- 落盘策略：批量 5s flush 或 50 条 flush
- 字段中**禁止**含明文 API Key / 用户密码

### 8.3 访问
- 仅 Settings → "导出审计" 可读
- 导出格式：JSON Lines

---

## 9. 应急流程

### 9.1 密钥失效（401）
1. 捕获 `URLError.userAuthenticationRequired` / HTTP 401
2. `KeychainStore.delete(.apiKey)`
3. 弹窗"API Key 无效，请重新输入"
4. 写入 `AuditLogEntity{action: "key_invalid"}`

### 9.2 月度超支
1. `BudgetGuard.triggered = .monthly`
2. 阻断后续所有 Provider 调用
3. UI 红色横幅 + CostMeter 变红
4. 写入 `AuditLogEntity{action: "budget_block", risk: "high"}`
5. 提供"调整预算"入口

### 9.3 注入检测
1. 工具结果包裹 + 黑名单命中
2. 写入 `AuditLogEntity{action: "injection_detected", risk: "high"}`
3. UI 显示 ⚠️ + 隐藏可疑内容预览
4. 连续 3 次 → 弹窗"建议结束会话"

### 9.4 工具超时
- 单工具执行 > 30s → 取消
- 单工具并发 > 5 → 拒绝排队
- 写入 `AuditLogEntity{action: "tool_timeout"}`

---

## 10. 验收清单（必须全部通过）

### 10.1 静态
- [ ] `grep -r "UserDefaults" Visor/` 无 API Key 写入
- [ ] `grep -r "print(" Visor/` 无明文 Key 前缀
- [ ] `Info.plist` 无 `NSAllowsArbitraryLoads`
- [ ] 无第三方 Analytics SDK

### 10.2 动态
- [ ] Keychain 写入 / 读取 / 删除 OK
- [ ] API Key 不会出现在 URL 字符串中
- [ ] 关闭网络 → UI 提示而非崩溃
- [ ] 月度预算拉满 → 熔断 + 写审计
- [ ] 注入检测样本拦截率 ≥ 95%
- [ ] 高危工具（shell / fs）默认拒绝
- [ ] 所有异常路径有友好提示

### 10.3 审计
- [ ] `AuditLogEntity` 表只追加
- [ ] 导出 JSON Lines 格式正确
- [ ] 不含明文 API Key

---

## 11. 不在范围

- 防越狱（iOS 沙箱外）
- 防设备物理获取（Keychain AfterFirstUnlock 已是基线）
- 抗量子加密（待 iOS 27+ PQC SDK 稳定后引入）

---

## 12. 引用

- Apple Keychain Services：https://developer.apple.com/documentation/security/keychain_services
- CryptoKit AES.GCM：https://developer.apple.com/documentation/cryptokit/aes/gcm
- OWASP LLM Top 10：https://owasp.org/www-project-top-10-for-large-language-model-applications/
