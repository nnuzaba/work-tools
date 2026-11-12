import AppKit
import ServiceManagement
import SwiftUI

/// One clickable line in the panel: colored icon, title, and a grey detail line.
struct PanelRowItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let octicon: Octicon
    let tint: Color
    let url: URL
}

/// The dropdown under the menu bar icon, drawn by hand so it matches the design
/// (two-line rows, colored status icons) instead of a plain system menu.
struct MenuPanel: View {
    @ObservedObject var store: Store
    /// Plain `@State` needs a SwiftUI macro that only ships with Xcode, so view state lives here.
    @StateObject private var panelState = PanelState()

    private let rowsShownBeforeShowMore = 3
    private let maxRowsWhenExpanded = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            PanelDivider()
            section("Needs you", rows: needsYouRows)
            section("Your PRs", rows: yourPRRows)
            footer
        }
        .padding(5)
        .frame(width: 340)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("PR Watch").font(.system(size: 13, weight: .semibold))
            Text(store.statusLine)
                .font(.system(size: 11))
                .foregroundStyle(store.barState == .offline ? Color.red : Color.secondary)
            if let errorMessage = store.lastErrorMessage {
                Text(errorMessage).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func section(_ title: String, rows: [PanelRowItem]) -> some View {
        if !rows.isEmpty {
            let isExpanded = panelState.expandedSectionTitles.contains(title)
            let visibleCount = isExpanded ? min(rows.count, maxRowsWhenExpanded) : rowsShownBeforeShowMore
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 2)
            ForEach(rows.prefix(visibleCount)) { row in
                PanelRow(panelState: panelState, octicon: row.octicon, tint: row.tint, title: row.title, detail: row.detail) {
                    NSWorkspace.shared.open(row.url)
                }
            }
            if rows.count > rowsShownBeforeShowMore {
                let hiddenCount = min(rows.count, maxRowsWhenExpanded) - rowsShownBeforeShowMore
                PanelRow(panelState: panelState, icon: isExpanded ? "chevron.up" : "chevron.down", tint: .secondary,
                         title: isExpanded ? "Show less" : "Show \(hiddenCount) more") {
                    if isExpanded { panelState.expandedSectionTitles.remove(title) } else { panelState.expandedSectionTitles.insert(title) }
                }
            }
            PanelDivider()
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            PanelRow(panelState: panelState, icon: "arrow.clockwise", title: store.refreshInFlight ? "Refreshing…" : "Refresh now",
                     shortcutHint: "⌘R") { store.refresh() }
                .keyboardShortcut("r")
            PanelRow(panelState: panelState, icon: store.alertsPaused ? "bell" : "bell.slash",
                     title: store.alertsPaused ? "Resume alerts" : "Pause alerts for 1 hour") { store.toggleAlertPause() }
            PanelRow(panelState: panelState, icon: "arrow.up.forward.square", title: "Open GitHub notifications") {
                NSWorkspace.shared.open(URL(string: "https://github.com/notifications")!)
            }
            let opensAtLogin = SMAppService.mainApp.status == .enabled
            PanelRow(panelState: panelState, icon: opensAtLogin ? "checkmark.square" : "square", title: "Open at login") {
                try? opensAtLogin ? SMAppService.mainApp.unregister() : SMAppService.mainApp.register()
                store.objectWillChange.send()
            }
            PanelDivider()
            PanelRow(panelState: panelState, icon: "power", title: "Quit PR Watch", shortcutHint: "⌘Q") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    private var needsYouRows: [PanelRowItem] {
        store.snapshot.reviewRequests
            .filter { store.snapshot.commentedPRKeys.contains($0.id) }
            .map { PanelRowItem(id: $0.id, title: $0.title, detail: "\(shortName($0.id)) · review requested",
                                octicon: .reviewRequested, tint: GitHubColor.accent, url: $0.url) }
    }

    private var yourPRRows: [PanelRowItem] {
        store.snapshot.myPRs.sorted { urgencyRank($0) < urgencyRank($1) }.map { pr in
            let (octicon, tint, detail) = statusSummary(for: pr)
            return PanelRowItem(id: pr.id, title: pr.title, detail: "\(shortName(pr.id)) · \(detail)",
                                octicon: octicon, tint: tint, url: pr.url)
        }
    }

    /// Drops the owner ("PromiseNetwork/promisepay#12" → "promisepay#12") so the status fits.
    private func shortName(_ fullName: String) -> String {
        fullName.split(separator: "/", maxSplits: 1).last.map(String.init) ?? fullName
    }

    /// Orders your PRs so the ones that need you come first and drafts sink to the bottom.
    private func urgencyRank(_ pr: PullRequest) -> Int {
        if pr.ciFailed { return 0 }
        if pr.reviewDecision == "CHANGES_REQUESTED" { return 1 }
        if pr.ciRunning { return 2 }
        if pr.reviewDecision == "APPROVED" { return 3 }
        return pr.isDraft ? 5 : 4
    }

    private func statusSummary(for pr: PullRequest) -> (octicon: Octicon, tint: Color, detail: String) {
        if pr.ciFailed { return (.failed, GitHubColor.failed, "CI failed") }
        if pr.ciRunning { return (.running, GitHubColor.pending, "CI running") }
        if pr.isDraft { return (.draftPullRequest, GitHubColor.neutral, "draft") }
        switch pr.reviewDecision {
        case "APPROVED": return (.approved, GitHubColor.open, "approved")
        case "CHANGES_REQUESTED": return (.changesRequested, GitHubColor.failed, "changes requested")
        default: return (.pullRequest, GitHubColor.open, "waiting on review")
        }
    }
}

/// A full-width button row that highlights on hover, like a menu item.
struct PanelRow: View {
    @ObservedObject var panelState: PanelState
    /// An SF Symbol name, used when there's no Octicon (the footer actions).
    var icon: String = "circle"
    var octicon: Octicon? = nil
    var tint: Color = .primary
    let title: String
    var detail: String? = nil
    var shortcutHint: String? = nil
    let action: () -> Void

    private var isHovered: Bool { panelState.hoveredRowKey == hoverKey }
    private var hoverKey: String { "\(title)|\(detail ?? "")" }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Group {
                    if let octicon {
                        octicon.image.resizable().frame(width: 16, height: 16)
                    } else {
                        Image(systemName: icon).font(.system(size: 14))
                    }
                }
                .foregroundStyle(tint)
                .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13)).lineLimit(1).truncationMode(.tail)
                    if let detail {
                        Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let shortcutHint {
                    Text(shortcutHint).font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, detail == nil ? 5 : 6)
            .contentShape(Rectangle())
            .background(isHovered ? Color.accentColor.opacity(0.18) : .clear,
                        in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { panelState.hoveredRowKey = hoverKey }
            else if isHovered { panelState.hoveredRowKey = nil }
        }
    }
}

/// Which sections are expanded and which row the mouse is over.
final class PanelState: ObservableObject {
    @Published var expandedSectionTitles: Set<String> = []
    @Published var hoveredRowKey: String?
}

struct PanelDivider: View {
    var body: some View {
        Divider().padding(.horizontal, 6).padding(.vertical, 4)
    }
}
