import Foundation
import SwiftData

/// 审计日志实体：只追加，禁止修改/删除（金融级基线）
/// actor: "user" / "runtime"
/// action: "tool_call" / "api_request" / "budget_block" / "injection_detected" / "policy_decision" / "key_invalid" / "tool_timeout"
/// riskLevel: "low" / "medium" / "high"
@Model
final class AuditLogEntity {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var actor: String
    var action: String
    /// JSON 负载（禁止含明文 API Key）
    var detail: String
    var riskLevel: String

    init(
        id: UUID = UUID(),
        actor: String,
        action: String,
        detail: String,
        riskLevel: String = "low"
    ) {
        self.id = id
        self.timestamp = Date()
        self.actor = actor
        self.action = action
        self.detail = detail
        self.riskLevel = riskLevel
    }
}
