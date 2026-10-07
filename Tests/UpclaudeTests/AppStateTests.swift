import Foundation
import Testing

@testable import UpclaudeLib

@Suite("AppState")
struct AppStateTests {

    @Test("sortedSessions orders by start time, newest first")
    func sortedSessionsByStartTime() {
        let state = AppState()
        let now = Date()
        state.sessions = [
            AgentSession(
                sessionId: "1", cwd: "/a", projectName: "a",
                startedAt: now.addingTimeInterval(-3600), isHookTracked: true),
            AgentSession(
                sessionId: "2", cwd: "/b", projectName: "b",
                startedAt: now, isHookTracked: true),
            AgentSession(
                sessionId: "3", cwd: "/c", projectName: "c",
                startedAt: now.addingTimeInterval(-1800), isHookTracked: true),
        ]

        let sorted = state.sortedSessions
        #expect(sorted[0].sessionId == "2")  // newest
        #expect(sorted[1].sessionId == "3")  // middle
        #expect(sorted[2].sessionId == "1")  // oldest
    }

    @Test("waitingCount counts only waiting sessions")
    func waitingCount() {
        let state = AppState()
        state.sessions = [
            AgentSession(sessionId: "1", cwd: "/a", projectName: "a", status: .working, isHookTracked: true),
            AgentSession(sessionId: "2", cwd: "/b", projectName: "b", status: .waiting, isHookTracked: true),
            AgentSession(sessionId: "3", cwd: "/c", projectName: "c", status: .waiting, isHookTracked: true),
        ]
        #expect(state.waitingCount == 2)
    }

    @Test("workingCount counts only working sessions")
    func workingCount() {
        let state = AppState()
        state.sessions = [
            AgentSession(sessionId: "1", cwd: "/a", projectName: "a", status: .working, isHookTracked: true),
            AgentSession(sessionId: "2", cwd: "/b", projectName: "b", status: .needsApproval, isHookTracked: true),
            AgentSession(sessionId: "3", cwd: "/c", projectName: "c", status: .waiting, isHookTracked: true),
        ]
        #expect(state.workingCount == 1)
    }

    @Test("status tracking reports approval and finished transitions once")
    func statusTransitions() {
        let state = AppState()
        func session(_ id: String, _ status: AgentStatus) -> AgentSession {
            AgentSession(sessionId: id, cwd: "/a", projectName: "a", status: status, isHookTracked: true)
        }

        // First sighting is never a transition.
        let first = state.updateStatusTracking([session("1", .waiting), session("2", .needsApproval)])
        #expect(first.finished.isEmpty)
        #expect(first.needsApproval.isEmpty)

        _ = state.updateStatusTracking([session("1", .working), session("2", .working)])
        let changed = state.updateStatusTracking([session("1", .waiting), session("2", .needsApproval)])
        #expect(changed.finished.map(\.sessionId) == ["1"])
        #expect(changed.needsApproval.map(\.sessionId) == ["2"])

        // No change, no repeat.
        let repeated = state.updateStatusTracking([session("1", .waiting), session("2", .needsApproval)])
        #expect(repeated.finished.isEmpty)
        #expect(repeated.needsApproval.isEmpty)

        // Answering a permission prompt with "no" is not a finished turn.
        let denied = state.updateStatusTracking([session("1", .waiting), session("2", .waiting)])
        #expect(denied.finished.isEmpty)
        #expect(denied.noLongerWaiting.isEmpty)

        // Working again, or gone: any earlier notification is stale.
        let resumed = state.updateStatusTracking([session("1", .working)])
        #expect(Set(resumed.noLongerWaiting) == ["1", "2"])
    }

    @Test("popup project label prefers the GitHub repo name over the folder name")
    func popupProjectLabel() {
        let withRepo = AgentSession(
            sessionId: "1", cwd: "/x/old-folder", projectName: "old-folder", isHookTracked: true,
            githubRepo: "owner/new-name")
        #expect(NotificationManager.projectLabel(for: withRepo) == "new-name")

        let local = AgentSession(sessionId: "2", cwd: "/x/local", projectName: "local", isHookTracked: true)
        #expect(NotificationManager.projectLabel(for: local) == "local")
    }

