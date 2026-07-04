import Foundation
import SwiftData

/// 工件实体：WRITE/PATCH 命令产物
@Model
final class ArtifactEntity {
    @Attribute(.unique) var id: UUID
    var path: String
    var html: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        path: String,
        html: String
    ) {
        self.id = id
        self.path = path
        self.html = html
        self.createdAt = Date()
    }
}
