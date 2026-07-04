import Foundation
import CoreGraphics

/// 设计令牌（对齐 open-design-spec.md §2）
enum DesignTokens {

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
    }

    enum Radius {
        static let s: CGFloat = 12
        static let m: CGFloat = 20
        static let l: CGFloat = 28
    }

    enum FontSize {
        static let caption: CGFloat = 13
        static let body: CGFloat = 15
        static let bodyLarge: CGFloat = 17
        static let title: CGFloat = 22
        static let display: CGFloat = 28
    }
}
