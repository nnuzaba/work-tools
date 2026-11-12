import Foundation

/// One pull request, trimmed down to what the menu shows.
struct PullRequest: Identifiable, Decodable {
    let number: Int
    let title: String
    let url: URL
    let isDraft: Bool
    let reviewDecision: String?
    let repository: Repo
    let commits: Commits

    struct Repo: Decodable { let nameWithOwner: String }
    struct Commits: Decodable { let nodes: [Node] }
    struct Node: Decodable { let commit: Commit }
    struct Commit: Decodable { let statusCheckRollup: Rollup? }
    struct Rollup: Decodable { let state: String }

    var id: String { "\(repository.nameWithOwner)#\(number)" }

    /// GitHub's combined CI result for the latest commit: SUCCESS, FAILURE, ERROR, PENDING,
    /// EXPECTED, or nil when the repo has no CI.
    var ciState: String? { commits.nodes.first?.commit.statusCheckRollup?.state }
    var ciFailed: Bool { ciState == "FAILURE" || ciState == "ERROR" }
    var ciRunning: Bool { ciState == "PENDING" || ciState == "EXPECTED" }
}

/// One unread item from github.com/notifications.
struct GitHubNotification: Identifiable, Decodable {
    let id: String
    let reason: String
    let updatedAt: Date
    let repository: Repo
    let subject: Subject

    struct Repo: Decodable { let fullName: String }
    struct Subject: Decodable {
        let title: String
        let url: String?
        let type: String
    }

    /// Changes whenever GitHub bumps the thread, so new activity on an old thread counts as new.
    var version: String { "\(id)@\(Int(updatedAt.timeIntervalSince1970))" }

    /// The PR number, or nil for CI notices (they don't point at a PR).
    var prNumber: Int? { subject.url?.split(separator: "/").last.flatMap { Int($0) } }

    /// "owner/repo#123", matching `PullRequest.id`.
    var prKey: String? { prNumber.map { "\(repository.fullName)#\($0)" } }

    /// The API hands back api.github.com links, so rebuild the web page link.
    /// CI notices have no link at all, so they open the repo's Actions page.
    var webURL: URL {
        let repoPage = "https://github.com/\(repository.fullName)"
        guard let prNumber else { return URL(string: "\(repoPage)/actions")! }
        return URL(string: "\(repoPage)/pull/\(prNumber)")!
    }
}

/// Everything one poll learns from GitHub.
struct Snapshot {
    var myPRs: [PullRequest] = []
    var reviewRequests: [PullRequest] = []
    var notifications: [GitHubNotification] = []
    /// Someone else's PRs you commented on or reviewed, as "owner/repo#123".
    var commentedPRKeys: Set<String> = []
}

struct GitHubError: Error {
    let message: String
}

/// Talks to GitHub through the `gh` CLI, so it reuses your existing login.
enum GitHub {
    /// Apps opened from Finder get a bare PATH, so look in Homebrew's spots directly.
    static let ghPath = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
        .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/bin/false"

    private static let pullRequestQuery = """
    query {
      mine: search(query: "is:pr is:open author:@me archived:false sort:updated-desc", type: ISSUE, first: 20) {
        nodes { ...prFields }
      }
      review: search(query: "is:pr is:open review-requested:@me archived:false sort:updated-desc", type: ISSUE, first: 20) {
        nodes { ...prFields }
      }
      commented: search(query: "is:pr -author:@me commenter:@me sort:updated-desc", type: ISSUE, first: 50) {
        nodes { ...prKey }
      }
      reviewed: search(query: "is:pr -author:@me reviewed-by:@me sort:updated-desc", type: ISSUE, first: 50) {
        nodes { ...prKey }
      }
    }
    fragment prKey on PullRequest { number repository { nameWithOwner } }
    fragment prFields on PullRequest {
      number title url isDraft reviewDecision
      repository { nameWithOwner }
      commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
    }
    """

    /// Runs `gh` with the given arguments and returns what it printed. Blocks, so call it off the main thread.
    static func run(_ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ghPath)
        process.arguments = arguments
        let output = Pipe(), errorOutput = Pipe()
        process.standardOutput = output
        process.standardError = errorOutput
        try process.run()
        let printed = output.fileHandleForReading.readDataToEndOfFile()
        let errorText = errorOutput.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errorText, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitHubError(message: message.isEmpty ? "gh exited with status \(process.terminationStatus)" : message)
        }
        return printed
    }

    /// Fetches your PRs, PRs waiting on your review, and unread PR/CI notifications.
    static func fetchSnapshot() throws -> Snapshot {
        struct SearchResponse: Decodable {
            let data: Results
            struct Results: Decodable { let mine, review: Search; let commented, reviewed: KeySearch }
            struct Search: Decodable { let nodes: [PullRequest] }
            struct KeySearch: Decodable { let nodes: [PRKey] }
            struct PRKey: Decodable { let number: Int; let repository: PullRequest.Repo }
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        let searchData = try run(["api", "graphql", "-f", "query=\(pullRequestQuery)"])
        let search = try decoder.decode(SearchResponse.self, from: searchData).data
        let notificationData = try run(["api", "notifications", "-X", "GET", "-f", "per_page=50"])
        let notifications = try decoder.decode([GitHubNotification].self, from: notificationData)
            .filter { $0.subject.type == "PullRequest" || $0.subject.type == "CheckSuite" }

        let commentedPRKeys = Set((search.commented.nodes + search.reviewed.nodes)
            .map { "\($0.repository.nameWithOwner)#\($0.number)" })
        return Snapshot(myPRs: search.mine.nodes, reviewRequests: search.review.nodes,
                        notifications: notifications, commentedPRKeys: commentedPRKeys)
    }

    private static let lastActorQuery = """
    query($owner: String!, $name: String!, $number: Int!) {
      viewer { login }
      repository(owner: $owner, name: $name) { pullRequest(number: $number) {
        timelineItems(last: 1, itemTypes: [ISSUE_COMMENT, PULL_REQUEST_REVIEW, PULL_REQUEST_COMMIT,
            MERGED_EVENT, CLOSED_EVENT, REOPENED_EVENT, REVIEW_REQUESTED_EVENT,
            READY_FOR_REVIEW_EVENT, HEAD_REF_FORCE_PUSHED_EVENT]) {
          nodes {
            ... on IssueComment { author { login } }
            ... on PullRequestReview { author { login } }
            ... on PullRequestCommit { commit { author { user { login } } } }
            ... on MergedEvent { actor { login } }
            ... on ClosedEvent { actor { login } }
            ... on ReopenedEvent { actor { login } }
            ... on ReviewRequestedEvent { actor { login } }
            ... on ReadyForReviewEvent { actor { login } }
            ... on HeadRefForcePushedEvent { actor { login } }
          } } } } }
    """

    /// True if you did the latest thing on the PR (comment, review, push, merge, ...),
    /// so there's nothing to alert you about. Treats errors as "no".
    static func viewerActedLast(repo: String, number: Int) -> Bool {
        let parts = repo.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return false }
        let jq = """
        .data.viewer.login == (.data.repository.pullRequest.timelineItems.nodes[0]
          | .author.login // .actor.login // .commit.author.user.login)
        """
        let answer = try? run(["api", "graphql", "-f", "owner=\(parts[0])", "-f", "name=\(parts[1])",
                               "-F", "number=\(number)", "-f", "query=\(lastActorQuery)", "--jq", jq])
        return answer.map { String(decoding: $0, as: UTF8.self).hasPrefix("true") } ?? false
    }
}
