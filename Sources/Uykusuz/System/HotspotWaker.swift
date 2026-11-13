import Foundation
import ObjectiveC

/// What a phone answered when asked to turn its hotspot on: the network to
/// join and its password. Held for the one join it is for; never logged,
/// never stored.
struct HotspotWake: Equatable, Sendable {
    let ssid: String
    let password: String
}

enum HotspotWakeAnswer: Equatable, Sendable {
    /// This Mac cannot ask: a macOS the call was not measured on, or the
    /// system's hotspot browser is gone. The hotspot then needs a saved
    /// password, as it did before devices were asked.
    case unavailable
    /// Asked, and no device of that name turned its hotspot on: none in
    /// reach, not on the same Apple account, or Bluetooth off.
    case noAnswer
    case woken(HotspotWake)
}

/// Asks a nearby iPhone or iPad to turn its Personal Hotspot on.
protocol HotspotWaking: Sendable {
    func wake(named name: String) async -> HotspotWakeAnswer
}

/// A phone that serves no one does not broadcast its hotspot, so a scan
/// for its name finds nothing however near it is. The Wi-Fi menu gets
/// around that by asking the phone over Bluetooth, through the private
/// Sharing framework (`SFRemoteHotspotSession`), and so does this: browse
/// for the devices of the same Apple account, ask the one whose name is
/// the configured hotspot's (`HotspotSSID.same`) to turn its hotspot on,
/// and hand back the network name and password it answers with.
///
/// Measured on macOS 26 only. There the three selectors exist and the
/// answer comes as `(SFRemoteHotspotInfo?, NSError?)`. On any other macOS
/// nothing is called, and a class or selector that is gone ends the
/// attempt before the first call: the failover then scans for the name as
/// it always did.
struct SharingHotspotWaker: HotspotWaking {
    static let framework = "/System/Library/PrivateFrameworks/Sharing.framework/Sharing"
    static let measuredMajorVersions: Set<Int> = [26]
    /// How long a device gets to show up; one in reach shows up at once.
    static let browseTimeout: TimeInterval = 10
    /// How long the device gets to answer once asked (measured: 2 s).
    static let answerTimeout: TimeInterval = 30

    var osMajorVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion

    func wake(named name: String) async -> HotspotWakeAnswer {
        // A test run must not reach for the phones around the Mac.
        guard !TestProcess.isRunning, Self.measuredMajorVersions.contains(osMajorVersion) else { return .unavailable }
        return await withCheckedContinuation { continuation in
            // On the main queue, as the call was measured.
            DispatchQueue.main.async {
                guard let attempt = Attempt(name: name, continuation: continuation) else {
                    continuation.resume(returning: .unavailable)
                    return
                }
                attempt.start()
            }
        }
    }

    /// The text of an object's string property, read only when the object
    /// has it (a missing key would raise).
    static func string(_ selector: Selector, of object: AnyObject) -> String? {
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue() as? String
    }

    /// One browse and one question. The session calls back on a queue of
    /// its own choosing, so the state is behind a lock, and the timeouts
    /// keep the attempt alive until it has answered.
    private final class Attempt: NSObject, @unchecked Sendable {
        private static let setDelegate = NSSelectorFromString("setDelegate:")
        private static let startBrowsing = NSSelectorFromString("startBrowsing")
        private static let stopBrowsing = NSSelectorFromString("stopBrowsing")
        private static let enable = NSSelectorFromString("enableRemoteHotspotForDevice:withCompletionHandler:")
        private static let deviceName = NSSelectorFromString("deviceName")
        private static let infoName = NSSelectorFromString("name")
        private static let infoPassword = NSSelectorFromString("password")

        private typealias Answer = @convention(block) (UnsafeRawPointer?, UnsafeRawPointer?) -> Void
        private typealias Enable = @convention(c) (AnyObject, Selector, AnyObject, Answer) -> Void

        private let name: String
        private let session: NSObject
        private let began = Date()
        private let lock = NSLock()
        private var continuation: CheckedContinuation<HotspotWakeAnswer, Never>?
        private var asked = false

        init?(name: String, continuation: CheckedContinuation<HotspotWakeAnswer, Never>) {
            guard dlopen(SharingHotspotWaker.framework, RTLD_NOW) != nil,
                  let type = NSClassFromString("SFRemoteHotspotSession") as? NSObject.Type,
                  [Self.setDelegate, Self.startBrowsing, Self.stopBrowsing, Self.enable].allSatisfy(type.instancesRespond(to:)) else {
                Log.info("hotspot wake: this macOS has no way to ask a device for its hotspot")
                return nil
            }
            self.name = name
            self.continuation = continuation
            session = type.init()
            super.init()
        }

        func start() {
            _ = session.perform(Self.setDelegate, with: self)
            _ = session.perform(Self.startBrowsing)
            DispatchQueue.main.asyncAfter(deadline: .now() + SharingHotspotWaker.browseTimeout) { [self] in
                if !lock.withLock({ asked }) { finish(nil, "no device named like the hotspot is in reach") }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + SharingHotspotWaker.browseTimeout + SharingHotspotWaker.answerTimeout) { [self] in
                finish(nil, "the device did not answer")
            }
        }

        /// `SFRemoteHotspotSessionDelegate`: the devices in reach, again
        /// whenever the list changes.
        @objc(session:updatedFoundDevices:)
        func session(_ session: AnyObject, updatedFoundDevices devices: NSArray) {
            let device = devices.map { $0 as AnyObject }.first { device in
                SharingHotspotWaker.string(Self.deviceName, of: device).map { HotspotSSID.same($0, name) } ?? false
            }
            guard let device else { return }
            let first = lock.withLock { () -> Bool in
                guard !asked, continuation != nil else { return false }
                asked = true
                return true
            }
            guard first else { return }
            Log.info("hotspot wake: asking the device to turn its hotspot on")
            let answer: Answer = { [self] first, second in
                var wake: HotspotWake?
                var problem = "the device answered without a network"
                for pointer in [first, second] {
                    guard let pointer else { continue }
                    let object = Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
                    if let error = object as? NSError {
                        problem = "the device refused: \(error.domain) \(error.code)"
                    } else if let ssid = SharingHotspotWaker.string(Self.infoName, of: object), !ssid.isEmpty,
                              let password = SharingHotspotWaker.string(Self.infoPassword, of: object) {
                        wake = HotspotWake(ssid: ssid, password: password)
                    }
                }
                finish(wake, wake == nil ? problem : nil)
            }
            unsafeBitCast(self.session.method(for: Self.enable), to: Enable.self)(self.session, Self.enable, device, answer)
        }

        private func finish(_ wake: HotspotWake?, _ problem: String?) {
            let waiting = lock.withLock { () -> CheckedContinuation<HotspotWakeAnswer, Never>? in
                defer { continuation = nil }
                return continuation
            }
            guard let waiting else { return }
            _ = session.perform(Self.stopBrowsing)
            if let problem {
                Log.info("hotspot wake: \(problem)")
            } else {
                Log.info("hotspot wake: the device turned its hotspot on after \(FailoverMachine.humanGap(Date().timeIntervalSince(began)))")
            }
            waiting.resume(returning: wake.map(HotspotWakeAnswer.woken) ?? .noAnswer)
        }
    }
}
