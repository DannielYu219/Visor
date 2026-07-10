import Foundation

/// Frontend Design Skill（设计有品牌感的界面）
struct FrontendDesignSkill: Skill {
    let name = "frontend-design"
    var displayName: String { "skill.frontendDesign".l }
    var skillDescription: String { "skill.frontendDesign".l }

    var systemPromptFragment: String {
        PromptLocalizer.text(named: "skill_frontend_design")
    }

    func matches(_ userInput: String) -> Bool {
        let keywords = [
            "设计", "界面", "页面", "design", "ui", "landing", "登录页", "首页",
            "首页设计", "app", "网站", "site", "page", "screen",
            "design", "interface", "page", "UI", "landing", "entwerfen", "interface",
            "concevoir", "interface", "page", "conception"
        ]
        return defaultMatches(keywords, in: userInput)
    }
}
