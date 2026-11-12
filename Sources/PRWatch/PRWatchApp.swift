import AppKit
import ServiceManagement
import SwiftUI

@main
struct PRWatchApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(store: store)
        } label: {
            Image(nsImage: menuBarImage(for: store.barState))
            if let count = badgeCount(for: store.barState) {
                Text("\(count)")
            }
        }
    }
}

private func badgeCount(for state: BarState) -> Int? {
    switch state {
    case .ciFailed(let count), .newActivity(let count): return count
    case .alertsPaused(let newCount): return newCount > 0 ? newCount : nil
    default: return nil
    }
}

/// Builds the menu bar glyph. Calm states stay black-and-white like other menu bar icons;
/// states that need you get a color.
private func menuBarImage(for state: BarState) -> NSImage {
    let (symbolName, tint): (String, NSColor?) = switch state {
    case .offline: ("icloud.slash", nil)
    case .ciFailed: ("xmark.circle", .systemRed)
    case .ciRunning: ("arrow.triangle.2.circlepath", .systemOrange)
    case .alertsPaused: ("bell.slash", nil)
    case .newActivity: ("arrow.triangle.pull", .systemBlue)
    case .allClear: ("arrow.triangle.pull", nil)
    }
    var config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
    if let tint { config = config.applying(.init(paletteColors: [tint])) }
    let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "PR Watch")?
        .withSymbolConfiguration(config) ?? NSImage()
    image.isTemplate = (tint == nil)
    return image
}

struct MenuContent: View {
    @ObservedObject var store: Store

    var body: some View {
        Text(store.statusLine)
        if let errorMessage = store.lastErrorMessage {
            Text(String(errorMessage.prefix(80)))
        }
        Divider()

        let reviewRequestsOnCommentedPRs = store.snapshot.reviewRequests
            .filter { store.snapshot.commentedPRKeys.contains($0.id) }
        if !reviewRequestsOnCommentedPRs.isEmpty {
            Section("Needs you") {
                ForEach(reviewRequestsOnCommentedPRs) { pr in
                    linkButton(pr.title, detail: "\(pr.id) · review requested", icon: "eye", url: pr.url)
                }
            }
        }

        if !store.snapshot.myPRs.isEmpty {
            Section("Your PRs") {
                ForEach(store.snapshot.myPRs) { pr in
                    let (icon, detail) = statusSummary(for: pr)
                    linkButton(pr.title, detail: "\(pr.id) · \(detail)", icon: icon, url: pr.url)
                }
            }
        }

        if !store.snapshot.notifications.isEmpty {
            Section("Recent") {
                ForEach(store.snapshot.notifications.prefix(5)) { item in
                    linkButton(item.subject.title, detail: "\(item.repository.fullName) · \(item.reason)",
                               icon: store.isNew(item) ? "bell.badge" : "bell", url: item.webURL)
                }
            }
        }

        Divider()
        Button(store.refreshInFlight ? "Refreshing…" : "Refresh now") { store.refresh() }
            .keyboardShortcut("r")
        Button(store.alertsPaused ? "Resume alerts" : "Pause alerts for 1 hour") { store.toggleAlertPause() }
        Button("Open GitHub notifications") {
            NSWorkspace.shared.open(URL(string: "https://github.com/notifications")!)
        }
        Toggle("Open at login", isOn: Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { shouldOpenAtLogin in
                try? shouldOpenAtLogin ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            }
        ))
        Divider()
        Button("Quit PR Watch") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func linkButton(_ title: String, detail: String, icon: String, url: URL) -> some View {
        let shortTitle = title.count > 48 ? title.prefix(47) + "…" : Substring(title)
        return Button { NSWorkspace.shared.open(url) } label: {
            Label("\(shortTitle)  —  \(detail)", systemImage: icon)
        }
    }

    private func statusSummary(for pr: PullRequest) -> (icon: String, detail: String) {
        if pr.ciFailed { return ("xmark.circle", "CI failed") }
        if pr.ciRunning { return ("clock", "CI running") }
        if pr.isDraft { return ("pencil.circle", "draft") }
        switch pr.reviewDecision {
        case "APPROVED": return ("checkmark.circle", "approved")
        case "CHANGES_REQUESTED": return ("exclamationmark.bubble", "changes requested")
        default: return ("circle", "waiting on review")
        }
    }
}
