import DocketCore
import SwiftUI

struct DocketCommands: Commands {
    let engine: InboxEngine
    let selection: Selection

    private var item: WorkItem? { engine.items.first { $0.id == selection.itemID } }

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Refresh") { Task { await engine.refreshAll() } }
                .keyboardShortcut("r")
            Picker("Theme", selection: Binding(get: { engine.settings.theme }, set: { theme in engine.update { $0.theme = theme } })) {
                ForEach(ThemeName.allCases) { Text($0.title).tag($0) }
            }
        }
        CommandMenu("Go") {
            ForEach(Array(InboxGroup.allCases.enumerated()), id: \.element) { index, group in
                Button(group.title) { selection.group = group }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
            }
        }
        CommandMenu("Item") {
            Button("\(item.map(Actions.primaryTitle) ?? "Start work")  ↩") { item.map { Actions.primary($0, engine: engine) } }
                .disabled(item == nil)
            Button("Open in Browser") { item.map(Actions.openInBrowser) }
                .keyboardShortcut("o")
                .disabled(item?.url == nil)
            Button("Copy Link") { item.map(Actions.copyLink) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(item?.url == nil)
            Divider()
            Button("Snooze…  S") { selection.snoozing = item }.disabled(item == nil)
            Button("Done  D") { item.map { engine.mark($0, .done) } }.disabled(item == nil)
            Button("Not Mine  M") { item.map { engine.mark($0, .notMine) } }.disabled(item == nil)
        }
    }
}
