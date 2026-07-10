import Foundation
import os.log

/// 文件工具集：FileWrite / FileRead / FileList / FileRemove / FileMkdir
/// 以 OpenAI Function Calling 形式暴露给模型；
/// 同时支持 CLI 块（`<visor-cli>`）调用路径
nonisolated struct FileTools {

    private static let logger = Logger(subsystem: "com.lyrastudio.Visor", category: "FileTools")

    // MARK: - Tool Definitions

    /// 全部工具定义（用于发给模型）
    /// file_patch 排在首位，引导模型优先使用局部替换而非全量覆盖
    static var all: [ToolDefinition] {
        [filePatch, fileWrite, fileRead, fileList, fileRemove, fileMkdir]
    }

    static var fileWrite: ToolDefinition {
        ToolDefinition.function(
            name: "file_write",
            description: "tool.desc.fileWrite".l,
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "path": .object([
                        "type": .string("string"),
                        "description": .string("tool.desc.fileWrite.path".l)
                    ]),
                    "content": .object([
                        "type": .string("string"),
                        "description": .string("tool.desc.fileWrite.content".l)
                    ])
                ]),
                "required": .array([.string("path"), .string("content")])
            ])
        )
    }

    static var filePatch: ToolDefinition {
        ToolDefinition.function(
            name: "file_patch",
            description: "tool.desc.filePatch".l,
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "path": .object([
                        "type": .string("string"),
                        "description": .string("tool.desc.filePatch.path".l)
                    ]),
                    "search": .object([
                        "type": .string("string"),
                        "description": .string("tool.desc.filePatch.search".l)
                    ]),
                    "replace": .object([
                        "type": .string("string"),
                        "description": .string("tool.desc.filePatch.replace".l)
                    ])
                ]),
                "required": .array([.string("path"), .string("search"), .string("replace")])
            ])
        )
    }

    static var fileRead: ToolDefinition {
        ToolDefinition.function(
            name: "file_read",
            description: "tool.desc.fileRead".l,
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "path": .object([
                        "type": .string("string"),
                        "description": .string("tool.desc.fileRead.path".l)
                    ])
                ]),
                "required": .array([.string("path")])
            ])
        )
    }

    static var fileList: ToolDefinition {
        ToolDefinition.function(
            name: "file_list",
            description: "tool.desc.fileList".l,
            parameters: .object([
                "type": .string("object"),
                "properties": .object([:]),
                "required": .array([])
            ])
        )
    }

    static var fileRemove: ToolDefinition {
        ToolDefinition.function(
            name: "file_remove",
            description: "tool.desc.fileRemove".l,
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "path": .object([
                        "type": .string("string"),
                        "description": .string("tool.desc.fileRemove.path".l)
                    ])
                ]),
                "required": .array([.string("path")])
            ])
        )
    }

    static var fileMkdir: ToolDefinition {
        ToolDefinition.function(
            name: "file_mkdir",
            description: "tool.desc.fileMkdir".l,
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "path": .object([
                        "type": .string("string"),
                        "description": .string("tool.desc.fileMkdir.path".l)
                    ])
                ]),
                "required": .array([.string("path")])
            ])
        )
    }

    // MARK: - 执行

    /// 执行一个 tool_call。返回 JSON 字符串（OpenAI tool 消息的 content 字段）
    static func execute(
        name: String,
        argumentsJSON: String,
        fs: FileSystemStore,
        sessionId: UUID
    ) -> String {
        do {
            let args = try parseArgs(argumentsJSON)
            switch name {
            case "file_write":
                let path = args["path"] as? String ?? ""
                let content = args["content"] as? String ?? ""
                let entry = try fs.write(content: content, to: path)
                FileSystemNotifier.shared.notify(sessionId: sessionId, path: path, kind: .write)
                return successJSON([
                    "ok": true,
                    "path": entry.path,
                    "size": entry.size
                ])
            case "file_patch":
                let path = args["path"] as? String ?? ""
                let search = args["search"] as? String ?? ""
                let replace = args["replace"] as? String ?? ""
                return applyPatch(fs: fs, sessionId: sessionId, path: path, search: search, replace: replace)
            case "file_read":
                let path = args["path"] as? String ?? ""
                let text = try fs.read(path)
                return successJSON([
                    "ok": true,
                    "path": path,
                    "content": text
                ])
            case "file_list":
                let entries = try fs.list()
                let arr = entries.map { e -> [String: Any] in
                    [
                        "path": e.path,
                        "size": e.size,
                        "modifiedAt": ISO8601DateFormatter().string(from: e.modifiedAt)
                    ]
                }
                return successJSON(["ok": true, "files": arr])
            case "file_remove":
                let path = args["path"] as? String ?? ""
                let removed = try fs.remove(path)
                FileSystemNotifier.shared.notify(sessionId: sessionId, path: path, kind: .remove)
                return successJSON(["ok": true, "path": path, "removed": removed])
            case "file_mkdir":
                let path = args["path"] as? String ?? ""
                let url = try fs.absoluteURL(for: path)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                return successJSON(["ok": true, "path": path])
            default:
                return errorJSON("unknown_tool", "tool.error.unknown".l(name))
            }
        } catch {
            return errorJSON("exec_error", "\(error)")
        }
    }

    /// 执行 CLI 块（流式解析后调用）
    @discardableResult
    static func executeCLI(
        _ command: CLIParser.Command,
        fs: FileSystemStore,
        sessionId: UUID
    ) -> String {
        switch command {
        case .write(let path, let content):
            do {
                let entry = try fs.write(content: content, to: path)
                FileSystemNotifier.shared.notify(sessionId: sessionId, path: path, kind: .write)
                return "✓ wrote \(entry.path) (\(entry.size) bytes)"
            } catch {
                return "✗ write failed: \(error)"
            }
        case .patch(let path, let search, let replace):
            return applyPatch(fs: fs, sessionId: sessionId, path: path, search: search, replace: replace)
        case .read(let path):
            do {
                let text = try fs.read(path)
                return text
            } catch {
                return "✗ read failed: \(error)"
            }
        case .remove(let path):
            do {
                let removed = try fs.remove(path)
                FileSystemNotifier.shared.notify(sessionId: sessionId, path: path, kind: .remove)
                return "✓ removed \(path) (existed=\(removed))"
            } catch {
                return "✗ remove failed: \(error)"
            }
        case .list:
            do {
                let entries = try fs.list()
                if entries.isEmpty {
                    return "(empty)"
                }
                return entries.map { "\($0.path)  \($0.size)B" }.joined(separator: "\n")
            } catch {
                return "✗ ls failed: \(error)"
            }
        case .mkdir(let path):
            do {
                let url = try fs.absoluteURL(for: path)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                return "✓ mkdir \(path)"
            } catch {
                return "✗ mkdir failed: \(error)"
            }
        case .unknown(let name, let raw):
            return "✗ unknown command: \(name) — \(raw.prefix(80))"
        }
    }

    // MARK: - 局部替换核心逻辑（函数调用与 CLI 共用）

    /// 对文件执行 SEARCH/REPLACE 局部替换
    /// - 要求 search 在文件中唯一匹配；0 或多次匹配均失败
    private static func applyPatch(
        fs: FileSystemStore,
        sessionId: UUID,
        path: String,
        search: String,
        replace: String
    ) -> String {
        guard !path.isEmpty else {
            return errorJSON("invalid_args", "tool.error.pathEmpty".l)
        }
        guard !search.isEmpty else {
            return errorJSON("invalid_args", "tool.error.searchEmpty".l)
        }
        guard fs.exists(path) else {
            return errorJSON("not_found", "tool.error.fileNotFound".l(path))
        }

        let original: String
        do {
            original = try fs.read(path)
        } catch {
            return errorJSON("read_error", "tool.error.readFailed".l("\(error)"))
        }

        let matchCount = Self.occurrences(of: search, in: original)
        if matchCount == 0 {
            return errorJSON("not_found", "tool.error.searchNotFound".l)
        }
        if matchCount > 1 {
            return errorJSON("ambiguous", "tool.error.searchAmbiguous".l(matchCount))
        }

        guard let range = original.range(of: search) else {
            return errorJSON("internal", "tool.error.internalReplace".l)
        }
        let updated = original.replacingCharacters(in: range, with: replace)

        do {
            let entry = try fs.write(content: updated, to: path)
            FileSystemNotifier.shared.notify(sessionId: sessionId, path: path, kind: .write)
            return successJSON([
                "path": entry.path,
                "size": entry.size,
                "replaced": 1
            ])
        } catch {
            return errorJSON("write_error", "tool.error.writeFailed".l("\(error)"))
        }
    }

    /// 统计子串出现次数（非正则，逐次推进 upperBound）
    private static func occurrences(of needle: String, in haystack: String) -> Int {
        var count = 0
        var searchStart = haystack.startIndex
        while searchStart < haystack.endIndex,
              let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            count += 1
            searchStart = range.upperBound
        }
        return count
    }

    // MARK: - JSON 工具

    private static func parseArgs(_ json: String) throws -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return obj
    }

    private static func successJSON(_ obj: [String: Any]) -> String {
        var withOk = obj
        withOk["ok"] = true
        guard let data = try? JSONSerialization.data(withJSONObject: withOk, options: [.sortedKeys]),
              let s = String(data: data, encoding: .utf8) else {
            return "{\"ok\":true}"
        }
        return s
    }

    private static func errorJSON(_ code: String, _ message: String) -> String {
        let obj: [String: Any] = ["ok": false, "error": code, "message": message]
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
              let s = String(data: data, encoding: .utf8) else {
            return "{\"ok\":false}"
        }
        return s
    }
}
