import AppKit
import Darwin
import Foundation

/// What the Mac is doing, for the notebook's look (`MacAdvisor`): booted
/// simulators, Docker containers, the apps holding the most memory or CPU,
/// and memory, swap, battery and disk. Names and figures only: no window
/// titles, file names, paths or command lines.
struct MacSnapshot: Equatable, Sendable {
    struct Simulator: Equatable, Sendable {
        var udid: String
        var name: String
        var runtime: String
        var bootedAt: Date?
        /// Apps running inside it.
        var openApps: [String] = []
        /// Processes outside it that name it, such as `simctl spawn … log
        /// stream` or a test run.
        var attached = 0
        /// When the newest Claude Code session that names it last wrote,
        /// within `sessionWindow`.
        var sessionWrote: Date?

        /// Someone is using it: never offered for a shutdown.
        var inUse: Bool { sessionWrote != nil || attached > 0 }
    }

    struct Container: Equatable, Sendable {
        var id: String
        var name: String
        var image: String
        var status: String
        var cpu: String?
        var memory: String?
    }

    struct App: Equatable, Sendable {
        var name: String
        /// nil for a process that is not part of an app.
        var bundleID: String?
        var memory: UInt64
        /// Percent of one core over the reading's two seconds.
        var cpu: Double
        /// When Uykusuz last saw it come to the front.
        var lastActive: Date?
        /// A Dock or menu bar app, which can be asked to quit.
        var canQuit: Bool
        var menuBar = false
    }

    var taken: Date
    var simulators: [Simulator] = []
    var containers: [Container] = []
    var apps: [App] = []
    var memoryTotal: UInt64 = 0
    /// `kern.memorystatus_vm_pressure_level`: 1 normal, 2 warning, 4 critical.
    var memoryPressure: Int?
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    var batteryPercent: Int?
    var charging = false
    var thermal: ProcessInfo.ThermalState = .nominal
    var diskFree: Int64?
    var diskTotal: Int64?
    var uptime: TimeInterval = 0
    var xcodeRunning = false
    var simulatorAppRunning = false
    /// Since Uykusuz started, which bounds what `lastActive` can say.
    var watchingSince: Date?
    /// Every running app, to tell whether an offered one still runs. Not sent.
    var runningBundleIDs: Set<String> = []

    static let appsByMemory = 10
    static let appsByCPU = 5
    static let busyCPU = 20.0
    static let simulatorsGroup = "iOS Simülatörleri"
    static let xcodeBundleID = "com.apple.dt.Xcode"
    static let simulatorBundleID = "com.apple.iphonesimulator"
    static let dockerBundleID = FreezePlanner.dockerBundleId
    /// Listed whatever they hold: what a look is most often about.
    static let alwaysListed: Set<String> = [xcodeBundleID, simulatorBundleID, dockerBundleID]

    // MARK: As text

