import AppKit
import DocketCore
import UserNotifications

/// Native notifications. Banners show even while Docket is frontmost.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    var onSelect: ((String) -> Void)?
    var onOpenInOrca: ((String) -> Void)?

    /// UNUserNotificationCenter needs an app bundle; `swift run` has none.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    func configure() {
        guard let center else { return }
        center.delegate = self
        let openInOrca = UNNotificationAction(identifier: "OPEN_ORCA", title: "Open in Orca", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "AGENT", actions: [openInOrca], intentIdentifiers: []),
            UNNotificationCategory(identifier: "ITEM", actions: [], intentIdentifiers: []),
        ])
        Task {
            let status = await center.notificationSettings().authorizationStatus
            NSLog("Docket notification authorization status: \(status.rawValue)")
            if status == .notDetermined { NSLog("Docket notification request granted: \(await requestPermission())") }
        }
    }

    @discardableResult
    func requestPermission() async -> Bool {
        do {
            return try await center?.requestAuthorization(options: [.alert, .sound, .badge]) ?? false
        } catch {
            NSLog("Docket notification permission failed: \(error)")
            return false
        }
    }

    func permissionGranted() async -> Bool {
        await center?.notificationSettings().authorizationStatus == .authorized
    }

    func post(_ events: [InboxEvent]) {
        guard let center else { return }
        for event in events {
            let content = UNMutableNotificationContent()
            content.title = event.title
            content.body = event.body
            content.sound = .default
            content.categoryIdentifier = event.workspaceID == nil ? "ITEM" : "AGENT"
            content.userInfo = ["itemID": event.itemID, "workspaceID": event.workspaceID ?? ""]
            center.add(UNNotificationRequest(identifier: "\(event.itemID)|\(event.kind.rawValue)", content: content, trigger: nil)) { error in
                if let error { NSLog("Docket notification failed: \(error)") }
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let itemID = info["itemID"] as? String ?? ""
        let workspaceID = info["workspaceID"] as? String ?? ""
        let action = response.actionIdentifier
        await MainActor.run {
            NSApp.activate()
            if action == "OPEN_ORCA", !workspaceID.isEmpty {
                onOpenInOrca?(workspaceID)
            }
            onSelect?(itemID)
        }
    }
}
