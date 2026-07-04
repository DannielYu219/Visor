import SwiftUI

/// Liquid Glass 视觉修饰符
/// 遵循 `open-design-spec.md` §3
extension View {

    /// 玻璃背景（默认圆角 20）
    func glassBackground(corner: CGFloat = DesignTokens.Radius.m) -> some View {
        self
            .background(.ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.04), radius: 16, y: 4)
    }

    /// 较厚的玻璃（用于弹窗 / Sheet）
    func glassBackgroundThick(corner: CGFloat = DesignTokens.Radius.l) -> some View {
        self
            .background(.regularMaterial,
                in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.06), radius: 24, y: 6)
    }
}
