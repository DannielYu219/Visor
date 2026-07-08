import SwiftUI
@preconcurrency import WebKit
import os.log

/// 画布渲染设置 UserDefaults keys
private let kCanvasWidth  = "canvas_preview_width"
private let kCanvasHeight = "canvas_preview_height"
private let kCanvasRadius = "canvas_preview_radius"

/// 设计画布：WebKit 渲染 session 工作目录中的文件
struct DesignCanvasView: View {
    let sessionId: UUID
    let skillName: String?
    /// 当前画布渲染的相对路径（内部管理，通过 FileSystemNotifier 切换）
    @State private var activePath: String = ""

    @State private var showSource: Bool = false
    @State private var showSettings: Bool = false
    @State private var showFileManager: Bool = false
    @State private var reloadTrigger: Int = 0
    @State private var copyToast: String?
    @State private var fileList: [FileSystemStore.FileEntry] = []
    @State private var currentHTML: String = ""

    // 画布渲染设置（0 = 填满容器）
    @State private var canvasWidth: Double = UserDefaults.standard.double(forKey: kCanvasWidth)
    @State private var canvasHeight: Double = UserDefaults.standard.double(forKey: kCanvasHeight)
    @State private var canvasRadius: Double = UserDefaults.standard.double(forKey: kCanvasRadius)

    // 画布容器实际尺寸（用于动态 max radius）
    @State private var containerSize: CGSize = .zero

    private let logger = Logger(subsystem: "com.lyrastudio.Visor", category: "DesignCanvasView")
    private let defaultsRadius: CGFloat = 16

    /// 实际预览尺寸（0 则用容器尺寸）
    private var previewSize: CGSize {
        let w = canvasWidth  > 0 ? canvasWidth  : containerSize.width
        let h = canvasHeight > 0 ? canvasHeight : containerSize.height
        return CGSize(width: max(w, 1), height: max(h, 1))
    }

    /// 圆角最大值 = min(w, h) / 2（模拟手表/音箱等异形屏）
    private var maxRadius: Double {
        let s = previewSize
        return Double(min(s.width, s.height) / 2)
    }

