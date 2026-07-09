import Foundation
import Security
import os.log

/// Keychain 封装：API Key 等敏感字段的金融级存储
/// 约束：永不使用 UserDefaults；永不在 print 中输出明文
nonisolated enum KeychainStore {

    enum Item: String {
        case openRouterAPIKey = "openrouter_api_key"
    }

    enum KeychainError: Error, LocalizedError {
        case unhandled(OSStatus)
        case dataConversion
        case notFound

        var errorDescription: String? {
            switch self {
            case .unhandled(let status):
                return "Keychain 错误（OSStatus \(status)）"
            case .dataConversion:
                return "Keychain 数据转换失败"
            case .notFound:
                return "Keychain 未找到对应项"
            }
        }
    }

    private static let service = "com.lyrastudio.Visor"
    private static let logger = Logger(subsystem: service, category: "KeychainStore")

    /// 写入（覆盖）
    static func set(_ value: String, for item: Item) throws {
        try set(value, account: item.rawValue)
    }

    /// 读取
    static func get(_ item: Item) -> String? {
        get(account: item.rawValue)
    }

    /// 删除
    static func delete(_ item: Item) throws {
        try delete(account: item.rawValue)
    }

    // MARK: - 通用 account API（用于自定义服务商等动态 account）

    /// 写入（覆盖）— 按 account 名存储
    static func set(_ value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.dataConversion
        }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        // 尝试更新
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            // 不存在则新增
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                logger.error("Keychain add failed: OSStatus=\(addStatus, privacy: .public)")
                throw KeychainError.unhandled(addStatus)
            }
        default:
            logger.error("Keychain update failed: OSStatus=\(updateStatus, privacy: .public)")
            throw KeychainError.unhandled(updateStatus)
        }
    }

    /// 读取 — 按 account 名读取
    static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            if status != errSecItemNotFound {
                logger.error("Keychain get failed: OSStatus=\(status, privacy: .public)")
            }
            return nil
        }
        return value
    }

    /// 删除 — 按 account 名删除
    static func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Keychain delete failed: OSStatus=\(status, privacy: .public)")
            throw KeychainError.unhandled(status)
        }
    }

    /// 便捷：OpenRouter API Key
    static var openRouterAPIKey: String? {
        get { get(.openRouterAPIKey) }
        set {
            if let v = newValue {
                try? set(v, for: .openRouterAPIKey)
            } else {
                try? delete(.openRouterAPIKey)
            }
        }
    }
}
