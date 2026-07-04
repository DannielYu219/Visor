import Foundation
import CryptoKit
import os.log

/// CryptoBox：AES-GCM 加密工具（CryptoKit 官方）
/// 用途：加密 SwiftData 中未来扩展的敏感字段
/// Phase 1：仅预留接口与单元自测；Phase 2+ 接入业务
enum CryptoBox {

    enum CryptoError: Error, LocalizedError {
        case keyDerivationFailed
        case encryptionFailed
        case decryptionFailed
        case invalidPayload

        var errorDescription: String? {
            switch self {
            case .keyDerivationFailed: return "密钥派生失败"
            case .encryptionFailed: return "加密失败"
            case .decryptionFailed: return "解密失败"
            case .invalidPayload: return "载荷格式无效"
            }
        }
    }

    private static let logger = Logger(subsystem: "com.lyrastudio.Visor", category: "CryptoBox")

    /// 生成对称密钥（持久化到 Keychain 由调用方管理）
    static func generateKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    /// 加密（输出 base64 字符串，含 nonce + ciphertext + tag）
    static func encrypt(_ plaintext: String, using key: SymmetricKey) throws -> String {
        guard let data = plaintext.data(using: .utf8) else {
            throw CryptoError.invalidPayload
        }
        do {
            let sealed = try AES.GCM.seal(data, using: key)
            guard let combined = sealed.combined else {
                throw CryptoError.encryptionFailed
            }
            return combined.base64EncodedString()
        } catch {
            logger.error("AES.GCM seal failed: \(String(describing: error), privacy: .public)")
            throw CryptoError.encryptionFailed
        }
    }

    /// 解密
    static func decrypt(_ base64String: String, using key: SymmetricKey) throws -> String {
        guard let combined = Data(base64Encoded: base64String) else {
            throw CryptoError.invalidPayload
        }
        do {
            let sealed = try AES.GCM.SealedBox(combined: combined)
            let opened = try AES.GCM.open(sealed, using: key)
            guard let plaintext = String(data: opened, encoding: .utf8) else {
                throw CryptoError.invalidPayload
            }
            return plaintext
        } catch {
            logger.error("AES.GCM open failed: \(String(describing: error), privacy: .public)")
            throw CryptoError.decryptionFailed
        }
    }

    /// 密钥派生：基于设备标识 + 可选密码（PBKDF2 替代方案，使用 HKDF）
    static func deriveKey(from material: Data, salt: Data = Data("Visor.salt.v1".utf8)) -> SymmetricKey {
        let inputKey = SymmetricKey(data: material)
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: salt,
            info: Data("Visor.derived.v1".utf8),
            outputByteCount: 32
        )
    }
}
