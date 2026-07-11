import Foundation
import SwiftData
import os.log
import UIKit

/// Visor 会话项目导出/导入编解码器
///
/// 文件格式：`.visor`（本质是标准 ZIP，STORE 方法）
///
/// 包结构：
/// ```
/// manifest.json    — 格式版本、导出时间、应用版本
/// session.json     — 会话元数据（标题、模型、费用、时间戳）
/// messages.json    — 对话上下文（消息数组，按时间正序）
/// canvas.json      — 画布设定（宽/高/圆角）
/// files/           — 会话产物文件（HTML/CSS/JS/资源，保留相对路径）
/// ```
///
/// 设计原则：
/// - 零第三方依赖，复用 MiniZip（自制 ZIP 编解码器）
/// - 导入时生成新 UUID，避免与现有会话冲突
/// - 不导出 API Key、预算、审计日志等全局/敏感数据
/// - 不导出 ArtifactEntity（未实际使用，文件本体在 FileSystemStore）
@MainActor
enum VisorProjectCodec {

    /// 当前格式版本（向后兼容用）
    nonisolated static let formatVersion: Int = 1

    /// 文件扩展名
    nonisolated static let fileExtension = "visor"

    /// UTType 标识符（conforming to .zip，可在 Info.plist 中注册为导出类型）
    nonisolated static let utTypeIdentifier = "com.lyrastudio.Visor.project"

    private static let logger = Logger(subsystem: "com.lyrastudio.Visor", category: "VisorProjectCodec")

    // MARK: - Codable 结构

    struct Manifest: Codable {
        var formatVersion: Int
        var exportedAt: Date
        var appVersion: String
        var appBuild: String
    }

    struct SessionSnapshot: Codable {
        var title: String
        var modelId: String
        var createdAt: Date
        var updatedAt: Date
        var totalCostUSD: Double
        var totalInputTokens: Int
        var totalOutputTokens: Int
    }

    struct MessageSnapshot: Codable {
        var id: UUID
        var role: String
        var content: String
        var toolCallBody: String?
        var toolCallId: String?
        var attachments: String?
        var costUSD: Double
        var inputTokens: Int
        var outputTokens: Int
        var createdAt: Date
    }

    struct CanvasSnapshot: Codable {
        var width: Double
        var height: Double
        var radius: Double
    }

    enum CodecError: Error, LocalizedError {
        case noSession(UUID)
        case readFilesFailed(String)
        case writeFilesFailed(String)
        case decodeFailed(String)
        case manifestMissing
        case unsupportedVersion(Int)
        case sessionMissing

        var errorDescription: String? {
            switch self {
            case .noSession(let id):           return "会话不存在：\(id.uuidString)"
            case .readFilesFailed(let m):      return "读取会话文件失败：\(m)"
            case .writeFilesFailed(let m):     return "写入会话文件失败：\(m)"
            case .decodeFailed(let m):         return "解析 .visor 文件失败：\(m)"
            case .manifestMissing:             return "缺少 manifest.json，文件可能已损坏"
            case .unsupportedVersion(let v):   return "不支持的格式版本：\(v)（当前版本 \(formatVersion)）"
            case .sessionMissing:              return "缺少 session.json，文件可能已损坏"
            }
        }
    }

    // MARK: - Export

