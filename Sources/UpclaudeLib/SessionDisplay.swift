import Foundation

/// How a session describes itself in the panel: names and one-line summaries.
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

    /// What the session is about, for the row: the most recent prompt, in quotes.
    public var promptSummary: String? {
        guard let prompt = lastPrompt ?? firstPrompt, !prompt.isEmpty else { return nil }
        return "“\(prompt)”"
    }
}
