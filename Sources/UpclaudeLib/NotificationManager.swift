import Foundation
import UserNotifications

/// Posts macOS notifications when a session needs approval or finishes its turn.
/// Each kind is opt-in through its own setting.
public final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = NotificationManager()

    public static let approvalKey = "notifyOnApproval"
    public static let finishedKey = "notifyOnFinished"

    public enum Event {
        case needsApproval
        case finished

        var settingKey: String {
            switch self {
            case .needsApproval: return NotificationManager.approvalKey
            case .finished: return NotificationManager.finishedKey
            }
        }

    }

    /// Called with the session id when the user clicks one of the app's own notifications.
    public var onOpenSession: ((String) -> Void)?

    /// Commands (as argument lists) that focus a session from outside the app. Used for
    /// notifications posted through terminal-notifier, which runs a shell command on click.
    public var focusCommands: ((AgentSession) -> [[String]])?

    /// Whether the user is already looking at the session, in which case it isn't notified.
    /// May block; it is called off the main thread.
    public var isSessionFocused: ((AgentSession) -> Bool)?

    /// Sessions with a notification showing. Only touched on `queue`.
    private var outstanding: [String: AgentSession] = [:]
    private var focusTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "upclaude.notifications", qos: .userInitiated)
    private static let focusCheckInterval: TimeInterval = 2

    /// What a notification says, independent of how it gets posted.
    private struct Message {
        let title: String
        let subtitle: String
        let body: String
        let sessionId: String
        /// Shell command to run on click, if the session can be focused from outside the app.
        let clickCommand: String?
    }

    /// UNUserNotificationCenter needs an app bundle; it traps in a bare executable (`swift run`).
    private static var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    private static let sessionIdKey = "sessionId"

    override private init() {
        super.init()
        if Self.isBundled {
            UNUserNotificationCenter.current().delegate = self
        }
    }

    /// Ask macOS for permission to show notifications, so the prompt appears when a setting
    /// is switched on rather than at the first event. macOS only prompts the first time.
    public func requestAuthorization() {
        guard Self.isBundled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    /// Same name the panel's group header shows: the GitHub repo name, or the folder name
    /// for repos without a GitHub remote.
    static func projectLabel(for session: AgentSession) -> String {
        session.githubRepo?.split(separator: "/").last.map(String.init) ?? session.projectName
    }

    // MARK: - Wording

    /// The three lines of a notification.
    struct Text: Equatable {
        /// Which session: "project · session title".
        let title: String
        /// What happened, plus one qualifier (turn length and branch, or the tool).
        let subtitle: String
        /// What to act on: Claude's reply, or the command or file awaiting approval.
        let body: String
    }

    static func text(for event: Event, session: AgentSession) -> Text {
        let title = "\(projectLabel(for: session)) · \(session.displayTitle)"
        switch event {
        case .finished:
            var subtitle = "Finished"
            if let duration = turnDuration(of: session) { subtitle += " after \(duration)" }
            if let branch = session.gitBranch, !branch.isEmpty { subtitle += " · \(branch)" }
            // Fall back to the prompt so the body still says what the turn was about.
            let body = session.lastReply ?? session.lastPrompt.map { "“\($0)”" } ?? ""
            return Text(title: title, subtitle: subtitle, body: truncated(body))
        case .needsApproval:
            let tool = session.activeTools?.values
                .filter { $0.status == .needsApproval }
                .min { ($0.addedAt ?? .distantFuture) < ($1.addedAt ?? .distantFuture) }
            var subtitle = "Needs approval"
            if let name = tool?.toolName, !name.isEmpty { subtitle += " · \(name)" }
            return Text(
                title: title, subtitle: subtitle, body: truncated(tool?.command ?? tool?.target ?? ""))
        }
    }

    /// How long the turn that just ended took, e.g. "45s", "4m", "1h 12m".
    static func turnDuration(of session: AgentSession) -> String? {
        guard let start = session.turnStartedAt, let end = session.updatedAt, end >= start else { return nil }
        let seconds = Int(end.timeIntervalSince(start))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }

    private static let maxBodyLength = 200

    private static func truncated(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return line.count > maxBodyLength ? line.prefix(maxBodyLength - 1) + "…" : line
    }

    // MARK: - Posting

    /// Post a notification for the session if the matching setting is on and the user
    /// isn't already looking at it.
    public func notify(_ event: Event, session: AgentSession) {
        guard UserDefaults.standard.bool(forKey: event.settingKey) else { return }
        let commands = focusCommands?(session) ?? []
        let text = Self.text(for: event, session: session)
        let message = Message(
            title: text.title,
            subtitle: text.subtitle,
            body: text.body,
            sessionId: session.sessionId,
            clickCommand: commands.isEmpty ? nil : Self.shellCommand(commands)
        )

        queue.async {
            if self.isSessionFocused?(session) == true { return }
            Self.post(message)
            self.outstanding[session.sessionId] = session
            self.startWatchingFocus()
        }
    }

    // MARK: - Dismissing

    /// Remove the session's notification, if one is showing. Called when it is no longer news:
    /// the user focused the session, it started working again, or it ended.
    public func dismiss(sessionId: String) {
        queue.async {
            guard self.outstanding.removeValue(forKey: sessionId) != nil else { return }
            Self.removeDelivered(sessionId: sessionId)
            if self.outstanding.isEmpty { self.stopWatchingFocus() }
        }
    }

    /// While notifications are showing, check every couple of seconds whether the user has
    /// switched to one of those sessions on their own, and dismiss its notification if so.
    private func startWatchingFocus() {
        guard focusTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.focusCheckInterval, repeating: Self.focusCheckInterval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            for (sessionId, session) in self.outstanding where self.isSessionFocused?(session) == true {
                self.outstanding.removeValue(forKey: sessionId)
                Self.removeDelivered(sessionId: sessionId)
            }
            if self.outstanding.isEmpty { self.stopWatchingFocus() }
        }
        timer.resume()
        focusTimer = timer
    }

    private func stopWatchingFocus() {
        focusTimer?.cancel()
        focusTimer = nil
    }

    /// Take the notification down from the screen and Notification Center. It may have been
    /// posted by either route, so ask both; removing one that isn't there does nothing.
    /// AppleScript notifications can't be removed.
    private static func removeDelivered(sessionId: String) {
        if isBundled {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [sessionId])
        }
        if let notifier = terminalNotifierPath {
            // `-remove` has been seen to hang instead of exiting, so don't let it linger.
            run(notifier, ["-remove", sessionId], killAfter: 3)
        }
    }

    private static func post(_ message: Message) {
        guard isBundled else {
            postWithoutBundle(message)
            return
        }

        // Ask here as well as from Settings: the setting can be on without permission ever
        // having been requested (imported settings, permission reset).
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, error in
            guard granted else {
                // macOS refuses some builds outright ("Notifications are not allowed for this
                // application", seen with ad-hoc signed bundles), so still deliver something.
                NSLog("[Notifications] not authorized, falling back: %@", String(describing: error))
                postWithoutBundle(message)
                return
            }
            center.add(request(for: message)) { error in
                if let error { NSLog("[Notifications] failed to post: %@", String(describing: error)) }
            }
        }
    }

    private static func request(for message: Message) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = message.title
        content.subtitle = message.subtitle
        content.body = message.body
        content.userInfo = [sessionIdKey: message.sessionId]
        // One notification per session: a newer event replaces the older one.
        return UNNotificationRequest(identifier: message.sessionId, content: content, trigger: nil)
    }

    // MARK: - Fallbacks

    /// Post without the app's own notification identity: unbundled development builds, or
    /// macOS denying permission. Prefers terminal-notifier, which can run a command on click.
    private static func postWithoutBundle(_ message: Message) {
        guard let notifier = terminalNotifierPath else {
            postWithAppleScript(message)
            return
        }
        // terminal-notifier rejects an empty message and treats some leading characters as
        // syntax unless they are escaped.
        func safe(_ text: String) -> String {
            guard let first = text.first else { return " " }
            return "[(<-".contains(first) ? "\\" + text : text
        }
        var arguments = [
            "-title", safe(message.title), "-subtitle", safe(message.subtitle),
            "-message", safe(message.body), "-group", message.sessionId,
        ]
        if let clickCommand = message.clickCommand {
            arguments += ["-execute", clickCommand]
        }
        run(notifier, arguments)
    }

    /// terminal-notifier, if installed in one of the usual Homebrew or Nix locations.
    private static let terminalNotifierPath: String? = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let directories = [
            "/opt/homebrew/bin", "/usr/local/bin", "/etc/profiles/per-user/\(NSUserName())/bin",
            "/run/current-system/sw/bin", "\(home)/.nix-profile/bin",
        ]
        return directories.map { "\($0)/terminal-notifier" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    /// Last resort. Shown by macOS as coming from Script Editor, and clicking it opens
    /// Script Editor rather than the session.
    private static func postWithAppleScript(_ message: Message) {
        func quoted(_ text: String) -> String {
            let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        let script =
            "display notification \(quoted(message.body)) with title \(quoted(message.title))"
            + " subtitle \(quoted(message.subtitle))"
        run("/usr/bin/osascript", ["-e", script])
    }

    private static func run(_ executable: String, _ arguments: [String], killAfter timeout: TimeInterval? = nil) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil, let timeout else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            if task.isRunning { task.terminate() }
        }
    }

    /// Join argument lists into one POSIX shell command line, running them in order.
    static func shellCommand(_ commands: [[String]]) -> String {
        commands.map { $0.map(shellQuoted).joined(separator: " ") }.joined(separator: "; ")
    }

    /// Quote one argument for a POSIX shell.
    static func shellQuoted(_ argument: String) -> String {
        "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show the banner even while Upclaude is the active app (e.g. its panel is open).
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner])
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let sessionId = userInfo[Self.sessionIdKey] as? String {
            DispatchQueue.main.async { self.onOpenSession?(sessionId) }
        }
        completionHandler()
    }
}
