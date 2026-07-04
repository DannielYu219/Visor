import Foundation

/// Skill 协议
/// 来源：Open Design 的 10 个 skill 是 Markdown 指令集
/// iOS 实现：将 Markdown 内容作为 system prompt 注入
nonisolated protocol Skill: Sendable {
    /// 唯一名称（英文，与 Open Design 的目录名一致）
    var name: String { get }
    /// 中文显示名
    var displayName: String { get }
    /// 描述（用于路由解释）
    var skillDescription: String { get }
    /// 注入到 system prompt 的指令（Markdown 内容）
    var systemPromptFragment: String { get }
    /// 路由判断：用户输入是否匹配本 skill
    func matches(_ userInput: String) -> Bool
}

extension Skill {
    /// 关键词匹配（中英文同义）
    func defaultMatches(_ keywords: [String], in userInput: String) -> Bool {
        let lower = userInput.lowercased()
        return keywords.contains { lower.contains($0.lowercased()) }
    }
}
