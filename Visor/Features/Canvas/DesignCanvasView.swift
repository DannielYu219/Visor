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
            webView
        }
        .glassBackground(corner: DesignTokens.Radius.m)
        .toolbar(.hidden, for: .navigationBar)
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
            // 左：标题
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

            // 右：四个独立圆形 Liquid Glass 按钮
            HStack(spacing: DesignTokens.Spacing.s) {
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
                        circularButtonIcon(systemName: "doc.text")
                    }
                    .accessibilityLabel("切换文件")
                }

                // 刷新
                Button {
                    reloadTrigger += 1
                } label: {
                    circularButtonIcon(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("刷新画布")

                // 源代码切换
                Button {
                    showSource.toggle()
                } label: {
                    circularButtonIcon(systemName: showSource ? "eye.slash" : "chevron.left.forwardslash.chevron.right")
                }
                .accessibilityLabel("显示 / 隐藏源代码")

                // 导出
                Button {
                    exportHTML()
                } label: {
                    circularButtonIcon(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("导出 HTML")
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.l)
        .padding(.top, DesignTokens.Spacing.s)
        .padding(.bottom, DesignTokens.Spacing.s)
    }

    /// 圆形 Liquid Glass 按钮（48pt 触控区）
    private func circularButtonIcon(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .medium))
            .frame(width: 44, height: 44)
            .foregroundStyle(.primary)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
            .contentShape(Circle())
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

    /// 导出当前 HTML 到临时文件并弹出 Share Sheet
    private func exportHTML() {
        guard !currentHTML.isEmpty else {
            withAnimation { copyToast = "画布为空，无内容可导出" }
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await MainActor.run { withAnimation { copyToast = nil } }
            }
            return
        }
        let fileName = (activePath as NSString).lastPathComponent.isEmpty ? "index.html" : (activePath as NSString).lastPathComponent
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("Visor_\(fileName)")
        do {
            try currentHTML.write(to: url, atomically: true, encoding: .utf8)
            // 直接通过 rootViewController present UIActivityViewController
            presentShareSheet(url: url)
        } catch {
            withAnimation { copyToast = "导出失败：\(error.localizedDescription)" }
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await MainActor.run { withAnimation { copyToast = nil } }
            }
        }
    }

    /// 通过 UIWindow rootViewController 弹出系统分享
    private func presentShareSheet(url: URL) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        // iPad 需要 popoverPresentationController
        if let pop = activityVC.popoverPresentationController {
            pop.sourceView = root.view
            pop.sourceRect = CGRect(x: root.view.bounds.midX, y: 40, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        root.present(activityVC, animated: true)
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
