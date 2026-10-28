import DocketCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        TabView {
            Tab("Sources", systemImage: "point.3.connected.trianglepath.dotted") { SourcesSettings() }
            Tab("Work", systemImage: "hammer") { WorkSettings() }
            Tab("Notifications", systemImage: "bell") { NotificationSettings() }
            Tab("Bots", systemImage: "cpu") { BotSettings() }
            Tab("Appearance", systemImage: "paintpalette") { AppearanceSettings() }
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
        }
        .frame(width: 640, height: 460)
        .scrollContentBackground(.hidden)
        .background(theme.backgroundPrimary)
        .buttonStyle(ThemedButtonStyle())
        .preferredColorScheme(theme.colorScheme)
        .tint(theme.accent)
    }
}

/// A binding into one settings value that saves on every change.
@MainActor
func setting<T>(_ engine: InboxEngine, _ path: WritableKeyPath<DocketCore.Settings, T>) -> Binding<T> {
    Binding(get: { engine.settings[keyPath: path] }, set: { value in engine.update { $0[keyPath: path] = value } })
}

/// Edits a list of strings as one per line.
@MainActor
func lines(_ engine: InboxEngine, _ path: WritableKeyPath<DocketCore.Settings, [String]>) -> Binding<String> {
    Binding(get: { engine.settings[keyPath: path].joined(separator: "\n") },
            set: { text in engine.update { $0[keyPath: path] = text.split(whereSeparator: \.isNewline).map(String.init) } })
}

struct SourcesSettings: View {
    @Environment(InboxEngine.self) private var engine

    var body: some View {
        Form {
            Section("GitHub") {
                GitHubSetup()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Repos and orgs")
                    TextEditor(text: lines(engine, \.repos)).font(.body.monospaced()).frame(height: 60)
                    Text("One per line: owner/* for a whole org, owner/repo for one repo.").font(.caption).foregroundStyle(.secondary)
                }
                TextField("Repo for new ticket worktrees", text: setting(engine, \.ticketRepo))
            }
            Section("Linear") {
                LinearSetup()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Waiting-for-input states")
                    TextEditor(text: lines(engine, \.waitingStates)).font(.body.monospaced()).frame(height: 40)
                    Text("One per line. My tickets in these states go to Waiting for input, unless a PR or agent needs me.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Disconnect") {
                    Keychain.write(nil)
                    Task { await engine.refreshLinear() }
                }
                .disabled(engine.status[.linear] == .notConnected)
            }
            Section("TickTick") {
                TickTickSetup()
                Button("Disconnect") {
                    Keychain.write(nil, service: Keychain.tickTickService)
                    Task { await engine.refreshTickTick() }
                }
                .disabled(engine.status[.tickTick] == .notConnected)
            }
            Section("Orca") { OrcaSetup() }
        }
        .formStyle(.grouped)
    }
}

struct WorkSettings: View {
    @Environment(InboxEngine.self) private var engine

    var body: some View {
        Form {
            Text("Placeholders: {url}, {ticket}, {number}, {repo}. Prepare creates the worktree for new items without starting an agent, inside work hours only.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(WorkKind.allCases) { kind in
                Section(kind.title) {
                    TextField("Agent", text: work(kind, \.agent))
                    TextField("Prompt", text: work(kind, \.prompt), axis: .vertical)
                    Picker("Automation", selection: work(kind, \.automation)) {
                        ForEach(Automation.allCases) { Text($0.title).tag($0) }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func work<T>(_ kind: WorkKind, _ path: WritableKeyPath<WorkSetting, T>) -> Binding<T> {
        Binding(get: { engine.settings.work(kind)[keyPath: path] },
                set: { value in engine.update { settings in
                    var work = settings.work(kind)
                    work[keyPath: path] = value
                    settings.work[kind.rawValue] = work
                } })
    }
}

struct NotificationSettings: View {
    @Environment(InboxEngine.self) private var engine

    var body: some View {
        Form {
            Section {
                ForEach(EventKind.allCases, id: \.self) { kind in
                    Toggle(kind.title, isOn: Binding(get: { engine.settings.notifies(kind) },
                                                     set: { on in engine.update { $0.notifications[kind.rawValue] = on } }))
                }
            } footer: {
                Text("Notifications only fire inside work hours. Snoozed, done and not-mine items stay silent.")
            }
            Section { NotificationSetup() }
        }
        .formStyle(.grouped)
    }
}

extension EventKind {
    var title: String {
        switch self {
        case .agentNeedsMe: "An agent needs me"
        case .agentResultUnread: "An agent result is unread"
        case .newReview: "New review request"
        case .humanFeedback: "Human feedback on my PR"
        case .reviewBotFeedback: "Review-bot feedback on my PR"
        case .ciFailed: "CI failed"
        case .readyToMerge: "Ready to merge"
        }
    }
}

struct BotSettings: View {
    @Environment(InboxEngine.self) private var engine

    var body: some View {
        Form {
            Section {
                TextEditor(text: lines(engine, \.bots.reviewBots)).font(.body.monospaced()).frame(height: 100)
            } header: { Text("Review bots") } footer: { Text("Their findings count as feedback and notify.") }
            Section {
                TextEditor(text: lines(engine, \.bots.noiseBots)).font(.body.monospaced()).frame(height: 100)
            } header: { Text("Noise bots") } footer: { Text("Ignored completely. Bots in neither list are ignored too.") }
        }
        .formStyle(.grouped)
    }
}

struct AppearanceSettings: View {
    @Environment(InboxEngine.self) private var engine

    var body: some View {
        Form {
            Picker("Theme", selection: setting(engine, \.theme)) {
                ForEach(ThemeName.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.radioGroup)
            HStack(spacing: 24) {
                ForEach(ThemeName.allCases) { name in
                    let theme = Theme.named(name)
                    DocketLogo(theme: theme).frame(width: 48, height: 48).padding(12)
                        .background(theme.backgroundPrimary, in: .rect(cornerRadius: theme.radiusMedium))
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct GeneralSettings: View {
    @Environment(InboxEngine.self) private var engine
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Work hours") {
                HStack {
                    ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { weekday in
                        let on = engine.settings.workHours.days.contains(weekday)
                        Button(Calendar.current.shortWeekdaySymbols[weekday - 1]) {
                            engine.update { if on { $0.workHours.days.remove(weekday) } else { $0.workHours.days.insert(weekday) } }
                        }
                        .buttonStyle(ThemedButtonStyle(prominent: on))
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                DatePicker("Start", selection: time(\.start), displayedComponents: .hourAndMinute)
                DatePicker("End", selection: time(\.end), displayedComponents: .hourAndMinute)
            }
            Section {
                Toggle("Launch at login", isOn: Binding(get: { engine.settings.launchAtLogin }, set: { setLaunchAtLogin($0) }))
                if let loginError { Text(loginError).foregroundStyle(.red).font(.caption) }
            }
        }
        .formStyle(.grouped)
    }

    private func time(_ path: WritableKeyPath<WorkHours, Int>) -> Binding<Date> {
        Binding(get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(engine.settings.workHours[keyPath: path] * 60)) },
                set: { date in
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                    engine.update { $0.workHours[keyPath: path] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0) }
                })
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
            engine.update { $0.launchAtLogin = on }
        } catch {
            loginError = error.localizedDescription
        }
    }
}
