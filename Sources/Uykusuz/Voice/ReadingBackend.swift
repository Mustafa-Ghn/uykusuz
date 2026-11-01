import AVFoundation
import Foundation

/// What `SummaryPlayer` needs from a voice: read from a word, stop, and say
/// which word it is on.
@MainActor
protocol ReadingBackend: AnyObject {
    /// The written word being heard.
    var onWord: ((Int) -> Void)? { get set }
    /// The reading got to the end.
    var onFinish: (() -> Void)? { get set }
    /// This voice cannot read here.
    var onFailure: (() -> Void)? { get set }
    func start(fromWord index: Int)
    /// False when there is nothing to pause.
    func pause() -> Bool
    /// False when there is nothing to go on from.
    func resume() -> Bool
    func stop()
}

/// The system's voice. AVSpeechSynthesizer reports each word as it reads it
/// (`willSpeakRangeOfSpeechString`), with every system voice; it cannot jump
/// inside an utterance, so a move stops the reading and starts it again from
/// the chosen word.
@MainActor
final class SystemReading: NSObject, ReadingBackend, AVSpeechSynthesizerDelegate {
    var onWord: ((Int) -> Void)?
    var onFinish: (() -> Void)?
    var onFailure: (() -> Void)?

    private let text: String
    private let words: [NSRange]
    private let voiceIdentifier: String?
    private let synthesizer = AVSpeechSynthesizer()
    /// Where in `text` the utterance being read starts.
    private var offset = 0
    /// The utterance whose reports count; an earlier one's late reports after
    /// a move are dropped.
    private var active: ObjectIdentifier?

    init(text: String, words: [NSRange], voiceIdentifier: String?) {
        self.text = text
        self.words = words
        self.voiceIdentifier = voiceIdentifier
        super.init()
        synthesizer.delegate = self
    }

    func start(fromWord index: Int) {
        guard words.indices.contains(index) else { return }
        stop()
        offset = words[index].location
        let utterance = AVSpeechUtterance(string: (text as NSString).substring(from: offset))
        if let voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "tr-TR")
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        active = ObjectIdentifier(utterance)
        synthesizer.speak(utterance)
    }

    func pause() -> Bool {
        synthesizer.pauseSpeaking(at: .word)
    }

    func resume() -> Bool {
        guard synthesizer.isPaused else { return false }
        return synthesizer.continueSpeaking()
    }

    func stop() {
        active = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func spoke(_ range: NSRange, of utterance: ObjectIdentifier) {
        guard utterance == active else { return }
        if let index = SummaryPlayer.wordIndex(containing: offset + range.location, in: words) {
            onWord?(index)
        }
    }

    private func finished(_ utterance: ObjectIdentifier) {
        guard utterance == active else { return }
        active = nil
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

/// Where a reading's sound goes. `EngineOutput` is the speakers; tests drive
/// `NaturalReading` with their own.
@MainActor
protocol ReadingOutput: AnyObject {
    /// The sound stopped by itself (headphones came or went) and what was queued is gone.
    var onInterrupted: (@MainActor () -> Void)? { get set }
    func start() throws
    /// Queues mono 48 kHz audio; `played` runs once it has been heard.
    func schedule(_ samples: ArraySlice<Float>, played: @escaping @MainActor () -> Void)
    /// Seconds played since `reset`, or nil when it cannot tell.
    var position: Double? { get }
    func pause()
    func resume() throws
    /// Drops what is queued and starts counting from zero.
    func reset()
    func shutDown()
}

/// AVAudioEngine, only while a reading is on: `shutDown` leaves nothing running.
/// It never touches the input node, so no microphone permission is involved.
@MainActor
final class EngineOutput: ReadingOutput {
    var onInterrupted: (@MainActor () -> Void)?
    private var routeChange: NSObjectProtocol?
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: SpeechModel.sampleRate, channels: 1)!
    /// A `reset` makes the completions of what it dropped arrive; those do not count.
    private var epoch = 0
    private let volume: Float

    init(volume: Float = 1) {
        self.volume = volume
    }

    func start() throws {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = volume
        engine.prepare()
        try engine.start()
        player.play()
        routeChange = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onInterrupted?() }
        }
    }

    func schedule(_ samples: ArraySlice<Float>, played: @escaping @MainActor () -> Void) {
        guard !samples.isEmpty, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)), let channel = buffer.floatChannelData?[0] else {
            played()
            return
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: samples.count)
        }
        let scheduledIn = epoch
        player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.epoch == scheduledIn else { return }
                played()
            }
        }
    }

    var position: Double? {
        guard let time = player.lastRenderTime, let at = player.playerTime(forNodeTime: time) else { return nil }
        return Double(at.sampleTime) / at.sampleRate
    }

    func pause() {
        player.pause()
        engine.pause()
    }

    func resume() throws {
        try engine.start()
        player.play()
    }

    func reset() {
        epoch += 1
        player.stop()
        if engine.isRunning { player.play() }
    }

    func shutDown() {
        if let routeChange { NotificationCenter.default.removeObserver(routeChange) }
        routeChange = nil
        epoch += 1
        player.stop()
        engine.stop()
    }
}

