# PR Watch

SwiftUI menu bar app. It polls GitHub through the `gh` CLI and draws a custom dropdown panel.

## Toolchain: Command Line Tools only, no Xcode

- Build with `--build-system native`. `scripts/bundle.sh` already does this; the default backend fails on plist parsing.
- Swift macros that ship with Xcode are missing. That means no `@State`, `@Observable`, or `#Preview`. View state lives in `ObservableObject` classes with `@Published` (see `PanelState`).

## Dev loop

After a change builds, install and relaunch the real app:

```bash
osascript -e 'tell application id "com.user.prwatch" to quit'
scripts/bundle.sh --install
open ~/Applications/PRWatch.app
```

The app must stay at `~/Applications/PRWatch.app`. "Open at login" (`SMAppService.mainApp`) is tied to that path.

## Checking the UI without clicking

`PRWatch --snapshot out.png` waits about 20 seconds for the first poll, saves the panel as a PNG, and quits. Run the binary from inside the bundle (`build/PRWatch.app/Contents/MacOS/PRWatch`). Run from `.build/release`, the Octicon SVGs aren't found and every icon falls back to a plain circle.

## Icons

Icons are GitHub's Octicons. To add one, copy `icons/<name>-16.svg` from the `primer/octicons` repo into `Resources/octicons/`, then add a case to the `Octicon` enum.

## GitHub data (`GitHub.swift`)

- Each poll makes one GraphQL query with several aliased searches. GitHub search can't OR two qualifiers together (for example `commenter:` and `reviewed-by:`), so each one gets its own search, and the results are merged in Swift.
- The `commented` and `reviewed` searches feed two things: alerts (`CommentedPR`), and the Reviewing section (open PRs only). These searches include merged and closed PRs, because alerts need them. That means their `first: 50` cap is shared with closed PRs.
- "Waiting on author" means you were the last human (bots skipped) to comment, review, push, or re-request review. It's computed from the last 5 timeline events.
