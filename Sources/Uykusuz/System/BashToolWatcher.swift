import Darwin
import Foundation

/// Whether a command Claude Code's Bash tool started is doing work (fork
/// addition). A command Claude waits on, a build or a test run, keeps the
/// CPU busy; one left running for good, a database proxy or a dev server,
/// mostly sleeps, and must not keep the Mac awake for days. So a tool
/// command counts while it is new (`newGrace`), or while its process tree
/// used at least `cpuThreshold` of CPU time between two readings within
/// `activeWindow`.
///
/// Read-only and local: the process table and each process's CPU time,
/// for this user's processes. Called once per `AgentAutoSession` tick.
@MainActor
final class BashToolWatcher {
    static let newGrace: TimeInterval = 5 * 60
    static let activeWindow: TimeInterval = 5 * 60
    /// CPU seconds between two readings (15 s apart) that mean work: about
    /// 1.7 % of one core on average.
    static let cpuThreshold: TimeInterval = 0.25

    struct Process: Equatable, Sendable {
        var pid: pid_t
        var ppid: pid_t
        var name: String
        var started: Date
    }

    private struct Key: Hashable {
        let pid: pid_t
        let started: Date
    }

    private let read: () -> [Process]
    private let isToolShell: (Process) -> Bool
    private let cpuTime: (pid_t) -> TimeInterval?
    private var lastReading: Date?
    private var lastCPU: [Key: TimeInterval] = [:]
    private var lastBusy: [Key: Date] = [:]

    init(
        read: @escaping () -> [Process] = BashToolWatcher.liveProcesses,
        isToolShell: @escaping (Process) -> Bool = BashToolWatcher.liveIsToolShell,
        cpuTime: @escaping (pid_t) -> TimeInterval? = BashToolWatcher.liveCPUTime
    ) {
        self.read = read
        self.isToolShell = isToolShell
        self.cpuTime = cpuTime
    }

    func isWorking(now: Date) -> Bool {
        let all = read()
        var children: [pid_t: [Process]] = [:]
        for process in all { children[process.ppid, default: []].append(process) }
        let shells = all.filter(isToolShell)
        let shellPIDs = Set(shells.map(\.pid))
        // The top of each command: a tool shell whose parent is not one.
        let tops = shells.filter { !shellPIDs.contains($0.ppid) }

        var cpuNow: [Key: TimeInterval] = [:]
        var busyNow: [Key: Date] = [:]
        var working = false
        for top in tops {
            let topKey = Key(pid: top.pid, started: top.started)
            var used: TimeInterval = 0
            var pending = [top]
            while let process = pending.popLast() {
                pending.append(contentsOf: children[process.pid] ?? [])
                guard let cpu = cpuTime(process.pid) else { continue }
                let key = Key(pid: process.pid, started: process.started)
                cpuNow[key] = cpu
                if let previous = lastCPU[key] {
                    used += max(cpu - previous, 0)
                } else if let lastReading, process.started > lastReading {
                    // Started since the last reading: all of its CPU is new.
                    used += cpu
                }
                // Seen for the first time otherwise (the first reading
                // after launch): only a baseline, so days of a proxy's CPU
                // are not taken for work just done.
            }
            let busy = used >= Self.cpuThreshold ? now : lastBusy[topKey]
            if let busy { busyNow[topKey] = busy }
            let isNew = now.timeIntervalSince(top.started) < Self.newGrace
            let recentlyBusy = busy.map { now.timeIntervalSince($0) < Self.activeWindow } ?? false
            if isNew || recentlyBusy { working = true }
        }
        lastCPU = cpuNow
        lastBusy = busyNow
        lastReading = now
        return working
    }

    // MARK: Live readings

    nonisolated static let shells: Set<String> = ["zsh", "bash", "sh", "fish"]

    /// A shell running a Bash tool command: it sources a snapshot from
    /// Claude Code's folder (`ClaudeActivity.bashToolMarker`).
    nonisolated static func liveIsToolShell(_ process: Process) -> Bool {
        shells.contains(process.name) && (ClaudeActivity.arguments(process.pid)?.contains(ClaudeActivity.bashToolMarker) ?? false)
    }

    /// Every process with its parent, short name and start time, via sysctl
    /// KERN_PROC_ALL.
    nonisolated static func liveProcesses() -> [Process] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return [] }
        size += size / 4
        let stride = MemoryLayout<kinfo_proc>.stride
        let capacity = size / stride + 1
        let buffer = UnsafeMutablePointer<kinfo_proc>.allocate(capacity: capacity)
        defer { buffer.deallocate() }
        size = capacity * stride
        guard sysctl(&mib, UInt32(mib.count), buffer, &size, nil, 0) == 0 else { return [] }
        return (0..<(size / stride)).map { i in
            let p = buffer[i]
            let name = withUnsafeBytes(of: p.kp_proc.p_comm) { raw in
                String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
            let start = p.kp_proc.p_un.__p_starttime
            return Process(
                pid: p.kp_proc.p_pid,
                ppid: p.kp_eproc.e_ppid,
                name: name,
                started: Date(timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000)
            )
        }
    }

    /// Mach time units to seconds.
    nonisolated private static let secondsPerTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()

    /// User and system CPU time a live process has used; nil when it cannot
    /// be read (gone, or another user's).
    nonisolated static func liveCPUTime(_ pid: pid_t) -> TimeInterval? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return nil }
        return Double(info.pti_total_user + info.pti_total_system) * secondsPerTick
    }
}
