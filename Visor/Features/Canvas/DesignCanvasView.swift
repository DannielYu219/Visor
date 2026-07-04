import SwiftUI
@preconcurrency import WebKit
import os.log

/// 设计画布：WebKit 渲染 session 工作目录中的文件
/// - 数据源：FileSystemStore + 订阅 FileSystemNotifier 实时刷新
/// - 默认渲染 index.html（如存在）
struct DesignCanvasView: View {
    let sessionId: UUID
    let activePath: String   // Agent 选中的入口路径
    let skillName: String?

    @State private var showSource: Bool = false
    @State private var reloadTrigger: Int = 0
    @State private var copyToast: String?
    @State private var fileList: [FileSystemStore.FileEntry] = []
    @State private var currentHTML: String = ""
    private let logger = Logger(subsystem: "com.lyrastudio.Visor", category: "DesignCanvasView")

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.2)
            webView
        }
        .glassBackground(corner: DesignTokens.Radius.m)
        .task(id: sessionId) {
            await reload()
            subscribe()
        }
        .onChange(of: activePath) { _, _ in
            Task { await reload() }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: DesignTokens.Spacing.s) {
            HStack(spacing: 6) {
                Image(systemName: "paintbrush.pointed.fill")
                    .foregroundStyle(.secondary)
                Text(activePath.isEmpty ? "设计画布" : activePath)
                    .font(.visorBody)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let skill = skillName {
                    Text("· \(skill)")
                        .font(.visorCaption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()

            // 文件切换
            if !fileList.isEmpty {
                Menu {
                    ForEach(fileList, id: \.path) { entry in
                        Button {
                            Task { await switchTo(entry.path) }
                        } label: {
                            HStack {
                                Text(entry.path)
                                if entry.path == activePath {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "doc.text")
                        .font(.system(size: 14))
                }
            }

            Button {
                reloadTrigger += 1
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14))
            }
            .accessibilityLabel("刷新画布")

            Button {
                showSource.toggle()
            } label: {
                Image(systemName: showSource ? "eye.slash" : "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 14))
            }
            .accessibilityLabel("显示 / 隐藏源代码")

            Button {
                copyHTML()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 14))
            }
            .accessibilityLabel("复制 HTML 源码")
        }
        .padding(.horizontal, DesignTokens.Spacing.l)
        .padding(.vertical, DesignTokens.Spacing.s)
    }

    // MARK: - WebView

    private var webView: some View {
        CanvasWebView(html: currentHTML, reloadTrigger: reloadTrigger)
            .overlay(alignment: .top) {
                if showSource {
                    sourcePanel
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .overlay(alignment: .bottom) {
                if let toast = copyToast {
                    Text(toast)
                        .font(.visorCaption)
                        .padding(.horizontal, DesignTokens.Spacing.l)
                        .padding(.vertical, DesignTokens.Spacing.s)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, DesignTokens.Spacing.l)
                        .transition(.opacity)
                }
            }
            .overlay {
                if currentHTML.isEmpty {
                    emptyState
                }
            }
    }

    private var emptyState: some View {
        VStack(spacing: DesignTokens.Spacing.m) {
            Image(systemName: "rectangle.dashed")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("画布为空")
                .font(.visorTitle)
            Text("在下方聊天框输入设计需求")
                .font(.visorBody)
                .foregroundStyle(.secondary)
        }
    }

    private var sourcePanel: some View {
        ScrollView {
            Text(currentHTML.isEmpty ? "（无内容）" : currentHTML)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DesignTokens.Spacing.l)
        }
        .frame(maxHeight: 240)
        .background(.regularMaterial)
    }

    // MARK: - Actions

    private func reload() async {
        do {
            let fs = try FileSystemStore(sessionId: sessionId)
            fileList = try fs.list()
            let path = activePath.isEmpty ? "index.html" : activePath
            if fs.exists(path) {
                currentHTML = try fs.read(path)
            } else {
                currentHTML = ""
            }
        } catch {
            logger.error("Canvas reload failed: \(String(describing: error), privacy: .public)")
            currentHTML = ""
        }
    }

    private func switchTo(_ path: String) async {
        do {
            let fs = try FileSystemStore(sessionId: sessionId)
            if fs.exists(path) {
                currentHTML = try fs.read(path)
                reloadTrigger += 1
            }
        } catch {
            logger.error("Switch failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func subscribe() {
        // 文件变更时自动刷新
        Task { @MainActor in
            for await note in FileSystemNotifier.shared.notifications(for: sessionId) {
                await reload()
                _ = note
            }
        }
    }

    private func copyHTML() {
        UIPasteboard.general.string = currentHTML
        withAnimation { copyToast = "已复制 \(activePath)（\(currentHTML.utf8.count) 字节）" }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                withAnimation { copyToast = nil }
            }
        }
    }
}

// MARK: - WKWebView Wrapper

private struct CanvasWebView: UIViewRepresentable {
    let html: String
    let reloadTrigger: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.allowsBackForwardNavigationGestures = false
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.lastLoadedHTML != html
            || context.coordinator.lastReloadTrigger != reloadTrigger {
            context.coordinator.lastLoadedHTML = html
            context.coordinator.lastReloadTrigger = reloadTrigger
            load(html: html, into: uiView)
        }
    }

    private func load(html: String, into view: WKWebView) {
        guard !html.isEmpty else {
            view.loadHTMLString("<html><body style='background:transparent'></body></html>", baseURL: nil)
            return
        }
        view.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastLoadedHTML: String = ""
        var lastReloadTrigger: Int = 0

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.targetFrame == nil {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
