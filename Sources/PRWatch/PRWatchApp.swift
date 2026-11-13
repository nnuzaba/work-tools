import AppKit
import SwiftUI

@main
struct PRWatchApp: App {
    @StateObject private var store = Store()

    init() {
        if let flagIndex = CommandLine.arguments.firstIndex(of: "--snapshot"),
           CommandLine.arguments.indices.contains(flagIndex + 1) {
            savePanelSnapshot(to: CommandLine.arguments[flagIndex + 1])
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuPanel(store: store)
        } label: {
            Image(nsImage: menuBarImage(for: store.barState))
            if let count = badgeCount(for: store.barState) {
                Text("\(count)")
            }
        }
        .menuBarExtraStyle(.window)
    }
}

/// For checking the design without clicking: `PRWatch --snapshot out.png` waits for the
/// first poll, saves the panel as an image, and quits.
@MainActor
private func savePanelSnapshot(to path: String) {
    let snapshotStore = Store()
    DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
        let renderer = ImageRenderer(content: MenuPanel(store: snapshotStore)
            .background(Color(nsColor: .windowBackgroundColor)))
        renderer.scale = 2
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
        exit(0)
    }
}

private func badgeCount(for state: BarState) -> Int? {
    switch state {
    case .needsFix(let count), .newActivity(let count): return count
    case .alertsPaused(let newCount): return newCount > 0 ? newCount : nil
    default: return nil
    }
}

/// Builds the menu bar glyph. Calm states stay black-and-white like other menu bar icons;
/// states that need you get a color.
private func menuBarImage(for state: BarState) -> NSImage {
    let (symbolName, tint): (String, NSColor?) = switch state {
    case .offline: ("icloud.slash", nil)
    case .needsFix: ("xmark.circle", .systemRed)
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
