import CryptoKit
import Foundation

/// Watches remote machines over SSH for their ~/.upclaude/sessions/*.json state files.
///
/// Each enabled RemoteHost gets one long-lived ssh connection running a small script that
/// prints the session list whenever a file changes, so updates arrive in well under a second.
/// (Polling with a fresh ssh connection every few seconds made remote status lag visibly.)
/// If the connection drops it is reopened after the host's `pollInterval`.
/// Results are merged with local sessions in AppState.
public class RemoteSessionWatcher {
    /// One host's connection. `generation` tells a current stream from one already replaced.
    private struct Stream {
        let process: Process
        let generation: Int
    }

    private var streams: [String: Stream] = [:]
    private var nextGeneration = 0
    private var hosts: [RemoteHost] = []
    private let onChange: (_ host: String, _ sessions: [AgentSession]) -> Void

    /// Callback fires per-host with the sessions discovered on that host.
    public init(onChange: @escaping (_ host: String, _ sessions: [AgentSession]) -> Void) {
        self.onChange = onChange
    }

    /// Update the set of remote hosts to watch. Opens and closes connections as needed.
    public func updateHosts(_ newHosts: [RemoteHost]) {
        let enabledHosts = newHosts.filter(\.isEnabled)
        let oldIds = Set(hosts.map(\.host))
        let newIds = Set(enabledHosts.map(\.host))

        // Close connections to removed/disabled hosts
        for hostId in oldIds.subtracting(newIds) {
            closeStream(for: hostId)
            // Clear sessions for removed hosts
            onChange(hostId, [])
        }

        hosts = enabledHosts

        // Once per launch, and when a host is added or re-enabled.
        for host in enabledHosts where !oldIds.contains(host.host) {
            openStream(for: host.host)
            Self.updateRemoteHookIfOutdated(host: host.host)
        }
    }

