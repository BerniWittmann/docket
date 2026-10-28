import AppKit
import DocketCore
import SwiftUI

/// First run: GitHub, Linear, TickTick, Orca and notifications. Every step can be skipped.
struct OnboardingView: View {
    @Environment(InboxEngine.self) private var engine
    @Environment(\.theme) private var theme
    @State private var step = 0

    private let titles = ["GitHub", "Linear", "TickTick", "Orca", "Notifications"]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 8) {
                DocketLogo(theme: theme).frame(width: 32, height: 32)
                Text("Welcome to Docket").font(theme.font(20, weight: .medium))
                Spacer()
                Text(theme.capsule("Step \(step + 1) of \(titles.count) · \(titles[step])")).font(theme.mono(11))
                    .foregroundStyle(theme.textSecondary)
            }
            SwiftUI.Group {
                switch step {
                case 0: GitHubSetup()
                case 1: LinearSetup()
                case 2: TickTickSetup()
                case 3: OrcaSetup()
                default: NotificationSetup()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
            HStack {
                if step > 0 { Button("Back") { step -= 1 } }
                Spacer()
                if step < titles.count - 1 {
                    Button("Skip") { advance() }
                    Button("Continue") { advance() }
                        .buttonStyle(ThemedButtonStyle(prominent: true))
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Finish") { advance() }
                        .buttonStyle(ThemedButtonStyle(prominent: true))
                        .keyboardShortcut(.defaultAction)
                }
            }
            .buttonStyle(ThemedButtonStyle())
        }
        .padding(24)
        .frame(width: 560)
        .background(theme.backgroundPrimary)
        .foregroundStyle(theme.textPrimary)
        .font(theme.font(13))
    }

    private func advance() {
        if step < titles.count - 1 {
            step += 1
        } else {
            engine.update { $0.onboarded = true }
            Task { await engine.refreshAll() }
        }
    }
}

struct StatusLine: View {
    enum Kind { case ok, problem, pending }
    let kind: Kind
    let text: String
    @Environment(\.theme) private var theme

    var body: some View {
        Label {
            Text(text).textSelection(.enabled)
        } icon: {
            Image(systemName: kind == .ok ? "checkmark.circle.fill" : kind == .problem ? "exclamationmark.triangle.fill" : "circle.dotted")
                .foregroundStyle(kind == .problem ? theme.needForeground : theme.accent)
        }
    }
}

struct GitHubSetup: View {
    @State private var result: Result<String, SourceError>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Docket reads GitHub through your local gh login. It never stores a token.")
            switch result {
            case nil:
                StatusLine(kind: .pending, text: "Checking gh auth status…")
            case .success(let output):
                StatusLine(kind: .ok, text: Self.account(in: output).map { "Logged in as \($0)" } ?? "Logged in")
            case .failure(let error):
                StatusLine(kind: .problem, text: error.localizedDescription)
                HStack {
                    Text("gh auth login").font(.system(.body, design: .monospaced))
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("gh auth login", forType: .string)
                    }
                    Button("Check again") { Task { await check() } }
                }
                .buttonStyle(ThemedButtonStyle())
                Text("Run it in a terminal, then check again.")
            }
        }
        .task { await check() }
    }

    private func check() async {
        result = nil
        result = await GitHubSource().authStatus()
    }

    static func account(in output: String) -> String? {
        output.range(of: #"account \S+"#, options: .regularExpression).map { String(output[$0].dropFirst("account ".count)) }
    }
}

