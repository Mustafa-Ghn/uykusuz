import Foundation

/// Code mode's idle dimming (fork addition): while code mode is on (lid
/// open, a session active, an agent at work), the display goes down to
/// `codeModeDimLevel` after `codeModeDimAfter` seconds without input and
/// the keyboard backlight goes off after `codeModeKeyboardOffAfter`. Any
/// input brings both back to the levels they had.
///
/// What it changed is held only here, in memory. While it holds a level
/// the brightness sampler must not take the dimmed value for the user's
/// (`isHoldingDisplay`, `isHoldingKeyboard`), and before a lid close it is
/// put back (`setActive(false)`), so the close journals the user's level,
/// not the dim. If the app dies while dimmed the panel stays dim until the
/// brightness keys or the next input after a relaunch; nothing worse.
@MainActor
final class CodeModeDimmer {
    /// Input within this many seconds counts as the user being back.
    static let activeWithin: TimeInterval = 1.5
    static let tickInterval: TimeInterval = 1

    private let display: any DisplayDimming
    private let keyboard: any KeyboardBacklighting
    private let idleSeconds: @Sendable () -> Double
    private let config: @MainActor () -> Config
    private var timer: (any DispatchSourceTimer)?
    private(set) var active = false
    /// The user's display level, held while the display is dimmed.
    private(set) var savedDisplay: Float?
    /// The user's keyboard level, held while the backlight is off.
    private(set) var savedKeyboard: Float?

    var isHoldingDisplay: Bool { savedDisplay != nil }
    var isHoldingKeyboard: Bool { savedKeyboard != nil }

    init(
        display: any DisplayDimming,
        keyboard: any KeyboardBacklighting,
        idleSeconds: @escaping @Sendable () -> Double,
        config: @escaping @MainActor () -> Config
    ) {
        self.display = display
        self.keyboard = keyboard
        self.idleSeconds = idleSeconds
        self.config = config
    }

    /// Turns the idle watch on or off. Off restores anything dimmed first.
    func setActive(_ on: Bool, startTimer: Bool = true) {
        guard on != active else { return }
        active = on
        if on {
            Log.info("code mode on")
            if startTimer { startTicking() }
        } else {
            timer?.cancel()
            timer = nil
            restore()
            Log.info("code mode off")
        }
    }

    /// One look at the idle time. Internal so tests drive it.
    func tick() {
        guard active else { return }
        let idle = idleSeconds()
        if idle < Self.activeWithin {
            restore()
            return
        }
        let c = config()
        if savedDisplay == nil, idle >= c.codeModeDimAfter {
            do {
                let current = try display.readBrightness()
                if current > c.codeModeDimLevel {
                    try display.setBrightness(c.codeModeDimLevel)
                    savedDisplay = current
                    Log.info("code mode: display dimmed after \(Int(idle)) s idle (was \(current))")
                }
            } catch {
                Log.error("code mode: display dim skipped: \(error.localizedDescription)")
            }
        }
        if savedKeyboard == nil, idle >= c.codeModeKeyboardOffAfter {
            do {
                if let current = try keyboard.readBrightness(), current > 0, !keyboard.isSuppressedOrDimmed() {
                    try keyboard.setBrightness(0)
                    savedKeyboard = current
                    Log.info("code mode: keyboard backlight off after \(Int(idle)) s idle (was \(current))")
                }
            } catch {
                Log.error("code mode: keyboard backlight off skipped: \(error.localizedDescription)")
            }
        }
    }

    /// Puts back what this dimmed. Safe to call any time.
    func restore() {
        if let level = savedDisplay {
            savedDisplay = nil
            do {
                try display.setBrightness(level)
                Log.info("code mode: display back to \(level)")
            } catch {
                Log.error("code mode: display restore to \(level) failed: \(error.localizedDescription)")
            }
        }
        if let level = savedKeyboard {
            savedKeyboard = nil
            do {
                try keyboard.setBrightness(level)
                Log.info("code mode: keyboard backlight back to \(level)")
            } catch {
                Log.error("code mode: keyboard backlight restore to \(level) failed: \(error.localizedDescription)")
            }
        }
    }

    private func startTicking() {
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + Self.tickInterval, repeating: Self.tickInterval, leeway: .milliseconds(200))
        t.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer = t
        t.resume()
    }
}
