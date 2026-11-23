import AppKit
import Carbon
import Combine
import SwiftUI

/// One task on today's list. The stopwatch is running while `startedAt` is set.
/// A paused task normally drops back to Up next, unless `isPausedOnCard` keeps its card on screen.
struct TaskItem: Codable, Identifiable {
    var id = UUID()
    var title: String
    var seconds: TimeInterval = 0
    var startedAt: Date?
    var doneMinutes: Int?
    var isPausedOnCard: Bool?

    var showsAsCard: Bool { startedAt != nil || isPausedOnCard == true }

    func elapsed(at now: Date) -> TimeInterval {
        seconds + (startedAt.map { now.timeIntervalSince($0) } ?? 0)
    }
}

/// Holds today's tasks and saves them to disk on every change. A fresh list starts only when the user asks.
@MainActor
final class TaskStore: ObservableObject {
    private struct Saved: Codable { var day: String; var tasks: [TaskItem] }

    @Published var tasks: [TaskItem] = [] { didSet { save() } }
    private var day = TaskStore.dayKey()
    private static let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("TaskFloat")
    private static let stateFile = folder.appendingPathComponent("state.json")
    private static let daysFolder = folder.appendingPathComponent("days")

    /// One finished day as saved in days/<day>.json.
    private struct DayLog: Codable { var day: String; var tasks: [LoggedTask] }
    private struct LoggedTask: Codable { var title: String; var minutes: Int; var isDone: Bool }

    init() {
        try? FileManager.default.createDirectory(at: Self.daysFolder, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: Self.stateFile),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            day = saved.day
            tasks = saved.tasks
        }
    }

    /// The date label for a list. The day flips at 4am, so a late-night session counts toward the day it started.
    static func dayKey(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date.addingTimeInterval(-4 * 3600))
    }

    static func format(minutes: Int) -> String {
        minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }

    /// Saves the list to history.md and days/<day>.json, drops done tasks, and zeroes out the unfinished ones.
    func startNewDay() {
        appendToHistory()
        saveDayLog()
        day = Self.dayKey()
        tasks = tasks.filter { $0.doneMinutes == nil }.map { TaskItem(title: $0.title) }
    }

    /// Adds a task to Up next and returns its id, or nil when the title is blank.
    @discardableResult
    func add(_ title: String) -> UUID? {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let task = TaskItem(title: trimmed)
        tasks.append(task)
        return task.id
    }

    /// Starts or resumes one task. Any other running task is paused but keeps its card, so only one clock runs.
    func start(_ id: UUID) {
        for other in tasks where other.id != id && other.startedAt != nil { pause(other.id, keepOnCard: true) }
        update(id) { task in
            if task.startedAt == nil { task.startedAt = Date() }
            task.isPausedOnCard = nil
        }
    }

    /// Stops the stopwatch. With `keepOnCard` the task stays up top as a paused card instead of going to Up next.
    func pause(_ id: UUID, keepOnCard: Bool) {
        update(id) { task in
            task.seconds = task.elapsed(at: Date())
            task.startedAt = nil
            task.isPausedOnCard = keepOnCard ? true : nil
        }
    }

    /// Pauses every running task but leaves its card in place. Used when the screen or the Mac goes to sleep.
    func pauseAllOnCards() {
        for task in tasks where task.startedAt != nil { pause(task.id, keepOnCard: true) }
    }

    /// Stops the stopwatch and logs whole minutes.
    func complete(_ id: UUID) {
        update(id) { task in
            task.seconds = task.elapsed(at: Date())
            task.startedAt = nil
            task.isPausedOnCard = nil
            task.doneMinutes = Int((task.seconds / 60).rounded())
        }
    }

    func reopen(_ id: UUID) { update(id) { $0.doneMinutes = nil } }

    func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { update(id) { $0.title = trimmed } }
    }

    /// Tasks sorted A to Z, ignoring case and reading numbers the way Finder does.
    var alphabetical: [TaskItem] {
        tasks.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func delete(_ id: UUID) { tasks.removeAll { $0.id == id } }

    /// Today's list as plain text, used for history.md.
    func summary() -> String {
        let done = alphabetical.compactMap { t in t.doneMinutes.map { "- \(t.title) — \(Self.format(minutes: $0))" } }
        let open = alphabetical.filter { $0.doneMinutes == nil }
            .map { "- \($0.title) — \(Self.format(minutes: Int($0.elapsed(at: Date()) / 60)))" }
        let total = tasks.compactMap(\.doneMinutes).reduce(0, +)
        var lines = ["## \(day)", "Done (\(Self.format(minutes: total))):"] + done
        if !open.isEmpty { lines += ["In progress:"] + open }
        return lines.joined(separator: "\n")
    }

    private func update(_ id: UUID, _ change: (inout TaskItem) -> Void) {
        if let index = tasks.firstIndex(where: { $0.id == id }) { change(&tasks[index]) }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(Saved(day: day, tasks: tasks)) {
            try? data.write(to: Self.stateFile, options: .atomic)
        }
    }

    /// Writes the day's work to days/<day>.json, one entry per task with its minutes and whether it's done.
    /// Unstarted carry-over tasks are skipped. Starting a new day twice on one day adds to the same file.
    private func saveDayLog() {
        let now = Date()
        let entries = alphabetical
            .map { LoggedTask(title: $0.title, minutes: $0.doneMinutes ?? Int($0.elapsed(at: now) / 60), isDone: $0.doneMinutes != nil) }
            .filter { $0.isDone || $0.minutes > 0 }
        guard !entries.isEmpty else { return }
        let url = Self.daysFolder.appendingPathComponent("\(day).json")
        var log = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(DayLog.self, from: $0) }
            ?? DayLog(day: day, tasks: [])
        log.tasks += entries
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(log) { try? data.write(to: url, options: .atomic) }
    }

    private func appendToHistory() {
        guard !tasks.isEmpty else { return }
        let url = Self.folder.appendingPathComponent("history.md")
        let entry = Data((summary() + "\n\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(entry)
            try? handle.close()
        } else {
            try? entry.write(to: url)
        }
    }
}

