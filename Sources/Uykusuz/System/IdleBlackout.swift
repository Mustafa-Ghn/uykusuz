import Foundation
import IOKit.pwr_mgt

/// Keeps the display from idling on its own: no screen saver and no
/// display sleep while held.
protocol DisplayAwakeHolding: AnyObject {
    func hold()
    func release()
}

/// Holds nothing: the default outside the live app, so tests never take a
/// system assertion.
final class NoDisplayAwake: DisplayAwakeHolding {
    func hold() {}
    func release() {}
}

/// One `PreventUserIdleDisplaySleep` assertion, as a video player takes:
/// loginwindow starts no screen saver and powerd does not sleep the display
/// while it is held.
final class DisplayAwakeAssertion: DisplayAwakeHolding {
    private var id: IOPMAssertionID = 0
    private var held = false

    func hold() {
        guard !held else { return }
        let r = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Uykusuz: boşta siyah ekran" as CFString,
            &id
        )
        if r == kIOReturnSuccess {
            held = true
        } else {
            Log.error("display assertion not taken (\(r)); the screen saver may start")
        }
    }

    func release() {
        guard held else { return }
        IOPMAssertionRelease(id)
        held = false
    }

    deinit {
        if held { IOPMAssertionRelease(id) }
    }
}

/// Locks the login session.
protocol ScreenLocking: Sendable {
    func lock() throws
}

/// Locks nothing: the default outside the live app, so tests never lock
/// the screen.
struct NoScreenLock: ScreenLocking {
    func lock() throws {}
}

/// Locks the session at once, as the Lock Screen item of Control Center
/// does: `SACLockScreenImmediate` in the private login framework. No screen
/// saver starts and the display is not touched, so a panel the idle black
/// screen holds at 0 shows nothing until the user comes back.
struct LoginScreenLock: ScreenLocking {
    static let frameworkPath = "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login"
    private typealias Lock = @convention(c) () -> Int32

    func lock() throws {
        guard let handle = dlopen(Self.frameworkPath, RTLD_LAZY),
              let symbol = dlsym(handle, "SACLockScreenImmediate") else {
            throw DisplayPowerError(what: "login.framework içinde SACLockScreenImmediate yok")
        }
        let result = unsafeBitCast(symbol, to: Lock.self)()
        if result != 0 { Log.info("SACLockScreenImmediate returned \(result)") }
    }
}

/// The idle black screen (fork addition): while a session runs with the lid
/// open, the screen saver and display sleep are held off (`awake`), and
/// after `idleBlackoutAfter` seconds without input the display goes to
/// brightness 0, which on a Mac laptop turns the backlight off, so the panel
/// gives no light. The keyboard backlight goes off after `keyboardOffAfter`.
/// Any input brings both back to the levels they had. When the user stays
/// away `lockAfterBlackout` past the black, the session is locked
/// (`ScreenLocking`): the assertion keeps macOS from locking it as it would
/// on display sleep.
///
/// What it changed is held only here, in memory. While it holds a level the
/// brightness sampler must not take the black for the user's level
/// (`isHoldingDisplay`, `isHoldingKeyboard`), and before a lid close it is
/// turned off (`setActive(false)`): the levels come back, so the close
/// journals the user's, and the assertion goes, so the close's display sleep
/// request is honoured. If the app dies while black, the panel stays dark
/// until the brightness keys or the next input after a relaunch.
@MainActor
final class IdleBlackout {
    /// Input within this many seconds counts as the user being back.
    static let activeWithin: TimeInterval = 1
    static let tickInterval: TimeInterval = 0.5

    private let display: any DisplayDimming
    private let keyboard: any KeyboardBacklighting
    private let idleSeconds: @Sendable () -> Double
    private let config: @MainActor () -> Config
    private let awake: any DisplayAwakeHolding
    private let screenLock: any ScreenLocking
    private var timer: (any DispatchSourceTimer)?
    private(set) var active = false
    /// Locked for this absence: not again until the user is back.
    private(set) var locked = false
    /// The user's display level, held while the display is black.
    private(set) var savedDisplay: Float?
    /// The user's keyboard level, held while the backlight is off.
    private(set) var savedKeyboard: Float?

