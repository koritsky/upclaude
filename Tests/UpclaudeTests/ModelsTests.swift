import Foundation
import Testing

@testable import UpclaudeLib

@Suite("Models")
struct ModelsTests {

    // MARK: - AgentStatus

    @Test("AgentStatus sort order: needsApproval < waiting < working < unknown < abandoned")
    func statusSortOrder() {
        #expect(AgentStatus.needsApproval.sortOrder < AgentStatus.waiting.sortOrder)
        #expect(AgentStatus.waiting.sortOrder < AgentStatus.working.sortOrder)
        #expect(AgentStatus.working.sortOrder < AgentStatus.unknown.sortOrder)
        #expect(AgentStatus.unknown.sortOrder < AgentStatus.abandoned.sortOrder)
    }

    @Test("AgentStatus display labels")
    func statusDisplayLabels() {
        #expect(AgentStatus.working.displayLabel == "Working")
        #expect(AgentStatus.needsApproval.displayLabel == "Approve")
        #expect(AgentStatus.waiting.displayLabel == "Your turn")
        #expect(AgentStatus.unknown.displayLabel == "Unknown")
        #expect(AgentStatus.abandoned.displayLabel == "Inactive")
    }

    // MARK: - AgentSession

    @Test("formattedContext formats percentage correctly")
    func formattedContext() {
        let session = AgentSession(sessionId: "1", cwd: "/a", projectName: "a", contextPct: 68.5, isHookTracked: true)
        #expect(session.formattedContext == "68%")

        let noContext = AgentSession(sessionId: "2", cwd: "/b", projectName: "b", isHookTracked: false)
        #expect(noContext.formattedContext == "—")
    }

    @Test("shortModelName extracts model family")
    func shortModelName() {
        let opus = AgentSession(
            sessionId: "1", cwd: "/a", projectName: "a", model: "claude-opus-5-5", isHookTracked: true)
        #expect(opus.shortModelName == "Opus")

        let sonnet = AgentSession(
            sessionId: "2", cwd: "/b", projectName: "b", model: "claude-sonnet-5-5", isHookTracked: true)
        #expect(sonnet.shortModelName == "Sonnet")

        let fable = AgentSession(
            sessionId: "5", cwd: "/e", projectName: "e", model: "claude-fable-5-1", isHookTracked: true)
        #expect(fable.shortModelName == "Fable")

        let haiku = AgentSession(
            sessionId: "3", cwd: "/c", projectName: "c", model: "claude-haiku-4-5-20251001", isHookTracked: true)
        #expect(haiku.shortModelName == "Haiku")

        let noModel = AgentSession(sessionId: "4", cwd: "/d", projectName: "d", isHookTracked: false)
        #expect(noModel.shortModelName == "—")
    }

    @Test("AgentSession decodes zellij pane when present")
    func decodesZellijPane() throws {
        let json = """
            {
                "session_id": "s1", "cwd": "/a", "project_name": "a", "is_hook_tracked": true,
                "zellij": {"session": "main", "pane_id": "terminal_10", "bin": "/opt/bin/zellij"}
            }
            """
        let session = try JSONDecoder().decode(AgentSession.self, from: Data(json.utf8))
        #expect(session.zellij == ZellijPane(session: "main", paneId: "terminal_10", bin: "/opt/bin/zellij"))

        let plain = """
            {"session_id": "s2", "cwd": "/a", "project_name": "a", "is_hook_tracked": true, "zellij": null}
            """
        #expect(try JSONDecoder().decode(AgentSession.self, from: Data(plain.utf8)).zellij == nil)
    }

    @Test("AgentSession decodes from JSON state file")
    func decodesFromJSON() throws {
        let json = """
            {
                "session_id": "42ac740e",
                "cwd": "/Users/test/project",
                "project_name": "project",
                "status": "waiting",
                "model": "claude-opus-4-6",
                "git_branch": "main",
                "slug": "test-slug",
                "context_pct": 68.5,
                "input_tokens": 137000,
                "output_tokens": 42000,
                "started_at": "2026-03-12T08:44:59Z",
                "updated_at": "2026-03-12T09:12:33Z",
                "is_hook_tracked": true
            }
            """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(
            AgentSession.self, from: json.data(using: .utf8)!  // swiftlint:disable:this force_unwrapping
        )

        #expect(session.sessionId == "42ac740e")
        #expect(session.status == .waiting)
        #expect(session.model == "claude-opus-4-6")
        #expect(session.contextPct == 68.5)
        #expect(session.isHookTracked == true)
    }

