import SwiftUI

/// 字号预设（对齐 DesignTokens.FontSize）
extension Font {
    static let visorCaption = Font.system(size: DesignTokens.FontSize.caption)
    static let visorBody = Font.system(size: DesignTokens.FontSize.body)
    static let visorBodyLarge = Font.system(size: DesignTokens.FontSize.bodyLarge)
    static let visorTitle = Font.system(size: DesignTokens.FontSize.title, weight: .semibold)
    static let visorDisplay = Font.system(size: DesignTokens.FontSize.display, weight: .bold)
}
