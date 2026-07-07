import SwiftUI

/// 字号预设（对齐 iPad HIG: 17px body base）
extension Font {
    static let visorCaption = Font.system(size: DesignTokens.FontSize.caption) // 12
    static let visorBody = Font.system(size: DesignTokens.FontSize.body) // 14
    static let visorBodyLarge = Font.system(size: DesignTokens.FontSize.bodyLarge) // 17
    static let visorTitle = Font.system(size: DesignTokens.FontSize.title, weight: .semibold) // 21
    static let visorDisplay = Font.system(size: DesignTokens.FontSize.display, weight: .bold) // 28
}
