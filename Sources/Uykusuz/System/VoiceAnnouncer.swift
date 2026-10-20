import Foundation

/// Speaks one sentence. `SaySpeech` runs `say`; tests record instead.
protocol SpeechSynthesizing: Sendable {
    func speak(_ text: String) async
}

/// Says nothing: the default outside the live app, so tests never speak.
struct NoSpeech: SpeechSynthesizing {
    func speak(_ text: String) async {}
}

/// `/usr/bin/say` with the Turkish voice, the text passed as one argument
/// after `--`, so nothing in it is read as an option. Bounded: a voice that
/// hangs is killed after `timeout`.
struct SaySpeech: SpeechSynthesizing {
    static let sayPath = "/usr/bin/say"
    var voice = "Yelda"
    var rate = 170
    var timeout: TimeInterval = 30

    func speak(_ text: String) async {
        do {
            let r = try await Shell.run(Self.sayPath, ["-v", voice, "-r", String(rate), "--", text], timeout: timeout)
            if !r.succeeded {
                Log.error("say exited \(r.status): \(r.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        } catch {
            Log.error("say failed: \(error.localizedDescription)")
        }
    }
}

/// Spoken alerts while the lid is closed (fork addition). With the lid
/// closed a notification is never seen and the lid-close mute
/// (`LidActions`) silences the output, so the alert turns the default
/// output up to `volume` and unmutes it, speaks, and puts back exactly the
/// volume and mute it found. The journal's saved volume is not touched:
/// the open still restores the user's level from it.
///
/// It takes no lock: an alert must never hold up an end or a lid
/// transaction. If the lid opens while it speaks, the lid open restores the
/// output from the journal, so the alert then leaves the output alone
/// instead of putting its mute back; the open's own reassert covers an
/// open that lands between that check and the write.
@MainActor
final class VoiceAnnouncer {
    /// The level an alert is spoken at, whatever the output was set to.
    static let volume: Float = 0.5

    private let audio: any AudioControlling
    private let speech: any SpeechSynthesizing
    private let lidClosed: @MainActor () -> Bool
    private let enabled: @MainActor () -> Bool

    init(
        audio: any AudioControlling,
        speech: any SpeechSynthesizing = SaySpeech(),
        lidClosed: @escaping @MainActor () -> Bool,
        enabled: @escaping @MainActor () -> Bool
    ) {
        self.audio = audio
        self.speech = speech
        self.lidClosed = lidClosed
        self.enabled = enabled
    }

    /// Speaks `text` if alerts are on and the lid is closed; otherwise does
    /// nothing. Returns once the sentence is over and the output is back.
    func announce(_ text: String) async {
        guard enabled(), lidClosed() else { return }
        await Self.speakAudibly(text, audio: audio, speech: speech, lidStillClosed: lidClosed)
    }

    /// Unmute and raise, speak, restore. If the output cannot be read the
    /// sentence is still spoken at whatever the output is set to.
    static func speakAudibly(
        _ text: String,
        audio: any AudioControlling,
        speech: any SpeechSynthesizing,
        lidStillClosed: @MainActor () -> Bool
    ) async {
        let before: AudioOutput
        do {
            before = try audio.read()
        } catch {
            Log.error("voice alert: output not readable (\(error.localizedDescription)); speaking without changing it")
            await speech.speak(text)
            return
        }
        let changed = before.muted || before.volume != volume
        if changed {
            do {
                try audio.apply(volume: volume, muted: false, deviceUID: before.deviceUID)
            } catch {
                Log.error("voice alert: could not unmute \(before.deviceUID): \(error.localizedDescription)")
            }
        }
        await speech.speak(text)
        if changed, !lidStillClosed() {
            Log.info("voice alert: the lid opened while speaking; the open restores the output")
        } else if changed {
            do {
                try audio.apply(volume: before.volume, muted: before.muted, deviceUID: before.deviceUID)
            } catch {
                Log.error("voice alert: could not put \(before.deviceUID) back to volume \(before.volume), muted \(before.muted): \(error.localizedDescription)")
            }
        }
        Log.info("voice alert spoken")
    }

    /// What is said before a session ends with the lid closed, or nil for
    /// an end the user asked for.
    static func endSentence(_ reason: EndReason, batteryPercent: Int?) -> String? {
        switch reason {
        case .timer: "Süre doldu. Oturum bitiyor, Mac uyuyacak."
        case .batteryFloor: "Pil yüzde \(batteryPercent ?? 0). Oturum bitiyor, Mac uyuyacak."
        case .batteryUnreadable: "Pil düzeyi okunamıyor. Oturum bitiyor, Mac uyuyacak."
        case .thermalCritical: "Mac aşırı ısındı. Oturum bitiyor, Mac uyuyacak."
        case .agentIdle: "Claude kapandı. Oturum bitiyor, Mac uyuyacak."
        case .user, .quit, .backstop, .recoveryUnavailable, .startFailed: nil
        }
    }
}