    var isHoldingDisplay: Bool { savedDisplay != nil }
    var isHoldingKeyboard: Bool { savedKeyboard != nil }

    init(
        display: any DisplayDimming,
        keyboard: any KeyboardBacklighting,
        idleSeconds: @escaping @Sendable () -> Double,
        config: @escaping @MainActor () -> Config,
        awake: any DisplayAwakeHolding = NoDisplayAwake(),
        screenLock: any ScreenLocking = NoScreenLock()
    ) {
        self.display = display
        self.keyboard = keyboard
        self.idleSeconds = idleSeconds
        self.config = config
        self.awake = awake
        self.screenLock = screenLock
    }

    /// Turns the idle watch on or off. Off restores anything it darkened
    /// and lets the display idle on its own again.
    func setActive(_ on: Bool, startTimer: Bool = true) {
        guard on != active else { return }
        active = on
        if on {
            awake.hold()
            Log.info("idle black screen on")
            if startTimer { startTicking() }
        } else {
            timer?.cancel()
            timer = nil
            restore()
            awake.release()
            Log.info("idle black screen off")
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
        if idle >= c.idleBlackoutAfter {
            darkenDisplay(idle: idle)
        }
        if c.lockAfterBlackout > 0, !locked, idle >= c.idleBlackoutAfter + c.lockAfterBlackout {
            // Once per absence, failed or not: never a retry every tick.
            locked = true
            do {
                try screenLock.lock()
                Log.info("idle black screen: session locked after \(Int(c.lockAfterBlackout / 60)) min black")
            } catch {
                Log.error("idle black screen: lock failed: \(error.localizedDescription)")
            }
        }
        if savedKeyboard == nil, idle >= c.keyboardOffAfter {
            do {
                if let current = try keyboard.readBrightness(), current > 0, !keyboard.isSuppressedOrDimmed() {
                    try keyboard.setBrightness(0)
                    savedKeyboard = current
                    Log.info("idle black screen: keyboard backlight off after \(Int(idle)) s idle (was \(current))")
                }
            } catch {
                Log.error("idle black screen: keyboard backlight off skipped: \(error.localizedDescription)")
            }
        }
    }

    /// Puts back what this darkened. Safe to call any time.
    func restore() {
        locked = false
        if let level = savedDisplay {
            savedDisplay = nil
            do {
                try display.setBrightness(level)
                Log.info("idle black screen: display back to \(level)")
            } catch {
                Log.error("idle black screen: display restore to \(level) failed: \(error.localizedDescription)")
            }
        }
        if let level = savedKeyboard {
            savedKeyboard = nil
            do {
                try keyboard.setBrightness(level)
                Log.info("idle black screen: keyboard backlight back to \(level)")
            } catch {
                Log.error("idle black screen: keyboard backlight restore to \(level) failed: \(error.localizedDescription)")
            }
        }
    }

    /// Brightness 0, saving the user's level the first time. Already black:
    /// set 0 again if something (auto-brightness) lit the panel since.
    private func darkenDisplay(idle: Double) {
        do {
            let current = try display.readBrightness()
            guard current > 0 else { return }
            try display.setBrightness(0)
            if savedDisplay == nil {
                savedDisplay = current
                Log.info("idle black screen: display off after \(Int(idle)) s idle (was \(current))")
            }
        } catch {
            Log.error("idle black screen: display darken skipped: \(error.localizedDescription)")
        }
    }

    private func startTicking() {
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + Self.tickInterval, repeating: Self.tickInterval, leeway: .milliseconds(100))
        t.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer = t
        t.resume()
    }
}
