import AppKit
import AVFoundation
import SwiftUI

/// Reads the away summary aloud on request (fork addition): play and pause,
/// the word being read highlighted, and a bar to move back and forth.
/// Nothing is spoken until the user presses play; Claude's reply
/// (`ClaudeReplyReader`) is the one thing that starts on its own, as the user
/// asked for by turning it on.
///
/// AVSpeechSynthesizer reports each word as it reads it
/// (`willSpeakRangeOfSpeechString`), with every system voice; it cannot
/// jump inside an utterance, so a move stops the reading and starts it
/// again from the chosen word.
@MainActor
@Observable
final class SummaryPlayer: NSObject, AVSpeechSynthesizerDelegate {
    /// How many words the back and forward buttons move.
    static let step = 5

    let text: String
    let words: [NSRange]
    /// Each line's range in `text`, without the line break. The window
    /// scrolls a long text by these.
    let paragraphs: [NSRange]
    /// Called when a reading gets to the end, not when it is stopped.
    @ObservationIgnored var onFinish: (@MainActor () -> Void)?
    private(set) var isPlaying = false
    /// The word being read, or the one a move landed on.
    private(set) var currentWord: Int?

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private let voiceIdentifier: String?
    /// Where in `text` the utterance being read starts.
    @ObservationIgnored private var offset = 0
    /// The utterance whose reports count; an earlier one's late reports
    /// after a move are dropped.
    @ObservationIgnored private var active: ObjectIdentifier?
    @ObservationIgnored private var paused = false

    init(text: String, voiceIdentifier: String?) {
        self.text = text
        self.voiceIdentifier = voiceIdentifier
        words = Self.words(in: text)
        paragraphs = Self.paragraphs(in: text)
        super.init()
        synthesizer.delegate = self
    }

    /// 0...1: how far into the text the reading is.
    var progress: Double {
        guard let currentWord, !words.isEmpty else { return 0 }
        return Double(currentWord) / Double(max(words.count - 1, 1))
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func play() {
        if paused, synthesizer.isPaused {
            paused = false
            isPlaying = synthesizer.continueSpeaking()
            return
        }
        speak(fromWord: currentWord ?? 0)
    }

    func pause() {
        guard isPlaying else { return }
        paused = synthesizer.pauseSpeaking(at: .word)
        isPlaying = false
    }

    func stop() {
        active = nil
        paused = false
        synthesizer.stopSpeaking(at: .immediate)
        isPlaying = false
    }

    func back() { move(to: (currentWord ?? 0) - Self.step) }
    func forward() { move(to: (currentWord ?? 0) + Self.step) }

    /// The bar was dragged to `fraction` of the text.
    func seek(to fraction: Double) {
        move(to: Self.wordIndex(atFraction: fraction, count: words.count))
    }

    /// The paragraph the current word is in.
    var currentParagraph: Int? {
        guard let currentWord, words.indices.contains(currentWord) else { return nil }
        return Self.paragraphIndex(containing: words[currentWord].location, in: paragraphs)
    }

    /// A paragraph, with the current word marked if it is in there.
    func highlighted(paragraph index: Int) -> AttributedString {
        let range = paragraphs[index]
        var attributed = AttributedString((text as NSString).substring(with: range))
        if index == currentParagraph, let currentWord {
            let word = NSRange(location: words[currentWord].location - range.location, length: words[currentWord].length)
            if let marked = Range(word, in: attributed) {
                attributed[marked].backgroundColor = Color.accentColor.opacity(0.28)
                attributed[marked].foregroundColor = Color.primary
            }
        }
        return attributed
    }

    // MARK: Pure helpers

    /// Each word's range in `text`, by the system's word boundaries.
    nonisolated static func words(in text: String) -> [NSRange] {
        var ranges: [NSRange] = []
        let ns = text as NSString
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byWords, .substringNotRequired]) { _, range, _, _ in
            ranges.append(range)
        }
        return ranges
    }

    /// Each non-empty line's range in `text`.
    nonisolated static func paragraphs(in text: String) -> [NSRange] {
        var ranges: [NSRange] = []
        let ns = text as NSString
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            if range.length > 0 { ranges.append(range) }
        }
        return ranges
    }

    nonisolated static func paragraphIndex(containing location: Int, in paragraphs: [NSRange]) -> Int? {
        paragraphs.lastIndex { $0.location <= location }
    }

    nonisolated static func wordIndex(atFraction fraction: Double, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(Int((fraction * Double(count - 1)).rounded()), 0), count - 1)
    }

    /// The word a reported range falls in, given where the utterance began.
    nonisolated static func wordIndex(containing location: Int, in words: [NSRange]) -> Int? {
        words.lastIndex { $0.location <= location }
    }

    // MARK: Reading

    private func move(to index: Int) {
        guard !words.isEmpty else { return }
        let target = min(max(index, 0), words.count - 1)
        let wasPlaying = isPlaying
        stop()
        currentWord = target
        if wasPlaying { speak(fromWord: target) }
    }

    private func speak(fromWord index: Int) {
        guard words.indices.contains(index) else { return }
        stop()
        offset = words[index].location
        currentWord = index
        let utterance = AVSpeechUtterance(string: (text as NSString).substring(from: offset))
        if let voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "tr-TR")
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        active = ObjectIdentifier(utterance)
        isPlaying = true
        synthesizer.speak(utterance)
    }

    private func spoke(_ range: NSRange, of utterance: ObjectIdentifier) {
        guard utterance == active else { return }
        if let index = Self.wordIndex(containing: offset + range.location, in: words) {
            currentWord = index
        }
    }

    private func finished(_ utterance: ObjectIdentifier) {
        guard utterance == active else { return }
        active = nil
        paused = false
        isPlaying = false
        // Read to the end: the next play starts over.
        currentWord = nil
        onFinish?()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.spoke(characterRange, of: id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finished(id) }
    }
}

