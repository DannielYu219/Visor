import Foundation

/// Wireframe Skill（快速线框图）
struct WireframeSkill: Skill {
    let name = "wireframe"
    var displayName: String { "skill.wireframe".l }
    var skillDescription: String { "skill.wireframe".l }

    var systemPromptFragment: String {
        PromptLocalizer.text(named: "skill_wireframe")
    }

    func matches(_ userInput: String) -> Bool {
        let keywords = [
            "线框", "wireframe", "草图", "方案", "探索",
            "几个版本", "多个方向", "sketch", "rough", "mockup",
            "maquette", "esquisse", "Skizze", "Entwurf"
        ]
        return defaultMatches(keywords, in: userInput)
    }
}