/// Screen-only state for the panel. It's a class because the Command Line Tools can't build `@State`.
@MainActor
final class PanelState: ObservableObject {
    @Published var draft = ""
    @Published var showTodo = false
    @Published var showDone = false
    @Published var renamingTaskID: UUID?
    @Published var renameDraft = ""
    @Published var themeName = UserDefaults.standard.string(forKey: "theme") ?? themes[0].name {
        didSet { UserDefaults.standard.set(themeName, forKey: "theme") }
    }

    /// How tall the task list is in full, and how tall its scroll box is on screen. Used to size the panel to fit.
    var listContentHeight: CGFloat = 0
    var listBoxHeight: CGFloat = 0
    private var panelFitAlreadyQueued = false

    /// Grows or shrinks the panel so the task list fits with no empty space under it.
    /// The resize waits for the next turn of the run loop, and several calls in a row share one resize.
    /// Resizing the window while SwiftUI is still laying it out made layout run again forever, freezing the app on ⌘↩.
    func fitPanelToList() {
        guard !panelFitAlreadyQueued else { return }
        panelFitAlreadyQueued = true
        DispatchQueue.main.async { [self] in
            panelFitAlreadyQueued = false
            guard listContentHeight > 0, listBoxHeight > 0 else { return }
            (NSApp.windows.first { $0 is FloatingPanel } as? FloatingPanel)?
                .fitHeight(adding: listContentHeight - listBoxHeight)
        }
    }

    var theme: Theme { themes.first { $0.name == themeName } ?? themes[0] }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// A look for the whole panel: the background, the card gradients, and whether text is light or dark.
/// A glass theme makes the panel and running cards see-through Liquid Glass, and uses its colors only as tints.
struct Theme {
    let name: String
    let background: [Color]
    let cards: [[Color]]
    let isDark: Bool
    let isGlass: Bool

