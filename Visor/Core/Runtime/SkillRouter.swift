import Foundation
import os.log

/// 简单关键词路由：用户输入 → Skill
/// Phase 2 实现；Phase 3 考虑升级为 LLM router
nonisolated final class SkillRouter: @unchecked Sendable {
    private let skills: [Skill]
    private let fallback: Skill
    private let logger = Logger(subsystem: "com.lyrastudio.Visor", category: "SkillRouter")

    init(skills: [Skill]) {
        // fallback 必须是最后一个
        if let last = skills.last, last.name == "opendesign" {
            self.skills = skills
            self.fallback = last
        } else {
            // 若没传入口 skill，构造一个
            let entry = OpenDesignSkill()
            self.skills = skills + [entry]
            self.fallback = entry
        }
    }

    /// 默认 skill 集合（按优先级排序）
    static let `default`: [Skill] = [
        MakeADeckSkill(),
        WireframeSkill(),
        FrontendDesignSkill(),
        OpenDesignSkill()
    ]

    /// 路由：返回最匹配的 skill + 注入到 system prompt 的指令
    func route(_ userInput: String) -> RoutedSkill {
        // 倒序匹配，第一个命中的 specialist 优先
        for skill in self.skills.reversed() {
            if skill.name == self.fallback.name { continue }
            if skill.matches(userInput) {
                self.logger.info("Routed to skill: \(skill.name, privacy: .public)")
                return RoutedSkill(
                    primary: skill,
                    systemPrompt: self.composeSystemPrompt(primary: skill)
                )
            }
        }
        // 兜底
        self.logger.info("Routed to fallback skill: \(self.fallback.name, privacy: .public)")
        return RoutedSkill(
            primary: self.fallback,
            systemPrompt: self.composeSystemPrompt(primary: self.fallback)
        )
    }

    /// 组合 system prompt：入口 skill + 选中的 specialist
    private func composeSystemPrompt(primary: Skill) -> String {
        if primary.name == self.fallback.name {
            return primary.systemPromptFragment
        }
        // 双层：入口规则 + specialist 指令
        return """
        \(self.fallback.systemPromptFragment)

        ---

        # Selected Specialist: \(primary.displayName)

        \(primary.systemPromptFragment)
        """
    }
}

struct RoutedSkill: Sendable {
    let primary: Skill
    let systemPrompt: String
}
