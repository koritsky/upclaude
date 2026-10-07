import Foundation
import Testing

@testable import UpclaudeLib

@Suite("HookManager")
struct HookManagerTests {

    @Test("isInstalled returns true when hooks exist in settings")
    func isInstalledDetectsHooks() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("upclaude-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let manager = HookManager(home: home)
        #expect(manager.isInstalled == false)

        try manager.installHooksInSettings()
        #expect(manager.isInstalled == true)
    }

    @Test("sessionsDirectoryPath points to ~/.upclaude/sessions")
    func sessionsDirectory() {
        let manager = HookManager()
        let expected = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".upclaude/sessions").path
        #expect(manager.sessionsDirectoryPath == expected)
    }
}
