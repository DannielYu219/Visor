import SwiftUI

/// Liquid Glass 视觉修饰符 + 统一的圆形 glass 按钮组件
/// 遵循 iPad 设计稿体系：ultraThinMaterial + Circle + 微边框 + 投影

// MARK: - Backdrop 修饰符

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

    /// 圆形 Liquid Glass 样式 — 统一定义，所有圆形按钮共享
    /// - Parameter size: touch target 尺寸，默认 48pt
    func circularGlass(size: CGFloat = DesignTokens.Touch.standard) -> some View {
        self
            .frame(width: size, height: size)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
            .contentShape(Circle())
    }
}

// MARK: - 共享圆形 Glass 按钮

/// 统一的圆形 Liquid Glass 按钮（触控目标 48pt，图标 20pt）
struct CircularGlassButton: View {
    let systemName: String
    let iconSize: CGFloat
    let size: CGFloat
    let action: () -> Void

    init(
        systemName: String,
        iconSize: CGFloat = DesignTokens.Touch.icon,
        size: CGFloat = DesignTokens.Touch.standard,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.iconSize = iconSize
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(.primary)
                .circularGlass(size: size)
        }
        .buttonStyle(.plain)
    }
}
