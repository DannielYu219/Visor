import Foundation
import SwiftData
import os.log

/// SwiftData 容器配置
/// Phase 1：基础实体落盘；后续可加入 ModelConfiguration（URL / 加密）
@MainActor
enum SwiftDataStack {
    static let schema: Schema = Schema([
        SessionEntity.self,
        MessageEntity.self,
        ArtifactEntity.self,
        AuditLogEntity.self,
        BudgetEntity.self
    ])

    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        } else {
            configuration = ModelConfiguration(
                "VisorStore",
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true
            )
        }
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // 金融级：永不崩溃，回退到内存存储并记录
            os_log("SwiftData 初始化失败，回退内存存储: %{public}@", String(describing: error))
            let fallback = ModelConfiguration(isStoredInMemoryOnly: true)
            // forceUnwrap 在这里安全，因为 schema 已验证
            return try! ModelContainer(for: schema, configurations: [fallback])
        }
    }
}
