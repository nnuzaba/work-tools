# TaskFloat

A floating always-on-top task timer. The whole app is one file, `TaskFloat.swift`, built with `swiftc` (Command Line Tools only, no Xcode project).

## Build and relaunch

```bash
./build.sh && pkill -x TaskFloat; open -g TaskFloat.app
```

`TaskFloat.app` is gitignored. The copy the user runs day to day is the one in the main checkout, so after landing a change, rebuild and relaunch there, not from a worktree that will be deleted. Task state lives in `~/Library/Application Support/TaskFloat/` and survives restarts.

## How the panel behaves

- It's an `NSPanel` with `.nonactivatingPanel`: it can be the key window while another app stays frontmost.
- **Shrinks to an icon when unfocused.** When the panel stops being the key window, it becomes a 48pt round button: a flickering fire while a task runs, or a yellow pause icon when nothing does. Clicking it makes the panel key, and the panel grows back with an animation. Launching the app usually makes the panel key, so it starts fully open.
- While it's an icon, the window's frame autosave is turned off, so a restart reopens the full panel, not the icon.

## Gotchas

- Never resize the window during a SwiftUI layout pass. Do it on the next run-loop turn (`DispatchQueue.main.async`), or layout loops forever and the app freezes.
- `hosting.safeAreaRegions = []` matters: without it, the hidden title bar's safe area added about 24pt of empty space to the icon window.
- `@State` doesn't build with the Command Line Tools, so screen state lives in the `PanelState` class.
- Animations that never stop belong in Core Animation layers (`FireView`), not SwiftUI. A `TimelineView` or `phaseAnimator` fire cost 5-7% CPU nonstop; the same fire as `CABasicAnimation`s costs 0%. Measure with `ps -o %cpu= -p $(pgrep -x TaskFloat)`.
- A pointing-hand cursor over the icon was tried (a tracking-area `NSView` with `.activeAlways`) and never showed, so it was removed.

## Checking a change without touching the user's screen

- `screencapture -o -l <windowID> out.png` grabs just the TaskFloat window. Get the ID from `CGWindowListCopyWindowInfo`, filtered by owner name `TaskFloat`.
- Window bounds from `CGWindowListCopyWindowInfo` can lag for a few seconds after a resize, so check the screenshot size too.

## History

Before TaskFloat moved into work-tools, it was its own repo at `~/repos/taskfloat`. Transcripts of those sessions are in `~/.claude/projects/-Users-nuzaba-nuzhat-repos-taskfloat/*.jsonl`, and they're the only record of changes made before the move.