    /// The snapshot as the lines Claude reads, in Turkish. `protected`: apps
    /// Uykusuz never asks to quit, marked so Claude does not offer it.
    func text(now: Date, protected: Set<String> = []) -> String {
        var lines: [String] = []
        lines.append("Mac \(Self.span(uptime)) önce açıldı.")
        var memory = "Bellek: \(Self.bytes(memoryTotal))"
        if let pressure = memoryPressure { memory += ", baskı \(Self.pressureName(pressure))" }
        memory += swapTotal > 0 ? ", takas \(Self.bytes(swapUsed)) / \(Self.bytes(swapTotal)) dolu." : ", takas kullanılmıyor."
        lines.append(memory)
        if let batteryPercent {
            lines.append("Pil: %\(batteryPercent), \(charging ? "şarjda" : "pilde"); ısı \(Self.thermalName(thermal)).")
        } else {
            lines.append("Pil yok; ısı \(Self.thermalName(thermal)).")
        }
        if let diskFree {
            lines.append("Disk: \(Self.bytes(UInt64(max(diskFree, 0)))) boş" + (diskTotal.map { " / \(Self.bytes(UInt64(max($0, 0))))" } ?? "") + ".")
        }
        lines.append("Xcode \(xcodeRunning ? "açık" : "kapalı"), Simulator uygulaması \(simulatorAppRunning ? "açık" : "kapalı").")
        if runningBundleIDs.contains(Self.dockerBundleID) {
            lines.append("Docker Desktop açık; sanal makinesi com.apple.Virtualization.VirtualMachine adıyla görünebilir.")
        }
        if simulators.isEmpty {
            lines.append("Açık simülatör yok.")
        } else {
            lines.append("Açık simülatörler:")
            for s in simulators {
                var line = "- \(s.name) (\(s.runtime)), udid \(s.udid)"
                if let booted = s.bootedAt { line += ", \(Self.span(now.timeIntervalSince(booted))) önce açıldı" }
                if !s.openApps.isEmpty { line += ", içinde açık: \(s.openApps.joined(separator: ", "))" }
                if let wrote = s.sessionWrote { line += ", bir Claude Code oturumu bununla çalışıyor (\(Self.span(now.timeIntervalSince(wrote))) önce yazdı)" }
                if s.attached > 0 { line += ", \(s.attached) süreç buna bağlı" }
                if !s.inUse { line += ", kullanan bir oturum ya da süreç görünmüyor" }
                lines.append(line)
            }
        }
        if containers.isEmpty {
            lines.append("Çalışan Docker kapsayıcısı yok.")
        } else {
            lines.append("Çalışan Docker kapsayıcıları:")
            for c in containers {
                var line = "- \(c.name) (\(c.image)), id \(c.id), \(c.status)"
                if let cpu = c.cpu { line += ", işlemci \(cpu)" }
                if let memory = c.memory { line += ", bellek \(memory)" }
                lines.append(line)
            }
        }
        lines.append("En çok bellek ya da işlemci kullananlar:")
        for app in apps {
            var line = "- \(app.name)"
            if let id = app.bundleID { line += " (\(id))" }
            line += ": \(Self.bytes(app.memory)) bellek, işlemci %\(Int(app.cpu.rounded()))"
            if let active = app.lastActive {
                line += ", en son \(Self.span(now.timeIntervalSince(active))) önce öne geldi"
            } else if app.canQuit, !app.menuBar, let since = watchingSince {
                line += ", son \(Self.span(now.timeIntervalSince(since))) içinde hiç öne gelmedi"
            }
            if app.menuBar { line += ", menü çubuğu uygulaması" }
            if let id = app.bundleID, protected.contains(id) { line += ", Uykusuz bundan çıkmaz" }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    static func bytes(_ value: UInt64) -> String {
        let gb = Double(value) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb).replacingOccurrences(of: ".", with: ",") }
        return "\(Int((Double(value) / 1_048_576).rounded())) MB"
    }