/// The natural voice for a window's text: the whole text is voiced from the
/// start in the background, far faster than it is heard (`NaturalVoice`), and
/// plays as it arrives. A move inside what has arrived is immediate; a move
/// ahead of it waits the moment it takes to get there.
@MainActor
final class NaturalReading: ReadingBackend {
    nonisolated static let paragraphPause = 0.35
    /// How often the mark follows the sound. A reading is the only time this runs.
    static let markInterval: TimeInterval = 0.05

    var onWord: ((Int) -> Void)?
    var onFinish: (() -> Void)?
    var onFailure: (() -> Void)?

    private let text: String
    private let words: [NSRange]
    private let paragraphs: [NSRange]
    private let voice: NaturalVoice
    private let makeOutput: @MainActor () -> any ReadingOutput

    private struct Segment {
        let start: Double
        let samples: [Float]
        var end: Double { start + Double(samples.count) / SpeechModel.sampleRate }
    }

    private var output: (any ReadingOutput)?
    private var generation: Task<Void, Never>?
    /// Which voicing the arriving audio has to belong to: a stop ends one
    /// whose last piece may still be on its way.
    private var voicing = UUID()
    private var segments: [Segment] = []
    private var timeline = ReadingTimeline()
    private var generated = false
    /// Audio time of where the output's count started.
    private var base = 0.0
    /// The segments handed to the output, and how many of those it has played.
    private var nextToSchedule = 0
    private var outstanding = 0
    /// A word the audio has not reached: start there once it does.
    private var waitingFor: Int?
    private var playing = false
    private var markTimer: Timer?
    private var lastMarked: Int?
    /// The sound stopped by itself during a pause: `resume` queues it again.
    private var interrupted = false

    init(
        text: String,
        words: [NSRange],
        paragraphs: [NSRange],
        voice: NaturalVoice = .shared,
        makeOutput: @escaping @MainActor () -> any ReadingOutput = { EngineOutput() }
    ) {
        self.text = text
        self.words = words
        self.paragraphs = paragraphs
        self.voice = voice
        self.makeOutput = makeOutput
    }

    func start(fromWord index: Int) {
        guard words.indices.contains(index) else { return }
        playing = true
        if output == nil {
            let made = makeOutput()
            do {
                try made.start()
            } catch {
                Log.error("natural voice: no output: \(error.localizedDescription)")
                playing = false
                onFailure?()
                return
            }
            made.onInterrupted = { [weak self] in self?.soundInterrupted() }
            output = made
        } else {
            do {
                try output?.resume()
            } catch {
                Log.error("natural voice: no output: \(error.localizedDescription)")
            }
        }
        if generation == nil { generate() }
        startMarking()
        go(toWord: index)
    }

    func pause() -> Bool {
        guard playing else { return false }
        playing = false
        output?.pause()
        stopMarking()
        return true
    }

    func resume() -> Bool {
        guard !playing, output != nil else { return false }
        do {
            try output?.resume()
        } catch {
            Log.error("natural voice: could not go on: \(error.localizedDescription)")
            return false
        }
        playing = true
        startMarking()
        if interrupted {
            interrupted = false
            go(toWord: lastMarked ?? 0)
        }
        return true
    }