    /// 是否填满容器
    private var isFillContainer: Bool { canvasWidth <= 0 && canvasHeight <= 0 }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            webView
        }
        .background(
            GeometryReader { geo in
                Color.clear.onAppear {
                    containerSize = geo.size
                }.onChange(of: geo.size) { _, new in
                    containerSize = new
                }
            }
        )
        .glassBackground(corner: DesignTokens.Radius.l)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: sessionId) {
            await reload()
            subscribe()
        }
        .popover(isPresented: $showSettings) {
            canvasSettingsPopover
        }
        .sheet(isPresented: $showFileManager) {
            FileManagerSheet(sessionId: sessionId) { url in
                importFile(url)
            }
            .presentationDetents([.large])
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: DesignTokens.Spacing.m) {
            HStack(spacing: 6) {
                Image(systemName: "paintbrush.pointed.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                Text(activePath.isEmpty ? "设计画布" : (activePath as NSString).lastPathComponent)
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

            HStack(spacing: DesignTokens.Spacing.m) {
                CircularGlassButton(systemName: "folder.badge.gearshape", action: {
                    showFileManager = true
                })
                .accessibilityLabel("文件管理")

                CircularGlassButton(systemName: "arrow.clockwise", action: {
                    reloadTrigger += 1
                })
                .accessibilityLabel("刷新画布")

                CircularGlassButton(
                    systemName: showSource ? "eye.slash" : "chevron.left.forwardslash.chevron.right",
                    action: { showSource.toggle() }
                )
                .accessibilityLabel("显示 / 隐藏源代码")

                CircularGlassButton(systemName: "square.and.arrow.up", action: {
                    exportHTML()
                })
                .accessibilityLabel("导出 HTML")

                CircularGlassButton(systemName: "gearshape", action: {
                    showSettings.toggle()
                })
                .accessibilityLabel("画布设置")
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.l)
        .padding(.vertical, DesignTokens.Spacing.s)
    }

    // MARK: - Canvas Settings Popover

    private var canvasSettingsPopover: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
            Text("画布渲染设置")
                .font(.visorTitle)

            if !isFillContainer {
                Text("当前预览: \(Int(previewSize.width)) × \(Int(previewSize.height))")
                    .font(.visorCaption)
                    .foregroundStyle(.secondary)
            } else {
                Text("填满画布，尺寸随窗口自适应")
                    .font(.visorCaption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                Text("预览宽度 (px，0 = 填满)")
                    .font(.visorCaption)
                    .foregroundStyle(.secondary)
                TextField("填满", value: $canvasWidth, format: .number)
                    .font(.visorBody)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .onChange(of: canvasWidth) { _, new in
                        UserDefaults.standard.set(Double(new), forKey: kCanvasWidth)
                    }
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                Text("预览高度 (px，0 = 填满)")
                    .font(.visorCaption)
                    .foregroundStyle(.secondary)
                TextField("填满", value: $canvasHeight, format: .number)
                    .font(.visorBody)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .onChange(of: canvasHeight) { _, new in
                        UserDefaults.standard.set(Double(new), forKey: kCanvasHeight)
                    }
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                Text("圆角 (pt，最大 \(Int(maxRadius)))")
                    .font(.visorCaption)
                    .foregroundStyle(.secondary)
                TextField("\(Int(defaultsRadius))", value: $canvasRadius, format: .number)
                    .font(.visorBody)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .onChange(of: canvasRadius) { _, new in
                        // 钳位到 [0, maxRadius]
                        let clamped = min(max(new, 0), maxRadius)
                        if clamped != new {
                            canvasRadius = clamped
                        }
                        UserDefaults.standard.set(Double(clamped), forKey: kCanvasRadius)
                    }
            }

            HStack {
                Button("复位 — 填满画布") {
                    canvasWidth  = 0
                    canvasHeight = 0
                    canvasRadius = defaultsRadius
                    UserDefaults.standard.set(0.0, forKey: kCanvasWidth)
                    UserDefaults.standard.set(0.0, forKey: kCanvasHeight)
                    UserDefaults.standard.set(Double(defaultsRadius), forKey: kCanvasRadius)
                }
                .font(.visorCaption)

                Spacer()
            }
        }
        .padding(DesignTokens.Spacing.xxl)
        .frame(idealWidth: 320)
        .presentationCompactAdaptation(.popover)
    }

    // MARK: - WebView

    private var webView: some View {
        Group {
            if isFillContainer {
                // 填满容器，无固定 frame
                CanvasWebView(
                    html: currentHTML,
                    reloadTrigger: reloadTrigger,
                    viewportWidth: Int(previewSize.width),
                    viewportHeight: Int(previewSize.height)
                )
                .clipShape(RoundedRectangle(cornerRadius: CGFloat(canvasRadius), style: .continuous))
            } else {
                // 固定尺寸 + 居中
                CanvasWebView(
                    html: currentHTML,
                    reloadTrigger: reloadTrigger,
                    viewportWidth: Int(previewSize.width),
                    viewportHeight: Int(previewSize.height)
                )
                .frame(width: previewSize.width, height: previewSize.height)
                .clipShape(RoundedRectangle(cornerRadius: CGFloat(canvasRadius), style: .continuous))
                .background(
                    RoundedRectangle(cornerRadius: CGFloat(canvasRadius), style: .continuous)
                        .fill(Color.visorBackground)
                        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
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
                .font(.system(size: 13, design: .monospaced))
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
        Task { @MainActor in
            for await switchPath in FileSystemNotifier.shared.notifications(for: sessionId) {
                if let path = switchPath {
                    // switchTo=true：切换画布渲染目标
                    activePath = path
                    await reload()
                } else {
                    // 普通文件变更：仅刷新当前文件
                    await reload()
                }
            }
        }
    }

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
            presentShareSheet(url: url)
        } catch {
            withAnimation { copyToast = "导出失败：\(error.localizedDescription)" }
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await MainActor.run { withAnimation { copyToast = nil } }
            }
        }
    }

    /// 从外部 URL 导入文件到 session 沙盒
    private func importFile(_ url: URL) {
        let sid = sessionId
        Task {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                await MainActor.run { copyToast = "无法读取文件（可能不是 UTF-8 文本）" }
                return
            }
            guard content.utf8.count < 1_000_000 else {
                await MainActor.run { copyToast = "文件过大（>1MB）" }
                return
            }

            let filename = url.lastPathComponent
            do {
                let fs = try FileSystemStore(sessionId: sid)
                let isHTML = filename.lowercased().hasSuffix(".html")
                _ = try fs.write(content: content, to: filename)
                FileSystemNotifier.shared.notify(
                    sessionId: sid, path: filename, kind: .write, switchTo: isHTML
                )
                await MainActor.run {
                    copyToast = "✓ 已导入：\(filename)"
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        await MainActor.run { withAnimation { copyToast = nil } }
                    }
                }
            } catch {
                await MainActor.run { copyToast = "导入失败：\(error.localizedDescription)" }
            }
        }
    }

    private func presentShareSheet(url: URL) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
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
    let viewportWidth: Int
    let viewportHeight: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.clipsToBounds = true
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
        let injected = injectViewport(html)
        view.loadHTMLString(injected, baseURL: nil)
    }

    /// 在 <head> 中注入 viewport meta
    private func injectViewport(_ raw: String) -> String {
        let meta = "<meta name=\"viewport\" content=\"width=\(viewportWidth), height=\(viewportHeight), initial-scale=1.0\">"
        if raw.contains("<meta name=\"viewport\"") {
            return raw.replacingOccurrences(
                of: "<meta name=\"viewport\"[^>]*>",
                with: meta,
                options: .regularExpression
            )
        }
        if let headRange = raw.range(of: "<head>", options: .caseInsensitive)
            ?? raw.range(of: "<head ", options: .caseInsensitive) {
            let insertPos = raw[headRange].hasSuffix(">") ? headRange.upperBound : headRange.upperBound
            var result = raw
            result.insert(contentsOf: meta, at: insertPos)
            return result
        }
        return "<head>\(meta)</head>" + raw
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
