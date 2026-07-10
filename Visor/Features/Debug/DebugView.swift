import SwiftUI

/// Debug 面板：三标签（终端 / Token / 错误）
struct DebugView: View {
    @ObservedObject private var bus = DebugBus.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: Tab = .terminal
    @State private var filter: String = ""

    enum Tab: String, CaseIterable, Identifiable {
        case terminal
        case token
        case error
        var id: String { rawValue }
        var label: String {
            switch self {
            case .terminal: return "debug.tab.terminal".l
            case .token: return "debug.tab.token".l
            case .error: return "debug.tab.error".l
            }
        }
        var icon: String {
            switch self {
            case .terminal: return "terminal"
            case .token: return "dollarsign.circle"
            case .error: return "exclamationmark.triangle"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    ForEach(Tab.allCases) { tab in
                        Label(tab.label, systemImage: tab.icon).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, DesignTokens.Spacing.l)
                .padding(.vertical, DesignTokens.Spacing.s)

                Divider().opacity(0.2)

                eventList
            }
            .navigationTitle("Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("debug.action.clear".l, role: .destructive) {
                            DebugBus.shared.clear()
                        }
                        Button("debug.action.copyAll".l) {
                            let dump = bus.events.map(serialize).joined(separator: "\n")
                            UIPasteboard.general.string = dump
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("common.done".l) { dismiss() }
                }
            }
        }
    }

    private var eventList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if filteredEvents.isEmpty {
                        emptyState
                    } else {
                        ForEach(filteredEvents) { event in
                            eventRow(event)
                                .id(event.id)
                        }
                    }
                }
                .padding(.vertical, DesignTokens.Spacing.s)
            }
            .onChange(of: bus.events.last?.id) { _, lastId in
                if let lastId {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: selectedTab.icon)
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(selectedTab == .terminal
                 ? "debug.empty.terminal".l
                 : selectedTab == .token
                 ? "debug.empty.token".l
                 : "debug.empty.error".l)
                .font(.visorCaption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignTokens.Spacing.xxl)
    }

    @ViewBuilder
    private func eventRow(_ event: DebugEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: event.iconName)
                    .font(.system(size: 11))
                    .foregroundStyle(event.levelColor)
                Text(event.title)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary)
                Spacer()
                Text(event.timestamp.formatted(.dateTime.hour().minute().second()))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            if !event.detail.isEmpty {
                Text(event.detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(8)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.l)
        .padding(.vertical, DesignTokens.Spacing.s)
        .background(event.level == .error
                    ? Color.red.opacity(0.06)
                    : Color.clear)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.15)
        }
    }

    // MARK: - Filtering

    private var filteredEvents: [DebugEvent] {
        let kind: DebugEvent.Kind
        switch selectedTab {
        case .terminal: kind = .cli
        case .token: kind = .token
        case .error: kind = .error
        }
        return bus.events
            .filter { $0.kind == kind || (selectedTab == .terminal && $0.kind == .tool) }
            .filter { event in
                filter.isEmpty
                || event.title.localizedCaseInsensitiveContains(filter)
                || event.detail.localizedCaseInsensitiveContains(filter)
            }
            .suffix(500)
    }

    private func serialize(_ event: DebugEvent) -> String {
        let fmt = ISO8601DateFormatter()
        return "[\(fmt.string(from: event.timestamp))] [\(event.kind.rawValue)] [\(event.level.rawValue)] \(event.title)\n\(event.detail)"
    }
}