    /// 导出指定会话为 `.visor` 文件，返回临时文件 URL
    ///
    /// - Parameter sessionId: 要导出的会话 ID
    /// - Parameter context: SwiftData 上下文
    /// - Returns: 临时文件 URL（调用方负责分享/清理）
    static func export(sessionId: UUID, context: ModelContext) async throws -> URL {
        // 1. 读取会话实体
        guard let session = try fetchSession(id: sessionId, context: context) else {
            throw CodecError.noSession(sessionId)
        }

        // 2. 读取消息（按时间正序）
        let messages = try fetchMessages(id: sessionId, context: context)

        // 3. 读取画布设定（UserDefaults，按 session 隔离）
        let canvas = CanvasSnapshot(
            width:  UserDefaults.standard.double(forKey: "canvas_width_\(sessionId.uuidString)"),
            height: UserDefaults.standard.double(forKey: "canvas_height_\(sessionId.uuidString)"),
            radius: UserDefaults.standard.double(forKey: "canvas_radius_\(sessionId.uuidString)")
        )

        // 4. 读取会话产物文件（FileSystemStore）
        var fileEntries: [(name: String, data: Data)] = []
        do {
            let fs = try FileSystemStore(sessionId: sessionId)
            let list = try fs.list()
            for entry in list {
                let absURL = try fs.absoluteURL(for: entry.path)
                let data = try Data(contentsOf: absURL)
                // 统一使用正斜杠，ZIP 规范
                let zipName = "files/" + entry.path.replacingOccurrences(of: "\\", with: "/")
                fileEntries.append((name: zipName, data: data))
            }
        } catch {
            logger.error("读取会话文件失败：\(String(describing: error), privacy: .public)")
            // 文件读取失败不致命，继续导出（可能 session 目录尚未创建）
        }

        // 5. 序列化 JSON 条目
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let manifest = Manifest(
            formatVersion: formatVersion,
            exportedAt: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
            appBuild: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        )

        let sessionSnap = SessionSnapshot(
            title: session.title,
            modelId: session.modelId,
            createdAt: session.createdAt,
            updatedAt: session.updatedAt,
            totalCostUSD: session.totalCostUSD,
            totalInputTokens: session.totalInputTokens,
            totalOutputTokens: session.totalOutputTokens
        )

        let messageSnaps = messages.map { entity in
            MessageSnapshot(
                id: entity.id,
                role: entity.role,
                content: entity.content,
                toolCallBody: entity.toolCallBody,
                toolCallId: entity.toolCallId,
                attachments: entity.attachments,
                costUSD: entity.costUSD,
                inputTokens: entity.inputTokens,
                outputTokens: entity.outputTokens,
                createdAt: entity.createdAt
            )
        }

        var entries: [(name: String, data: Data)] = []
        entries.append((name: "manifest.json", data: try encoder.encode(manifest)))
        entries.append((name: "session.json", data: try encoder.encode(sessionSnap)))
        entries.append((name: "messages.json", data: try encoder.encode(messageSnaps)))
        entries.append((name: "canvas.json",  data: try encoder.encode(canvas)))
        entries.append(contentsOf: fileEntries)

        // 6. 打包 ZIP
        let zipData = try MiniZip.encode(entries)

        // 7. 写入临时文件
        let tempDir = FileManager.default.temporaryDirectory
        let safeTitle = sanitizeFilename(session.title)
        let filename = "\(safeTitle).\(fileExtension)"
        let url = tempDir.appendingPathComponent(filename)

        // 若同名临时文件已存在，先删除
        try? FileManager.default.removeItem(at: url)
        try zipData.write(to: url, options: .atomic)

        logger.info("导出成功：\(filename, privacy: .public)，\(zipData.count) 字节")
        return url
    }

    // MARK: - Import

