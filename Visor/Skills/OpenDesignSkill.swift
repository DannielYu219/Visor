import Foundation

/// Open Design 入口 skill（路由 + 基础规则）
/// 来自 Open Design 的 `opendesign` SKILL.md（简化版，保留核心约束）
struct OpenDesignSkill: Skill {
    let name = "opendesign"
    var displayName: String { "skill.openDesign".l }
    var skillDescription: String { "skill.openDesign".l }

    var systemPromptFragment: String {
        PromptLocalizer.text(named: "skill_opendesign")
    }

    func matches(_ userInput: String) -> Bool {
        // 入口 skill 永远兜底匹配
        return true
    }
}
