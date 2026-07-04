import Foundation
import Combine
import os.log

/// 预算熔断（金融级安全：会话/日/月三段）
/// Phase 1：内存态即可（Settings 可写回 SwiftData）
@MainActor
final class BudgetGuard: ObservableObject {

    enum Period: String, CaseIterable, Sendable {
        case session
        case daily
        case monthly
    }

    struct Limit: Sendable, Equatable {
        var sessionUSD: Double = 5.0
        var dailyUSD: Double = 20.0
        var monthlyUSD: Double = 200.0
    }

    @Published private(set) var limit: Limit
    @Published private(set) var sessionSpent: Double = 0
    @Published private(set) var dailySpent: Double = 0
    @Published private(set) var monthlySpent: Double = 0

    @Published private(set) var triggeredPeriod: Period?
    private let logger = Logger(subsystem: "com.lyrastudio.Visor", category: "BudgetGuard")

    init(limit: Limit? = nil) {
        self.limit = limit ?? Limit()
    }

    /// 检查并增加本次预估费用
    /// - Returns: 允许时返回 true；超限时返回 false 并设置 triggeredPeriod
    @discardableResult
    func checkAndCharge(estimatedUSD: Double) -> Bool {
        if triggeredPeriod != nil { return false }
        if sessionSpent + estimatedUSD > limit.sessionUSD {
            triggeredPeriod = .session
            logger.error("Budget triggered: session")
            return false
        }
        if dailySpent + estimatedUSD > limit.dailyUSD {
            triggeredPeriod = .daily
            logger.error("Budget triggered: daily")
            return false
        }
        if monthlySpent + estimatedUSD > limit.monthlyUSD {
            triggeredPeriod = .monthly
            logger.error("Budget triggered: monthly")
            return false
        }
        // 预扣
        sessionSpent += estimatedUSD
        dailySpent += estimatedUSD
        monthlySpent += estimatedUSD
        return true
    }

    /// 实际结算（流式完成后）
    func settle(actualUSD: Double) {
        // 已 checkAndCharge 预扣，Phase 1 直接累加差值由调用方处理
    }

    /// 重置会话计数（新会话开始时）
    func resetSession() {
        sessionSpent = 0
        if triggeredPeriod == .session { triggeredPeriod = nil }
    }

    /// 用户更新预算
    func update(limit: Limit) {
        self.limit = limit
    }

    /// 警告阈值（80%）查询
    func isWarning(period: Period) -> Bool {
        switch period {
        case .session:
            return limit.sessionUSD > 0 && sessionSpent / limit.sessionUSD >= 0.8
        case .daily:
            return limit.dailyUSD > 0 && dailySpent / limit.dailyUSD >= 0.8
        case .monthly:
            return limit.monthlyUSD > 0 && monthlySpent / limit.monthlyUSD >= 0.8
        }
    }
}
