import AppKit
import SwiftUI

/// GitHub's own icons (Octicons, MIT license), shipped as SVGs in the app's
/// Resources/octicons folder by scripts/bundle.sh.
enum Octicon: String {
    case pullRequest = "git-pull-request-16"
    case draftPullRequest = "git-pull-request-draft-16"
    case failed = "x-circle-16"
    case conflicts = "alert-16"
    case running = "dot-fill-16"
    case approved = "check-circle-16"
    case changesRequested = "file-diff-16"
    case reviewRequested = "eye-16"

    /// The icon as a one-color template, so SwiftUI can tint it. Falls back to a plain
    /// circle if the SVG is missing (for example when run outside the .app bundle).
    var image: Image {
        guard let url = Bundle.main.url(forResource: rawValue, withExtension: "svg", subdirectory: "octicons"),
              let svgImage = NSImage(contentsOf: url) else {
            return Image(systemName: "circle")
        }
        svgImage.isTemplate = true
        return Image(nsImage: svgImage).renderingMode(.template)
    }
}

/// The status colors github.com uses, in light and dark versions.
enum GitHubColor {
    static let open = dynamic(light: 0x1A7F37, dark: 0x3FB950)
    static let failed = dynamic(light: 0xD1242F, dark: 0xF85149)
    static let pending = dynamic(light: 0x9A6700, dark: 0xD29922)
    static let neutral = dynamic(light: 0x59636E, dark: 0x9198A1)
    static let accent = dynamic(light: 0x0969DA, dark: 0x4493F8)

    private static func dynamic(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}