    init(_ name: String, background: [UInt32], cards: [[UInt32]], isDark: Bool = true, isGlass: Bool = false) {
        self.name = name
        self.background = background.map(Color.init(hex:))
        self.cards = cards.map { $0.map(Color.init(hex:)) }
        self.isDark = isDark
        self.isGlass = isGlass
    }
}

let themes = [
    Theme("Midnight", background: [0x1F1A3D, 0x3D1A52],
          cards: [[0xFF5C8F, 0xFF9E45], [0x805CFF, 0x3DA1FF], [0x00C2AD, 0x73DB57], [0xF04DDB, 0x8566FF]]),
    Theme("Sunset", background: [0x2B1320, 0x4A1F2A],
          cards: [[0xFF6B6B, 0xFFB347], [0xFF4E8A, 0xFF8F6B], [0xF7B733, 0xFC4A1A], [0xE96443, 0x904E95]]),
    Theme("Ocean", background: [0x0B1D33, 0x0E3A4A],
          cards: [[0x2193B0, 0x6DD5ED], [0x1CB5E0, 0x4E54C8], [0x11998E, 0x38EF7D], [0x4568DC, 0x00C9A7]]),
    Theme("Matcha", background: [0x14231B, 0x1F3A2B],
          cards: [[0x56AB2F, 0xA8E063], [0x11998E, 0x7BD389], [0x3A9D78, 0x9FD9A8], [0x8BBF3F, 0x3E9E5B]]),
    Theme("Daylight", background: [0xFFF7EC, 0xFDE8EF],
          cards: [[0xFF7EB3, 0xFF9F6E], [0x7F7FFF, 0x5AB8FF], [0x2EC4B6, 0x6BCB5B], [0xB57BFF, 0xFF7EB3]], isDark: false),
    Theme("Liquid Glass", background: [0x1A1A2E, 0x1A1A2E],
          cards: [[0xFF5C8F, 0xFF9E45], [0x805CFF, 0x3DA1FF], [0x00C2AD, 0x73DB57], [0xF04DDB, 0x8566FF]], isGlass: true),
]

/// Shrinks a button a little while it's held down, so every click feels answered.
struct Pressable: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Running tasks get big colorful cards. Up next and Done fold away under tappable headers.
struct ContentView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var ui: PanelState
    @FocusState private var renameFieldFocused: Bool

