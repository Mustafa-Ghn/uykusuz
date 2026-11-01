import AppKit
import Observation

/// Marks the word being read on the screen itself, on the text the user is
/// looking at, instead of on the copy in the reading window. Nothing can reach
/// into another app's window, so it looks: it finds the screen's words in a
/// picture (`ScreenLook`), matches them to the text (`WordAligner`) and puts a
/// see-through mark over the word (`WordMarker`). It looks when a reading starts,
/// after the screen is scrolled or clicked or another app comes forward, and
/// every `lookInterval` while reading, for what moves on its own.
@MainActor
@Observable
final class ScreenFollower {
    /// Where the word being read is, by the last look at the screen.
    enum Place: Equatable {
        /// The first look is under way.
        case looking
        case marked(CGRect)
        /// The text is on the screen but this word is scrolled away.
        case above
        case below
        /// The text is not on the screen.
        case nowhere
        case noPermission
    }

    static let lookInterval: Duration = .seconds(2)
    /// How long a scroll has to be over before looking again.
    static let settleDelay: Duration = .milliseconds(150)
    /// One look can miss what is there, and the window should not jump for it.
    static let missesToGiveUp = 2

    static let aboveNote = "Okunan yer ekranın üstünde kaldı. Yazıyı yukarı kaydırırsanız orada işaretlenir."
    static let belowNote = "Okunan yer ekranın altında. Yazıyı aşağı kaydırırsanız orada işaretlenir."
    static let nowhereNote = "Bu yazı ekranda görünmüyor, burada izleyebilirsiniz."
    static let permissionNote = "Yazıyı ekranın üzerinde işaretlemek için ekran kaydı izni gerekiyor. Uykusuz listede açık görünüyorsa kapatıp yeniden açın."

    private(set) var place: Place = .looking

    /// The reading window shows the text only when the screen cannot.
    var textBelongsInWindow: Bool {
        switch place {
        case .looking, .marked: false
        case .above, .below, .nowhere, .noPermission: true
        }
    }

    var note: String? {
        switch place {
        case .looking, .marked: nil
        case .above: Self.aboveNote
        case .below: Self.belowNote
        case .nowhere: Self.nowhereNote
        case .noPermission: Self.permissionNote
        }
    }

    typealias Look = @Sendable (_ near: CGPoint?) async throws -> [ScreenWord]
    typealias Watch = @MainActor (_ moved: @escaping @MainActor (_ scrolling: Bool) -> Void) -> @MainActor () -> Void

    @ObservationIgnored private let reading: [String]
    @ObservationIgnored private let hasPermission: @MainActor () -> Bool
    @ObservationIgnored private let look: Look
    @ObservationIgnored private let mark: @MainActor (CGRect?) -> Void
    @ObservationIgnored private let watch: Watch
    @ObservationIgnored private let word: @MainActor () -> Int?
    @ObservationIgnored private let isPlaying: @MainActor () -> Bool
    @ObservationIgnored private let interval: Duration
    @ObservationIgnored private let settle: Duration

    /// Each word of the text's place on the screen, by the last look that found any.
    @ObservationIgnored private var places: [CGRect?] = []
    @ObservationIgnored private var misses = 0
    @ObservationIgnored private var looking = false
    @ObservationIgnored private var lookAgain = false
    /// The mark is stale until the next look: the screen is moving under it.
    @ObservationIgnored private var moving = false
    @ObservationIgnored private var stopped = false
    @ObservationIgnored private var unwatch: (@MainActor () -> Void)?
    @ObservationIgnored private var ticking: Task<Void, Never>?
    @ObservationIgnored private var settling: Task<Void, Never>?

    init(
        reading: [String],
        hasPermission: @escaping @MainActor () -> Bool,
        look: @escaping Look,
        mark: @escaping @MainActor (CGRect?) -> Void,
        watch: @escaping Watch,
        word: @escaping @MainActor () -> Int?,
        isPlaying: @escaping @MainActor () -> Bool,
        interval: Duration = ScreenFollower.lookInterval,
        settle: Duration = ScreenFollower.settleDelay
    ) {
        self.reading = reading
        self.hasPermission = hasPermission
        self.look = look
        self.mark = mark
        self.watch = watch
        self.word = word
        self.isPlaying = isPlaying
        self.interval = interval
        self.settle = settle
    }

    func start() {
        guard hasPermission() else {
            place = .noPermission
            return
        }
        unwatch = watch { [weak self] scrolling in self?.screenMoved(scrolling: scrolling) }
        lookNow()
        ticking = Task { [weak self, interval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                if self.isPlaying() { self.lookNow() }
            }
        }
    }

