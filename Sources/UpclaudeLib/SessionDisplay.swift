import Foundation

/// How a session describes itself in the panel: names, durations, and one-line summaries.
extension AgentSession {

    /// Model name as people say it: "Opus 5.5" from "claude-opus-5-5", "Haiku 4.5" from
    /// "claude-haiku-4-5-20251001". Falls back to the raw id for anything unfamiliar.
    public var prettyModelName: String {
        guard let model, !model.isEmpty else { return "—" }
        var parts = model.split(separator: "-").map(String.init)
        if parts.first == "claude" { parts.removeFirst() }
        guard let family = parts.first, family.allSatisfy(\.isLetter) else { return model }

        // Version numbers follow the family; a trailing 8-digit part is a release date.
        let version = parts.dropFirst().prefix { $0.allSatisfy(\.isNumber) && $0.count < 8 }
        let name = family.prefix(1).uppercased() + family.dropFirst()
        return version.isEmpty ? name : "\(name) \(version.joined(separator: "."))"
    }

    /// Model with the effort it runs at, e.g. "Opus 5.5 · medium". Just the model when the
    /// effort isn't known.
    public var modelAndEffort: String {
        guard let effort, !effort.isEmpty else { return prettyModelName }
        return "\(prettyModelName) · \(effort)"
    }

    /// First 8 characters of the session id, enough to recognize it.
    public var shortSessionId: String {
        String(sessionId.prefix(8))
    }

    /// When the session entered its current status, where that is known: the moment a turn
    /// started, ended, or asked for approval.
    public var statusSince: Date? {
        switch status {
        case .working:
            return turnStartedAt
        case .waiting:
            return turnEndedAt ?? updatedAt
        case .needsApproval:
            let asked = activeTools?.values
                .filter { $0.status == .needsApproval }
                .compactMap(\.addedAt)
                .min()
            return asked ?? updatedAt
        case .unknown, .abandoned:
            return nil
        }
    }

    /// How long the session has been in its current status, e.g. "12m". Nil when unknown.
    public func statusDurationText(now: Date = Date()) -> String? {
        guard let since = statusSince, now >= since else { return nil }
        return Self.compactDuration(now.timeIntervalSince(since))
    }

    /// A duration at the precision a glance needs: "now", "12m", "1h 5m", "2d 3h".
    public static func compactDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h \(minutes % 60)m" }
        return "\(hours / 24)d \(hours % 24)h"
    }

    /// What the session is about, for the row: the most recent prompt, in quotes.
    public var promptSummary: String? {
        guard let prompt = lastPrompt ?? firstPrompt, !prompt.isEmpty else { return nil }
        return "“\(prompt)”"
    }
}
