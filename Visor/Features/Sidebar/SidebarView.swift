import SwiftUI
import SwiftData

/// 会话侧边栏（左栏）：可折叠的会话列表
struct SidebarView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SessionEntity.updatedAt, order: .reverse) private var sessions: [SessionEntity]
    @Binding var selectedSessionId: UUID?
    @Binding var isCollapsed: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.2)
            sessionList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.visorSecondaryBackground)
    }

    private var header: some View {
        HStack {
            if !isCollapsed {
                Text("会话")
                    .font(.visorTitle)
                    .padding(.leading, DesignTokens.Spacing.l)
            }
            Spacer()
            Button {
                Task { await createNew() }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
            }
            .accessibilityLabel("新建会话")
            .padding(.trailing, DesignTokens.Spacing.l)
        }
        .padding(.vertical, DesignTokens.Spacing.s)
    }

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(sessions) { session in
                    sessionRow(session)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.s)
            .padding(.vertical, DesignTokens.Spacing.s)
        }
    }

    @ViewBuilder
    private func sessionRow(_ session: SessionEntity) -> some View {
        let isSelected = session.id == selectedSessionId
        Button {
            selectedSessionId = session.id
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "bubble.left.fill" : "bubble.left")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                if !isCollapsed {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.title)
                            .font(.visorBody)
                            .lineLimit(1)
                        Text(session.updatedAt.formatted(.relative(presentation: .numeric)))
                            .font(.visorCaption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    if isSelected {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.s)
            .padding(.vertical, DesignTokens.Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.s)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : .clear)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                deleteSession(session)
            } label: {
                Label("删除会话", systemImage: "trash")
            }
        }
    }

    @MainActor
    private func deleteSession(_ session: SessionEntity) {
        let id = session.id
        // 删除文件系统目录
        let fm = FileManager.default
        if let appSupport = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false) {
            let dir = appSupport
                .appendingPathComponent("Visor", isDirectory: true)
                .appendingPathComponent("sessions", isDirectory: true)
                .appendingPathComponent(id.uuidString, isDirectory: true)
            try? fm.removeItem(at: dir)
        }
        // 删除 SwiftData 记录
        context.delete(session)
        try? context.save()
        // 选中第一个剩余会话，或新建
        if selectedSessionId == id {
            let remaining = sessions.sorted { $0.updatedAt > $1.updatedAt }
            if let first = remaining.first {
                selectedSessionId = first.id
            } else {
                Task { await createNew() }
            }
        }
    }

    @MainActor
    private func createNew() async {
        let new = SessionEntity(title: "新会话")
        context.insert(new)
        try? context.save()
        selectedSessionId = new.id
    }
}
