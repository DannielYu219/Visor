import Foundation

/// Tool 协议
/// iOS 实现：模型在文本流中输出 ```html ... ``` 围栏，HTMLCaptureTool 捕获
/// 未来扩展：模型可调用 function calling（OpenAI 兼容），但 Phase 2 不接
protocol Tool: Sendable {
    var name: String { get }
    var displayName: String { get }
    var toolDescription: String { get }
    var riskLevel: RiskLevel { get }

    /// 执行（Phase 2：纯文本输入；Phase 3+：JSON Schema）
    func execute(input: String) async throws -> ToolResult
}

enum RiskLevel: String, Sendable, CaseIterable {
    case low
    case medium
    case high
    case forbidden
}

struct ToolResult: Sendable {
    /// 是否捕获到产物（HTML 写盘）
    let capturedHTML: String?
    /// 文本回执（显示在聊天中）
    let message: String
    /// 错误信息（如有）
    let error: String?

    init(capturedHTML: String? = nil, message: String, error: String? = nil) {
        self.capturedHTML = capturedHTML
        self.message = message
        self.error = error
    }
}
