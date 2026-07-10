import Foundation
import SwiftUI
import Combine

/// 应用支持的语言
///
/// - `.system`：跟随系统语言（回退到英文）
/// - 其余：固定到对应语言
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case zhHans   // 简体中文
    case ja       // 日本語
    case en       // English (US)
    case de       // Deutsch
    case fr       // Français

    var id: String { rawValue }

    /// 用于 .lproj 目录匹配的代码
    /// `.system` 返回 nil，由 Bundle 自行决定
    var lprojCode: String? {
        switch self {
        case .system: return nil
        case .zhHans: return "zh-Hans"
        case .ja:     return "ja"
        case .en:     return "en"
        case .de:     return "de"
        case .fr:     return "fr"
        }
    }

    /// 设置页显示名称（用对应语言书写，便于用户识别）
    var displayName: String {
        switch self {
        case .system: return NSLocalizedString("lang.system", value: "跟随系统", comment: "语言选项：跟随系统")
        case .zhHans: return "简体中文"
        case .ja:     return "日本語"
        case .en:     return "English (US)"
        case .de:     return "Deutsch"
        case .fr:     return "Français"
        }
    }

    /// 系统语言自动解析后的实际 lproj 代码
    static var systemResolvedCode: String? {
        let preferred = Locale.preferredLanguages.first ?? "en"
        if preferred.hasPrefix("zh-Hans") || preferred.hasPrefix("zh-CN") { return "zh-Hans" }
        if preferred.hasPrefix("zh-Hant") || preferred.hasPrefix("zh-TW") { return "zh-Hans" } // 暂仅简中
        if preferred.hasPrefix("ja") { return "ja" }
        if preferred.hasPrefix("de") { return "de" }
        if preferred.hasPrefix("fr") { return "fr" }
        if preferred.hasPrefix("en") { return "en" }
        return "en"
    }
}

/// 应用语言管理器
///
/// 设计要点：
/// - 持久化用户选择到 UserDefaults（`appLanguage`）
/// - 通过 Bundle swizzling 让 `NSLocalizedString` / `Text("...")` 即时响应语言变更（无需重启）
/// - 暴露 `objectWillChange` 让 SwiftUI 视图自动刷新
@MainActor
final class LanguageManager: ObservableObject {

    static let shared = LanguageManager()

    /// 通知名：语言已变更（用于触发 SwiftUI 全局刷新或 Locale 环境切换）
    nonisolated static let didChange = Notification.Name("Visor.LanguageDidChange")

    /// 当前选择的语言（持久化）
    @Published var selected: AppLanguage {
        didSet {
            UserDefaults.standard.set(selected.rawValue, forKey: Self.storageKey)
            applyLanguage()
        }
    }

    /// 当前生效的 lproj 代码（供 PromptLocalizer / 非 strings 资源使用）
    var currentLprojCode: String {
        selected.lprojCode ?? AppLanguage.systemResolvedCode ?? "en"
    }

    /// 当前生效的 Locale（用于 SwiftUI `.environment(\.locale)`）
    var currentLocale: Locale {
        let code = currentLprojCode
        // 把 zh-Hans 拆成 language-script 形式给 Locale
        if code == "zh-Hans" { return Locale(identifier: "zh-Hans") }
        return Locale(identifier: code)
    }

    private static let storageKey = "appLanguage"

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.storageKey) ?? AppLanguage.system.rawValue
        self.selected = AppLanguage(rawValue: raw) ?? .system
        // 安装 swizzling（仅一次）
        Self.installSwizzleIfNeeded()
        applyLanguage()
    }

    /// 应用当前语言到 Bundle.main（通过 swizzling）
    private func applyLanguage() {
        let code = currentLprojCode
        Self.activeLprojCode = code
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    // MARK: - Bundle Swizzling

    /// 当前激活的 lproj 代码（被 swizzled 方法读取）
    nonisolated(unsafe) static var activeLprojCode: String = "en"

    /// 标记位，防止重复 swizzle
    nonisolated(unsafe) private static var swizzled: Bool = false

    private static func installSwizzleIfNeeded() {
        guard !swizzled else { return }
        swizzled = true

        let original = class_getInstanceMethod(Bundle.self, #selector(Bundle.localizedString(forKey:value:table:)))
        let swizzledImpl = class_getInstanceMethod(Bundle.self, #selector(Bundle.visor_localizedString(forKey:value:table:)))
        if let o = original, let s = swizzledImpl {
            method_exchangeImplementations(o, s)
        }
    }
}

// MARK: - Bundle Swizzling 扩展

extension Bundle {
    /// Swizzled 实现：优先从用户选定的 .lproj 子 bundle 取字符串
    @objc func visor_localizedString(forKey key: String, value: String?, table: String?) -> String {
        // 用 exchangeImplementations 后，self 已是 Bundle.main 或子 bundle；
        // 调用"原本"的方法要走 visor_localized...（交换后的实现指向原始）
        let activeCode = LanguageManager.activeLprojCode
        if let path = Bundle.main.path(forResource: activeCode, ofType: "lproj"),
           let lprojBundle = Bundle(path: path) {
            // 注意：这里调用 visor_localized... 会再次进入本方法（递归一次），
            // 但 lprojBundle 不是 Bundle.main，其 path(forResource:activeCode) 通常返回 nil，
            // 所以会落到下面的 fallback，调用原始实现。安全。
            return lprojBundle.visor_localizedString(forKey: key, value: value, table: table)
        }
        // 没有匹配的 lproj，回退到原始系统行为
        return self.visor_localizedString(forKey: key, value: value, table: table)
    }
}

// MARK: - String 扩展：便捷本地化

extension String {
    /// `"settings.title".l` — 等价于 NSLocalizedString，但更简洁
    nonisolated var l: String {
        NSLocalizedString(self, comment: "")
    }

    /// 带参数的本地化
    nonisolated func l(_ args: CVarArg...) -> String {
        let fmt = NSLocalizedString(self, comment: "")
        return String(format: fmt, arguments: args)
    }
}

// MARK: - PromptLocalizer：加载 .txt 形式的长 prompt

/// 加载按语言分目录的长文本 prompt
/// - 资源位于 `Resources/{lang}.lproj/{name}.txt`
enum PromptLocalizer {

    /// 取指定 prompt 的当前语言版本
    static func text(named name: String) -> String {
        let code = LanguageManager.shared.currentLprojCode
        // 1. 优先从当前语言的 lproj 子 bundle 加载
        if let bundle = lprojBundle(for: code),
           let url = bundle.url(forResource: name, withExtension: "txt"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }
        // 2. 回退到英文
        if code != "en",
           let bundle = lprojBundle(for: "en"),
           let url = bundle.url(forResource: name, withExtension: "txt"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }
        // 3. 再回退到主 bundle 顶层（任意语言）
        if let url = Bundle.main.url(forResource: name, withExtension: "txt"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }
        return ""
    }

    /// 取指定语言的 lproj Bundle
    static func lprojBundle(for code: String) -> Bundle? {
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }
}
