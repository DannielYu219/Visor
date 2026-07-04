import SwiftUI

/// 费用计
struct CostMeter: View {
    let sessionUSD: Double
    let sessionLimitUSD: Double
    let dailyUSD: Double
    let dailyLimitUSD: Double
    let monthlyUSD: Double
    let monthlyLimitUSD: Double

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            Text("费用概览")
                .font(.visorTitle)
                .foregroundStyle(.primary)

            meterRow(label: "本次会话", spent: sessionUSD, limit: sessionLimitUSD)
            meterRow(label: "今日", spent: dailyUSD, limit: dailyLimitUSD)
            meterRow(label: "本月", spent: monthlyUSD, limit: monthlyLimitUSD)
        }
        .padding(DesignTokens.Spacing.l)
        .glassBackground(corner: DesignTokens.Radius.m)
    }

    @ViewBuilder
    private func meterRow(label: String, spent: Double, limit: Double) -> some View {
        let ratio = limit > 0 ? min(spent / limit, 1.5) : 0
        let isOver = spent >= limit && limit > 0

        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack {
                Text(label)
                    .font(.visorCaption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "$%.4f / $%.2f", spent, limit))
                    .font(.visorCaption)
                    .foregroundStyle(isOver ? Color.visorStatusFailedText : .secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.visorTertiaryBackground)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(isOver ? Color.visorStatusFailedText : Color.accentColor)
                        .frame(width: max(0, min(ratio, 1.0)) * geo.size.width)
                }
            }
            .frame(height: 6)
        }
    }
}
