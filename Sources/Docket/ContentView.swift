import DocketCore
import SwiftUI

struct ContentView: View {
    @Environment(InboxEngine.self) private var engine
    @Environment(Selection.self) private var selection
    @Environment(\.theme) private var theme

    var body: some View {
        @Bindable var selection = selection
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } content: {
            ItemListView()
                .navigationSplitViewColumnWidth(min: 320, ideal: 420)
        } detail: {
            if let item = engine.items.first(where: { $0.id == selection.itemID }) {
                DetailView(item: item)
            } else {
                ContentUnavailableView("Nothing selected", systemImage: "tray", description: Text("Pick an item to see what it needs."))
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .preferredColorScheme(theme.colorScheme)
        .tint(theme.accent)
        .accentColor(theme.accent)
        .foregroundStyle(theme.textPrimary)
        .font(theme.font(13))
        .confirmationDialog("Snooze until", isPresented: Binding(get: { selection.snoozing != nil }, set: { if !$0 { selection.snoozing = nil } }),
                            presenting: selection.snoozing) { item in
            ForEach(SnoozeOption.presets, id: \.self) { option in
                Button(option.title) { snooze(item, option) }
            }
            Button("Pick a Date…") { selection.pickingDate = item }
        }
        .sheet(isPresented: Binding(get: { !engine.settings.onboarded }, set: { _ in })) {
            OnboardingView().interactiveDismissDisabled()
        }
        .sheet(item: $selection.pickingDate) { item in
            SnoozeDatePicker { date in snooze(item, .until(date)) }
        }
        .overlay(alignment: .bottom) {
            if let error = engine.actionError {
                Text(error)
                    .font(theme.font(13))
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(theme.needBackground, in: .capsule)
                    .foregroundStyle(theme.needForeground)
                    .padding()
                    .onTapGesture { engine.actionError = nil }
            }
        }
    }

    private func snooze(_ item: WorkItem, _ option: SnoozeOption) {
        engine.mark(item, .snoozed(until: option.date(from: .now, hours: engine.settings.workHours)))
        selection.snoozing = nil
    }
}

struct SnoozeDatePicker: View {
    var onPick: (Date) -> Void
    @State private var date = Calendar.current.date(byAdding: .day, value: 2, to: .now)!
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Snooze until").font(.headline)
            DatePicker("Date", selection: $date, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.graphical)
                .labelsHidden()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Snooze") { onPick(date); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
    }
}