/// The small window the summary comes in: title, the text with the word
/// being read marked, and the controls. A text too long for the screen
/// scrolls, following the paragraph being read.
struct SummaryPlayerView: View {
    static let width: CGFloat = 400
    static let padding: CGFloat = 16
    static let paragraphSpacing: CGFloat = 6
    static let maxTextHeight: CGFloat = 340

    let player: SummaryPlayer
    let title: String
    let told: String
    let onClose: () -> Void
    /// Once: the drawing below runs again for every word.
    private let scrolls: Bool
    @State private var dragging: Double?

    init(player: SummaryPlayer, title: String, told: String, onClose: @escaping () -> Void) {
        self.player = player
        self.title = title
        self.told = told
        self.onClose = onClose
        scrolls = Self.needsScrolling(player.text, paragraphs: player.paragraphs.count)
    }

    /// Whether the text is taller than the window lets it be, at `.body`.
    static func needsScrolling(_ text: String, paragraphs: Int) -> Bool {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let height = (text as NSString).boundingRect(
            with: NSSize(width: width - 2 * padding, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        ).height
        return height + CGFloat(max(paragraphs - 1, 0)) * paragraphSpacing > maxTextHeight
    }

    private var paragraphs: some View {
        VStack(alignment: .leading, spacing: Self.paragraphSpacing) {
            ForEach(player.paragraphs.indices, id: \.self) { index in
                Text(player.highlighted(paragraph: index))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .id(index)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "eye")
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Text(told)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Kapat")
            }
            if scrolls {
                ScrollViewReader { proxy in
                    ScrollView { paragraphs }
                        .frame(height: Self.maxTextHeight)
                        .onChange(of: player.currentParagraph) { _, paragraph in
                            guard let paragraph else { return }
                            withAnimation { proxy.scrollTo(paragraph, anchor: .top) }
                        }
                }
            } else {
                paragraphs
            }
            HStack(spacing: 14) {
                Button(action: player.back) { Image(systemName: "backward.fill") }
                    .help("\(SummaryPlayer.step) kelime geri")
                Button(action: player.toggle) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 18)
                }
                .keyboardShortcut(.space, modifiers: [])
                .help(player.isPlaying ? "Durdur" : "Dinle")
                Button(action: player.forward) { Image(systemName: "forward.fill") }
                    .help("\(SummaryPlayer.step) kelime ileri")
                Slider(
                    value: Binding(get: { dragging ?? player.progress }, set: { dragging = $0 }),
                    in: 0...1
                ) { editing in
                    if !editing, let value = dragging {
                        player.seek(to: value)
                        dragging = nil
                    }
                }
                .disabled(player.words.count < 2)
            }
            .buttonStyle(.borderless)
            .font(.title3)
        }
        .padding(Self.padding)
        .frame(width: Self.width)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Clicks reach the controls in a window that is not key.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Puts the summary up at the top right of the screen without taking focus
/// from the app in front, and takes it down (stopping the reading) when
/// closed, replaced, or the lid closes.
@MainActor
final class SummaryPanel {
    private var panel: NSPanel?
    private var player: SummaryPlayer?
    private var onClose: (@MainActor () -> Void)?

    /// `autoplay`: start reading as soon as it is up. `onFinish` is told when
    /// a reading gets to the end, `onClose` when the window goes, for whatever
    /// reason.
    func show(
        _ text: String,
        told: Date,
        title: String = AwaySummary.title,
        autoplay: Bool = false,
        onFinish: (@MainActor () -> Void)? = nil,
        onClose: (@MainActor () -> Void)? = nil
    ) async {
        let voice = await TurkishVoice.current().identifier
        close()
        let player = SummaryPlayer(text: text, voiceIdentifier: voice)
        player.onFinish = onFinish
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "tr_TR")
        clock.dateFormat = "HH:mm"
        let view = SummaryPlayerView(player: player, title: title, told: clock.string(from: told)) { [weak self] in self?.close() }
        let host = FirstMouseHostingView(rootView: view)
        let size = host.fittingSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - size.width - 16, y: screen.maxY - size.height - 12))
        }
        panel.orderFrontRegardless()
        self.panel = panel
        self.player = player
        self.onClose = onClose
        guard autoplay else { return }
        player.play()
        // Nothing to say (no words in it): over already.
        if !player.isPlaying { onFinish?() }
    }

    func close() {
        player?.onFinish = nil
        player?.stop()
        player = nil
        panel?.orderOut(nil)
        panel = nil
        let closed = onClose
        onClose = nil
        closed?()
    }

    var isShowing: Bool { panel != nil }
    var isReading: Bool { player?.isPlaying ?? false }
}
