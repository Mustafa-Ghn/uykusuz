import Foundation
import ObjectiveC

/// macOS's "Ask to join hotspots" (Sistem Ayarları > Wi-Fi > Erişim
/// noktalarına katılmak için sor), which the hotspot failover wants on
/// Otomatik (fork addition). Read through the private CoreWiFi framework,
/// as System Settings' Wi-Fi pane does (`CWFInterface.autoHotspotMode`);
/// read only, never changed (a change needs an administrator).
///
/// Only Otomatik's value is known: 3, read on macOS 26 with the setting on
/// Otomatik. Anything else is "not automatic", whichever of Never and Ask
/// it is. On a macOS the call was not measured on, the setting reads as
/// unknown and Settings shows nothing rather than a guess.
enum HotspotJoinMode: Equatable, Sendable {
    case automatic
    case notAutomatic(Int)
    case unknown

    static let automaticValue = 3
    static let measuredMajorVersions: Set<Int> = [26]

    static func from(raw: Int?) -> HotspotJoinMode {
        guard let raw else { return .unknown }
        return raw == automaticValue ? .automatic : .notAutomatic(raw)
    }

    /// Asks the Wi-Fi daemon, so it can wait a moment: call off the main
    /// actor.
    static func read(osMajorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion) -> HotspotJoinMode {
        guard measuredMajorVersions.contains(osMajorVersion) else { return .unknown }
        return from(raw: readRaw())
    }

    private static func readRaw() -> Int? {
        guard dlopen("/System/Library/PrivateFrameworks/CoreWiFi.framework/CoreWiFi", RTLD_NOW) != nil,
              let type = NSClassFromString("CWFInterface") as? NSObject.Type else { return nil }
        let getter = NSSelectorFromString("autoHotspotMode")
        guard type.instancesRespond(to: getter) else { return nil }
        let interface = type.init()
        let activate = NSSelectorFromString("activate")
        let invalidate = NSSelectorFromString("invalidate")
        if interface.responds(to: activate) { _ = interface.perform(activate) }
        defer { if interface.responds(to: invalidate) { _ = interface.perform(invalidate) } }
        guard let implementation = interface.method(for: getter) else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Int
        return unsafeBitCast(implementation, to: Getter.self)(interface, getter)
    }

    /// System Settings' Wi-Fi pane.
    static let wifiSettingsURL = URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")!
}