    @Test("iterm2SessionId decodes when present")
    func iterm2SessionIdPresent() throws {
        let json = """
            {
                "session_id": "abc123",
                "cwd": "/tmp",
                "project_name": "test",
                "status": "working",
                "is_hook_tracked": true,
                "iterm2_session_id": "w0t0p0.DEADBEEF-1234-5678-9ABC-DEF012345678"
            }
            """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(
            AgentSession.self, from: json.data(using: .utf8)!  // swiftlint:disable:this force_unwrapping
        )
        #expect(session.iterm2SessionId == "w0t0p0.DEADBEEF-1234-5678-9ABC-DEF012345678")
    }

    @Test("iterm2SessionId is nil when absent")
    func iterm2SessionIdAbsent() throws {
        let json = """
            {
                "session_id": "abc456",
                "cwd": "/tmp",
                "project_name": "test",
                "status": "waiting",
                "is_hook_tracked": true
            }
            """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(
            AgentSession.self, from: json.data(using: .utf8)!  // swiftlint:disable:this force_unwrapping
        )
        #expect(session.iterm2SessionId == nil)
    }

    @Test("elapsedTime formats hours and minutes")
    func elapsedTime() {
        let recent = AgentSession(
            sessionId: "1", cwd: "/a", projectName: "a",
            startedAt: Date().addingTimeInterval(-300),  // 5 min ago
            isHookTracked: true
        )
        #expect(recent.elapsedTime == "5m")

        let old = AgentSession(
            sessionId: "2", cwd: "/b", projectName: "b",
            startedAt: Date().addingTimeInterval(-7500),  // 2h 5m ago
            isHookTracked: true
        )
        #expect(old.elapsedTime == "2h 5m")

        let noStart = AgentSession(sessionId: "3", cwd: "/c", projectName: "c", isHookTracked: false)
        #expect(noStart.elapsedTime == "—")
    }

    // MARK: - ContextSnapshot

    @Test("ContextSnapshot decodes from JSON with short keys")
    func contextSnapshotDecodes() throws {
        let json = """
            {"t": "2026-03-22T10:30:05Z", "pct": 42.5}
            """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(
            ContextSnapshot.self, from: json.data(using: .utf8)!  // swiftlint:disable:this force_unwrapping
        )
        #expect(snapshot.pct == 42.5)
    }

    @Test("AgentSession decodes with context_snapshots")
    func sessionWithSnapshots() throws {
        let json = """
            {
                "session_id": "s1",
                "cwd": "/tmp",
                "project_name": "test",
                "status": "working",
                "is_hook_tracked": true,
                "context_snapshots": [
                    {"t": "2026-03-22T10:00:00Z", "pct": 10.0},
                    {"t": "2026-03-22T10:05:00Z", "pct": 25.3}
                ]
            }
            """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(
            AgentSession.self, from: json.data(using: .utf8)!  // swiftlint:disable:this force_unwrapping
        )
        #expect(session.contextSnapshots?.count == 2)
        #expect(session.contextSnapshots?.last?.pct == 25.3)
    }

    @Test("AgentSession decodes without context_snapshots (backward compat)")
    func sessionWithoutSnapshots() throws {
        let json = """
            {
                "session_id": "s2",
                "cwd": "/tmp",
                "project_name": "test",
                "status": "working",
                "is_hook_tracked": false
            }
            """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(
            AgentSession.self, from: json.data(using: .utf8)!  // swiftlint:disable:this force_unwrapping
        )
        #expect(session.contextSnapshots == nil)
    }

    // MARK: - Session display