    /// The output changed under a reading. The engine has stopped and dropped
    /// its queue, so it starts again and goes on from the word being heard. Right
    /// after a change a device may not be ready yet, so a failed start gets
    /// one more try before the reading gives up on this voice.
    private func soundInterrupted() {
        guard output != nil else { return }
        guard playing else {
            interrupted = true
            return
        }
        let word = lastMarked ?? 0
        do {
            try output?.resume()
            go(toWord: word)
        } catch {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, self.playing, self.output != nil else { return }
                do {
                    try self.output?.resume()
                    self.go(toWord: word)
                } catch {
                    Log.error("natural voice: no output after a change: \(error.localizedDescription)")
                    self.failed(self.voicing)
                }
            }
        }
    }

    func stop() {
        playing = false
        stopMarking()
        generation?.cancel()
        generation = nil
        voicing = UUID()
        output?.shutDown()
        output = nil
        waitingFor = nil
        interrupted = false
        nextToSchedule = 0
        outstanding = 0
        base = 0
        lastMarked = nil
        segments = []
        timeline = ReadingTimeline()
        generated = false
    }

    // MARK: Voicing

    private func generate() {
        let voice = self.voice
        let text = self.text, words = self.words, paragraphs = self.paragraphs
        let id = voicing
        generation = Task.detached(priority: .utility) { [weak self] in
            do {
                try await voice.begin()
            } catch {
                Log.error("natural voice: \(error.localizedDescription)")
                await self?.failed(id)
                return
            }
            do {
                let plan = try await Self.plan(text: text, words: words, paragraphs: paragraphs, voice: voice)
                var time = 0.0
                for (number, paragraph) in plan.paragraphs.enumerated() {
                    var spoken = 0
                    for (i, piece) in SpokenPieces.chunk(paragraph.letters).enumerated() {
                        try Task.checkCancellation()
                        let rendered = try await voice.render(piece, seed: TorchNoise.pieceSeed(0, i))
                        var marks: [(Double, Int)] = []
                        var frames = 0
                        for count in rendered.wordFrames {
                            if let word = paragraph.word(ofSpoken: spoken) {
                                marks.append((time + Double(frames) / SpeechModel.framesPerSecond, word))
                            }
                            spoken += 1
                            frames += count
                        }
                        var samples = rendered.samples
                        samples += [Float](repeating: 0, count: Int((rendered.pause * SpeechModel.sampleRate).rounded()))
                        let start = time
                        time += Double(samples.count) / SpeechModel.sampleRate
                        await self?.arrived(id, start: start, samples: samples, marks: marks)
                    }
                    if number + 1 < plan.paragraphs.count {
                        let gap = [Float](repeating: 0, count: Int(Self.paragraphPause * SpeechModel.sampleRate))
                        await self?.arrived(id, start: time, samples: gap, marks: [])
                        time += Self.paragraphPause
                    }
                }
                await self?.voicedAll(id)
            } catch is CancellationError {
                // A stop.
            } catch {
                Log.error("natural voice: \(error.localizedDescription)")
                await self?.failed(id)
            }
            await voice.end()
        }
    }

    private nonisolated static func plan(text: String, words: [NSRange], paragraphs: [NSRange], voice: NaturalVoice) async throws -> ReadingPlan {
        // The sentences are voiced one at a time, so the plan is made in the voice's own isolation.
        var said: [String: String] = [:]
        let ns = text as NSString
        for range in paragraphs {
            var pieces: [NSRange] = []
            ns.enumerateSubstrings(in: range, options: [.bySentences, .substringNotRequired]) { _, sentence, _, _ in pieces.append(sentence) }
            if pieces.isEmpty { pieces = [range] }
            for piece in pieces {
                let sentence = ns.substring(with: piece)
                if said[sentence] == nil { said[sentence] = try await voice.letters(of: sentence) }
            }
        }
        let table = said
        return ReadingPlan.make(text: text, words: words, paragraphs: paragraphs) { table[$0] ?? "" }
    }

    private func arrived(_ id: UUID, start: Double, samples: [Float], marks: [(Double, Int)]) {
        guard id == voicing else { return }
        segments.append(Segment(start: start, samples: samples))
        for (time, word) in marks { timeline.append(time: time, word: word) }
        if let word = waitingFor {
            if timeline.time(ofWord: word) != nil {
                go(toWord: word)
            }
        } else {
            feed()
        }
    }

    private func voicedAll(_ id: UUID) {
        guard id == voicing else { return }
        generated = true
        if let word = waitingFor {
            if let last = timeline.words.last {
                // Past the last word there is sound for: read from that one.
                go(toWord: min(word, last))
            } else {
                // Nothing to say in it.
                waitingFor = nil
            }
        }
        finishIfOver()
    }

    private func failed(_ id: UUID) {
        guard id == voicing else { return }
        let wasPlaying = playing
        stop()
        if wasPlaying { onFailure?() }
    }

    // MARK: Playing

    private func go(toWord word: Int) {
        guard let time = timeline.time(ofWord: word) else {
            waitingFor = word
            return
        }
        waitingFor = nil
        output?.reset()
        outstanding = 0
        lastMarked = nil
        base = time
        guard let index = segments.lastIndex(where: { $0.start <= time }) else { return }
        let segment = segments[index]
        let skip = min(Int((time - segment.start) * SpeechModel.sampleRate), segment.samples.count)
        nextToSchedule = index + 1
        schedule(segment.samples[skip...])
        feed()
    }

    private func feed() {
        guard waitingFor == nil else { return }
        while nextToSchedule < segments.count {
            schedule(segments[nextToSchedule].samples[...])
            nextToSchedule += 1
        }
    }

    private func schedule(_ samples: ArraySlice<Float>) {
        outstanding += 1
        output?.schedule(samples) { [weak self] in
            guard let self else { return }
            self.outstanding -= 1
            self.finishIfOver()
        }
    }

    private func finishIfOver() {
        guard generated, outstanding == 0, nextToSchedule == segments.count, waitingFor == nil, output != nil else { return }
        let done = onFinish
        stop()
        done?()
    }

    // MARK: The mark

    private func startMarking() {
        guard markTimer == nil else { return }
        let timer = Timer(timeInterval: Self.markInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.mark() }
        }
        timer.tolerance = Self.markInterval / 2
        RunLoop.main.add(timer, forMode: .common)
        markTimer = timer
    }

    private func stopMarking() {
        markTimer?.invalidate()
        markTimer = nil
    }

    /// Internal so tests drive it.
    func mark() {
        guard let position = output?.position, position >= 0, waitingFor == nil else { return }
        guard let word = timeline.word(at: base + position), word != lastMarked else { return }
        lastMarked = word
        onWord?(word)
    }
}
