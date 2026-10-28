import AppKit
import DocketCore

/// Item actions shared by the keyboard, the menus and the detail pane. None of them write to GitHub or Linear.
@MainActor
enum Actions {
    /// The item's kind of work when it has one (reusing its workspace), else Orca, Linear or the browser.
    static func primary(_ item: WorkItem, engine: InboxEngine) {
        if item.need.kind != nil {
            Task {
                await engine.startWork(item)
                if engine.actionError == nil { activateOrca() }
            }
        } else if let workspace = item.workspace {
            openInOrca(workspace, engine: engine)
        } else {
            openInBrowser(item)
        }
    }

    /// Names what the primary action does, such as "Re-review" or "Start ticket".
    static func primaryTitle(_ item: WorkItem) -> String {
        if let kind = item.need.kind { return item.need.urgency == .reReview ? "Re-review" : kind.title }
        if item.workspace != nil { return "Open in Orca" }
        if item.isTodo { return "Open in TickTick" }
        if item.ticket != nil && item.need.url == item.ticket?.url { return "Open in Linear" }
        return "Open in browser"
    }

    /// Spells out the primary action's exact step, for its tooltip.
    static func primaryHelp(_ item: WorkItem, engine: InboxEngine) -> String {
        let place = item.workspace.map { $0.shortBranch.isEmpty ? $0.displayName : $0.shortBranch }
        guard let kind = item.need.kind else {
            switch primaryTitle(item) {
            case "Open in Orca": return "Opens \(place ?? "the workspace") in Orca."
            case "Open in Linear": return "Opens \(item.linkedTicket?.identifier ?? "the ticket") in Linear."
            case "Open in TickTick": return "Opens the task in TickTick on the web."
            default: return "Opens \(item.url ?? "the link") in the browser."
            }
        }
        let work = engine.settings.work(kind)
        let prompt = PromptTemplate.fill(work.prompt, item: item)
        let reusesWorkspace = kind == .continueTicket && item.workspace != nil
        switch WorkPlan(workspace: item.workspace, agent: work.agent, prompt: reusesWorkspace ? nil : prompt) {
        case .create:
            let name = WorkRef(item: item, viewer: engine.github?.viewer, ticketRepo: engine.settings.ticketRepo)?.branch ?? "a new worktree"
            return "Creates the worktree \(name) in Orca and starts \(work.agent) with “\(prompt)”."
        case .open where reusesWorkspace:
            return "Opens \(place ?? "the workspace") in Orca without a new prompt."
        case .open:
            return "Opens \(place ?? "the workspace") in Orca. Its agent is still busy, so no prompt is sent."
        case .send:
            return "Sends “\(prompt)” to the \(work.agent) session in \(place ?? "the workspace"), keeping its context."
        case .newTerminal:
            return "Starts \(work.agent) with “\(prompt)” in \(place ?? "the workspace")."
        case .nothing:
            return ""
        }
    }

    static func openInOrca(_ workspace: Workspace, engine: InboxEngine) {
        Task {
            await engine.open(workspace)
            if engine.actionError == nil { activateOrca() }
        }
    }

    /// The Orca CLI switches tabs inside Orca but leaves another app in front.
    static func activateOrca() {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.stablyai.orca").first?.activate()
    }

    static func openInBrowser(_ item: WorkItem) {
        if let url = item.url.flatMap(URL.init(string:)) { NSWorkspace.shared.open(url) }
    }

    static func openInLinear(_ item: WorkItem) {
        if let url = item.linkedTicket.flatMap({ URL(string: $0.url) }) { NSWorkspace.shared.open(url) }
    }

    static func copyLink(_ item: WorkItem) {
        guard let url = item.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }
}