    @Test("shellQuoted wraps arguments and escapes single quotes")
    func shellQuoting() {
        #expect(NotificationManager.shellQuoted("plain") == "'plain'")
        #expect(NotificationManager.shellQuoted("two words") == "'two words'")
        #expect(NotificationManager.shellQuoted("it's") == "'it'\\''s'")
        #expect(
            NotificationManager.shellCommand([["/bin/a", "x y"], ["/bin/b"]]) == "'/bin/a' 'x y'; '/bin/b'")
    }

    @Test("finished notification names the session, turn length, branch, and Claude's reply")
    func finishedNotificationText() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var session = AgentSession(sessionId: "1", cwd: "/x/repo", projectName: "repo", isHookTracked: true)
        session.title = "fix-login"
        session.gitBranch = "feat/x"
        session.turnStartedAt = start
        session.updatedAt = start.addingTimeInterval(245)
        session.lastPrompt = "fix the login bug"
        session.lastReply = "Fixed the bug."
        var text = NotificationManager.text(for: .finished, session: session)
        #expect(text.title == "repo · fix-login")
        #expect(text.subtitle == "Finished after 4m · feat/x")
        #expect(text.body == "Fixed the bug.")

        // Without a recorded reply the body falls back to the prompt, quoted.
        session.lastReply = nil
        text = NotificationManager.text(for: .finished, session: session)
        #expect(text.body == "“fix the login bug”")

        // Nothing optional recorded: still a sensible notification.
        let bare = AgentSession(sessionId: "2", cwd: "/x/repo", projectName: "repo", isHookTracked: true)
        text = NotificationManager.text(for: .finished, session: bare)
        #expect(text.subtitle == "Finished")
        #expect(text.body.isEmpty)
    }

    @Test("approval notification names the tool and what it wants to run")
    func approvalNotificationText() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var session = AgentSession(sessionId: "1", cwd: "/x/repo", projectName: "repo", isHookTracked: true)
        session.title = "deploy"
        session.activeTools = [
            "a": ActiveTool(status: .working, toolName: "Read", addedAt: now),
            "b": ActiveTool(
                status: .needsApproval, toolName: "Bash", command: "git push\norigin main",
                addedAt: now.addingTimeInterval(1)),
            "c": ActiveTool(
                status: .needsApproval, toolName: "Edit", target: "/x/app.py",
                addedAt: now.addingTimeInterval(2)),
        ]
        let text = NotificationManager.text(for: .needsApproval, session: session)
        #expect(text.title == "repo · deploy")
        #expect(text.subtitle == "Needs approval · Bash")
        #expect(text.body == "git push")
    }

    @Test("turn duration formats seconds, minutes, and hours")
    func turnDurationFormat() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        func duration(_ seconds: TimeInterval) -> String? {
            var session = AgentSession(sessionId: "1", cwd: "/a", projectName: "a", isHookTracked: true)
            session.turnStartedAt = start
            session.updatedAt = start.addingTimeInterval(seconds)
            return NotificationManager.turnDuration(of: session)
        }
        #expect(duration(45) == "45s")
        #expect(duration(245) == "4m")
        #expect(duration(4320) == "1h 12m")
        #expect(duration(-5) == nil)
    }

    @Test("activeSessions excludes unknown and abandoned")
    func activeSessions() {
        let state = AppState()
        state.sessions = [
            AgentSession(sessionId: "1", cwd: "/a", projectName: "a", status: .working, isHookTracked: true),
            AgentSession(sessionId: "2", cwd: "/b", projectName: "b", status: .unknown, isHookTracked: false),
            AgentSession(sessionId: "3", cwd: "/c", projectName: "c", status: .waiting, isHookTracked: true),
        ]
        #expect(state.activeSessions.count == 2)
    }

    @Test("toggleExpanded toggles session expansion")
    func toggleExpanded() {
        let state = AppState()
        #expect(state.expandedSessionId == nil)

        state.toggleExpanded(sessionId: "abc")
        #expect(state.expandedSessionId == "abc")

        state.toggleExpanded(sessionId: "abc")
        #expect(state.expandedSessionId == nil)

        state.toggleExpanded(sessionId: "abc")
        state.toggleExpanded(sessionId: "def")
        #expect(state.expandedSessionId == "def")
    }
}