    var body: some View {
        let sorted = store.alphabetical
        let cardTasks = sorted.filter(\.showsAsCard)
        let todo = sorted.filter { !$0.showsAsCard && $0.doneMinutes == nil }
        let done = sorted.filter { $0.doneMinutes != nil }
        let doneTotal = TaskStore.format(minutes: done.compactMap(\.doneMinutes).reduce(0, +))
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Today").font(.title3.bold()).allowsHitTesting(false)
                if !done.isEmpty {
                    Text("🔥 \(doneTotal)").font(.caption.bold()).foregroundStyle(.orange)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.orange.opacity(0.2), in: Capsule())
                        .allowsHitTesting(false)
                }
                Spacer()
                Group {
                    Menu {
                        Picker("Theme", selection: $ui.themeName) {
                            ForEach(themes, id: \.name) { Text($0.name).tag($0.name) }
                        }
                        .pickerStyle(.inline)
                    } label: { Image(systemName: "paintpalette") }
                        .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).fixedSize()
                        .help("Theme")
                    Menu {
                        Button("Clear Done and start a new day") { act { store.startNewDay() } }
                    } label: { Image(systemName: "arrow.counterclockwise") }
                        .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).fixedSize()
                        .help("Start a new day")
                    Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.help("Quit")
                }
                .foregroundStyle(.secondary)
            }
            // Stretch the grab area over the panel's padding, so the whole top edge drags too.
            .background(DragHandle().padding(EdgeInsets(top: -12, leading: -12, bottom: -5, trailing: -12)))
            HStack(spacing: 6) {
                Image(systemName: "plus").foregroundStyle(.secondary)
                TextField("Add a task  ·  ⌘↩ starts it", text: $ui.draft).textFieldStyle(.plain)
                    .onSubmit { addDraft(startNow: false) }
                    // Command-Return never reaches onSubmit, so a hidden shortcut button catches it.
                    .background(Button("") { addDraft(startNow: true) }.keyboardShortcut(.return, modifiers: .command).hidden())
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if cardTasks.isEmpty {
                        emptyCard(next: todo.first)
                    } else {
                        VStack(spacing: 6) { ForEach(cardTasks) { taskCard($0) } }
                    }
                    if !todo.isEmpty {
                        section("Up next", detail: "\(todo.count)", isOpen: $ui.showTodo)
                        if ui.showTodo { ForEach(todo) { todoRow($0) } }
                    }
                    if !done.isEmpty {
                        section("Done", detail: "\(done.count) · \(doneTotal)", isOpen: $ui.showDone)
                        if ui.showDone { ForEach(done) { doneRow($0) } }
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { ui.listContentHeight = $0; ui.fitPanelToList() }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { ui.listBoxHeight = $0; ui.fitPanelToList() }
        }
        .buttonStyle(Pressable())
        .fontDesign(.rounded)
        .padding(12)
        .ignoresSafeArea(edges: .top)
        .frame(minWidth: 260, minHeight: 160)
        .background(LinearGradient(colors: ui.theme.background, startPoint: .top, endPoint: .bottom)
            .opacity(ui.theme.isGlass ? 0 : 1).ignoresSafeArea())
        .background(Color.clear
            .glassEffect(ui.theme.isGlass ? .regular.tint(ui.theme.background[0].opacity(0.35)) : .identity, in: .rect)
            .ignoresSafeArea())
        .environment(\.colorScheme, ui.theme.isDark ? .dark : .light)
        .animation(.easeOut(duration: 0.25), value: ui.themeName)
    }

    /// A big card for a task that's running, or paused but kept on screen. Paused cards fade a bit.
    private func taskCard(_ task: TaskItem) -> some View {
        let isRunning = task.startedAt != nil
        return HStack(spacing: 4) {
            titleOrRenameField(task).font(.headline).lineLimit(2)
            Spacer()
            if isRunning {
                roundButton("pause.fill", help: "Pause") { act { store.pause(task.id, keepOnCard: true) } }
            } else {
                roundButton("play.fill", help: "Resume") { startAndFoldUpNext(task.id) }
            }
            roundButton("arrow.down.to.line", help: "Pause and move to Up next") {
                act { store.pause(task.id, keepOnCard: false) }
            }
            roundButton("checkmark", help: "Mark done") { act { store.complete(task.id) } }
        }
        .opacity(isRunning ? 1 : 0.75)
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: colors(task), startPoint: .topLeading, endPoint: .bottomTrailing)
            .opacity(ui.theme.isGlass ? 0.55 : 1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        // Glass inside the glass panel renders flat gray, so glass cards fake it with a see-through tint and a bright rim.
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(.white.opacity(ui.theme.isGlass ? 0.3 : 0), lineWidth: 1))
        .shadow(color: colors(task)[0].opacity(ui.theme.isGlass ? 0.3 : 0.45), radius: 8, y: 3)
        .transition(.scale(scale: 0.95).combined(with: .opacity))
        .contextMenu { menu(task) }
    }

    private func emptyCard(next: TaskItem?) -> some View {
        VStack(spacing: 8) {
            Text(next == nil ? "Add a task to get rolling 🚀" : "Nothing running").foregroundStyle(.secondary)
            if let next {
                Button { startAndFoldUpNext(next.id) } label: {
                    Label("Start \(next.title)", systemImage: "play.fill").lineLimit(1)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(LinearGradient(colors: colors(next), startPoint: .leading, endPoint: .trailing),
                                    in: Capsule())
                }
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity)
        .padding(14)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
    }

    /// Each task keeps the same card gradient, picked from its id.
    private func colors(_ task: TaskItem) -> [Color] {
        let cards = ui.theme.cards
        return cards[Int(task.id.uuid.0) % cards.count]
    }

    private func todoRow(_ task: TaskItem) -> some View {
        HStack(spacing: 8) {
            Circle().fill(LinearGradient(colors: colors(task), startPoint: .top, endPoint: .bottom))
                .frame(width: 8, height: 8)
            titleOrRenameField(task).lineLimit(1)
            Spacer()
            if task.seconds > 0 { Text(TaskStore.format(minutes: Int(task.seconds / 60))).foregroundStyle(.secondary) }
            Button { startAndFoldUpNext(task.id) } label: { Image(systemName: "play.fill").foregroundStyle(colors(task)[0]) }
                .help("Start")
        }
        .font(.callout)
        .padding(.leading, 4)
        .contextMenu { menu(task) }
    }

    private func doneRow(_ task: TaskItem) -> some View {
        HStack(spacing: 8) {
            Button { act { store.reopen(task.id) } } label: { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                .help("Move back to Up next")
            Text(task.title).strikethrough().lineLimit(1)
            Spacer()
            Text(TaskStore.format(minutes: task.doneMinutes ?? 0)).monospacedDigit()
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .contextMenu { menu(task) }
    }

    private func section(_ title: String, detail: String, isOpen: Binding<Bool>) -> some View {
        Button { withAnimation(.easeOut(duration: 0.2)) { isOpen.wrappedValue.toggle() } } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right").rotationEffect(.degrees(isOpen.wrappedValue ? 90 : 0))
                Text(title.uppercased()).tracking(0.8)
                Text(detail).foregroundStyle(.tertiary)
                Spacer()
            }
            .font(.caption.bold())
            .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private func roundButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                .frame(width: 24, height: 24).background(.white.opacity(0.25), in: Circle())
        }
        .help(help)
    }

    @ViewBuilder private func menu(_ task: TaskItem) -> some View {
        if task.doneMinutes == nil {
            Button("Rename") { startRenaming(task) }
            Button("Mark done") { act { store.complete(task.id) } }
        }
        Button("Delete") { act { store.delete(task.id) } }
    }

    /// The task's name, or a text box while it's being renamed. Double-click a name to rename it.
    /// Return or clicking away saves, and Escape cancels.
    @ViewBuilder private func titleOrRenameField(_ task: TaskItem) -> some View {
        if ui.renamingTaskID == task.id {
            TextField("Task name", text: $ui.renameDraft).textFieldStyle(.plain)
                .focused($renameFieldFocused)
                .onAppear { renameFieldFocused = true }
                .onSubmit { finishRenaming(task.id, save: true) }
                .onExitCommand { finishRenaming(task.id, save: false) }
                .onChange(of: renameFieldFocused) { if !renameFieldFocused { finishRenaming(task.id, save: true) } }
        } else {
            Text(task.title).onTapGesture(count: 2) { startRenaming(task) }
        }
    }

    private func startRenaming(_ task: TaskItem) {
        if let current = ui.renamingTaskID { finishRenaming(current, save: true) }
        ui.renameDraft = task.title
        ui.renamingTaskID = task.id
        NSApp.windows.first { $0 is FloatingPanel }?.makeKey()
    }

    /// Ignores calls for a task that isn't the one being renamed, such as a late focus change from an old text box.
    private func finishRenaming(_ id: UUID, save: Bool) {
        guard ui.renamingTaskID == id else { return }
        if save { act { store.rename(id, to: ui.renameDraft) } }
        ui.renamingTaskID = nil
    }

    /// Runs a list change with a quick spring so tasks glide between sections instead of jumping.
    private func act(_ change: () -> Void) { withAnimation(.spring(duration: 0.3, bounce: 0.2)) { change() } }

    /// Return adds the draft to Up next. Command-Return adds it and starts it right away.
    private func addDraft(startNow: Bool) {
        if let id = store.add(ui.draft), startNow { startAndFoldUpNext(id) }
        ui.draft = ""
    }

    /// Starts or resumes a task and folds Up next away so the running card has room.
    private func startAndFoldUpNext(_ id: UUID) {
        act {
            store.start(id)
            ui.showTodo = false
        }
    }
}