    /// Delete a session file on a remote host via SSH.
    public func deleteSession(_ sessionId: String, on host: String) {
        // Validate sessionId is a safe filename (UUID format) before passing to SSH.
        let safeChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        guard sessionId.unicodeScalars.allSatisfy({ safeChars.contains($0) }) else { return }

        DispatchQueue.global(qos: .utility).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            task.arguments = Self.sshArguments(
                host: host, command: "rm -f ~/.upclaude/sessions/\(sessionId).json")
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try? task.run()
            task.waitUntilExit()
        }
    }

    public func stop() {
        for hostId in Array(streams.keys) {
            closeStream(for: hostId)
        }
        hosts.removeAll()
    }

    // MARK: - Streaming

    /// Runs on the remote host: prints the session list as one JSON line whenever a state
    /// file is added, removed, or rewritten, checking a few times a second. An empty line
    /// every 10s is a heartbeat, so the script notices a closed connection and exits.
    /// Must not contain single quotes; it is passed to the remote shell inside them.
    static let watchScript = """
        import glob, json, os, time
        d = os.path.expanduser("~/.upclaude/sessions")
        last, beat = None, time.time()
        while True:
            files = sorted(glob.glob(d + "/*.json"))
            seen = []
            for f in files:
                try:
                    st = os.stat(f)
                    seen.append((f, st.st_mtime_ns, st.st_size))
                except OSError:
                    pass
            now = time.time()
            if seen != last:
                last, sessions = seen, []
                for f in files:
                    try:
                        with open(f) as fh:
                            sessions.append(json.load(fh))
                    except Exception:
                        last = None
                print(json.dumps(sessions), flush=True)
                beat = now
            elif now - beat > 10:
                print("", flush=True)
                beat = now
            time.sleep(0.3)
        """

    /// Decode one line of the watch script's output. Nil for heartbeats and anything unreadable.
    static func decodeSessions(line: Data, host: String) -> [AgentSession]? {
        guard !line.isEmpty else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let sessions = try? decoder.decode([AgentSession].self, from: line) else { return nil }
        // Tag each session with its host. (Whether its process is alive can't be checked from here.)
        return sessions.map { session in
            var tagged = session
            tagged.remoteHost = host
            return tagged
        }
    }

    private func openStream(for hostId: String) {
        closeStream(for: hostId)
        nextGeneration += 1
        let generation = nextGeneration

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = Self.sshArguments(
            host: hostId, command: "python3 -u -c '\(Self.watchScript)'", keepAlive: true)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        // Output arrives in arbitrary chunks; hand over complete lines only.
        var buffer = Data()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: buffer.startIndex..<newline)
                buffer.removeSubrange(buffer.startIndex...newline)
                guard let sessions = Self.decodeSessions(line: line, host: hostId) else { continue }
                DispatchQueue.main.async {
                    guard self?.streams[hostId]?.generation == generation else { return }
                    self?.onChange(hostId, sessions)
                }
            }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.streamEnded(hostId: hostId, generation: generation) }
        }

        streams[hostId] = Stream(process: process, generation: generation)
        do {
            try process.run()
        } catch {
            streamEnded(hostId: hostId, generation: generation)
        }
    }

    /// The connection dropped or never opened: show no sessions for the host and try again
    /// after its poll interval, unless it has been closed or replaced meanwhile.
    private func streamEnded(hostId: String, generation: Int) {
        guard streams[hostId]?.generation == generation else { return }
        streams.removeValue(forKey: hostId)
        onChange(hostId, [])

        guard let host = hosts.first(where: { $0.host == hostId }) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + host.pollInterval) { [weak self] in
            guard let self, self.streams[hostId] == nil,
                self.hosts.contains(where: { $0.host == hostId })
            else { return }
            self.openStream(for: hostId)
        }
    }

    private func closeStream(for hostId: String) {
        guard let stream = streams.removeValue(forKey: hostId) else { return }
        if stream.process.isRunning { stream.process.terminate() }
    }

    // MARK: - SSH

    /// Arguments for a non-interactive ssh call that runs one command.
    /// `keepAlive` is for long-lived connections: it makes ssh notice a dead link within about
    /// half a minute instead of hanging.
    static func sshArguments(
        host: String, command: String, connectTimeout: Int = 5, keepAlive: Bool = false
    ) -> [String] {
        var options = [
            "-o", "ConnectTimeout=\(connectTimeout)",
            // No interactive prompts — fail if key auth doesn't work.
            "-o", "BatchMode=yes",
            // The user's ssh config may forward ports for this host. We only run a command,
            // and re-requesting forwards an open session already holds would fail.
            "-o", "ClearAllForwardings=yes",
        ]
        if keepAlive {
            options += ["-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=2"]
        }
        return options + [host, command]
    }

    // MARK: - Hook script

    /// Shell command that writes the hook script on the remote host. It goes to a temporary
    /// file first and is moved into place, so a hook that fires mid-write never runs half a file.
    static func writeHookCommand(_ hookScript: String) -> String {
        """
        mkdir -p ~/.upclaude/hooks ~/.upclaude/sessions && \
        cat > ~/.upclaude/hooks/upclaude-hook.py.new << 'UPCLAUDE_HOOK_EOF'
        \(hookScript)
        UPCLAUDE_HOOK_EOF
        chmod 755 ~/.upclaude/hooks/upclaude-hook.py.new && \
        mv ~/.upclaude/hooks/upclaude-hook.py.new ~/.upclaude/hooks/upclaude-hook.py
        """
    }

    /// SHA-256 of the file `writeHookCommand` produces: the script plus the newline the
    /// here-document adds after it.
    static func installedHookHash(for hookScript: String) -> String {
        SHA256.hash(data: Data((hookScript + "\n").utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The hash in the first field of `sha256sum` / `shasum -a 256` output, or nil if there is none.
    static func parseHash(_ output: String) -> String? {
        guard let field = output.split(whereSeparator: \.isWhitespace).first, field.count == 64 else {
            return nil
        }
        return String(field)
    }

    /// Bring the hook script on a remote host up to date with this build.
    ///
    /// A host only got a new hook when the user reinstalled from Settings, so fixes to the hook
    /// never reached it. This rewrites the script when one is installed and differs. It does not
    /// install hooks on a host that has none, and does not touch the host's Claude settings.
    static func updateRemoteHookIfOutdated(host: String) {
        guard let hookScript = try? HookManager.remoteHookScript() else { return }
        let expected = installedHookHash(for: hookScript)

        DispatchQueue.global(qos: .utility).async {
            let hashCommand =
                "f=~/.upclaude/hooks/upclaude-hook.py; [ -f $f ] && "
                + "{ sha256sum $f 2>/dev/null || shasum -a 256 $f; }"
            guard let output = runSSH(host: host, command: hashCommand),
                let installed = parseHash(output), installed != expected
            else { return }
            _ = runSSH(host: host, command: writeHookCommand(hookScript), connectTimeout: 10)
        }
    }

    /// Run a command over ssh and return its output, or nil if ssh or the command failed.
    private static func runSSH(host: String, command: String, connectTimeout: Int = 5) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        task.arguments = sshArguments(host: host, command: command, connectTimeout: connectTimeout)
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Check if hooks are installed on a remote host by looking for the state files directory
    /// and the hook script.
    public static func checkRemoteHooks(
        host: String, completion: @escaping (RemoteHookStatus) -> Void
    ) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        task.arguments = sshArguments(
            host: host,
            command: "test -f ~/.upclaude/hooks/upclaude-hook.py && echo installed || echo missing")

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        DispatchQueue.global(qos: .utility).async {
            do {
                try task.run()
                task.waitUntilExit()

                guard task.terminationStatus == 0 else {
                    DispatchQueue.main.async { completion(.error) }
                    return
                }

                let output =
                    String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let status: RemoteHookStatus = output == "installed" ? .installed : .notInstalled
                DispatchQueue.main.async { completion(status) }
            } catch {
                DispatchQueue.main.async { completion(.error) }
            }
        }
    }

    /// Install hooks on a remote host by copying the hook script and merging into Claude settings.
    public static func installRemoteHooks(
        host: String, completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let hookScript: String
        do {
            hookScript = try HookManager.remoteHookScript()
        } catch {
            completion(.failure(error))
            return
        }

        let installCommand = """
            \(writeHookCommand(hookScript)) && \
            python3 -c "
            import json, os
            settings_path = os.path.expanduser('~/.claude/settings.json')
            os.makedirs(os.path.dirname(settings_path), exist_ok=True)
            settings = {}
            if os.path.isfile(settings_path):
                try:
                    settings = json.load(open(settings_path))
                except: pass
            hooks = settings.get('hooks', {})
            hook_cmd = 'python3 ~/.upclaude/hooks/upclaude-hook.py'
            events = ['SessionStart','PostToolUse','PermissionRequest','Stop','UserPromptSubmit','SessionEnd','SubagentStart','SubagentStop']
            for event in events:
                entries = [e for e in hooks.get(event, []) if not any('upclaude' in h.get('command','') for h in e.get('hooks',[]))]
                entries.append({'matcher':'*','hooks':[{'type':'command','command':hook_cmd,'timeout':10}]})
                hooks[event] = entries
            notifs = [e for e in hooks.get('Notification', []) if not any('upclaude' in h.get('command','') for h in e.get('hooks',[]))]
            for m in ['idle_prompt','permission_prompt']:
                notifs.append({'matcher':m,'hooks':[{'type':'command','command':hook_cmd+' '+m,'timeout':10}]})
            hooks['Notification'] = notifs
            settings['hooks'] = hooks
            with open(settings_path, 'w') as f:
                json.dump(settings, f, indent=2, sort_keys=True)
            print('ok')
            "
            """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        task.arguments = sshArguments(host: host, command: installCommand, connectTimeout: 10)

        let pipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = pipe
        task.standardError = errPipe

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try task.run()
                task.waitUntilExit()

                if task.terminationStatus == 0 {
                    DispatchQueue.main.async { completion(.success(())) }
                } else {
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let errMsg =
                        String(data: errData, encoding: .utf8) ?? "SSH command failed"
                    DispatchQueue.main.async {
                        completion(
                            .failure(
                                NSError(
                                    domain: "RemoteHooks", code: 1,
                                    userInfo: [NSLocalizedDescriptionKey: errMsg])))
                    }
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    deinit {
        stop()
    }
}
