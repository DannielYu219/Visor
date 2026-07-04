import Foundation
import os.log

/// 文件工具集：FileWrite / FileRead / FileList / FileRemove / FileMkdir
/// 以 OpenAI Function Calling 形式暴露给模型；
/// 同时支持 CLI 块（`<visor-cli>`）调用路径
nonisolated struct FileTools {

    private static let logger = Logger(subsystem: "com.lyrastudio.Visor", category: "FileTools")

    // MARK: - Tool Definitions

    /// 全部工具定义（用于发给模型）
    static var all: [ToolDefinition] {
        [fileWrite, fileRead, fileList, fileRemove, fileMkdir]
    }

    static var fileWrite: ToolDefinition {
        ToolDefinition.function(
            name: "file_write",
            description: """
            写入或覆盖一个文件到当前 session 的工作目录。路径相对于 session 根，例如 "index.html"、"assets/style.css"。
            用于把设计稿（HTML/CSS/JS）落到文件系统，画布会实时刷新预览。
            """,
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "path": .object([
                        "type": .string("string"),
                        "description": .string("相对路径，例如 index.html")
                    ]),
                    "content": .object([
                        "type": .string("string"),
                        "description": .string("UTF-8 文本内容")
                    ])
                ]),
                "required": .array([.string("path"), .string("content")])
            ])
        )
    }

    static var fileRead: ToolDefinition {
        ToolDefinition.function(
            name: "file_read",
            description: "读取 session 工作目录中的一个文件，返回 UTF-8 文本内容。",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "path": .object([
                        "type": .string("string"),
                        "description": .string("相对路径")
                    ])
                ]),
                "required": .array([.string("path")])
            ])
        )
    }

    static var fileList: ToolDefinition {
        ToolDefinition.function(
            name: "file_list",
            description: "列出 session 工作目录中的所有文件（含子目录），返回 JSON 数组。",
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
            description: "删除一个文件。",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "path": .object([
                        "type": .string("string"),
                        "description": .string("相对路径")
                    ])
                ]),
                "required": .array([.string("path")])
            ])
        )
    }

    static var fileMkdir: ToolDefinition {
        ToolDefinition.function(
            name: "file_mkdir",
            description: "创建子目录（支持嵌套路径）。",
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "path": .object([
                        "type": .string("string"),
                        "description": .string("相对路径")
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
                return errorJSON("unknown_tool", "工具不存在：\(name)")
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
