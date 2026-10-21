import AppKit
import AVFoundation
import SwiftUI

/// Reads the away summary aloud on request (fork addition): play and pause,
/// the word being read highlighted, and a bar to move back and forth.
/// Nothing is spoken until the user presses play.
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

    /// The text with the current word marked.
    var highlighted: AttributedString {
        var attributed = AttributedString(text)
        if let currentWord, words.indices.contains(currentWord),
           let range = Range(words[currentWord], in: attributed) {
            attributed[range].backgroundColor = Color.accentColor.opacity(0.28)
            attributed[range].foregroundColor = Color.primary
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
/// being read marked, and the controls.
struct SummaryPlayerView: View {
    let player: SummaryPlayer
    let told: String
    let onClose: () -> Void
    @State private var dragging: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "eye")
                    .foregroundStyle(.secondary)
                Text(AwaySummary.title)
                    .font(.headline)
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
            Text(player.highlighted)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
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
        .padding(16)
        .frame(width: 400)
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

    func show(_ text: String, told: Date) async {
        let voice = await TurkishVoice.current().identifier
        close()
        let player = SummaryPlayer(text: text, voiceIdentifier: voice)
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "tr_TR")
        clock.dateFormat = "HH:mm"
        let view = SummaryPlayerView(player: player, told: clock.string(from: told)) { [weak self] in self?.close() }
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
    }

    func close() {
        player?.stop()
        player = nil
        panel?.orderOut(nil)
        panel = nil
    }

    var isShowing: Bool { panel != nil }
}
