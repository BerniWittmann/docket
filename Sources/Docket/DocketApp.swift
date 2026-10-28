import AppKit
import DocketCore
import SwiftUI

@main
enum Main {
    /// `Docket --render-icon <path>` writes the app icon PNG for scripts/bundle.sh.
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-icon"), i + 1 < args.count {
            MainActor.assumeIsolated {
                do { try DocketLogo.renderIcon(to: args[i + 1]); exit(0) } catch { exit(1) }
            }
        }
        // `Docket --record-linear <path>` saves the raw Linear response, for test fixtures.
        if let i = args.firstIndex(of: "--record-linear"), i + 1 < args.count {
            let done = DispatchSemaphore(value: 0)
            Task.detached {
                guard let key = Keychain.read(),
                      let data = try? await LinearSource.post(LinearSource.query, key: key),
                      (try? data.write(to: URL(fileURLWithPath: args[i + 1]))) != nil else { exit(1) }
                done.signal()
            }
            done.wait()
            exit(0)
        }
        DocketApp.main()
    }
}

struct DocketApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    /// `Docket --demo` shows made-up items, for screenshots.
    @State private var engine = CommandLine.arguments.contains("--demo") ? Demo.engine() : InboxEngine()
    @State private var selection = Selection()

    var body: some Scene {
        Window("Docket", id: "main") {
            ContentView()
                .environment(\.theme, Theme.named(engine.settings.theme))
                .environment(engine)
                .environment(selection)
                .task { connect() }
                .background(OpenWindowCatcher(selection: selection))
        }
        .defaultSize(width: 1180, height: 720)
        .commands { DocketCommands(engine: engine, selection: selection) }

        Settings {
            SettingsView()
                .environment(\.theme, Theme.named(engine.settings.theme))
                .environment(engine)
        }
    }

    @MainActor
    private func connect() {
        let notifier = Notifier.shared
        notifier.onSelect = { [engine, selection] id in
            NSLog("Docket notification clicked: \(id)")
            selection.openMainWindow?()
            guard let item = engine.items.first(where: { $0.id == id }) else { return }
            selection.group = item.group
            selection.itemID = id
        }
        notifier.onOpenInOrca = { [engine] id in
            if let workspace = engine.workspaces.first(where: { $0.id == id }) { Actions.openInOrca(workspace, engine: engine) }
        }
        if !CommandLine.arguments.contains("--demo") { engine.deliver = { notifier.post($0) } }
        engine.start()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // Set before launch finishes, so a click that launches Docket is delivered too.
        MainActor.assumeIsolated { Notifier.shared.configure() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool { true }
}

/// The selected group and item, shared by the window and the menus.
@MainActor
@Observable
final class Selection {
    var group: InboxGroup = .agents
    var itemID: WorkItem.ID?
    var snoozing: WorkItem?
    var pickingDate: WorkItem?
    /// Brings the main window back, reopening it when it was closed.
    var openMainWindow: (() -> Void)?
}

/// Hands SwiftUI's openWindow action to code outside the view tree.
private struct OpenWindowCatcher: View {
    let selection: Selection
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear.onAppear { selection.openMainWindow = { openWindow(id: "main") } }
    }
}