    static func span(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(seconds, 0) / 60)
        if minutes < 60 { return "\(max(minutes, 1)) dakika" }
        let hours = minutes / 60
        if hours < 48 { return "\(hours) saat" }
        return "\(hours / 24) gün"
    }

    static func pressureName(_ level: Int) -> String {
        switch level {
        case 4: "kritik"
        case 2: "yüksek"
        default: "normal"
        }
    }

    static func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .fair: "ılık"
        case .serious: "sıcak"
        case .critical: "çok sıcak"
        default: "normal"
        }
    }

    // MARK: Parsing

    /// `xcrun simctl list devices booted -j`.
    static func parseSimulators(_ json: Data) -> [Simulator] {
        struct List: Decodable {
            struct Device: Decodable {
                let udid: String
                let name: String
                let state: String
                let lastBootedAt: String?
            }
            let devices: [String: [Device]]
        }
        guard let list = try? JSONDecoder().decode(List.self, from: json) else { return [] }
        let iso = ISO8601DateFormatter()
        var out: [Simulator] = []
        for (runtime, devices) in list.devices.sorted(by: { $0.key < $1.key }) {
            for device in devices where device.state == "Booted" && UUID(uuidString: device.udid) != nil {
                out.append(Simulator(
                    udid: device.udid,
                    name: device.name,
                    runtime: runtimeName(runtime),
                    bootedAt: device.lastBootedAt.flatMap { iso.date(from: $0) }
                ))
            }
        }
        return out
    }

    /// `com.apple.CoreSimulator.SimRuntime.iOS-26-0` as "iOS 26.0".
    static func runtimeName(_ identifier: String) -> String {
        let last = identifier.split(separator: ".").last.map(String.init) ?? identifier
        let parts = last.split(separator: "-").map(String.init)
        guard parts.count >= 2 else { return last }
        return parts[0] + " " + parts.dropFirst().joined(separator: ".")
    }

    /// `docker ps` with `{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}` and
    /// `docker stats --no-stream` with `{{.ID}}\t{{.CPUPerc}}\t{{.MemUsage}}`.
    static func parseContainers(ps: String, stats: String) -> [Container] {
        var figures: [String: (cpu: String, memory: String)] = [:]
        for line in stats.split(separator: "\n") {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard f.count >= 3, f[1] != "--" else { continue }
            figures[f[0]] = (f[1], f[2])
        }
        return ps.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard f.count >= 4, isContainerID(f[0]) else { return nil }
            let figure = figures[f[0]]
            return Container(id: f[0], name: f[1], image: f[2], status: f[3], cpu: figure?.cpu, memory: figure?.memory)
        }
    }

    static func isContainerID(_ value: String) -> Bool {
        (12...64).contains(value.count) && value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    /// What a process is counted under: the outermost app it is part of,
    /// every simulator process together, or its own executable's name.
    static func group(path: String?, name: String) -> (name: String, appPath: String?) {
        guard let path, !path.isEmpty else { return (name, nil) }
        if path.contains("/CoreSimulator/") { return (simulatorsGroup, nil) }
        if let range = path.range(of: ".app/") {
            let appPath = String(path[..<range.lowerBound]) + ".app"
            return (URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent, appPath)
        }
        return (URL(fileURLWithPath: path).lastPathComponent, nil)
    }

    struct ProcessReading: Sendable {
        var path: String?
        var name: String
        var memory: UInt64
        var cpuTime: TimeInterval
    }

    struct RunningApp: Sendable {
        var path: String
        var bundleID: String
        /// In the Dock or the menu bar: not a background agent.
        var canQuit: Bool
        var menuBar = false
    }

    /// Processes added up per app (`group`), heaviest first: the top
    /// `appsByMemory` by memory, any of the top `appsByCPU` by CPU that
    /// works harder than `busyCPU`, and the apps of `alwaysListed` that run.
    /// `before` holds each pid's CPU time two seconds earlier. Uykusuz itself
    /// is left out.
    static func apps(
        _ readings: [pid_t: ProcessReading],
        before: [pid_t: TimeInterval],
        seconds: TimeInterval,
        running: [RunningApp],
        lastActive: [String: Date],
        ownBundleID: String?
    ) -> [App] {
        var sums: [String: App] = [:]
        for (pid, reading) in readings {
            let (name, appPath) = group(path: reading.path, name: reading.name)
            let owner = appPath.flatMap { path in running.first { $0.path == path } }
            if let ownBundleID, owner?.bundleID == ownBundleID { continue }
            var app = sums[name] ?? App(
                name: name,
                bundleID: owner?.bundleID,
                memory: 0,
                cpu: 0,
                lastActive: owner.flatMap { lastActive[$0.bundleID] },
                canQuit: owner?.canQuit ?? false,
                menuBar: owner?.menuBar ?? false
            )
            app.memory += reading.memory
            if let earlier = before[pid], seconds > 0 {
                app.cpu += max(reading.cpuTime - earlier, 0) / seconds * 100
            }
            sums[name] = app
        }
        let all = Array(sums.values)
        var chosen = Array(all.sorted { $0.memory > $1.memory }.prefix(appsByMemory))
        for app in all.sorted(by: { $0.cpu > $1.cpu }).prefix(appsByCPU) where app.cpu >= busyCPU && !chosen.contains(where: { $0.name == app.name }) {
            chosen.append(app)
        }
        for app in all where app.bundleID.map(alwaysListed.contains) == true && !chosen.contains(where: { $0.name == app.name }) {
            chosen.append(app)
        }
        return chosen
    }

    // MARK: Live

    static let cpuWindow: Duration = .seconds(2)
    static let commandTimeout: TimeInterval = 15
    /// How recent a session's transcript has to be for its simulators to count as in use.
    static let sessionWindow: TimeInterval = 6 * 3600
    /// How much of a transcript's end is searched for a simulator's UDID.
    static let transcriptTail = 2 << 20

    /// Which simulators a Claude Code session is working with: the UDID in the
    /// end of a transcript written within `sessionWindow` (a name such as
    /// "iPhone 17 Pro" is too common to tell). Only searched: nothing of the
    /// transcripts is kept or sent.
    nonisolated static func sessionUse(of udids: [String], projects: URL, now: Date, tail: Int = transcriptTail) -> [String: Date] {
        guard !udids.isEmpty, let files = FileManager.default.enumerator(at: projects, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]) else { return [:] }
        let needles = udids.map { ($0, Data($0.utf8)) }
        var out: [String: Date] = [:]
        for case let url as URL in files where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let wrote = values.contentModificationDate,
                  now.timeIntervalSince(wrote) <= sessionWindow,
                  let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }
            let size = (try? handle.seekToEnd()) ?? 0
            try? handle.seek(toOffset: size > UInt64(tail) ? size - UInt64(tail) : 0)
            guard let data = try? handle.readToEnd() else { continue }
            for (udid, needle) in needles where data.range(of: needle) != nil {
                out[udid] = max(out[udid] ?? .distantPast, wrote)
            }
        }
        return out
    }

    /// For each simulator, the processes outside it whose arguments or
    /// environment name its UDID. What runs inside one (under its
    /// `launchd_sim`) names it too, and does not count.
    nonisolated static func attachedCounts(_ udids: [String], processes: [BashToolWatcher.Process], arguments: (pid_t) -> String?) -> [String: Int] {
        guard !udids.isEmpty else { return [:] }
        var children: [pid_t: [pid_t]] = [:]
        for p in processes { children[p.ppid, default: []].append(p.pid) }
        var inside = Set<pid_t>()
        var stack = processes.filter { $0.name == "launchd_sim" }.map(\.pid)
        while let pid = stack.popLast() {
            guard inside.insert(pid).inserted else { continue }
            stack += children[pid] ?? []
        }
        var out: [String: Int] = [:]
        for p in processes where !inside.contains(p.pid) {
            guard let text = arguments(p.pid) else { continue }
            for udid in udids where text.contains(udid) { out[udid, default: 0] += 1 }
        }
        return out
    }

    /// The apps running inside each simulator, from their executables' paths.
    static func simulatorApps(paths: [String]) -> [String: [String]] {
        var out: [String: Set<String>] = [:]
        for path in paths {
            guard let devices = path.range(of: "/CoreSimulator/Devices/"),
                  let bundle = path.range(of: "/data/Containers/Bundle/Application/", range: devices.upperBound..<path.endIndex) else { continue }
            let udid = String(path[devices.upperBound..<bundle.lowerBound])
            let rest = path[bundle.upperBound...].split(separator: "/")
            guard UUID(uuidString: udid) != nil, rest.count >= 2, rest[1].hasSuffix(".app") else { continue }
            out[udid, default: []].insert(String(rest[1].dropLast(4)))
        }
        return out.mapValues { $0.sorted() }
    }

    /// The Mac now. `lastActive`: bundle id to when it last came to the front.
    @MainActor
    static func live(lastActive: [String: Date], watchingSince: Date?, now: Date = Date()) async -> MacSnapshot {
        let running = NSWorkspace.shared.runningApplications.compactMap { app -> RunningApp? in
            guard let path = app.bundleURL?.path, let id = app.bundleIdentifier else { return nil }
            return RunningApp(path: path, bundleID: id, canQuit: app.activationPolicy != .prohibited, menuBar: app.activationPolicy == .accessory)
        }
        let ids = Set(running.map(\.bundleID))
        let own = Bundle.main.bundleIdentifier
        let measured = await Task.detached(priority: .utility) { () -> (apps: [App], simulatorApps: [String: [String]], hasSimulators: Bool, hasDockerVM: Bool) in
            let first = liveReadings()
            try? await Task.sleep(for: cpuWindow)
            let second = liveReadings()
            let seconds = Double(cpuWindow.components.seconds)
            let apps = apps(second, before: first.mapValues(\.cpuTime), seconds: seconds, running: running, lastActive: lastActive, ownBundleID: own)
            let names = second.values.map(\.name)
            return (apps, simulatorApps(paths: second.values.compactMap(\.path)), names.contains("launchd_sim"), names.contains(where: DockerWatcher.isVirtualMachine))
        }.value
        var snapshot = MacSnapshot(taken: now)
        snapshot.apps = measured.apps
        snapshot.watchingSince = watchingSince
        snapshot.runningBundleIDs = ids
        snapshot.xcodeRunning = ids.contains(xcodeBundleID)
        snapshot.simulatorAppRunning = ids.contains(simulatorBundleID)
        if measured.hasSimulators {
            var simulators = await liveSimulators()
            let udids = simulators.map(\.udid)
            let use = await Task.detached(priority: .utility) { () -> (sessions: [String: Date], attached: [String: Int]) in
                (sessionUse(of: udids, projects: ClaudeDigest.defaultProjectsDirectory, now: now),
                 attachedCounts(udids, processes: BashToolWatcher.liveProcesses(), arguments: ClaudeActivity.arguments))
            }.value
            for i in simulators.indices {
                let udid = simulators[i].udid
                simulators[i].openApps = measured.simulatorApps[udid] ?? []
                simulators[i].sessionWrote = use.sessions[udid]
                simulators[i].attached = use.attached[udid] ?? 0
            }
            snapshot.simulators = simulators
        }
        if measured.hasDockerVM { snapshot.containers = await liveContainers() }
        snapshot.memoryTotal = ProcessInfo.processInfo.physicalMemory
        snapshot.memoryPressure = sysctlInt32("kern.memorystatus_vm_pressure_level").map(Int.init)
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
            snapshot.swapUsed = swap.xsu_used
            snapshot.swapTotal = swap.xsu_total
        }
        let power = PowerMonitor.readBattery()
        snapshot.batteryPercent = power.battery.percent
        snapshot.charging = power.charging
        snapshot.thermal = ProcessInfo.processInfo.thermalState
        let disk = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        snapshot.diskFree = disk?.volumeAvailableCapacityForImportantUsage
        snapshot.diskTotal = disk?.volumeTotalCapacity.map(Int64.init)
        snapshot.uptime = ProcessInfo.processInfo.systemUptime
        return snapshot
    }

    /// This user's processes: path, memory as Activity Monitor counts it,
    /// and CPU time. Another user's cannot be read and are left out.
    nonisolated static func liveReadings() -> [pid_t: ProcessReading] {
        var out: [pid_t: ProcessReading] = [:]
        for process in BashToolWatcher.liveProcesses() where process.pid > 0 {
            var usage = rusage_info_v2()
            let read = withUnsafeMutablePointer(to: &usage) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(process.pid, RUSAGE_INFO_V2, $0) }
            }
            guard read == 0, let cpu = BashToolWatcher.liveCPUTime(process.pid) else { continue }
            var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
            let length = proc_pidpath(process.pid, &buffer, UInt32(buffer.count))
            let path = length > 0 ? String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self) : nil
            out[process.pid] = ProcessReading(path: path, name: process.name, memory: usage.ri_phys_footprint, cpuTime: cpu)
        }
        return out
    }

    nonisolated static func sysctlInt32(_ name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
    }

    static let xcrunPath = "/usr/bin/xcrun"

    /// Only asked while a simulator runs (`launchd_sim`), so a Mac without
    /// Xcode never sees the developer tools prompt.
    nonisolated static func liveSimulators() async -> [Simulator] {
        do {
            let result = try await Shell.run(xcrunPath, ["simctl", "list", "devices", "booted", "-j"], timeout: commandTimeout)
            guard result.succeeded else {
                Log.error("mac advisor: simctl exited \(result.status)")
                return []
            }
            return parseSimulators(Data(result.stdout.utf8))
        } catch {
            Log.error("mac advisor: simctl failed: \(error.localizedDescription)")
            return []
        }
    }

    /// Docker Desktop's own socket only, as `DockerRule` does.
    nonisolated static func liveContainers() async -> [Container] {
        guard let host = try? DockerRule.verifiedDesktopHost(), let docker = Shell.locate(DockerRule.dockerCandidates) else { return [] }
        do {
            let ps = try await Shell.run(docker, ["--host", host, "ps", "--format", "{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}"], timeout: commandTimeout)
            guard ps.succeeded else { return [] }
            let stats = try? await Shell.run(docker, ["--host", host, "stats", "--no-stream", "--format", "{{.ID}}\t{{.CPUPerc}}\t{{.MemUsage}}"], timeout: commandTimeout)
            return parseContainers(ps: ps.stdout, stats: stats.flatMap { $0.succeeded ? $0.stdout : nil } ?? "")
        } catch {
            Log.error("mac advisor: docker failed: \(error.localizedDescription)")
            return []
        }
    }
}

/// `Uykusuz --mac-snapshot`: prints what a look would tell Claude about the
/// Mac now. Nothing is sent and nothing is written.
enum MacSnapshotCommand {
    static let flag = "--mac-snapshot"

    @MainActor
    static func run(_ arguments: [String]) -> Int32? {
        guard arguments.first == flag else { return nil }
        var text: String?
        Task { @MainActor in
            let now = Date()
            text = await MacSnapshot.live(lastActive: [:], watchingSince: nil, now: now).text(now: now)
        }
        // Before AppKit starts: the run loop carries the main actor's work.
        while text == nil {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }
        print(text ?? "")
        return 0
    }
}

