import Darwin
import Foundation

/// One look at Docker Desktop.
struct DockerActivity: Equatable, Sendable {
    /// What is at work: containers by name, commands as `docker build`.
    var working: [String] = []
    /// Containers that are up and doing nothing.
    var idle: [String] = []

    var isBusy: Bool { !working.isEmpty }
}

/// Whether Docker Desktop is in use (fork addition), for the messages to the
/// phone (`DockerAlerts`). A container being up says little: a database left
/// running for days is not use, and a build runs no container at all. So, as
/// in `BashToolWatcher`, a container counts while it is new (`newGrace`) or
/// while `docker stats` shows it working (`cpuThreshold`), and a command that
/// moves images (`docker build`, `pull`, `push`) counts while it runs.
///
/// Read-only and local: the process table, those commands' arguments and
/// `docker stats`, which is asked only while Docker's virtual machine runs. A
/// Docker Desktop that is closed, in Resource Saver or paused by Uykusuz
/// (`DockerRule`) has no container working and is not disturbed.
@MainActor
final class DockerWatcher {
    /// How long a container that was not there before counts without working.
    /// Long enough for a temporary one a task keeps using between commands.
    static let newGrace: TimeInterval = 15 * 60
    /// Percent of one core, as `docker stats` shows it. An idle database
    /// stays well under 1.
    static let cpuThreshold: Double = 10
    static let statsTimeout: TimeInterval = 15

    struct Container: Equatable, Sendable {
        var id: String
        var name: String
        var cpu: Double
    }

    private let processes: () -> [BashToolWatcher.Process]
    private let isStopped: (pid_t) -> Bool
    private let arguments: (pid_t) -> [String]?
    private let containers: () async throws -> [Container]
    /// The containers of the last answer; nil until the first one, whose
    /// containers were there before Uykusuz was looking.
    private var seen: Set<String>?
    private var started: [String: Date] = [:]
    private var failing = false

    init(
        processes: @escaping () -> [BashToolWatcher.Process] = BashToolWatcher.liveProcesses,
        isStopped: @escaping (pid_t) -> Bool = DockerWatcher.liveIsStopped,
        arguments: @escaping (pid_t) -> [String]? = DockerWatcher.liveArguments,
        containers: @escaping () async throws -> [Container] = DockerWatcher.liveContainers
    ) {
        self.processes = processes
        self.isStopped = isStopped
        self.arguments = arguments
        self.containers = containers
    }

    /// nil when Docker could not answer: nothing is known, in either direction.
    func look(now: Date) async -> DockerActivity? {
        let all = processes()
        let commands = Self.commandsAtWork(all, arguments: arguments)
        let engine = all.filter { $0.name.hasPrefix(Self.enginePrefix) }
        // Paused by the Docker rule, which needs no running container: asking
        // would only wait for the timeout.
        if engine.contains(where: { isStopped($0.pid) }) {
            return DockerActivity(working: commands)
        }
        var running: [Container] = []
        if engine.contains(where: { Self.isVirtualMachine($0.name) }) {
            do {
                running = try await containers()
                if failing { Log.info("docker watcher: docker stats answers again") }
                failing = false
            } catch {
                if !failing { Log.error("docker watcher: docker stats failed: \(error.localizedDescription)") }
                failing = true
                return nil
            }
        }
        var activity = DockerActivity(working: commands)
        var startedNow: [String: Date] = [:]
        for container in running.sorted(by: { $0.name < $1.name }) {
            if let known = started[container.id] {
                startedNow[container.id] = known
            } else if let seen, !seen.contains(container.id) {
                startedNow[container.id] = now
            }
            let isNew = startedNow[container.id].map { now.timeIntervalSince($0) < Self.newGrace } ?? false
            if isNew || container.cpu >= Self.cpuThreshold {
                activity.working.append(container.name)
            } else {
                activity.idle.append(container.name)
            }
        }
        seen = Set(running.map(\.id))
        started = startedNow
        return activity
    }

    // MARK: Commands

