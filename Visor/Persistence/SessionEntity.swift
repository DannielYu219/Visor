import Foundation
import SwiftData

/// 会话实体：代表一次完整的对话
@Model
final class SessionEntity {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var totalCostUSD: Double
    var totalInputTokens: Int
    var totalOutputTokens: Int
    var modelId: String

    @Relationship(deleteRule: .cascade, inverse: \MessageEntity.session)
    var messages: [MessageEntity] = []

    init(
        id: UUID = UUID(),
        title: String = "新会话",
        modelId: String = "openai/gpt-5.5-pro"
    ) {
        self.id = id
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.totalCostUSD = 0
        self.totalInputTokens = 0
        self.totalOutputTokens = 0
        self.modelId = modelId
    }
}
