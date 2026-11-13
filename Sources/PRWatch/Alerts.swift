import Foundation

/// Settings shared with the old pr-watch.sh, read from ~/.config/pr-watch/config.
/// Re-read on every poll, so edits apply within a minute.
struct WatchConfig {
    var notifyOnMyPRs = true
    var notifyOnCI = true
    var notifyOnPRsICommented = true
    var notifyOnPushesToPRsICommented = true
    var notifyOnAllMentions = false
    var watchedReposPattern = "."

    static func load() -> WatchConfig {
        var config = WatchConfig()
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/pr-watch/config")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return config }
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let parts = line.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "'\"")))
            }
            guard parts.count == 2 else { continue }
            let isYes = parts[1] == "yes"
            switch parts[0] {
            case "notify_on_my_prs": config.notifyOnMyPRs = isYes
            case "notify_on_ci": config.notifyOnCI = isYes
            case "notify_on_prs_i_commented": config.notifyOnPRsICommented = isYes
            case "notify_on_pushes_to_prs_i_commented": config.notifyOnPushesToPRsICommented = isYes
            case "notify_on_all_mentions": config.notifyOnAllMentions = isYes
            case "watched_repos_pattern": config.watchedReposPattern = parts[1]
            default: break
            }
        }
        return config
    }

    func watches(repo: String) -> Bool {
        repo.range(of: watchedReposPattern, options: .regularExpression) != nil
    }
}

/// Decides which GitHub notifications become Mac alerts, and sends them.
enum Alerts {
    /// The alert heading for a notification, or nil if your settings say to skip it.
    /// Same rules as pr-watch.sh.
    static func heading(for item: GitHubNotification, config: WatchConfig, commentedPRKeys: Set<String>) -> String? {
        guard config.watches(repo: item.repository.fullName) else { return nil }
        switch item.reason {
        case "author":
            return config.notifyOnMyPRs ? "Update on your PR" : nil
        case "ci_activity":
            return config.notifyOnCI ? "CI finished" : nil
        case "mention" where config.notifyOnAllMentions, "team_mention" where config.notifyOnAllMentions:
            return "You were mentioned"
        default:
            let isCommentedPR = item.prKey.map(commentedPRKeys.contains) ?? false
            return config.notifyOnPRsICommented && isCommentedPR ? "New activity on a PR you commented on" : nil
        }
    }

    /// Pops a Mac notification. Uses terminal-notifier when installed so a click opens the PR.
    static func send(heading: String, message: String, subtitle: String, url: URL) {
        let process = Process()
        let notifierPath = ["/opt/homebrew/bin/terminal-notifier", "/usr/local/bin/terminal-notifier"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
        if let notifierPath {
            process.executableURL = URL(fileURLWithPath: notifierPath)
            process.arguments = ["-title", heading, "-message", message, "-subtitle", subtitle,
                                 "-open", url.absoluteString]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", "on run argv", "-e",
                                 "display notification (item 2 of argv) with title (item 1 of argv) subtitle (item 3 of argv)",
                                 "-e", "end run", heading, message, subtitle]
        }
        try? process.run()
    }
}

/// Which notifications you've already been alerted about or looked at in the menu.
/// Saved to disk so a restart doesn't replay old alerts.
struct SeenState: Codable {
    var alertedVersions: Set<String> = []
    var viewedVersions: Set<String> = []
    /// Latest commit we saw on each PR you commented on, keyed by "owner/repo#123".
    var commentedPRHeads: [String: String] = [:]
    /// Your PRs that had failed CI or merge conflicts last poll, so we alert only when one flips.
    var failingCIPRKeys: Set<String> = []
    var conflictingPRKeys: Set<String> = []

    private static let file = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/state/pr-watch-app/seen.json")

    /// Nil on the very first run, before anything has been saved.
    static func load() -> SeenState? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(SeenState.self, from: data)
    }

    func save() {
        try? FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? JSONEncoder().encode(self).write(to: Self.file)
    }
}

extension SeenState {
    /// Fills in missing fields with defaults, so a file saved by an older version still loads.
    init(from decoder: Decoder) throws {
        let saved = try decoder.container(keyedBy: CodingKeys.self)
        alertedVersions = try saved.decodeIfPresent(Set<String>.self, forKey: .alertedVersions) ?? []
        viewedVersions = try saved.decodeIfPresent(Set<String>.self, forKey: .viewedVersions) ?? []
        commentedPRHeads = try saved.decodeIfPresent([String: String].self, forKey: .commentedPRHeads) ?? [:]
        failingCIPRKeys = try saved.decodeIfPresent(Set<String>.self, forKey: .failingCIPRKeys) ?? []
        conflictingPRKeys = try saved.decodeIfPresent(Set<String>.self, forKey: .conflictingPRKeys) ?? []
    }
}