/// The empty strip behind the header that moves the panel.
/// Shows an open hand on hover and a closed hand while dragging, then snaps to a corner on release.
final class DragHandleView: NSView {
    private var grabOffset = NSPoint.zero

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.openHand.set() }
    override func mouseEntered(with event: NSEvent) { NSCursor.openHand.set() }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }

    override func mouseDown(with event: NSEvent) {
        guard let origin = window?.frame.origin else { return }
        let mouse = NSEvent.mouseLocation
        grabOffset = NSPoint(x: mouse.x - origin.x, y: mouse.y - origin.y)
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let panel = window as? FloatingPanel else { return }
        let mouse = NSEvent.mouseLocation
        let draggedTo = NSRect(origin: NSPoint(x: mouse.x - grabOffset.x, y: mouse.y - grabOffset.y), size: panel.frame.size)
        panel.setFrameOrigin(panel.keepingHeaderOnScreen(draggedTo).origin)
        NSCursor.closedHand.set()
    }

    override func mouseUp(with event: NSEvent) {
        (window as? FloatingPanel)?.snapToNearbyCorner()
        let mouseStillOnHandle = window.map { bounds.contains(convert($0.mouseLocationOutsideOfEventStream, from: nil)) } ?? false
        (mouseStillOnHandle ? NSCursor.openHand : NSCursor.arrow).set()
    }
}

