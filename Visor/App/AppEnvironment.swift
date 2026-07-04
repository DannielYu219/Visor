import Foundation
import SwiftData

/// 依赖容器（Phase 1 轻量版；Phase 2+ 注入 AgentRuntime / ToolRegistry）
@MainActor
@Observable
final class AppEnvironment {
    let modelContainer: ModelContainer
    let openRouterClient: OpenRouterClient
    let pricingTable: ModelPricingTable
    let budgetGuard: BudgetGuard

    init() {
        self.modelContainer = SwiftDataStack.makeContainer()
        self.openRouterClient = OpenRouterClient()
        self.pricingTable = .shared
        self.budgetGuard = BudgetGuard()
    }
}
