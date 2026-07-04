import Foundation
import SwiftData

/// 预算实体：周期限额 + 累计花费
/// period: "session" / "daily" / "monthly"
@Model
final class BudgetEntity {
    @Attribute(.unique) var id: UUID
    var period: String
    var limitUSD: Double
    var spentUSD: Double
    var periodStart: Date
    var periodEnd: Date

    init(
        id: UUID = UUID(),
        period: String,
        limitUSD: Double,
        spentUSD: Double = 0,
        periodStart: Date = Date(),
        periodEnd: Date
    ) {
        self.id = id
        self.period = period
        self.limitUSD = limitUSD
        self.spentUSD = spentUSD
        self.periodStart = periodStart
        self.periodEnd = periodEnd
    }

    /// 预算使用百分比（0.0 ~ 1.0+，超过 1.0 即超支）
    var usageRatio: Double {
        guard limitUSD > 0 else { return 0 }
        return spentUSD / limitUSD
    }

    var isOverBudget: Bool {
        spentUSD >= limitUSD
    }
}
