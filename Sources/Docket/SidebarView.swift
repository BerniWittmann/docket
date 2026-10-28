import DocketCore
import SwiftUI

struct SidebarView: View {
    @Environment(InboxEngine.self) private var engine
    @Environment(Selection.self) private var selection
    @Environment(\.theme) private var theme

    var body: some View {
        @Bindable var selection = selection
        List(selection: Binding(get: { selection.group }, set: { if let g = $0 { selection.group = g } })) {
            ForEach(InboxGroup.allCases) { group in
                Label(group.title, systemImage: group.symbol)
                    .font(theme.font(13, weight: selection.group == group ? .medium : .regular))
                    .badge(Text("\(engine.items(in: group).count)").font(theme.mono(11)))
                    .tag(group)
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.backgroundSecondary)
        .safeAreaInset(edge: .top) {
            HStack(spacing: 8) {
                DocketLogo(theme: theme).frame(width: 24, height: 24)
                Text("Docket").font(theme.font(16, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
        }
        .safeAreaInset(edge: .bottom) { SourceStatusFooter() }
    }
}

extension InboxGroup {
    var symbol: String {
        switch self {
        case .agents: "sparkles"
        case .reviews: "eye"
        case .myPRs: "arrow.triangle.pull"
        case .tickets: "ticket"
        case .todos: "checklist"
        case .waiting: "hourglass"
        case .snoozed: "moon.zzz"
        case .waitingForInput: "person.badge.clock"
        }
    }
}

struct SourceStatusFooter: View {
    @Environment(InboxEngine.self) private var engine
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(SourceKind.allCases) { source in
                let status = engine.status[source] ?? .notConnected
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Circle().fill(status.color(theme)).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(theme.capsule(source.title)).font(theme.mono(11))
                        if let detail = status.detail {
                            Text(detail).font(theme.font(11))
                                .foregroundStyle(status.errorMessage == nil ? theme.textSecondary : theme.needForeground)
                                .lineLimit(3)
                        }
                    }
                }
                .help(status.errorMessage ?? "")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }
}

extension SourceStatus {
    func color(_ theme: Theme) -> Color {
        switch self {
        case .ok: theme.accent
        case .loading: theme.chipStroke
        case .notConnected: theme.chipStroke
        case .error: theme.needForeground
        }
    }

    var detail: String? {
        switch self {
        case .ok(let date): "Updated \(date.formatted(date: .omitted, time: .shortened))"
        case .loading: "Loading…"
        case .notConnected: "Not connected"
        case .error(let message): message
        }
    }
}
