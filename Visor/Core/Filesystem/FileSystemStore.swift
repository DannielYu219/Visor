import Foundation
import os.log

/// 沙盒文件系统：每个 session 一个目录，存储 Agent 写入的 HTML / 资源文件
/// 设计：路径沙盒化（防止越权访问）、自动创建父目录、UTF-8 读写、原子写
/// 配合 ArtifactEntity（SwiftData 索引）使用
nonisolated struct FileSystemStore: Sendable {

    /// 单个文件元信息
    struct FileEntry: Sendable, Hashable {
        let path: String       // 相对 session 根，例如 "index.html" 或 "assets/style.css"
        let size: Int          // 字节
        let modifiedAt: Date
    }

    private let logger = Logger(subsystem: "com.lyrastudio.Visor", category: "FileSystemStore")

    /// session 工作根：<AppSupport>/Visor/sessions/<sessionId>/
    let rootURL: URL

    init(sessionId: UUID) throws {
        let fm = FileManager.default
        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let base = appSupport
            .appendingPathComponent("Visor", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(sessionId.uuidString, isDirectory: true)

        // 如果 base 路径上存在一个文件（而非目录），先删除它
        // 否则 createDirectory 会因"同名文件已存在"而失败（Code=516）
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: base.path, isDirectory: &isDir) {
            if !isDir.boolValue {
                // 是文件不是目录，删除后重建
                try? fm.removeItem(at: base)
            }
        }
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        self.rootURL = base
    }

    // MARK: - 路径解析

    /// 将相对路径解析为绝对 URL。拒绝越权（..）
    func absoluteURL(for relativePath: String) throws -> URL {
        let normalized = Self.normalize(relativePath)
        guard !normalized.contains("..") else {
            throw FileSystemError.pathTraversal(relativePath)
        }
        return rootURL.appendingPathComponent(normalized, isDirectory: false)
    }

    /// 相对路径的根目录 URL
    var rootDirectoryURL: URL { rootURL }

    // MARK: - 写

    /// 原子写：先写临时文件再 rename，避免半写状态
    func write(content: String, to relativePath: String) throws -> FileEntry {
        let url = try absoluteURL(for: relativePath)
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let tempURL = url.appendingPathExtension("tmp-\(UUID().uuidString.prefix(8))")
        do {
            try content.write(to: tempURL, atomically: true, encoding: .utf8)
            // 覆盖：先删目标（如果存在），再 move（保证原子性）
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try FileManager.default.moveItem(at: tempURL, to: url)
        } catch {
            // 清理临时文件
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
        return entry(for: relativePath) ?? FileEntry(path: relativePath, size: 0, modifiedAt: Date())
    }

    // MARK: - 读

    func read(_ relativePath: String) throws -> String {
        let url = try absoluteURL(for: relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// 文件存在？
    func exists(_ relativePath: String) -> Bool {
        guard let url = try? absoluteURL(for: relativePath) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - 列表

    /// 列出 session 内所有文件（递归）
    func list() throws -> [FileEntry] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var out: [FileEntry] = []
        for case let url as URL in enumerator {
            let attrs = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = attrs?.fileSize ?? 0
            let mtime = attrs?.contentModificationDate ?? Date()
            let rel = Self.relativePath(of: url, from: rootURL)
            out.append(FileEntry(path: rel, size: size, modifiedAt: mtime))
        }
        return out.sorted { $0.path < $1.path }
    }

    // MARK: - 元信息

    func entry(for relativePath: String) -> FileEntry? {
        guard let url = try? absoluteURL(for: relativePath) else { return nil }
        let attrs = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return FileEntry(
            path: relativePath,
            size: attrs?.fileSize ?? 0,
            modifiedAt: attrs?.contentModificationDate ?? Date()
        )
    }

    // MARK: - 删除

    @discardableResult
    func remove(_ relativePath: String) throws -> Bool {
        let url = try absoluteURL(for: relativePath)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
            return true
        }
        return false
    }

    // MARK: - 工具

    /// 规范化路径：去除前导 ./ 和多余分隔符
    static func normalize(_ path: String) -> String {
        var p = path.trimmingCharacters(in: .whitespaces)
        while p.hasPrefix("./") { p.removeFirst(2) }
        if p.hasPrefix("/") { p.removeFirst() }
        return p
    }

    static func relativePath(of url: URL, from base: URL) -> String {
        let urlPath = url.standardizedFileURL.path
        let basePath = base.standardizedFileURL.path
        if urlPath.hasPrefix(basePath) {
            var rel = String(urlPath.dropFirst(basePath.count))
            if rel.hasPrefix("/") { rel.removeFirst() }
            return rel
        }
        return url.lastPathComponent
    }
}

enum FileSystemError: Error, LocalizedError {
    case pathTraversal(String)

    var errorDescription: String? {
        switch self {
        case .pathTraversal(let p):
            return "路径越权：\(p)"
        }
    }
}
