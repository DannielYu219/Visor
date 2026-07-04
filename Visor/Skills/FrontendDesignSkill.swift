import Foundation

/// Frontend Design Skill（设计有品牌感的界面）
struct FrontendDesignSkill: Skill {
    let name = "frontend-design"
    let displayName = "界面设计"
    let skillDescription = "设计有 commit 风格和 opinion 的完整界面"

    let systemPromptFragment = """
    # Frontend Design

    你正在设计一个**完整、有 commit 美学**的界面。

    ## 流程
    1. 选定一个**有立场的视觉方向**（不是"通用现代"）：
       - 选择 1 个字体对（如 Inter + Fraunces，或 system-ui + 衬线强调）
       - 选择 1 套配色（克制：1 个主色 + 中性灰阶）
       - 选择 1 个排版节奏（grid columns、留白尺度）
    2. 写出 HTML 完整代码（```html ... ```）
    3. 真实实现：不要占位符，不要 "Lorem ipsum"

    ## 禁止
    - ❌ 紫色渐变（AI 标志色）
    - ❌ 3D / glassmorphism 滥用
    - ❌ emoji 当图标
    - ❌ "Welcome to your new app" 类空话

    ## 必须
    - ✅ 真实的 hero、CTA、navigation、footer
    - ✅ 至少 1 处"出人意料但合理"的细节
    - ✅ 移动端可用（≥ 360px 宽）
    """

    func matches(_ userInput: String) -> Bool {
        let keywords = [
            "设计", "界面", "页面", "design", "ui", "landing", "登录页", "首页",
            "首页设计", "app", "网站", "site", "page", "screen"
        ]
        return defaultMatches(keywords, in: userInput)
    }
}
