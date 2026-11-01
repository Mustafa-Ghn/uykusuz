import Foundation

/// Spec section 4, Docker rule: if Docker Desktop is running, has no running
/// containers and no docker command is at work, it is frozen like any other
/// app (bypassing its denylist entry). Any error means Docker is left alone.
///
/// A BuildKit `docker build`, a `docker pull` and a `docker push` run no
/// container, so `docker ps` answers empty through all of them and a SIGSTOP
/// would hang them until the lid opens. So does a `docker run` still fetching
/// its image, a `docker load` and more (`unseenVerbs`). The process table
/// shows them (`DockerWatcher.commandsAtWork`).
///
/// The rule only *decides*; `LidActions` journals `dockerFrozen` and the
/// pids before the group is actually stopped.
///
/// The idle answer is a snapshot, so `LidActions` asks twice: once to pick
/// Docker up (`idleDockerGroup`) and once more right before the SIGSTOP
/// (`isStillIdle`), after the journal write, with only the per-pid kernel
/// lookups left between the answer and the signal. A container or a command
/// that starts inside that last window is still frozen along with Desktop;
/// nothing in this process can close it, which is why the rule is off by
/// default.
struct DockerRule: Sendable {
    static let bundleId = FreezePlanner.dockerBundleId
    static let timeout: TimeInterval = 5

    static let dockerCandidates: [String] = [
        "/usr/local/bin/docker",
        "/opt/homebrew/bin/docker",
        "\(NSHomeDirectory())/.docker/bin/docker",
        "/Applications/Docker.app/Contents/Resources/bin/docker",
    ]

    /// Docker Desktop's own engine socket. The probe binds to it with
    /// `--host`, which the CLI ranks above `DOCKER_HOST`, `DOCKER_CONTEXT`
    /// and `docker context use`, so an ambient remote or empty daemon cannot
    /// answer for the local Desktop that is about to be frozen.
    static let desktopSocket = "\(NSHomeDirectory())/.docker/run/docker.sock"

    struct EndpointError: Error, LocalizedError, Sendable {
        let path: String
        let reason: String
        var errorDescription: String? { "docker endpoint \(path): \(reason)" }
    }

    /// The process table cannot say which commands are at work.
    struct CommandsUnknownError: Error, LocalizedError, Sendable {
        let reason: String
        var errorDescription: String? { "docker commands unknown: \(reason)" }
    }

    /// Runs `docker ps -q` and returns true only on a clean, empty answer.
    typealias ContainerProbe = @Sendable () async throws -> Bool
    /// The docker commands at work, by name. Throws when they cannot be known.
    typealias CommandProbe = @Sendable () throws -> [String]

    let freezer: any Freezing
    let probe: ContainerProbe
    let commands: CommandProbe

    /// Asks the real Docker Desktop and the real process table.
    init(freezer: any Freezing) {
        self.init(freezer: freezer, probe: DockerRule.liveProbe, commands: DockerRule.liveCommands)
    }

    /// A fake engine has no commands unless a test gives it some: a real
    /// `docker build` next to `swift test` must not change the answer.
    init(freezer: any Freezing, probe: @escaping ContainerProbe, commands: @escaping CommandProbe = { [] }) {
        self.freezer = freezer
        self.probe = probe
        self.commands = commands
    }

    /// The Docker Desktop process tree if it is running *and* idle, else nil.
    func idleDockerGroup(config: Config) async -> FreezeGroup? {
        guard config.dockerRule else { return nil }
        let groups = freezer.plan(bundleIds: [Self.bundleId], config: config, applyDenylist: false)
        guard let docker = groups.first else { return nil }
        return await isIdle(check: "first") ? docker : nil
    }

    /// The second check. True only when both answers say idle again; busy, a
    /// command at work, a failed probe and a timeout all return false.
    func isStillIdle() async -> Bool {
        await isIdle(check: "second")
    }

    /// One check, the same at both points. Every answer gets its own log
    /// line, so a release check can read which check saw what. The process
    /// table comes last: `docker ps` can take up to `timeout`, and a command
    /// started while it runs still has to be seen.
    private func isIdle(check: String) async -> Bool {
        do {
            guard try await probe() else {
                Log.info("docker rule: \(check) check found containers running, Docker left alone")
                return false
            }
            let atWork = try commands()
            guard atWork.isEmpty else {
                Log.info("docker rule: \(check) check found \(atWork.joined(separator: ", ")) at work, Docker left alone")
                return false
            }
            Log.info("docker rule: \(check) check found no running container and no docker command at work")
            return true
        } catch {
            Log.error("docker rule: \(check) check failed, Docker left alone: \(error.localizedDescription)")
            return false
        }
    }