    /// 导入 `.visor` 文件，创建新会话
    ///
    /// - Parameters:
    ///   - url: .visor 文件 URL（可能是 security-scoped）
    ///   - context: SwiftData 上下文
    ///   - selectHandler: 新会话创建后回调，用于 UI 切换选中
    /// - Returns: 新创建的会话 ID
    @discardableResult
    static func importProject(
        from url: URL,
        context: ModelContext,
        selectHandler: ((UUID) -> Void)? = nil
    ) async throws -> UUID {

        // 1. 读取文件（处理 security-scoped resource）
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let zipData: Data
        do {
            zipData = try Data(contentsOf: url)
        } catch {
            throw CodecError.decodeFailed(error.localizedDescription)
        }

        // 2. 解压
        let entries: [(name: String, data: Data)]
        do {
            entries = try MiniZip.decode(zipData)
        } catch {
            throw CodecError.decodeFailed(error.localizedDescription)
        }

        // 3. 解析条目
        var manifestData: Data?
        var sessionData: Data?
        var messagesData: Data?
        var canvasData: Data?
        var fileEntries: [(name: String, data: Data)] = []   // files/ 前缀

        for entry in entries {
            if entry.name == "manifest.json" { manifestData = entry.data }
            else if entry.name == "session.json" { sessionData = entry.data }
            else if entry.name == "messages.json" { messagesData = entry.data }
            else if entry.name == "canvas.json" { canvasData = entry.data }
            else if entry.name.hasPrefix("files/") {
                // 去掉 "files/" 前缀，恢复相对路径
                let rel = String(entry.name.dropFirst("files/".count))
                fileEntries.append((name: rel, data: entry.data))
            }
        }

        guard let manifestData else { throw CodecError.manifestMissing }
        guard let sessionData else { throw CodecError.sessionMissing }

        // 4. 解码 JSON
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let manifest: Manifest
        do { manifest = try decoder.decode(Manifest.self, from: manifestData) }
        catch { throw CodecError.decodeFailed("manifest.json: \(error.localizedDescription)") }

        // 版本兼容检查（当前仅支持 v1，未来高版本需向后迁移）
        guard manifest.formatVersion <= formatVersion else {
            throw CodecError.unsupportedVersion(manifest.formatVersion)
        }

        let sessionSnap: SessionSnapshot
        do { sessionSnap = try decoder.decode(SessionSnapshot.self, from: sessionData) }
        catch { throw CodecError.decodeFailed("session.json: \(error.localizedDescription)") }

        let messageSnaps: [MessageSnapshot]
        if let messagesData {
            do { messageSnaps = try decoder.decode([MessageSnapshot].self, from: messagesData) }
            catch { throw CodecError.decodeFailed("messages.json: \(error.localizedDescription)") }
        } else {
            messageSnaps = []
        }

        let canvas: CanvasSnapshot
        if let canvasData {
            do { canvas = try decoder.decode(CanvasSnapshot.self, from: canvasData) }
            catch { throw CodecError.decodeFailed("canvas.json: \(error.localizedDescription)") }
        } else {
            canvas = CanvasSnapshot(width: 0, height: 0, radius: 16)
        }

        // 5. 创建新会话（新 UUID 避免冲突）
        let newSessionId = UUID()
        let newSession = SessionEntity(
            id: newSessionId,
            title: sessionSnap.title,
            modelId: sessionSnap.modelId
        )
        newSession.createdAt = sessionSnap.createdAt
        newSession.updatedAt = Date()   // 导入即更新
        newSession.totalCostUSD = sessionSnap.totalCostUSD
        newSession.totalInputTokens = sessionSnap.totalInputTokens
        newSession.totalOutputTokens = sessionSnap.totalOutputTokens
        context.insert(newSession)

        // 6. 创建消息（保留原始 ID 以维持 toolCall 关联，保留原始时间戳维持顺序）
        for snap in messageSnaps {
            let entity = MessageEntity(
                id: snap.id,
                role: snap.role,
                content: snap.content,
                toolCallBody: snap.toolCallBody,
                toolCallId: snap.toolCallId,
                attachments: snap.attachments,
                costUSD: snap.costUSD,
                inputTokens: snap.inputTokens,
                outputTokens: snap.outputTokens
            )
            entity.createdAt = snap.createdAt
            entity.session = newSession
            context.insert(entity)
        }

        try context.save()

        // 7. 恢复画布设定（使用新 session UUID 作为 key）
        let defaults = UserDefaults.standard
        let keyPrefix = newSessionId.uuidString
        defaults.set(canvas.width,  forKey: "canvas_width_\(keyPrefix)")
        defaults.set(canvas.height, forKey: "canvas_height_\(keyPrefix)")
        defaults.set(canvas.radius, forKey: "canvas_radius_\(keyPrefix)")

        // 8. 恢复会话产物文件
        if !fileEntries.isEmpty {
            do {
                let fs = try FileSystemStore(sessionId: newSessionId)
                for entry in fileEntries {
                    // 跳过目录条目（以 / 结尾）
                    guard !entry.name.hasSuffix("/") else { continue }
                    // 写入文件（FileSystemStore 会自动创建子目录）
                    let text = String(data: entry.data, encoding: .utf8)
                    if let text {
                        _ = try fs.write(content: text, to: entry.name)
                    } else {
                        // 非 UTF-8 文件（如二进制资源）：直接写 Data
                        let absURL = try fs.absoluteURL(for: entry.name)
                        try FileManager.default.createDirectory(
                            at: absURL.deletingLastPathComponent(),
                            withIntermediateDirectories: true
                        )
                        try entry.data.write(to: absURL, options: .atomic)
                    }
                }
                logger.info("恢复 \(fileEntries.count) 个文件到 session \(newSessionId.uuidString, privacy: .public)")
            } catch {
                logger.error("恢复文件失败：\(String(describing: error), privacy: .public)")
                // 文件恢复失败不回滚已创建的会话（用户至少能看到对话历史）
            }
        }

        // 9. 通知 UI 切换到新会话
        selectHandler?(newSessionId)

        logger.info("导入成功：session \(newSessionId.uuidString, privacy: .public)，\(messageSnaps.count) 条消息")
        return newSessionId
    }

    // MARK: - 辅助

    /// 查询会话实体
    private static func fetchSession(id: UUID, context: ModelContext) throws -> SessionEntity? {
        let descriptor = FetchDescriptor<SessionEntity>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    /// 查询会话消息（按时间正序）
    private static func fetchMessages(id sessionId: UUID, context: ModelContext) throws -> [MessageEntity] {
        let descriptor = FetchDescriptor<MessageEntity>(
            predicate: #Predicate { $0.session?.id == sessionId },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    /// 将会话标题转换为安全的文件名
    private static func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = name
            .components(separatedBy: invalid)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // 限制长度，避免文件名过长
        let trimmed = cleaned.count > 40 ? String(cleaned.prefix(40)) : cleaned
        return trimmed.isEmpty ? "Visor-Session" : trimmed
    }
}
