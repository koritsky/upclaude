import Foundation
import Testing

@testable import UpclaudeLib

@Suite("SessionStateWatcher")
struct SessionStateWatcherTests {

    @Test("readAllSessions parses JSON state files")
    func readsStateFiles() throws {
        // Create a temp directory with test state files
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("upclaude-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let formatter = ISO8601DateFormatter()
        let now = formatter.string(from: Date())
        let stateJSON = """
            {
                "session_id": "test-123",
                "cwd": "/tmp/test",
                "project_name": "test",
                "status": "working",
                "model": "claude-opus-4-6",
                "context_pct": 42.0,
                "started_at": "\(now)",
                "updated_at": "\(now)",
                "is_hook_tracked": true
            }
            """
        try stateJSON.write(
            to: tmpDir.appendingPathComponent("test-123.json"),
            atomically: true, encoding: .utf8
        )

        let watcher = SessionStateWatcher(sessionsDirectory: tmpDir.path) { _ in }
        let sessions = watcher.readAllSessions()

        #expect(sessions.count == 1)
        #expect(sessions[0].sessionId == "test-123")
        #expect(sessions[0].status == .working)
        #expect(sessions[0].model == "claude-opus-4-6")
        #expect(sessions[0].contextPct == 42.0)
    }

    @Test("readAllSessions skips non-json files")
    func skipsNonJSON() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("upclaude-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        try "not json".write(
            to: tmpDir.appendingPathComponent("readme.txt"),
            atomically: true, encoding: .utf8
        )
        try "{}invalid".write(
            to: tmpDir.appendingPathComponent("bad.json"),
            atomically: true, encoding: .utf8
        )

        let watcher = SessionStateWatcher(sessionsDirectory: tmpDir.path) { _ in }
        let sessions = watcher.readAllSessions()
        #expect(sessions.isEmpty)
    }

    @Test("readAllSessions handles empty directory")
    func handlesEmptyDir() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("upclaude-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let watcher = SessionStateWatcher(sessionsDirectory: tmpDir.path) { _ in }
        let sessions = watcher.readAllSessions()
        #expect(sessions.isEmpty)
    }
}

@Suite("RemoteSessionWatcher")
struct RemoteSessionWatcherTests {

    @Test("ssh calls are non-interactive and never request port forwards")
    func sshArguments() {
        let arguments = RemoteSessionWatcher.sshArguments(host: "box", command: "echo hi", connectTimeout: 10)
        #expect(arguments.suffix(2) == ["box", "echo hi"])
        #expect(arguments.contains("BatchMode=yes"))
        #expect(arguments.contains("ClearAllForwardings=yes"))
        #expect(arguments.contains("ConnectTimeout=10"))
    }

    @Test("installed hook hash covers the newline the here-document adds")
    func installedHookHash() {
        // sha256 of "x\n"
        #expect(
            RemoteSessionWatcher.installedHookHash(for: "x")
                == "73cb3858a687a8494ca3323053016282f3dad39d42cf62ca4e79dda2aac7d9ac")
        #expect(
            RemoteSessionWatcher.installedHookHash(for: "x")
                != RemoteSessionWatcher.installedHookHash(for: "y"))
    }

    @Test("parseHash reads sha256sum output and rejects anything else")
    func parseHash() {
        let hash = String(repeating: "a", count: 64)
        #expect(RemoteSessionWatcher.parseHash("\(hash)  /home/u/.upclaude/hooks/upclaude-hook.py\n") == hash)
        #expect(RemoteSessionWatcher.parseHash("") == nil)
        #expect(RemoteSessionWatcher.parseHash("sha256sum: no such file") == nil)
    }

    @Test("hook is written to a temporary file and moved into place")
    func writeHookCommand() {
        let command = RemoteSessionWatcher.writeHookCommand("print('hi')")
        #expect(command.contains("cat > ~/.upclaude/hooks/upclaude-hook.py.new << 'UPCLAUDE_HOOK_EOF'"))
        #expect(command.contains("\nprint('hi')\nUPCLAUDE_HOOK_EOF\n"))
        #expect(command.hasSuffix("mv ~/.upclaude/hooks/upclaude-hook.py.new ~/.upclaude/hooks/upclaude-hook.py"))
    }

    @Test("long-lived connections ask ssh to detect a dead link")
    func sshKeepAlive() {
        let arguments = RemoteSessionWatcher.sshArguments(host: "box", command: "x", keepAlive: true)
        #expect(arguments.contains("ServerAliveInterval=15"))
        #expect(arguments.suffix(2) == ["box", "x"])
        #expect(!RemoteSessionWatcher.sshArguments(host: "box", command: "x").contains("ServerAliveInterval=15"))
    }

    @Test("watch script can be passed to the remote shell inside single quotes")
    func watchScriptQuoting() {
        #expect(!RemoteSessionWatcher.watchScript.contains("'"))
        #expect(RemoteSessionWatcher.watchScript.hasPrefix("import glob"))
    }

    @Test("stream lines decode to sessions tagged with their host; heartbeats are skipped")
    func decodeStreamLine() {
        let line = Data(
            #"[{"session_id": "s1", "cwd": "/a", "project_name": "a", "is_hook_tracked": true, "status": "working"}]"#
                .utf8)
        let sessions = RemoteSessionWatcher.decodeSessions(line: line, host: "box")
        #expect(sessions?.count == 1)
        #expect(sessions?.first?.remoteHost == "box")
        #expect(sessions?.first?.status == .working)

        #expect(RemoteSessionWatcher.decodeSessions(line: Data("[]".utf8), host: "box")?.isEmpty == true)
        #expect(RemoteSessionWatcher.decodeSessions(line: Data(), host: "box") == nil)
        #expect(RemoteSessionWatcher.decodeSessions(line: Data("garbage".utf8), host: "box") == nil)
    }
}