    /// The reading window went: nothing looks at the screen after this.
    func stop() {
        stopped = true
        unwatch?()
        unwatch = nil
        ticking?.cancel()
        settling?.cancel()
        mark(nil)
    }

    /// The word being read changed, or the reading stopped or started.
    func readingChanged() {
        guard !stopped else { return }
        refresh()
    }

    private func screenMoved(scrolling: Bool) {
        if scrolling {
            moving = true
            mark(nil)
        }
        settling?.cancel()
        settling = Task { [weak self, settle] in
            try? await Task.sleep(for: settle)
            guard !Task.isCancelled else { return }
            self?.lookNow()
        }
    }

    private func lookNow() {
        guard !stopped else { return }
        guard !looking else {
            lookAgain = true
            return
        }
        looking = true
        lookAgain = false
        let near = places.lazy.compactMap { $0 }.first.map { CGPoint(x: $0.midX, y: $0.midY) }
        Task { [weak self, look, reading] in
            let found = (try? await look(near)) ?? []
            // A very long text takes a moment, which the window should not feel.
            let aligned = await Task.detached(priority: .userInitiated) {
                WordAligner.align(reading: reading, screen: found.map(\.text))
            }.value
            guard let self else { return }
            self.looking = false
            guard !self.stopped else { return }
            // The screen moved under this picture.
            if self.lookAgain {
                self.lookNow()
                return
            }
            self.moving = false
            self.apply(found, aligned)
        }
    }

    private func apply(_ onScreen: [ScreenWord], _ aligned: [Int?]) {
        if aligned.contains(where: { $0 != nil }) {
            misses = 0
            places = aligned.map { $0.map { onScreen[$0].rect } }
        } else {
            misses += 1
            // Having looked near the last place, the text may have gone to another display.
            if places.isEmpty || misses >= Self.missesToGiveUp {
                places = []
            } else {
                mark(nil)
                return
            }
        }
        refresh()
    }

    private func refresh() {
        guard let word = word() else {
            mark(nil)
            if case .looking = place { return }
            place = places.isEmpty ? .nowhere : place
            return
        }
        if case .looking = place, places.isEmpty, looking { return }
        let now = Self.place(of: word, in: places)
        // The place by the last look still stands while the screen moves.
        guard !moving else { return }
        if case let .marked(rect) = now { mark(rect) } else { mark(nil) }
        if place != now { place = now }
    }

    /// A word on the screen has its own place; one that is not, between words
    /// that are, stays on the last one before it (a code block's name, a word
    /// recognition missed).
    nonisolated static func place(of word: Int, in places: [CGRect?]) -> Place {
        guard let first = places.firstIndex(where: { $0 != nil }), let last = places.lastIndex(where: { $0 != nil }) else { return .nowhere }
        if word < first { return .above }
        if word > last { return .below }
        for index in stride(from: word, through: first, by: -1) {
            if let rect = places[index] { return .marked(rect) }
        }
        return .above
    }
}

extension ScreenFollower {
    /// The words of a text as they are matched against the screen's.
    static func foldedWords(of player: SummaryPlayer) -> [String] {
        let ns = player.text as NSString
        return player.words.map { WordAligner.fold(ns.substring(with: $0)) }
    }

    /// What tells it the screen moved: the scroll wheel and letting go of the
    /// mouse anywhere (only that they happened, with no permission asked), and
    /// another app or space coming forward.
    static func watchScreen(_ moved: @escaping @MainActor (_ scrolling: Bool) -> Void) -> @MainActor () -> Void {
        let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel, .leftMouseUp]) { event in
            let scrolling = event.type == .scrollWheel
            MainActor.assumeIsolated { moved(scrolling) }
        }
        let center = NSWorkspace.shared.notificationCenter
        let observers = [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { moved(false) }
            }
        }
        return {
            if let monitor { NSEvent.removeMonitor(monitor) }
            for observer in observers { center.removeObserver(observer) }
        }
    }
}

/// The see-through mark over the word being read. It takes no clicks and is
/// left out of the app's own pictures of the screen.
@MainActor
final class WordMarker {
    /// The same color the reading window marks a word with, a little stronger
    /// since it lies over the letters.
    static let opacity: CGFloat = 0.35

    private var panel: NSPanel?

    func show(_ rect: CGRect) {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.setFrame(rect.insetBy(dx: -2, dy: -1), display: true)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle, .transient]
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(Self.opacity).cgColor
        view.layer?.cornerRadius = 3
        panel.contentView = view
        return panel
    }
}