struct LinearSetup: View {
    @Environment(InboxEngine.self) private var engine
    @State private var key = ""
    @State private var message: (StatusLine.Kind, String)?
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paste a personal Linear API key (Linear → Settings → Security & access → Personal API keys). It is stored in your Keychain.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                SecureField("lin_api_…", text: $key).textFieldStyle(.roundedBorder)
                Button("Connect") { Task { await connect() } }
                    .buttonStyle(ThemedButtonStyle(prominent: true))
                    .disabled(key.isEmpty || checking)
            }
            if checking { StatusLine(kind: .pending, text: "Checking the key…") }
            if let message { StatusLine(kind: message.0, text: message.1) }
        }
        .task {
            if let stored = await Task.detached(operation: { Keychain.read() }).value,
               let name = try? await LinearSource().validate(key: stored) {
                message = (.ok, "Connected as \(name)")
            }
        }
    }

    private func connect() async {
        checking = true
        defer { checking = false }
        do {
            let name = try await LinearSource().validate(key: key)
            Keychain.write(key)
            key = ""
            message = (.ok, "Connected as \(name)")
            await engine.refreshLinear()
        } catch {
            message = (.problem, error.localizedDescription)
        }
    }
}

struct TickTickSetup: View {
    @Environment(InboxEngine.self) private var engine
    @State private var token = ""
    @State private var lists: [TickTickList] = []
    @State private var message: (StatusLine.Kind, String)?
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paste a TickTick API token (TickTick web → Settings → Account → API Token). It is stored in your Keychain. Tasks tagged #docket show in Docket, and everything that needs you is mirrored into the list you pick.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                SecureField("API token", text: $token).textFieldStyle(.roundedBorder)
                Button("Connect") { Task { await connect() } }
                    .buttonStyle(ThemedButtonStyle(prominent: true))
                    .disabled(token.isEmpty || checking)
            }
            if checking { StatusLine(kind: .pending, text: "Checking the token…") }
            if let message { StatusLine(kind: message.0, text: message.1) }
            if !lists.isEmpty {
                Picker("Mirror into", selection: setting(engine, \.tickTickListID)) {
                    Text("Pick a list").tag(String?.none)
                    ForEach(lists) { Text($0.name).tag(Optional($0.id)) }
                }
            }
        }
        .task { await loadLists() }
    }

    private func loadLists() async {
        guard let found = try? await engine.tickTickLists(), !found.isEmpty else { return }
        lists = found
        message = (.ok, "Connected")
    }

    private func connect() async {
        checking = true
        defer { checking = false }
        do {
            lists = try await TickTickSource().lists(token: token)
            Keychain.write(token, service: Keychain.tickTickService)
            token = ""
            message = (.ok, "Connected")
            await engine.refreshTickTick()
        } catch {
            message = (.problem, error.localizedDescription)
        }
    }
}

struct OrcaSetup: View {
    @Environment(InboxEngine.self) private var engine
    @State private var path = ""

    var body: some View {
        let found = OrcaHarness.locate(configured: engine.settings.orcaPath)
        VStack(alignment: .leading, spacing: 12) {
            Text("Docket reads agent states and starts work through the Orca CLI.")
            if let found {
                StatusLine(kind: .ok, text: "Found \(found)")
            } else {
                StatusLine(kind: .problem, text: "The Orca CLI was not found.")
            }
            HStack {
                TextField("Path to the orca CLI", text: $path).textFieldStyle(.roundedBorder)
                Button("Use path") { engine.update { $0.orcaPath = path.isEmpty ? nil : path } }
                    .buttonStyle(ThemedButtonStyle())
            }
            if !path.isEmpty && !FileManager.default.isExecutableFile(atPath: path) {
                StatusLine(kind: .problem, text: "No executable at that path.")
            }
        }
        .onAppear { path = engine.settings.orcaPath ?? "" }
    }
}

struct NotificationSetup: View {
    @State private var granted: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Docket notifies you inside work hours when an agent or a person needs you.")
            switch granted {
            case true?: StatusLine(kind: .ok, text: "Notifications are allowed.")
            case false?:
                StatusLine(kind: .problem, text: "Notifications are not allowed yet.")
                HStack {
                    Button("Allow notifications") { Task { granted = await Notifier.shared.requestPermission() } }
                        .buttonStyle(ThemedButtonStyle(prominent: true))
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                    }
                    .buttonStyle(ThemedButtonStyle())
                }
            case nil: StatusLine(kind: .pending, text: "Checking…")
            }
        }
        .task { granted = await Notifier.shared.permissionGranted() }
    }
}