/// Puts a `DragHandleView` behind SwiftUI content.
struct DragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandleView { DragHandleView() }
    func updateNSView(_ view: DragHandleView, context: Context) {}
}

/// A small always-on-top window that shows on every Space, including over full-screen apps.
/// Clicking it does not pull focus away from the app you are working in.
final class FloatingPanel: NSPanel {
    private var fittedHeight: CGFloat?

    init(content: NSView) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 320),
                   styleMask: [.titled, .resizable, .utilityWindow, .fullSizeContentView, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        title = "Today"
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isFloatingPanel = true
        hidesOnDeactivate = false
        // A clear window lets the glass theme show the desktop through. Other themes paint over all of it anyway.
        isOpaque = false
        backgroundColor = .clear
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        // Only the header's drag handle moves the panel, so every drag can end with a corner snap.
        isMovable = false
        [.closeButton, .miniaturizeButton, .zoomButton].forEach { standardWindowButton($0)?.isHidden = true }
        contentView = content
        if !setFrameUsingName("TaskFloat") { center() }
        setFrame(keepingHeaderOnScreen(frame), display: false)
        setFrameAutosaveName("TaskFloat")
    }

    override var canBecomeKey: Bool { true }

    /// AppKit normally pushes a window up out of the Dock's strip when it reopens. Using our own rule instead
    /// keeps the panel in a bottom corner it was snapped to, while still keeping the header reachable.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        keepingHeaderOnScreen(frameRect)
    }

    /// Moves `rect` just enough that its header can still be grabbed: the top edge stays below the menu bar,
    /// and the middle of the header stays on a screen. The bottom may still hang under the Dock.
    func keepingHeaderOnScreen(_ rect: NSRect) -> NSRect {
        let headerMiddle = NSPoint(x: rect.midX, y: rect.maxY - 1)
        let headerScreen = NSScreen.screens.first { $0.frame.contains(headerMiddle) } ?? screen ?? NSScreen.main
        guard let area = headerScreen?.visibleFrame else { return rect }
        var fixed = rect
        fixed.origin.y = min(rect.minY, area.maxY - rect.height)
        fixed.origin.x = min(max(rect.minX, area.minX - rect.width / 2), area.maxX - rect.width / 2)
        return fixed
    }

    /// Grows or shrinks the panel by `change` points, but never taller than the screen.
    /// A panel in the bottom half of the screen keeps its bottom edge still, so it stays tucked in a bottom corner.
    /// Skips heights it already fit to, so dragging the panel taller by hand sticks until the list changes.
    func fitHeight(adding change: CGFloat) {
        guard isVisible, let area = screen?.visibleFrame else { return }
        let height = min(frame.height + change, area.height - 24)
        guard abs(height - (fittedHeight ?? frame.height)) > 0.5 else { return }
        fittedHeight = height
        let originY = frame.midY < area.midY ? frame.minY : frame.maxY - height
        setFrame(keepingHeaderOnScreen(NSRect(x: frame.minX, y: originY, width: frame.width, height: height)), display: true)
    }

    /// If the panel was let go within 80 points of a screen corner, glides it neatly into that corner.
    /// Bottom corners use the real screen edge, not the top of the Dock, because the Dock only fills the middle.
    func snapToNearbyCorner() {
        guard let screen else { return }
        let area = screen.visibleFrame, gap: CGFloat = 12, reach: CGFloat = 80
        let nearX = [area.minX + gap, area.maxX - gap - frame.width].first { abs(frame.minX - $0) < reach }
        let nearY = [screen.frame.minY + gap, area.maxY - gap - frame.height].first { abs(frame.minY - $0) < reach }
        guard let nearX, let nearY else { return }
        setFrame(NSRect(origin: NSPoint(x: nearX, y: nearY), size: frame.size), display: true, animate: true)
    }

    /// This app has no menu bar, so Cmd+X/C/V/A/Z would do nothing in the text field. Send them by hand.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let actions: [String: Selector] = [
            "x": #selector(NSText.cut(_:)), "c": #selector(NSText.copy(_:)), "v": #selector(NSText.paste(_:)),
            "a": #selector(NSText.selectAll(_:)), "z": Selector(("undo:")),
        ]
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           let action = actions[event.charactersIgnoringModifiers ?? ""],
           NSApp.sendAction(action, to: nil, from: self) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel?
    private var store: TaskStore?
    private var menuBarItem: NSStatusItem?
    private var toggleHotKey: EventHotKeyRef?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let ui = PanelState()
        let store = TaskStore()
        self.store = store
        let hosting = NSHostingView(rootView: ContentView(store: store, ui: ui))
        // Let the user drag the window to any size instead of snapping it to the content's size.
        hosting.sizingOptions = [.minSize]
        let panel = FloatingPanel(content: hosting)
        panel.orderFrontRegardless()
        self.panel = panel
        // The list measures itself before the panel is on screen, when fitting is skipped, so fit once it shows.
        DispatchQueue.main.async { ui.fitPanelToList() }
        addMenuBarItem()
        registerToggleHotKey()
        let workspaceEvents = NSWorkspace.shared.notificationCenter
        for sleepEvent in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification] {
            workspaceEvents.addObserver(self, selector: #selector(pauseAllForSleep), name: sleepEvent, object: nil)
        }
    }

    /// Pauses every running task when the display or the whole Mac goes to sleep, so idle time isn't counted.
    @objc func pauseAllForSleep() {
        MainActor.assumeIsolated { store?.pauseAllOnCards() }
    }

    /// Hides the panel if it's showing, or brings it back if it's hidden.
    @objc func togglePanel() {
        guard let panel else { return }
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    /// A menu bar icon that shows or hides the panel, so it's easy to find again after hiding it.
    private func addMenuBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Show or hide TaskFloat")
        item.button?.toolTip = "Show or hide TaskFloat (⌃⌥T)"
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        menuBarItem = item
    }

    /// Makes Control+Option+T show or hide the panel from any app.
    /// Uses the old Carbon hotkey API because it works without asking for Accessibility permission.
    private func registerToggleHotKey() {
        var pressEvent = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, delegatePointer in
            let delegate = Unmanaged<AppDelegate>.fromOpaque(delegatePointer!).takeUnretainedValue()
            MainActor.assumeIsolated { delegate.togglePanel() }
            return noErr
        }, 1, &pressEvent, Unmanaged.passUnretained(self).toOpaque(), nil)
        let hotKeyID = EventHotKeyID(signature: OSType(0x5446_4C54), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_T), UInt32(controlKey | optionKey), hotKeyID,
                            GetApplicationEventTarget(), 0, &toggleHotKey)
    }
}
