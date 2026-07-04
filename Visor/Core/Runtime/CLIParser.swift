import Foundation
import os.log

/// visor-cli 解析器
/// 从模型流式输出中识别并提取 `<visor-cli>` 块，解析为结构化 CLI 命令
///
/// 块语法（XML 风格）：
/// ```
/// <visor-cli>
/// write path=index.html
/// <!DOCTYPE html>
/// <html>...</html>
/// </visor-cli>
///
/// <visor-cli>cat path=index.html</visor-cli>
///
/// <visor-cli>ls</visor-cli>
///
/// <visor-cli>rm path=old.html</visor-cli>
/// ```
///
/// 设计：
/// - 使用 O(n) 单遍扫描（与 AgentRunner 缓冲扫描相同的算法思路）
/// - 跳过未配对的开始标签（防 XML 截断）
/// - 命令名 + key=value 属性形式，body 部分作为 stdin / content
struct CLIParser {

    enum Command: Sendable, Equatable {
        case write(path: String, content: String)
        case read(path: String)
        case remove(path: String)
        case list
        case mkdir(path: String)
        case unknown(name: String, raw: String)
    }

    private static let openTag = "<visor-cli>"
    private static let closeTag = "</visor-cli>"

    private let logger = Logger(subsystem: "com.lyrastudio.Visor", category: "CLIParser")

    /// 从文本中提取所有完整的 CLI 块内容（不包含外层标签）
    /// - Returns: 块内容数组（按出现顺序）
    func extractBlocks(from text: String) -> [String] {
        var blocks: [String] = []
        var searchStart = text.startIndex
        while let openRange = text.range(of: Self.openTag, range: searchStart..<text.endIndex) {
            let afterOpen = openRange.upperBound
            if let closeRange = text.range(of: Self.closeTag, range: afterOpen..<text.endIndex) {
                let body = text[afterOpen..<closeRange.lowerBound]
                blocks.append(String(body))
                searchStart = closeRange.upperBound
            } else {
                // 未配对：跳过
                break
            }
        }
        return blocks
    }

    /// 解析单个 CLI 块为命令
    func parse(_ block: String) -> Command {
        // 块结构：第一行是命令（带 key=value 属性），后续行是 body
        let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .unknown(name: "", raw: block)
        }

        // 切分首行与 body
        let lines = trimmed.components(separatedBy: "\n")
        let firstLine = lines[0].trimmingCharacters(in: .whitespaces)
        let bodyLines = Array(lines.dropFirst())
        let body = bodyLines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 解析首行：cmd attr=value attr=value ...
        let tokens = firstLine.split(separator: " ", omittingEmptySubsequences: true)
        guard let cmd = tokens.first else {
            return .unknown(name: "", raw: block)
        }
        let attrs = Self.parseAttributes(String(tokens.dropFirst().joined(separator: " ")))

        switch cmd {
        case "write", "w":
            guard let path = attrs["path"] else {
                return .unknown(name: String(cmd), raw: block)
            }
            return .write(path: path, content: body)
        case "cat", "read":
            guard let path = attrs["path"] else {
                return .unknown(name: String(cmd), raw: block)
            }
            return .read(path: path)
        case "rm", "remove":
            guard let path = attrs["path"] else {
                return .unknown(name: String(cmd), raw: block)
            }
            return .remove(path: path)
        case "mkdir":
            guard let path = attrs["path"] else {
                return .unknown(name: String(cmd), raw: block)
            }
            return .mkdir(path: path)
        case "ls", "list":
            return .list
        default:
            return .unknown(name: String(cmd), raw: block)
        }
    }

    /// 解析 key=value 属性（值用单引号 / 双引号 / 无引号）
    private static func parseAttributes(_ s: String) -> [String: String] {
        var out: [String: String] = [:]
        var i = s.startIndex
        while i < s.endIndex {
            // 跳过空白
            while i < s.endIndex, s[i].isWhitespace { i = s.index(after: i) }
            if i >= s.endIndex { break }
            // 读 key
            let keyStart = i
            while i < s.endIndex, s[i] != "=", !s[i].isWhitespace {
                i = s.index(after: i)
            }
            let key = String(s[keyStart..<i])
            if i >= s.endIndex || s[i] != "=" { continue }
            i = s.index(after: i)  // 跳过 =
            // 读 value
            if i < s.endIndex, s[i] == "\"" || s[i] == "'" {
                let quote = s[i]
                i = s.index(after: i)
                let valStart = i
                while i < s.endIndex, s[i] != quote {
                    i = s.index(after: i)
                }
                out[key] = String(s[valStart..<i])
                if i < s.endIndex { i = s.index(after: i) }  // 跳过 closing quote
            } else {
                let valStart = i
                while i < s.endIndex, !s[i].isWhitespace {
                    i = s.index(after: i)
                }
                out[key] = String(s[valStart..<i])
            }
        }
        return out
    }

    // MARK: - 流式增量解析

    /// 流式解析上下文：在 delta 增量上识别并产出已闭合的块
    /// 设计：保留 holdback 防止 `<visor-cli>` 被截断
    final class StreamContext {
        private var buffer = ""
        private static let openTag = "<visor-cli>"
        private static let closeTag = "</visor-cli>"
        private static let maxBuffer = 16 * 1024

        /// 喂入一段 delta，返回这一段出现的完整 CLI 块
        /// - Returns: 块内容数组 + 未配对部分留在 buffer
        func feed(_ delta: String) -> [String] {
            buffer.append(delta)
            if buffer.count > Self.maxBuffer {
                // 防止无限增长：丢弃最早的字符
                buffer = String(buffer.suffix(Self.maxBuffer))
            }
            var blocks: [String] = []
            while let openRange = buffer.range(of: Self.openTag),
                  let closeRange = buffer.range(of: Self.closeTag, range: openRange.upperBound..<buffer.endIndex) {
                let body = String(buffer[openRange.upperBound..<closeRange.lowerBound])
                blocks.append(body)
                buffer = String(buffer[closeRange.upperBound..<buffer.endIndex])
            }
            // 保留尾部可能未闭合的 <visor-cli
            if let lastOpen = buffer.range(of: Self.openTag, options: .backwards) {
                buffer = String(buffer[lastOpen.lowerBound..<buffer.endIndex])
            } else if buffer.count > Self.openTag.count {
                // 没有任何 <visor-cli> 在尾部，保留 openTag 长度的尾作为 holdback
                buffer = String(buffer.suffix(Self.openTag.count))
            }
            return blocks
        }

        /// 收尾：处理残余 buffer
        func flush() -> [String] {
            let blocks: [String] = []
            buffer.removeAll(keepingCapacity: false)
            return blocks
        }
    }
}
