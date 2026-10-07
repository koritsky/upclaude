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
