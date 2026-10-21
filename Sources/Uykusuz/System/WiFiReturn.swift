import CoreWLAN
import Foundation

/// When to leave the hotspot for a known Wi-Fi network (fork addition).
/// Pure, so the rules can be pinned without a radio.
///
/// Uykusuz never picks a network or holds a Wi-Fi password: it only leaves
/// the hotspot, and macOS joins one of the networks it already knows, with
/// the password it already has. So it leaves only when that is safe: a
/// known network that needs a password is in range and strong enough, and
/// no known network without one is (macOS might pick that). A network seen
/// open under the name of a known secured one counts as open.
enum WiFiReturnPolicy {
    struct Seen: Equatable, Sendable {
        let ssid: String
        let rssi: Int
        /// No password: open or Enhanced Open (OWE).
        let open: Bool
    }

    struct Known: Equatable, Sendable {
        let ssid: String
        let open: Bool
    }

    enum Decision: Equatable, Sendable {
        case stay(String)
        case leave(String)
    }

    /// A weaker one would not hold a connection better than the hotspot.
    static let minimumRSSI = -72

    static func decide(hotspot: String, seen: [Seen], known: [Known], minimumRSSI: Int = minimumRSSI) -> Decision {
        var knownBySSID: [String: Known] = [:]
        for network in known { knownBySSID[network.ssid] = knownBySSID[network.ssid] ?? network }
        let inRange = seen.filter { $0.ssid != hotspot && knownBySSID[$0.ssid] != nil }
        if let open = inRange.first(where: { $0.open || knownBySSID[$0.ssid]?.open == true }) {
            return .stay("bilinen parolasız bir ağ çevrede (\(open.ssid))")
        }
        guard let best = inRange.filter({ $0.rssi >= minimumRSSI }).max(by: { $0.rssi < $1.rssi }) else {
            return .stay("çevrede yeterince güçlü, bilinen ve parolalı bir ağ yok")
        }
        return .leave(best.ssid)
    }
}

/// The Wi-Fi radio as `WiFiReturn` uses it. `CoreWLANRadio` is the live one.
protocol WiFiRadio: Sendable {
    /// nil without Location permission or when not joined.
    func currentSSID() -> String?
    /// Whether the network joined now has no password; nil when not joined.
    func currentIsOpen() -> Bool?
    func scan() throws -> [WiFiReturnPolicy.Seen]
    func known() -> [WiFiReturnPolicy.Known]
    func disassociate()
}

struct CoreWLANRadio: WiFiRadio {
    private var interface: CWInterface? { CWWiFiClient.shared().interface() }

    static func isOpen(_ security: CWSecurity) -> Bool {
        security == .none || security == .OWE || security == .oweTransition
    }

    func currentSSID() -> String? { interface?.ssid() }

    func currentIsOpen() -> Bool? {
        guard let interface, interface.ssid() != nil else { return nil }
        let security = interface.security()
        return security == .unknown ? nil : Self.isOpen(security)
    }

    func scan() throws -> [WiFiReturnPolicy.Seen] {
        guard let interface else { return [] }
        return try interface.scanForNetworks(withSSID: nil).compactMap { network in
            guard let ssid = network.ssid else { return nil }
            let open = network.supportsSecurity(.none) || network.supportsSecurity(.OWE) || network.supportsSecurity(.oweTransition)
            return WiFiReturnPolicy.Seen(ssid: ssid, rssi: network.rssiValue, open: open)
        }
    }

    func known() -> [WiFiReturnPolicy.Known] {
        let profiles = interface?.configuration()?.networkProfiles.array as? [CWNetworkProfile] ?? []
        return profiles.compactMap { profile in
            profile.ssid.map { WiFiReturnPolicy.Known(ssid: $0, open: Self.isOpen(profile.security)) }
        }
    }

    func disassociate() { interface?.disassociate() }
}