    nonisolated static let enginePrefix = "com.docker."
    /// Apple's Virtualization framework and Docker VMM, as the process table
    /// shortens their names to 16 characters.
    nonisolated static func isVirtualMachine(_ name: String) -> Bool {
        name.hasPrefix("com.docker.virt") || name.hasPrefix("com.docker.krun")
    }

    /// What `docker`, `docker compose` and `docker buildx` are asked that
    /// runs until the work is done. `up`, `run` and `exec` are not here: they
    /// can stay open for days, and what they run shows in `docker stats`.
    nonisolated static let workingVerbs: [(argument: String, label: String)] = [
        ("build", "docker build"), ("--build", "docker build"), ("bake", "docker build"),
        ("pull", "docker pull"), ("push", "docker push"),
    ]

    /// The commands at work, each once, by name only: their arguments can
    /// hold anything and are not kept.
    nonisolated static func commandsAtWork(_ processes: [BashToolWatcher.Process], arguments: (pid_t) -> [String]?) -> [String] {
        var labels: Set<String> = []
        for process in processes where ["docker", "docker-buildx", "docker-compose"].contains(process.name) {
            guard let words = arguments(process.pid)?.dropFirst() else { continue }
            if let verb = workingVerbs.first(where: { words.contains($0.argument) }) {
                labels.insert(verb.label)
            }
        }
        return labels.sorted()
    }

    // MARK: Live readings

    nonisolated static func liveIsStopped(_ pid: pid_t) -> Bool {
        guard case let .present(state) = SignalProcessControl.processTableState(pid: pid) else { return false }
        return state.stopped
    }

    /// A process's arguments, without its environment, via sysctl
    /// KERN_PROCARGS2 (the caller's own processes only).
    nonisolated static func liveArguments(_ pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return parseArguments(Array(buffer.prefix(size)))
    }

    /// KERN_PROCARGS2's layout: the argument count, the executable's path,
    /// zero bytes up to the first argument, then the arguments and the
    /// environment, each ending in a zero byte.
    nonisolated static func parseArguments(_ buffer: [UInt8]) -> [String]? {
        guard buffer.count > 4 else { return nil }
        let count = buffer.prefix(4).withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        guard count > 0 else { return nil }
        var index = 4
        while index < buffer.count, buffer[index] != 0 { index += 1 }
        while index < buffer.count, buffer[index] == 0 { index += 1 }
        var words: [String] = []
        while index < buffer.count, words.count < count {
            let end = buffer[index...].firstIndex(of: 0) ?? buffer.count
            words.append(String(decoding: buffer[index..<end], as: UTF8.self))
            index = end + 1
        }
        return words.count == count ? words : nil
    }

    /// Bound to Docker Desktop's own socket, as `DockerRule`'s probe is. No
    /// socket is no engine: nothing runs.
    nonisolated static let liveContainers: @Sendable () async throws -> [Container] = {
        guard let host = try? DockerRule.verifiedDesktopHost() else { return [] }
        guard let docker = Shell.locate(DockerRule.dockerCandidates) else {
            throw ShellError.launchFailed(exe: "docker", underlying: "not found in \(DockerRule.dockerCandidates.joined(separator: ", "))")
        }
        let result = try await Shell.run(docker, statsArguments(host: host), timeout: statsTimeout)
        guard result.succeeded else {
            throw SleepGuardError(command: "docker --host \(host) stats", status: result.status, stderr: result.stderr)
        }
        return parseStats(result.stdout)
    }

    nonisolated static func statsArguments(host: String) -> [String] {
        ["--host", host, "stats", "--no-stream", "--format", "{{.ID}}\t{{.Name}}\t{{.CPUPerc}}"]
    }

    /// One container a line. A container going away can show `--` for its
    /// name or its figures while it does.
    nonisolated static func parseStats(_ output: String) -> [Container] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 3, !fields[0].isEmpty, fields[0] != "--" else { return nil }
            let name = fields[1].isEmpty || fields[1] == "--" ? fields[0] : fields[1]
            let cpu = Double(fields[2].trimmingCharacters(in: CharacterSet(charactersIn: "% "))) ?? 0
            return Container(id: fields[0], name: name, cpu: cpu)
        }
    }
}
