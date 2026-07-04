import Foundation
import os.log

/// HTML Capture Tool
/// 职责：从模型流式输出中提取 ```html ... ``` 围栏
/// 输出：通知 AgentRuntime 刷新 WebKit
struct HTMLCaptureTool: Tool {
    let name = "html_capture"
    let displayName = "HTML 捕获"
    let toolDescription = "从模型输出中提取完整 HTML 文档并刷新画布"
    let riskLevel: RiskLevel = .low

    private let logger = Logger(subsystem: "com.lyrastudio.Visor", category: "HTMLCaptureTool")

    /// 围栏开始标记
    private static let fenceOpen = "```html"
    private static let fenceClose = "```"

    /// 从完整文本中提取最后一个 HTML 围栏内容
    /// - Returns: 若有围栏则返回 HTML；否则返回 nil
    func execute(input: String) async throws -> ToolResult {
        guard let html = Self.extractLastHTML(from: input) else {
            return ToolResult(message: "未发现 HTML 围栏", error: nil)
        }
        // 安全检查：大小限制（防 OOM）
        let maxBytes = 200_000
        guard html.utf8.count <= maxBytes else {
            let truncated = String(html.prefix(maxBytes))
            logger.error("HTML 超出 \(maxBytes) 字节，已截断")
            return ToolResult(
                capturedHTML: truncated,
                message: "HTML 超 200KB，已截断",
                error: nil
            )
        }
        // DOCTYPE 检查（必须以 <!DOCTYPE html> 或 <html 开头）
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        guard lower.hasPrefix("<!doctype html") || lower.hasPrefix("<html") else {
            return ToolResult(
                message: "HTML 围栏存在但缺少 <!DOCTYPE html> / <html>",
                error: "invalid_html_structure"
            )
        }
        return ToolResult(
            capturedHTML: trimmed,
            message: "已捕获 HTML（\(html.utf8.count) 字节）",
            error: nil
        )
    }

    /// 提取最后一个完整的 ```html ... ``` 围栏
    static func extractLastHTML(from text: String) -> String? {
        // 从尾部向前扫描 ```html 标记
        var searchStart = text.endIndex
        while let fenceStartRange = text.range(of: fenceOpen, options: .backwards, range: text.startIndex..<searchStart) {
            // 跳过 fenceOpen 后的换行
            let contentStart = text.index(after: fenceStartRange.upperBound)
            // 如果紧跟换行，跳过
            let actualStart: String.Index
            if contentStart < text.endIndex, text[contentStart] == "\n" {
                actualStart = text.index(after: contentStart)
            } else {
                actualStart = contentStart
            }
            // 向后找 fenceClose
            let rest = text[actualStart...]
            if let fenceEndRange = rest.range(of: fenceClose) {
                let contentEnd = fenceEndRange.lowerBound
                return String(text[actualStart..<contentEnd])
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
            }
            // 否则继续向前找更早的 fenceOpen
            searchStart = fenceStartRange.lowerBound
        }
        return nil
    }
}
