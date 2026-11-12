import AppKit

/// What the menu bar icon is saying, most urgent first.
enum BarState: Equatable {
    case offline
    case ciFailed(count: Int)
    case ciRunning
    case alertsPaused(newCount: Int)
    case newActivity(count: Int)
    case allClear
}

/// Polls GitHub every minute and holds the latest results for the menu.
@MainActor
final class Store: ObservableObject {
    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var lastErrorMessage: String?
    /// GitHub blips a lot, so one failed poll isn't enough to show the offline icon.
    @Published private(set) var failedPollsInARow = 0
    @Published private(set) var refreshInFlight = false
    @Published private(set) var alertsPausedUntil: Date?
    @Published private(set) var seenState = SeenState()

    private let pollIntervalSeconds: TimeInterval = 60
    private var pollTimer: Timer?
    /// False until the first poll after a fresh install. That poll marks everything as
    /// already seen instead of replaying your whole inbox as alerts.
    private var hasSeenBaseline: Bool

    init() {
        let savedSeenState = SeenState.load()
        seenState = savedSeenState ?? SeenState()
        hasSeenBaseline = savedSeenState != nil
        refresh()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.markAllViewed() }
        }
    }

    var alertsPaused: Bool { alertsPausedUntil.map { $0 > Date() } ?? false }

    func toggleAlertPause() {
        alertsPausedUntil = alertsPaused ? nil : Date().addingTimeInterval(60 * 60)
    }

    func isNew(_ item: GitHubNotification) -> Bool { !seenState.viewedVersions.contains(item.version) }

    /// Called when the menu closes: everything you just saw stops counting as new.
    func markAllViewed() {
        guard hasSeenBaseline else { return }
        seenState.viewedVersions = Set(snapshot.notifications.map(\.version))
        seenState.save()
    }

    /// One Mac alert waiting to go out.
    private struct PendingAlert {
        let heading, message, repo: String
        let prNumber: Int?
        let url: URL
    }

    /// Alerts about notifications and pushes that showed up since the last poll.
    private func sendAlerts(for freshSnapshot: Snapshot) {
        let freshVersions = Set(freshSnapshot.notifications.map(\.version))
        let unalertedItems = freshSnapshot.notifications.filter { !seenState.alertedVersions.contains($0.version) }
        let previousHeads = seenState.commentedPRHeads
        seenState.alertedVersions = freshVersions
        seenState.commentedPRHeads = freshSnapshot.commentedPRs.mapValues(\.headRefOid)
        let isBaselinePoll = !hasSeenBaseline
        if isBaselinePoll {
            seenState.viewedVersions = freshVersions
            hasSeenBaseline = true
        }
        seenState.save()
        guard !isBaselinePoll, !alertsPaused else { return }

        let config = WatchConfig.load()
        var pendingAlerts: [PendingAlert] = []
        if config.notifyOnPushesToPRsICommented {
            for pr in freshSnapshot.commentedPRs.values where config.watches(repo: pr.repository.nameWithOwner) {
                guard let previousHead = previousHeads[pr.key], previousHead != pr.headRefOid else { continue }
                let commitsPage = URL(string: "https://github.com/\(pr.repository.nameWithOwner)/pull/\(pr.number)/commits")!
                pendingAlerts.append(PendingAlert(heading: "New commits pushed", message: pr.title,
                                                  repo: pr.repository.nameWithOwner, prNumber: pr.number, url: commitsPage))
            }
        }
        for item in unalertedItems {
            guard let heading = Alerts.heading(for: item, config: config,
                                               commentedPRKeys: freshSnapshot.commentedPRKeys) else { continue }
            pendingAlerts.append(PendingAlert(heading: heading, message: item.subject.title,
                                              repo: item.repository.fullName, prNumber: item.prNumber, url: item.webURL))
        }
        guard !pendingAlerts.isEmpty else { return }
        Task.detached {
            for alert in pendingAlerts {
                if let prNumber = alert.prNumber, GitHub.viewerActedLast(repo: alert.repo, number: prNumber) { continue }
                Alerts.send(heading: alert.heading, message: alert.message, subtitle: alert.repo, url: alert.url)
            }
        }
    }

    /// Starts a poll unless one is already running. On failure the old data stays on screen.
    func refresh() {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        Task {
            let result = await Task.detached { Result { try GitHub.fetchSnapshot() } }.value
            switch result {
            case .success(let freshSnapshot):
                sendAlerts(for: freshSnapshot)
                snapshot = freshSnapshot
                lastErrorMessage = nil
                failedPollsInARow = 0
                lastCheckedAt = Date()
            case .failure(let error):
                lastErrorMessage = (error as? GitHubError)?.message ?? error.localizedDescription
                failedPollsInARow += 1
            }
            refreshInFlight = false
        }
    }

    var failingPRs: [PullRequest] { snapshot.myPRs.filter(\.ciFailed) }

    var barState: BarState {
        if failedPollsInARow >= 2 || (lastCheckedAt == nil && lastErrorMessage != nil) { return .offline }
        if !failingPRs.isEmpty { return .ciFailed(count: failingPRs.count) }
        if snapshot.myPRs.contains(where: \.ciRunning) { return .ciRunning }
        let newItemCount = snapshot.notifications.filter(isNew).count
        if alertsPaused { return .alertsPaused(newCount: newItemCount) }
        return newItemCount > 0 ? .newActivity(count: newItemCount) : .allClear
    }

    /// The grey line at the top of the menu.
    var statusLine: String {
        let checkedText = lastCheckedAt.map { "checked at \($0.formatted(date: .omitted, time: .shortened))" }
            ?? "checking…"
        switch barState {
        case .offline: return "Can't reach GitHub · retrying every minute"
        case .ciFailed(let count): return "CI failed on \(count) of your PRs · \(checkedText)"
        case .ciRunning: return "CI running · \(checkedText)"
        case .alertsPaused:
            let resumeTime = alertsPausedUntil?.formatted(date: .omitted, time: .shortened) ?? ""
            return "Alerts paused until \(resumeTime) · \(checkedText)"
        case .newActivity(let count): return "\(count) new · \(checkedText)"
        case .allClear: return "Nothing new · \(checkedText)"
        }
    }
}
