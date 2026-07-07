import Foundation
import CoreGraphics

/// 设计令牌（对齐 ipad-chat.html Apple HIG）
/// 同心圆角规则：R_outer - padding = R_inner
///   例: R_l(28) - S_l(16) = R_s(12)  →  R_m(20) - S_s(8) = R_s(12)
enum DesignTokens {

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
        static let xxxxl: CGFloat = 48
    }

    enum Radius {
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 20
        static let l: CGFloat = 28
    }

    enum FontSize {
        static let caption: CGFloat = 14
        static let body: CGFloat = 16
        static let bodyLarge: CGFloat = 19
        static let title: CGFloat = 24
        static let display: CGFloat = 32
    }

    /// 触控目标尺寸
    enum Touch {
        static let standard: CGFloat = 48
        static let icon: CGFloat = 20
        static let compact: CGFloat = 44
        static let compactIcon: CGFloat = 18
    }
}
