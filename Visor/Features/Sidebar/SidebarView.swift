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
                Text("sidebar.title".l)
                    .font(.visorTitle)
                    .padding(.leading, DesignTokens.Spacing.l)
            }
            Spacer()
            CircularGlassButton(
                systemName: "plus",
                iconSize: DesignTokens.Touch.icon,
                size: DesignTokens.Touch.standard,
                action: { Task { await createNew() } }
            )
            .accessibilityLabel("sidebar.new".l)
            .padding(.trailing, DesignTokens.Spacing.l)
        }
        .padding(.vertical, DesignTokens.Spacing.m)
    }

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: DesignTokens.Spacing.xs) {
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
            HStack(spacing: DesignTokens.Spacing.m) {
                Image(systemName: isSelected ? "bubble.left.fill" : "bubble.left")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 24, alignment: .center)
                if !isCollapsed {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.title)
                            .font(.visorBodyLarge)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Text(session.updatedAt.formatted(.relative(presentation: .numeric)))
                            .font(.visorCaption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: DesignTokens.Spacing.s)
                    if isSelected {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.l)
            .padding(.vertical, 14)
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
                Label("sidebar.delete".l, systemImage: "trash")
            }
        }
    }

    @MainActor
    private func deleteSession(_ session: SessionEntity) {
        let id = session.id
        let fm = FileManager.default
        if let appSupport = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false) {
            let dir = appSupport
                .appendingPathComponent("Visor", isDirectory: true)
                .appendingPathComponent("sessions", isDirectory: true)
                .appendingPathComponent(id.uuidString, isDirectory: true)
            try? fm.removeItem(at: dir)
        }
        context.delete(session)
        try? context.save()
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
        let new = SessionEntity(title: "sidebar.newSession.defaultTitle".l)
        context.insert(new)
        try? context.save()
        selectedSessionId = new.id
    }
}
