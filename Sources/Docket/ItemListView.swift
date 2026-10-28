import DocketCore
import SwiftUI

struct ItemListView: View {
    @Environment(InboxEngine.self) private var engine
    @Environment(Selection.self) private var selection
    @Environment(\.theme) private var theme
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var selection = selection
        let items = engine.items(in: selection.group)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(items) { item in
                        ItemRow(item: item)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(item.id == selection.itemID ? theme.backgroundTertiary : .clear,
                                        in: .rect(cornerRadius: theme.radiusSmall))
                            .overlay(alignment: .leading) {
                                if item.id == selection.itemID {
                                    Capsule().fill(theme.accent).frame(width: 3).padding(.vertical, 8)
                                }
                            }
                            .contentShape(.rect)
                            .onTapGesture { selection.itemID = item.id; focused = true }
                            .id(item.id)
                    }
                }
                .padding(8)
            }
            .onChange(of: selection.group, initial: true) {
                // The sidebar takes focus when its selection changes; take it back once that settles.
                DispatchQueue.main.async { focused = true }
                selectFirst(items: engine.items(in: selection.group))
                if let first = engine.items(in: selection.group).first { proxy.scrollTo(first.id, anchor: .top) }
            }
            .onChange(of: selection.itemID) { if let id = selection.itemID { withAnimation { proxy.scrollTo(id) } } }
        }
        .background(theme.backgroundPrimary)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .defaultFocus($focused, true)
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("All clear", systemImage: "checkmark.circle", description: Text("Nothing in \(selection.group.title)."))
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .onKeyPress(.downArrow) { move(1, in: items) }
        .onKeyPress(.upArrow) { move(-1, in: items) }
        .navigationTitle(selection.group.title)
        .onKeyPress(.return) { act { Actions.primary($0, engine: engine) } }
        .onKeyPress("s") { act { selection.snoozing = $0 } }
        .onKeyPress("d") { act { engine.mark($0, .done) } }
        .onKeyPress("m") { act { engine.mark($0, .notMine) } }
        .onCopyCommand {
            guard let url = current?.url else { return [] }
            return [NSItemProvider(object: url as NSString)]
        }
        .onChange(of: items.map(\.id)) { if !items.contains(where: { $0.id == selection.itemID }) { selectFirst(items: items) } }
        .toolbar {
            Button { Task { await engine.refreshAll() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .help("Refresh (⌘R)")
        }
    }

    private var current: WorkItem? { engine.items.first { $0.id == selection.itemID } }

    private func act(_ action: (WorkItem) -> Void) -> KeyPress.Result {
        guard let current else { return .ignored }
        action(current)
        return .handled
    }

    private func move(_ offset: Int, in items: [WorkItem]) -> KeyPress.Result {
        guard !items.isEmpty else { return .ignored }
        let index = items.firstIndex { $0.id == selection.itemID } ?? -offset
        selection.itemID = items[min(max(index + offset, 0), items.count - 1)].id
        return .handled
    }

    private func selectFirst(items: [WorkItem]) {
        if !items.contains(where: { $0.id == selection.itemID }) { selection.itemID = items.first?.id }
    }
}

struct ItemRow: View {
    let item: WorkItem
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                StatusLabel(item: item, size: 11)
                Spacer()
                Text(item.need.since, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                    .font(theme.font(11))
                    .foregroundStyle(theme.textSecondary)
                    .help("Waiting since \(item.need.since.formatted())")
            }
            Text(item.title).font(theme.font(13, weight: .medium)).lineLimit(2)
            HStack(spacing: 4) {
                ForEach(item.chips, id: \.self) { chip in
                    if let state = chip.agentState { Chip(agentState: state, label: chip.text) } else { Chip(text: chip.text, icon: chip.icon) }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

/// What an item needs, as plain text so it does not read like one of the item's reference pills.
struct StatusLabel: View {
    let item: WorkItem
    var size: CGFloat = 11
    @Environment(\.theme) private var theme

    var body: some View {
        Text(theme.capsule(item.need.headline))
            .font(theme.mono(size, weight: .semibold))
            .foregroundStyle(item.needsMe ? theme.needForeground : theme.textSecondary)
            .lineLimit(1)
    }
}

/// A capsule label, optionally with a GitHub or Linear mark. Agent states and needs get their own colours.
struct Chip: View {
    enum Style: Hashable { case plain, need, working, done }

    let text: String
    var icon: String?
    var style = Style.plain
    @Environment(\.theme) private var theme

    init(text: String, icon: String? = nil, style: Style = .plain) {
        self.text = text
        self.icon = icon
        self.style = style
    }

    init(text: String, needsMe: Bool) {
        self.init(text: text, style: needsMe ? .need : .plain)
    }

    /// The chip for an Orca agent state.
    init(agentState state: String, label: String? = nil) {
        let style: Style = switch state {
        case "blocked", "waiting", "permission", "awaiting": .need
        case "working": .working
        case "done": .done
        default: .plain
        }
        self.init(text: label ?? state, style: style)
    }

    var body: some View {
        let (foreground, background) = colors
        HStack(spacing: 4) {
            if let icon {
                Image(icon).resizable().renderingMode(.template).scaledToFit().frame(width: 10, height: 10)
            }
            Text(theme.capsule(text))
        }
        .font(theme.mono(10, weight: style == .plain ? .regular : .semibold))
        .lineLimit(1)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(background, in: .capsule)
        .overlay { Capsule().strokeBorder(style == .plain ? theme.chipStroke : .clear, lineWidth: 1) }
        .foregroundStyle(foreground)
    }

    private var colors: (Color, Color) {
        switch style {
        case .plain: (theme.textSecondary, theme.backgroundTertiary)
        case .need: (theme.needForeground, theme.needBackground)
        case .working: (theme.workingForeground, theme.workingBackground)
        case .done: (theme.doneForeground, theme.doneBackground)
        }
    }
}

/// What a row's chip shows.
struct ChipInfo: Hashable {
    var text: String
    var icon: String?
    var agentState: String?
}

extension WorkItem {
    var needsMe: Bool { ![.waiting, .snoozed, .waitingForInput].contains(group) }
    var isTodo: Bool { id.hasPrefix("todo:") }


    var chips: [ChipInfo] {
        var chips: [ChipInfo] = []
        if let linkedTicket { chips.append(ChipInfo(text: linkedTicket.identifier, icon: "linear")) }
        chips += pullRequests.map { ChipInfo(text: "\($0.repoName)#\($0.number)", icon: "github") }
        if let todo, !isTodo { chips.append(ChipInfo(text: todo.dueLabel, icon: "ticktick")) }
        if let agent = workspace?.mainAgent { chips.append(ChipInfo(text: "agent \(agent.state)", agentState: agent.state)) }
        else if workspace != nil { chips.append(ChipInfo(text: "worktree")) }
        return chips
    }
}

extension Todo {
    var dueLabel: String {
        guard let dueDate else { return "to-do" }
        if Calendar.current.isDateInToday(dueDate) { return "due today" }
        return "due \(dueDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))"
    }
}