/// Back from the hotspot to a known Wi-Fi network (fork addition): while a
/// session runs and the Mac is on the configured hotspot, every `interval`
/// the networks in range are scanned, and when `WiFiReturnPolicy` says so
/// the hotspot is left so macOS joins the known network. If macOS ends up
/// on a network without a password anyway, it is left too and the hotspot
/// joined again. A return that did not take waits `cooldown` before the
/// next. Turned off in Settings (`Config.returnToKnownWiFi`).
@MainActor
final class WiFiReturn {
    static let interval: TimeInterval = 2 * 60
    static let cooldown: TimeInterval = 10 * 60
    /// How long macOS gets to join the known network before it is checked.
    static let settle: Duration = .seconds(30)

    private let config: @MainActor () -> Config
    private let radio: any WiFiRadio
    private let rejoinHotspot: @MainActor () async -> Void
    private let clock: @MainActor () -> Date
    private var timer: Timer?
    private var checking = false
    private var lastLeave: Date?
    private var lastStayReason: String?

    init(
        config: @escaping @MainActor () -> Config,
        radio: any WiFiRadio = CoreWLANRadio(),
        clock: @escaping @MainActor () -> Date = { Date() },
        rejoinHotspot: @escaping @MainActor () async -> Void
    ) {
        self.config = config
        self.radio = radio
        self.clock = clock
        self.rejoinHotspot = rejoinHotspot
    }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// One look. Internal so tests drive it; `settle` is injected there.
    func check(settle: Duration = WiFiReturn.settle) async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        let c = config()
        let hotspot = HotspotSSID.normalized(c.hotspotSSID)
        guard c.returnToKnownWiFi, !hotspot.isEmpty else { return }
        let radio = self.radio
        guard await Task.detached(priority: .utility, operation: { radio.currentSSID() }).value == hotspot else {
            lastStayReason = nil
            return
        }
        let now = clock()
        if let lastLeave, now.timeIntervalSince(lastLeave) < Self.cooldown { return }
        let reading = await Task.detached(priority: .utility) { () -> (seen: [WiFiReturnPolicy.Seen], known: [WiFiReturnPolicy.Known])? in
            guard let seen = try? radio.scan() else { return nil }
            return (seen, radio.known())
        }.value
        guard let reading else {
            Log.error("wifi return: the scan failed; staying on the hotspot")
            return
        }
        switch WiFiReturnPolicy.decide(hotspot: hotspot, seen: reading.seen, known: reading.known) {
        case let .stay(reason):
            if reason != lastStayReason {
                Log.info("wifi return: staying on the hotspot: \(reason)")
                lastStayReason = reason
            }
        case let .leave(target):
            lastStayReason = nil
            lastLeave = now
            Log.info("wifi return: leaving the hotspot; known secured network \(target) is in range")
            await Task.detached(priority: .utility) { radio.disassociate() }.value
            try? await Task.sleep(for: settle)
            await verify(after: target, hotspot: hotspot)
        }
    }

    /// After the hotspot was left: on a network without a password, leave
    /// it and join the hotspot again; not joined at all, the failover's
    /// outage handling brings the hotspot back.
    private func verify(after target: String, hotspot: String) async {
        let radio = self.radio
        let (ssid, open) = await Task.detached(priority: .utility) { (radio.currentSSID(), radio.currentIsOpen()) }.value
        switch (ssid, open) {
        case (nil, _):
            Log.info("wifi return: not joined to a network yet; the failover takes over if Wi-Fi stays down")
        case let (current?, true?):
            Log.error("wifi return: macOS joined \(current), which has no password; leaving it for the hotspot")
            await Task.detached(priority: .utility) { radio.disassociate() }.value
            await rejoinHotspot()
        case let (current?, _) where current == hotspot:
            Log.info("wifi return: macOS went back to the hotspot; trying again in \(Int(Self.cooldown / 60)) min")
        case let (current?, _):
            Log.info("wifi return: now on \(current)\(current == target ? "" : " (macOS chose it over \(target))")")
        }
    }
}
