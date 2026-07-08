import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// 底部输入栏（整体 pill 胶囊容器，内嵌圆形 glass 发送按钮 + 左侧附件按钮）
struct ComposerBar: View {

    @Bindable var viewModel: ChatViewModel
    /// 文件选取回调（由父视图实现：写入 FileSystemStore）
    let onPickFile: (URL) -> Void

    @FocusState private var isFocused: Bool
    @State private var showPhotoPicker: Bool = false
    @State private var showFilePicker: Bool = false
    @State private var selectedItem: PhotosPickerItem?
    @State private var isProcessingImage: Bool = false
    @State private var toast: String?

    private let thumbnailSize: CGFloat = 56
    private let maxImageBytes: Int = 4_000_000

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            // 选中图片缩略图行
            if !viewModel.draftAttachments.isEmpty {
                attachmentsRow
            }

            // 主输入栏（pill 胶囊）
            HStack(alignment: .center, spacing: 0) {
                // 左侧 + 按钮（附件菜单）
                Menu {
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("照片", systemImage: "photo")
                    }
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("文件", systemImage: "doc")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: DesignTokens.Touch.compactIcon, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: DesignTokens.Touch.compact, height: DesignTokens.Touch.compact)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.draftAttachments.count >= ChatViewModel.maxAttachments)
                .opacity(viewModel.draftAttachments.count >= ChatViewModel.maxAttachments ? 0.4 : 1.0)
                .accessibilityLabel("添加附件")
                .padding(.leading, 6)
                .padding(.vertical, 6)

                TextField(
                    "输入消息…",
                    text: $viewModel.draft,
                    axis: .vertical
                )
                .font(.visorBodyLarge)
                .lineLimit(1...5)
                .padding(.leading, 8)
                .padding(.trailing, 4)
                .padding(.vertical, 10)
                .focused($isFocused)
                .submitLabel(.send)
                .onSubmit(submit)

                // 圆形 glass 发送 / 停止按钮
                Button(action: action) {
                    Image(systemName: viewModel.isStreaming ? "stop.fill" : "arrow.up")
                        .font(.system(size: DesignTokens.Touch.compactIcon, weight: .medium))
                        .foregroundStyle(viewModel.isStreaming ? Color.visorStatusFailedText : .primary)
                        .frame(width: DesignTokens.Touch.compact, height: DesignTokens.Touch.compact)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.isStreaming && viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && viewModel.draftAttachments.isEmpty)
                .opacity(canSend ? 1.0 : 0.4)
                .accessibilityLabel(viewModel.isStreaming ? "停止生成" : "发送消息")
                .padding(.trailing, 6)
                .padding(.vertical, 6)
            }
            .frame(minHeight: DesignTokens.Touch.compact + 12)
            .background(Color.visorSecondaryBackground, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.04), radius: 16, y: 4)
            .padding(.horizontal, DesignTokens.Spacing.l)
            .padding(.bottom, 0)
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedItem, matching: .images)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [
                .html,
                .json,
                .plainText,
                .sourceCode,
                .xml
            ],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    onPickFile(url)
                }
            case .failure(let err):
                toast = "文件选取失败：\(err.localizedDescription)"
            }
        }
        .onChange(of: selectedItem) { _, new in
            guard let new else { return }
            selectedItem = nil
            processImage(new)
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
        if isProcessingImage {
            ProgressView("处理图片…")
                .font(.visorCaption)
                .padding(.bottom, DesignTokens.Spacing.xs)
        }
    }

    // MARK: - Subviews

    /// 附件缩略图行
    private var attachmentsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignTokens.Spacing.s) {
                ForEach(Array(viewModel.draftAttachments.enumerated()), id: \.offset) { idx, dataURL in
                    ZStack(alignment: .topTrailing) {
                        if let img = Self.imageFromDataURL(dataURL) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: thumbnailSize, height: thumbnailSize)
                                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.s, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignTokens.Radius.s, style: .continuous)
                                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                                )
                        } else {
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.s, style: .continuous)
                                .fill(Color.visorTertiaryBackground)
                                .frame(width: thumbnailSize, height: thumbnailSize)
                                .overlay(
                                    Image(systemName: "photo")
                                        .foregroundStyle(.secondary)
                                )
                        }

                        // 删除按钮
                        Button {
                            viewModel.removeAttachment(at: idx)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white, Color.black.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .padding(4)
                        .contentShape(Rectangle())
                    }
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.l)
        }
        .frame(height: thumbnailSize + DesignTokens.Spacing.xs)
    }

    // MARK: - Helpers

    private var canSend: Bool {
        if viewModel.isStreaming { return true }
        let trimmed = viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty || !viewModel.draftAttachments.isEmpty
    }

    private var action: () -> Void {
        viewModel.isStreaming ? viewModel.stop : viewModel.send
    }

    private func submit() {
        guard !viewModel.isStreaming else { return }
        guard canSend else { return }
        // 若有图片附件但当前模型不支持 vision，提示但不阻止发送
        if !viewModel.draftAttachments.isEmpty,
           let model = OpenRouterModels.find(viewModel.selectedModelId),
           !model.supportsVision {
            toast = "当前模型不支持图片输入，请切换到 GPT-4o / Gemini Flash / Claude Haiku"
        }
        viewModel.send()
    }

    /// 处理 PhotosPicker 选中的图片：压缩 + base64
    private func processImage(_ item: PhotosPickerItem) {
        isProcessingImage = true
        Task {
            defer { Task { @MainActor in isProcessingImage = false } }

            guard let data = try? await item.loadTransferable(type: Data.self) else {
                await MainActor.run { toast = "图片加载失败" }
                return
            }
            guard let uiImage = UIImage(data: data) else {
                await MainActor.run { toast = "图片格式无效" }
                return
            }

            // 压缩到 max 1024×1024
            let resized = Self.resizeImage(uiImage, maxDimension: 1024)
            guard let jpegData = resized.jpegData(compressionQuality: 0.7) else {
                await MainActor.run { toast = "图片编码失败" }
                return
            }
            guard jpegData.count < maxImageBytes else {
                await MainActor.run { toast = "图片过大（>4MB），请选择更小的图片" }
                return
            }

            let dataURL = "data:image/jpeg;base64,\(jpegData.base64EncodedString())"

            await MainActor.run {
                if !viewModel.addAttachment(dataURL) {
                    toast = "最多 \(ChatViewModel.maxAttachments) 张图片"
                }
            }
        }
    }

    /// 把 UIImage 等比缩放到 maxDimension
    private static func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxEdge = max(size.width, size.height)
        guard maxEdge > maxDimension else { return image }
        let scale = maxDimension / maxEdge
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// 从 data URL 字符串解码出 UIImage
    private static func imageFromDataURL(_ dataURL: String) -> UIImage? {
        guard let commaIdx = dataURL.range(of: ",") else { return nil }
        let base64 = String(dataURL[commaIdx.upperBound...])
        guard let data = Data(base64Encoded: base64) else { return nil }
        return UIImage(data: data)
    }
}
