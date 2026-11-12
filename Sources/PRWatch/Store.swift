import Foundation

/// What the menu bar icon is saying, most urgent first.
enum BarState: Equatable {
    case offline
    case ciFailed(count: Int)
    case ciRunning
    case newActivity(count: Int)
    case allClear
}

/// Polls GitHub every minute and holds the latest results for the menu.
@MainActor
final class Store: ObservableObject {
    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var refreshInFlight = false

    private let pollIntervalSeconds: TimeInterval = 60
    private var pollTimer: Timer?

    init() {
        refresh()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
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
                snapshot = freshSnapshot
                lastErrorMessage = nil
                lastCheckedAt = Date()
            case .failure(let error):
                lastErrorMessage = (error as? GitHubError)?.message ?? error.localizedDescription
            }
            refreshInFlight = false
        }
    }

    var failingPRs: [PullRequest] { snapshot.myPRs.filter(\.ciFailed) }

    var barState: BarState {
        if lastErrorMessage != nil { return .offline }
        if !failingPRs.isEmpty { return .ciFailed(count: failingPRs.count) }
        if snapshot.myPRs.contains(where: \.ciRunning) { return .ciRunning }
        let newItemCount = snapshot.notifications.count + snapshot.reviewRequests.count
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
        case .newActivity(let count): return "\(count) new · \(checkedText)"
        case .allClear: return "Nothing new · \(checkedText)"
        }
    }
}