    /// `unix://` URL for `socketPath` once it is known to be a Unix socket.
    /// Throws otherwise, so the caller leaves Docker alone rather than let
    /// the CLI fall back to whatever daemon the environment points at.
    static func verifiedDesktopHost(socketPath: String = desktopSocket) throws -> String {
        let type: FileAttributeType?
        do {
            type = try FileManager.default.attributesOfItem(atPath: socketPath)[.type] as? FileAttributeType
        } catch {
            throw EndpointError(path: socketPath, reason: "not found (\(error.localizedDescription))")
        }
        guard type == .typeSocket else {
            throw EndpointError(path: socketPath, reason: "not a Unix socket")
        }
        return "unix://\(socketPath)"
    }

    static func probeArguments(host: String) -> [String] {
        ["--host", host, "ps", "-q"]
    }

    /// True when `docker --host <desktop socket> ps -q` succeeds and prints nothing.
    static let liveProbe: ContainerProbe = makeProbe()

    /// `docker` nil means the first of `dockerCandidates` found at call time.
    static func makeProbe(docker: String? = nil, socketPath: String = desktopSocket) -> ContainerProbe {
        {
            guard let docker = docker ?? Shell.locate(dockerCandidates) else {
                throw ShellError.launchFailed(exe: "docker", underlying: "not found in \(dockerCandidates.joined(separator: ", "))")
            }
            let host = try verifiedDesktopHost(socketPath: socketPath)
            let r = try await Shell.run(docker, probeArguments(host: host), timeout: timeout)
            guard r.succeeded else {
                throw SleepGuardError(command: "docker --host \(host) ps -q", status: r.status, stderr: r.stderr)
            }
            return r.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// What also keeps Docker running, on top of `DockerWatcher.workingVerbs`:
    /// commands that can take minutes with nothing in `docker ps`. They stay
    /// out of that list because it also tells the phone about work, and `up`
    /// and `run` stay open for days. That cannot mislead this rule: it reads
    /// the process table only after `docker ps -q` answered empty, so a live
    /// `docker run` has not opened its container yet. Any `run` counts, so
    /// `docker model run` and `docker mcp gateway run` do too: they have no
    /// container either, and a stopped Docker would hang them.
    static let unseenVerbs: [(argument: String, label: String)] = [
        // Opening a container: the image comes first.
        ("run", "docker run"), ("create", "docker create"), ("start", "docker start"), ("restart", "docker restart"),
        ("up", "docker compose up"), ("scale", "docker compose scale"), ("watch", "docker compose watch"),
        // Images and the files of stopped containers, on their way in or out.
        ("load", "docker load"), ("import", "docker import"), ("save", "docker save"), ("export", "docker export"),
        ("commit", "docker commit"), ("cp", "docker cp"),
        // Removing images and volumes.
        ("prune", "docker prune"), ("rmi", "docker rmi"), ("rm", "docker rm"), ("down", "docker compose down"),
    ]

    /// The commands at work on this Mac, whichever daemon they talk to: a
    /// process's environment is not read, and leaving Docker running is the
    /// safe side.
    static let liveCommands: CommandProbe = makeCommandProbe(
        processes: { BashToolWatcher.liveProcesses() },
        arguments: { DockerWatcher.liveArguments($0) },
        isGone: { liveIsGone($0) }
    )

    /// `DockerWatcher.commandsAtWork` for a decision to SIGSTOP. A message to
    /// the phone can skip what it cannot read; here not knowing is an error,
    /// so Docker is left alone.
    static func makeCommandProbe(
        processes: @escaping @Sendable () -> [BashToolWatcher.Process],
        arguments: @escaping @Sendable (pid_t) -> [String]?,
        isGone: @escaping @Sendable (pid_t) -> Bool
    ) -> CommandProbe {
        {
            let table = processes()
            // `liveProcesses` answers a failed read with nothing. A good one
            // always holds this process.
            guard !table.isEmpty else {
                throw CommandsUnknownError(reason: "the process table could not be read")
            }
            var unread: [pid_t] = []
            let atWork = DockerWatcher.commandsAtWork(table, verbs: DockerWatcher.workingVerbs + unseenVerbs) { pid in
                let words = arguments(pid)
                if words == nil { unread.append(pid) }
                return words
            }
            // The kernel gives a process's arguments to its own user only, so
            // `sudo docker build` has none to read. One that ended since the
            // table was read is no command at work.
            if atWork.isEmpty, let pid = unread.first(where: { !isGone($0) }) {
                throw CommandsUnknownError(reason: "the arguments of pid \(pid) could not be read")
            }
            return atWork
        }
    }

    /// Exited, zombies included. A lookup that fails is not gone.
    static func liveIsGone(_ pid: pid_t) -> Bool {
        if case .absent = SignalProcessControl.processTableState(pid: pid) { return true }
        return false
    }
}
