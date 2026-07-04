# Open Design 设计规范（Liquid Glass）

> Visor iOS 项目 · 2026-07-03 · 配套 `agent-overview.md` / `security-policy.md`

---

## 1. 布局原则

### 1.1 三栏 NavigationSplitView
| 断点 | 布局 |
|------|------|
| `compactWidth` (<1024pt) | 单栏 + Toolbar 弹出 Sidebar/Inspector |
| `regularWidth` (≥1024pt iPad) | 三栏：Sidebar / Main / Inspector |

- Sidebar：会话列表 260pt 固定
- Main：弹性撑满
- Inspector：360pt 固定

### 1.2 边距尺度
- 紧凑 `12pt`（行内）
- 标准 `16pt`（卡片内）
- 宽松 `24pt`（区块间）

### 1.3 安全区
- 顶部尊重 `safeAreaInsets.top`
- 底部尊重键盘上推（`@FocusState` 联动）

---

## 2. 设计令牌

### 2.1 间距（Spacing）
| Token | 值 | 用途 |
|-------|----|----|
| `space.xs` | 4 | 图标-文字 |
| `space.s` | 8 | 行内 |
| `space.m` | 12 | 组件内 |
| `space.l` | 16 | 卡片内 |
| `space.xl` | 20 | 区块内 |
| `space.xxl` | 24 | 区块间 |

### 2.2 圆角（Radius）
| Token | 值 | 用途 |
|-------|----|----|
| `radius.s` | 12 | 按钮 |
| `radius.m` | 20 | 卡片 |
| `radius.l` | 28 | 主容器 |

### 2.3 字号（Font）
| Token | iOS | 用途 |
|-------|-----|----|
| `caption` | 13 | 元数据 |
| `body` | 15 | 正文 |
| `bodyLarge` | 17 | 消息 |
| `title` | 22 | 卡片标题 |
| `display` | 28 | 空状态 |

### 2.4 阴影
| Token | 值 |
|-------|----|
| `shadow.glass` | `radius: 16, y: 4, opacity: 0.04` |

---

## 3. Liquid Glass 视觉规则

### 3.1 材质
- `.ultraThinMaterial`：消息气泡背景
- `.regularMaterial`：弹窗 / 确认 Sheet
- `.thickMaterial`：Modal 全屏

### 3.2 高光描边
```swift
.strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
```

### 3.3 主样式修饰符
```swift
extension View {
    func glassBackground(corner: CGFloat = 20) -> some View {
        self
            .background(.ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.04), radius: 16, y: 4)
    }
}
```

### 3.4 配色
- 主色：`AccentColor`（Xcode Assets）
- 中性：`Color(.systemBackground)` / `Color(.secondarySystemBackground)`
- 错误：`Color(.systemRed)` + opacity 0.12 背景
- 成功：`Color(.systemGreen)` + opacity 0.12 背景

---

## 4. 组件库

### 4.1 MessageBubble
- 用户：右对齐，主色描边，背景 `ultraThinMaterial`
- 助手：左对齐，无描边
- 工具：居中，`ToolCallCard` 替代
- 圆角：`radius.m`（20）
- 内边距：`space.l`（16）
- 字号：`bodyLarge`（17）

### 4.2 ComposerBar
- 底部 fixed，高度自适应
- 输入框：多行 `TextField`，最大 5 行
- 发送按钮：圆形 `Image(systemName: "arrow.up")`
- 键盘上推：`@FocusState` 联动

### 4.3 ToolCallCard
- 紧凑卡片：图标 + 工具名 + 状态徽章
- 状态徽章：
  - 待确认：`Color.orange.opacity(0.12)` + "待确认"
  - 执行中：`Color.blue.opacity(0.12)` + "执行中"
  - 成功：`Color.green.opacity(0.12)` + "成功"
  - 失败：`Color.red.opacity(0.12)` + "失败"（必须可见，不静默）
- 点击展开 `toolCallBody` JSON

### 4.4 CostMeter
- Inspector 顶部固定
- 实时显示：本次会话 USD 累计 / 今日 USD / 当月 USD
- 进度条 + 预算百分比
- 超支变红 + ⚠️ 图标

### 4.5 ConfirmationSheet
- 危险工具调用前弹出
- 显示：工具名 / 参数 / 风险说明
- 按钮：取消 / 允许（主色）

---

## 5. 可访问性

### 5.1 Dynamic Type
- 所有文本使用 `.font(.body)` 等相对字号
- 不使用 `.lineLimit(1)` 限制长内容

### 5.2 VoiceOver
- 图标按钮必须有 `.accessibilityLabel`
- ToolCallCard 状态用 `.accessibilityValue` 暴露
- CostMeter 百分比读屏

### 5.3 Reduce Motion
- `repeatForever()` **禁止**（项目记忆硬约束）
- `withAnimation` 在 `accessibilityReduceMotion` 时关闭
- 流式滚动不强制动画

### 5.4 深色模式
- 全部使用语义色（`Color(.systemBackground)`）
- Liquid Glass 材质自动适配

---

## 6. 不在范围

- 自定义 SF Symbols 字体
- Lottie 动画
- 自绘图表
- 多语言（中/英 UI 字串即可）

---

## 7. 引用

- Apple Human Interface Guidelines：https://developer.apple.com/design/human-interface-guidelines/
- Liquid Glass（iOS 26）：WWDC 2025 Session 219
- SwiftUI Materials：`Material` 协议文档
