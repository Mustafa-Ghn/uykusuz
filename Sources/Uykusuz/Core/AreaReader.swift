import Foundation
import Observation

/// Reads aloud the part of the screen the user draws, when they ask for it: a
/// system-wide shortcut or the menu dims the screen, the mouse draws an area,
/// and what is written there comes in the summary's window (`SummaryPanel`),
/// with its marked word, pause and bar. Pressing again while drawing gives up;
/// pressing during such a reading ends it.
///
/// The screen recording permission is used for this and nothing else: one
/// picture is taken after the area is drawn, and it is gone once its text has
/// been read (`ScreenText`). Nothing looks at the screen in between.
@MainActor
@Observable
final class AreaReader {
    /// As Settings and the menu show the shortcut.
    static let shortcutLabel = "\u{2303}\u{2325}S"
    static let title = "Seçilen alan"
    static let nothingToRead = "Seçilen alanda okunacak yazı bulunamadı."
    static let unreadable = "Seçilen alan okunamadı."
    static let needsPermission = "Alan okumak için ekran kaydı izni gerekiyor. Sistem Ayarları > Gizlilik ve Güvenlik > Ekran ve Sistem Sesi Kaydı bölümünde Uykusuz'u açın; açık görünüyorsa kapatıp yeniden açın. Sonra Uykusuz'dan çıkıp yeniden başlatın. Uykusuz ekrana yalnızca siz alan çizince bakar."

    /// What the drawn area says; nil when the user gave up drawing.
    typealias Read = @MainActor () async throws -> String?
    typealias Present = @MainActor (_ text: String, _ autoplay: Bool, _ onFinish: @escaping @MainActor () -> Void, _ onClose: @escaping @MainActor () -> Void) async -> Void

    @ObservationIgnored private let config: @MainActor () -> Config
    @ObservationIgnored private let hasPermission: @MainActor () -> Bool
    @ObservationIgnored private let askPermission: @MainActor () -> Void
    @ObservationIgnored private let read: Read
    @ObservationIgnored private let giveUp: @MainActor () -> Void
    @ObservationIgnored private let present: Present
    @ObservationIgnored private let dismiss: @MainActor () -> Void
    @ObservationIgnored private let windowIsReading: @MainActor () -> Bool
    @ObservationIgnored private let setShortcut: @MainActor (Bool) -> Bool
    @ObservationIgnored private let linger: TimeInterval
    @ObservationIgnored private var lingering: Task<Void, Never>?
    /// From the press until the area's text is known.
    @ObservationIgnored private var reading = false
    /// The text in the window, when it is ours. Replacing a window closes it,
    /// and `shownID` keeps that close from counting as the user's.
    @ObservationIgnored private var shownID: UUID?

    /// Another app has the shortcut to itself, for Settings.
    private(set) var shortcutTaken = false

    init(
        config: @escaping @MainActor () -> Config,
        hasPermission: @escaping @MainActor () -> Bool,
        askPermission: @escaping @MainActor () -> Void,
        read: @escaping Read,
        giveUp: @escaping @MainActor () -> Void,
        present: @escaping Present,
        dismiss: @escaping @MainActor () -> Void,
        windowIsReading: @escaping @MainActor () -> Bool,
        setShortcut: @escaping @MainActor (Bool) -> Bool,
        linger: TimeInterval = ClaudeReplyReader.lingerAfterEnd
    ) {
        self.config = config
        self.hasPermission = hasPermission
        self.askPermission = askPermission
        self.read = read
        self.giveUp = giveUp
        self.present = present
        self.dismiss = dismiss
        self.windowIsReading = windowIsReading
        self.setShortcut = setShortcut
        self.linger = linger
    }

    /// Takes the shortcut, for the life of the app.
    func start() {
        settingChanged()
    }

    func settingChanged() {
        shortcutTaken = !setShortcut(config().listenAreaShortcut)
    }

    /// The shortcut, or the menu's "Alan seçip dinle".
    func listen() async {
        guard !reading else {
            giveUp()
            return
        }
        if shownID != nil, windowIsReading() {
            dismiss()
            return
        }
        guard hasPermission() else {
            askPermission()
            await show(Self.needsPermission, autoplay: false)
            return
        }
        reading = true
        defer { reading = false }
        let text: String?
        do {
            text = try await read()
        } catch {
            Log.error("area reader: \(error.localizedDescription)")
            await show(Self.unreadable, autoplay: true)
            return
        }
        guard let text else { return }
        Log.info("area reader: reading \(text.count) characters aloud")
        await show(text.isEmpty ? Self.nothingToRead : text, autoplay: true)
    }

    private func show(_ text: String, autoplay: Bool) async {
        let id = UUID()
        shownID = id
        lingering?.cancel()
        lingering = nil
        await present(text, autoplay, { [weak self] in self?.finished(id) }, { [weak self] in self?.closed(id) })
    }

    private func finished(_ id: UUID) {
        guard id == shownID else { return }
        lingering?.cancel()
        lingering = Task { [weak self, linger] in
            try? await Task.sleep(for: .seconds(linger))
            guard !Task.isCancelled, let self, id == self.shownID, !self.windowIsReading() else { return }
            self.dismiss()
        }
    }

    private func closed(_ id: UUID) {
        guard id == shownID else { return }
        shownID = nil
        lingering?.cancel()
        lingering = nil
    }
}
