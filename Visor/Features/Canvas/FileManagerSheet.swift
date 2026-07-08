import SwiftUI
import UniformTypeIdentifiers
import os.log

/// 文件管理 Sheet（画布工具栏入口）
/// 列出 session 内所有文件，支持切换/预览/导出/删除/上传
/// 触屏优先：行高 ≥56pt，大按钮，精简操作
struct FileManagerSheet: View {
    let sessionId: UUID
    /// 文件导入回调（由 DesignCanvasView 实现：写入 FileSystemStore）
    var onPickFile: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var files: [FileSystemStore.FileEntry] = []
    @State private var activePath: String = ""
    @State private var previewPath: String?
    @State private var previewContent: String = ""
    @State private var toast: String?
    @State private var showFilePicker: Bool = false

    private let logger = Logger(subsystem: "com.lyrastudio.Visor", category: "FileManagerSheet")

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                fileList

                Divider().opacity(0.2)

                bottomBar
            }
            .background(Color.visorBackground)
            .navigationTitle("文件管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .overlay(alignment: .top) {
                if let toast = toast {
                    Text(toast)
                        .font(.visorCaption)
                        .padding(.horizontal, DesignTokens.Spacing.l)
                        .padding(.vertical, DesignTokens.Spacing.s)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, DesignTokens.Spacing.s)
                        .transition(.opacity)
                        .task(id: toast) {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            await MainActor.run { self.toast = nil }
                        }
                }
            }
            .task(id: sessionId) {
                await reload()
                await loadActivePath()
            }
            .onReceive(NotificationCenter.default.publisher(for: FileSystemNotifier.didChange)) { note in
                guard let info = note.userInfo,
                      let sid = info["sessionId"] as? UUID,
                      sid == sessionId else { return }
                Task { await reload() }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.html, .json, .plainText, .sourceCode, .xml],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        onPickFile(url)
                        toast = "已导入：\(url.lastPathComponent)"
                    }
                case .failure(let err):
                    toast = "文件选取失败：\(err.localizedDescription)"
                }
            }
        }
    }

    // MARK: - File List

    private var fileList: some View {
        Group {
            if files.isEmpty {
                emptyState
            } else {
                List {
                    Section {
                        ForEach(files, id: \.path) { entry in
                            fileRow(entry)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .listRowBackground(Color.visorSecondaryBackground.opacity(0.5))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deleteFile(entry)
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private func fileRow(_ entry: FileSystemStore.FileEntry) -> some View {
        Button {
                            handleTap(entry)
        } label: {
            HStack(spacing: DesignTokens.Spacing.m) {
                Image(systemName: fileIcon(entry.path))
                    .font(.system(size: 20))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.path)
                        .font(.visorBody)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(formatSize(entry.size))
                        .font(.visorCaption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if entry.path == activePath {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.accentColor)
                }

                Menu {
                    Button {
                        exportFile(entry)
                    } label: {
                        Label("导出", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        deleteFile(entry)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: DesignTokens.Spacing.m) {
            Image(systemName: "folder")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("暂无文件")
                .font(.visorTitle)
                .foregroundStyle(.secondary)
            Text("点击下方「+ 从文件」上传文件")
                .font(.visorBody)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: DesignTokens.Spacing.m) {
            Button {
                showFilePicker = true
            } label: {
                Label("从文件", systemImage: "doc.badge.plus")
                    .font(.visorBody)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(.horizontal, DesignTokens.Spacing.l)
        .padding(.vertical, DesignTokens.Spacing.m)
    }

    // MARK: - Actions

    private func handleTap(_ entry: FileSystemStore.FileEntry) {
        if entry.path.lowercased().hasSuffix(".html") {
            // HTML 文件：切换画布并关闭 Sheet
            FileSystemNotifier.shared.notify(
                sessionId: sessionId, path: entry.path, kind: .write, switchTo: true
            )
            activePath = entry.path
            dismiss()
        } else {
            // 非 HTML：内嵌预览
            previewPath = entry.path
            do {
                let fs = try FileSystemStore(sessionId: sessionId)
                previewContent = try fs.read(entry.path)
                showPreview()
            } catch {
                toast = "读取失败：\(error.localizedDescription)"
            }
        }
    }

    private func showPreview() {
        guard let path = previewPath else { return }
        let content = previewContent
        let pathDisplay = path
        DispatchQueue.main.async {
            // 简单实现：用 alert 显示前 500 字符
            // 完整预览可以用单独的 sheet，但为精简 UI 暂用 toast 提示
            self.toast = "预览 \(pathDisplay)：\n\(String(content.prefix(200)))…"
        }
    }

    private func deleteFile(_ entry: FileSystemStore.FileEntry) {
        Task {
            do {
                let fs = try FileSystemStore(sessionId: sessionId)
                _ = try fs.remove(entry.path)
                FileSystemNotifier.shared.notify(
                    sessionId: sessionId, path: entry.path, kind: .remove
                )
                await MainActor.run {
                    toast = "已删除：\(entry.path)"
                    if entry.path == activePath {
                        activePath = ""
                    }
                }
                await reload()
            } catch {
                await MainActor.run {
                    toast = "删除失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func exportFile(_ entry: FileSystemStore.FileEntry) {
        do {
            let fs = try FileSystemStore(sessionId: sessionId)
            let absURL = try fs.absoluteURL(for: entry.path)
            presentShareSheet(url: absURL)
        } catch {
            toast = "导出失败：\(error.localizedDescription)"
        }
    }

    private func presentShareSheet(url: URL) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let pop = activityVC.popoverPresentationController {
            pop.sourceView = root.view
            pop.sourceRect = CGRect(x: root.view.bounds.midX, y: root.view.bounds.midY, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        root.present(activityVC, animated: true)
    }

    // MARK: - Reload

    private func reload() async {
        do {
            let fs = try FileSystemStore(sessionId: sessionId)
            files = try fs.list()
        } catch {
            logger.error("Reload failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func loadActivePath() async {
        // 初次加载时，若 session 内有 index.html 则标记为当前
        do {
            let fs = try FileSystemStore(sessionId: sessionId)
            if fs.exists("index.html") {
                activePath = "index.html"
            } else if let first = files.first(where: { $0.path.lowercased().hasSuffix(".html") }) {
                activePath = first.path
            }
        } catch {
            // ignore
        }
    }

    // MARK: - Helpers

    private func fileIcon(_ path: String) -> String {
        let lower = path.lowercased()
        if lower.hasSuffix(".html") { return "globe" }
        if lower.hasSuffix(".css") { return "paintbrush" }
        if lower.hasSuffix(".js") { return "curlybraces" }
        if lower.hasSuffix(".json") { return "braces" }
        if lower.hasSuffix(".md") { return "doc.text" }
        return "doc"
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}