    @Test("prettyModelName reads the way people say it")
    func prettyModelName() {
        func name(_ model: String?) -> String {
            AgentSession(sessionId: "1", cwd: "/a", projectName: "a", model: model, isHookTracked: true)
                .prettyModelName
        }
        #expect(name("claude-opus-5-5") == "Opus 5.5")
        #expect(name("claude-haiku-4-5-20251001") == "Haiku 4.5")
        #expect(name("claude-fable-5-1") == "Fable 5.1")
        #expect(name("claude-sonnet-5") == "Sonnet 5")
        #expect(name("4-turbo") == "4-turbo")
        #expect(name(nil) == "—")
    }

    @Test("modelAndEffort appends the effort when it is known")
    func modelAndEffort() {
        var session = AgentSession(
            sessionId: "1", cwd: "/a", projectName: "a", model: "claude-opus-5-5", isHookTracked: true)
        #expect(session.modelAndEffort == "Opus 5.5")
        session.effort = "medium"
        #expect(session.modelAndEffort == "Opus 5.5 · medium")
    }

    @Test("promptSummary quotes the latest prompt and shortSessionId keeps eight characters")
    func promptSummaryAndShortId() {
        var session = AgentSession(
            sessionId: "210f971e-aff4-461b", cwd: "/a", projectName: "a", isHookTracked: true)
        #expect(session.promptSummary == nil)
        session.firstPrompt = "first"
        #expect(session.promptSummary == "“first”")
        session.lastPrompt = "latest"
        #expect(session.promptSummary == "“latest”")
        #expect(session.shortSessionId == "210f971e")
    }

    @Test("row widgets are shown only when they have something to show")
    func rowWidgets() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let recent = [
            ContextSnapshot(t: now.addingTimeInterval(-120), pct: 10),
            ContextSnapshot(t: now.addingTimeInterval(-60), pct: 12),
        ]
        let stale = [
            ContextSnapshot(t: now.addingTimeInterval(-9000), pct: 10),
            ContextSnapshot(t: now.addingTimeInterval(-8000), pct: 12),
        ]
        #expect(SparklineView.hasActivity(recent, now: now))
        #expect(!SparklineView.hasActivity(stale, now: now))
        #expect(!SparklineView.hasActivity([], now: now))

        #expect(!PRStatusIcon.hasContent(prInfo: nil, commitCount: nil))
        #expect(!PRStatusIcon.hasContent(prInfo: nil, commitCount: 0))
        #expect(PRStatusIcon.hasContent(prInfo: nil, commitCount: 2))
    }

    // MARK: - ClaudeSpinner

    @Test("ClaudeSpinner cycle goes out and back, resting on the smallest and fullest glyphs")
    func claudeSpinnerCycle() {
        let cycle = ClaudeSpinner.cycle(scale: 2)
        // Six glyphs out, four back; the ends aren't repeated but are held longer.
        #expect(cycle.frames.count == 10)
        #expect(
            cycle.durations == [0.36, 0.12, 0.12, 0.12, 0.12, 0.36, 0.12, 0.12, 0.12, 0.12])
    }

    @Test("ClaudeSpinner glyph at a moment follows the same schedule as the cycle")
    func claudeSpinnerGlyphAtTime() {
        // Cycle: · held 0.36s, then ✢ ✳ ✶ ✻ at 0.12s each, ✽ held 0.36s, then back.
        func glyph(_ offset: TimeInterval) -> String {
            ClaudeSpinner.glyph(at: Date(timeIntervalSinceReferenceDate: 1.68 * 1000 + offset))
        }
        #expect(glyph(0.01) == "·")
        #expect(glyph(0.35) == "·")
        #expect(glyph(0.37) == "✢")
        #expect(glyph(0.85) == "✽")
        #expect(glyph(1.19) == "✽")
        #expect(glyph(1.21) == "✻")
        #expect(glyph(1.67) == "✢")
    }

    @Test("ClaudeSpinner glyphs are drawn in a fixed square at the backing scale")
    func claudeSpinnerGlyphImage() {
        let image = ClaudeSpinner.glyphImage(ClaudeSpinner.restingGlyph, color: .gray, scale: 2)
        #expect(image?.width == 24)
        #expect(image?.height == 24)
        #expect(ClaudeSpinner.cycle(scale: 3).frames.first?.width == 36)
    }
}
