import Foundation

/// Manages installation and updates of Upclaude hooks in ~/.claude/settings.json.
/// Hooks are the primary mechanism for session discovery and state tracking.
public class HookManager {
    public static let shared = HookManager()

    private let upclaudeDir: URL
    private let hooksDir: URL
    private let sessionsDir: URL
    private let claudeSettingsPath: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        upclaudeDir = home.appendingPathComponent(".upclaude")
        hooksDir = upclaudeDir.appendingPathComponent("hooks")
        sessionsDir = upclaudeDir.appendingPathComponent("sessions")
        claudeSettingsPath = home.appendingPathComponent(".claude/settings.json")
    }

    /// Path to the sessions directory where hook state files are written
    public var sessionsDirectoryPath: String {
        sessionsDir.path
    }

    /// All hook events we register for. Claude Code requires each as a separate key.
    private static let hookEvents: [String] = [
        "SessionStart", "PreToolUse", "PostToolUse", "PostToolUseFailure",
        "PermissionRequest", "Stop", "StopFailure", "UserPromptSubmit",
        "SessionEnd", "SubagentStart", "SubagentStop",
    ]

    /// Check if all expected hooks are installed in settings
    public var isInstalled: Bool {
        guard let data = try? Data(contentsOf: claudeSettingsPath),
            let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }

        guard let hooks = settings["hooks"] as? [String: Any] else { return false }

        return Self.hookEvents.allSatisfy { event in
            guard let eventHooks = hooks[event] as? [[String: Any]] else { return false }
            return eventHooks.contains { entry in
                guard let hooksList = entry["hooks"] as? [[String: Any]] else { return false }
                return hooksList.contains { hook in
                    guard let command = hook["command"] as? String else { return false }
                    return command.contains("upclaude")
                }
            }
        }
    }

    /// Create directories and install the hook script
    public func ensureDirectories() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: hooksDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
    }

    /// Install the hook script from the app bundle to ~/.upclaude/hooks/
    public func installHookScript() throws {
        let fm = FileManager.default
        try ensureDirectories()

        let hookScriptContent = try Self.scriptSource("upclaude-hook.py")
        let destPath = hooksDir.appendingPathComponent("upclaude-hook.py")
        try hookScriptContent.write(to: destPath, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destPath.path)
    }

    /// Merge Upclaude hooks into ~/.claude/settings.json, preserving existing hooks.
    public func installHooksInSettings() throws {
        let fm = FileManager.default
        var settings: [String: Any] = [:]

        if fm.fileExists(atPath: claudeSettingsPath.path) {
            let data = try Data(contentsOf: claudeSettingsPath)
            if let existing = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                settings = existing
            }
        }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        let hookCommand = "python3 \(hooksDir.path)/upclaude-hook.py"

        let hookEntry: [String: Any] = [
            "type": "command",
            "command": hookCommand,
            "timeout": 10,
        ]

        let removeUpclaude: ([[String: Any]]) -> [[String: Any]] = { entries in
            entries.filter { entry in
                guard let hooksList = entry["hooks"] as? [[String: Any]] else { return true }
                return !hooksList.contains { hook in
                    (hook["command"] as? String)?.contains("upclaude") == true
                }
            }
        }

        // Register the same hook for all standard events
        for event in Self.hookEvents {
            var eventHooks = removeUpclaude(hooks[event] as? [[String: Any]] ?? [])
            eventHooks.append(["matcher": "*", "hooks": [hookEntry]])
            hooks[event] = eventHooks
        }

        settings["hooks"] = hooks

        let data = try JSONSerialization.data(
            withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: claudeSettingsPath, options: .atomic)
    }

    /// Full install: script + settings
    public func install() throws {
        try installHookScript()
        try installHooksInSettings()
    }

    /// Remove Upclaude hooks from settings.json and clean up local files.
    public func uninstall() throws {
        let fm = FileManager.default

        // Remove hooks from Claude settings
        if fm.fileExists(atPath: claudeSettingsPath.path) {
            let data = try Data(contentsOf: claudeSettingsPath)
            if var settings = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                var hooks = settings["hooks"] as? [String: Any]
            {
                for (event, eventHooks) in hooks {
                    guard var entries = eventHooks as? [[String: Any]] else { continue }
                    entries.removeAll { entry in
                        guard let hooksList = entry["hooks"] as? [[String: Any]] else {
                            return false
                        }
                        return hooksList.contains { hook in
                            (hook["command"] as? String)?.contains("upclaude") == true
                        }
                    }
                    if entries.isEmpty {
                        hooks.removeValue(forKey: event)
                    } else {
                        hooks[event] = entries
                    }
                }

                settings["hooks"] = hooks.isEmpty ? nil : hooks

                let newData = try JSONSerialization.data(
                    withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
                try newData.write(to: claudeSettingsPath, options: .atomic)
            }
        }

        // Clean up ~/.upclaude/sessions/ and hooks/
        try? fm.removeItem(at: sessionsDir)
        try? fm.removeItem(at: hooksDir)
    }

    /// The hook script content for remote installation
    public static func remoteHookScript() throws -> String {
        try scriptSource("upclaude-hook.py")
    }

    /// Load a Python script by name.
    /// Checks the .app resource bundle first (brew/release), then falls back
    /// to the repo source tree (development via `swift run`).
    public static func scriptSource(_ filename: String) throws -> String {
        let baseName = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension

        // 1. .app bundle: Contents/Resources/ (brew install / bundled .app)
        if let url = Bundle.main.url(forResource: baseName, withExtension: ext),
            let content = try? String(contentsOf: url, encoding: .utf8)
        {
            return content
        }

        // 2. Repo layout relative to executable (`swift run` → .build/debug/Upclaude)
        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        let repoPath =
            executableURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/UpclaudeLib/Resources/\(filename)")

        if let content = try? String(contentsOf: repoPath, encoding: .utf8) {
            return content
        }

        // 3. CWD fallback
        let cwdPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/UpclaudeLib/Resources/\(filename)")
        if let content = try? String(contentsOf: cwdPath, encoding: .utf8) {
            return content
        }

        throw HookError.scriptNotFound(filename)
    }

    public enum HookError: Error, LocalizedError {
        case scriptNotFound(String)

        public var errorDescription: String? {
            switch self {
            case .scriptNotFound(let name):
                return "Hook script '\(name)' not found in bundle or Resources/"
            }
        }
    }
}
