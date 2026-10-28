import AppKit
import DocketCore
import SwiftUI

struct DetailView: View {
    let item: WorkItem
    @Environment(InboxEngine.self) private var engine
    @Environment(Selection.self) private var selection
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                actions
                if let ticket = item.linkedTicket { ticketSection(ticket) }
                if !item.pullRequests.isEmpty { prSection }
                if let todo = item.todo { todoSection(todo) }
                if let activity = item.lastActivity { activitySection(activity) }
                if let workspace = item.workspace { agentSection(workspace) }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.backgroundPrimary)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            StatusLabel(item: item, size: 12)
            Text(item.title).font(theme.font(20, weight: .medium)).textSelection(.enabled)
            Text("\(item.group.title) · waiting since \(item.need.since.formatted(.relative(presentation: .named)))")
                .font(theme.font(12)).foregroundStyle(theme.textSecondary)
        }
    }

    private var actions: some View {
        FlowLayout(spacing: 8) {
            Button(Actions.primaryTitle(item)) { Actions.primary(item, engine: engine) }
                .buttonStyle(ThemedButtonStyle(prominent: true))
                .help("\(Actions.primaryHelp(item, engine: engine)) (↩)")
            if item.url != nil, Actions.primaryTitle(item) != "Open in browser" {
                Button("Open in Browser") { Actions.openInBrowser(item) }.help("⌘O")
            }
            if item.linkedTicket != nil, Actions.primaryTitle(item) != "Open in Linear" {
                Button("Open in Linear") { Actions.openInLinear(item) }
            }
            if let todo = item.todo, Actions.primaryTitle(item) != "Open in TickTick", let url = URL(string: todo.url) {
                Button("Open in TickTick") { NSWorkspace.shared.open(url) }
            }
            if let workspace = item.workspace, Actions.primaryTitle(item) != "Open in Orca" {
                Button("Open in Orca") { Actions.openInOrca(workspace, engine: engine) }
            }
            Menu {
                Button("Snooze…") { selection.snoozing = item }
                Button("Done") { engine.mark(item, .done) }
                Button("Not Mine") { engine.mark(item, .notMine) }
                Button("Copy Link") { Actions.copyLink(item) }
            } label: {
                Text("More…")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .buttonStyle(ThemedButtonStyle())
    }

    private func ticketSection(_ ticket: Ticket) -> some View {
        Section {
            if item.ticket == nil { Text(ticket.title).font(theme.font(13)) }
            HStack {
                Chip(text: ticket.identifier, icon: "linear")
                Chip(text: ticket.state.name)
                if item.ticket == nil {
                    Text(ticket.assignee.map { "Assigned to \($0)" } ?? "Unassigned")
                        .font(theme.font(12)).foregroundStyle(theme.textSecondary)
                }
                Spacer()
                Link("Open", destination: URL(string: ticket.url)!)
            }
        } header: { sectionTitle("Ticket") }
    }

    private var prSection: some View {
        Section {
            ForEach(item.pullRequests) { pr in
                HStack(alignment: .firstTextBaseline) {
                    Chip(text: "\(pr.repoName)#\(pr.number)", icon: "github",
                         style: pr.url == item.need.url && item.needsMe ? .need : .plain)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pr.title).lineLimit(2)
                        Text(pr.statusLine).font(theme.font(11)).foregroundStyle(theme.textSecondary)
                    }
                    Spacer()
                    Link("Open", destination: URL(string: pr.url)!)
                }
            }
        } header: { sectionTitle("Pull requests") }
    }

    private func todoSection(_ todo: Todo) -> some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                Chip(text: todo.dueLabel, icon: "ticktick")
                Text(todo.title).lineLimit(2)
                Spacer()
                Link("Open", destination: URL(string: todo.url)!)
            }
        } header: { sectionTitle("TickTick") }
    }

    private func activitySection(_ activity: Activity) -> some View {
        Section {
            Text("@\(activity.author) \(activity.summary) \(activity.at.formatted(.relative(presentation: .named)))")
                .font(theme.font(13))
                .help(activity.at.formatted())
        } header: { sectionTitle("Latest activity") }
    }

    private func agentSection(_ workspace: Workspace) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Chip(agentState: workspace.mainAgent?.state ?? "", label: workspace.mainAgent?.state ?? "no agent")
                    Text(workspace.shortBranch.isEmpty ? workspace.displayName : workspace.shortBranch)
                        .font(theme.mono(12)).foregroundStyle(theme.textSecondary)
                    if let since = workspace.mainAgent?.stateStartedAt {
                        Text("since \(since.formatted(.relative(presentation: .named)))").font(theme.font(12)).foregroundStyle(theme.textSecondary)
                    }
                    if workspace.unread { Chip(text: "unread", needsMe: true) }
                }
                if let message = workspace.mainAgent?.lastAssistantMessage, !message.isEmpty {
                    Text(message).font(theme.font(13)).lineLimit(8).textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.backgroundSecondary, in: .rect(cornerRadius: theme.radiusMedium))
                }
            }
        } header: { sectionTitle("Agent") }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased()).font(theme.mono(11)).foregroundStyle(theme.textSecondary)
    }
}

extension PullRequest {
    var statusLine: String {
        var parts = [state == .open ? (isDraft ? "Draft" : "Open") : state.rawValue.capitalized]
        if let reviewDecision { parts.append(reviewDecision.replacingOccurrences(of: "_", with: " ").capitalized) }
        if let checks { parts.append("CI \(checks.lowercased())") }
        if mergeable == "CONFLICTING" { parts.append("Conflict") }
        if let author { parts.append("by @\(author.login)") }
        return parts.joined(separator: " · ")
    }
}
