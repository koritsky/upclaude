import SwiftUI

// MARK: - Shared Sessions Content

/// Shared content section used by both panel and detached views:
/// usage limits, divider, and sessions list (or empty state).
public struct SessionsContent: View {
    @Environment(AppState.self) private var appState

    private let fitsContent: Bool

    public init(fitsContent: Bool = false) {
        self.fitsContent = fitsContent
    }

    public var body: some View {
        if let limits = appState.usageLimits {
            UsageLimitsView(
                limits: limits,
                error: appState.usageLimitsError
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        } else if let error = appState.usageLimitsError {
            HStack(spacing: 6) {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Button {
                    appState.refreshUsageLimits()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Retry loading usage data")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }

        if appState.sessions.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "apple.terminal")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                Text("No active sessions")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Start a Claude Code session to see it here")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
            SessionsTab(fitsContent: fitsContent)
        }
    }
}

// MARK: - Panel View

/// The main panel shown when clicking the menu bar icon.
/// Header with status summary, sessions list, and footer.
public struct PanelView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage("showFloatingWindow") private var showFloatingWindow = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            SessionsContent(fitsContent: true)

            Divider()

            footer
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(width: 420)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Upclaude")
                .font(.headline)

            Spacer()

            // How many sessions are in each state, in the same marks the rows use.
            HStack(spacing: 10) {
                StatusCount(status: .needsApproval, count: appState.needsApprovalCount)
                StatusCount(status: .waiting, count: appState.waitingCount)
                StatusCount(status: .working, count: appState.workingCount)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("\(appState.sessions.count) session\(appState.sessions.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                setFloatingWindow(!showFloatingWindow)
            } label: {
                Image(systemName: showFloatingWindow ? "pin.fill" : "pin")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(
                showFloatingWindow
                    ? "Close the floating window" : "Keep the panel open as a floating window")

            Button {
                appState.refreshUsageLimits()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(
                appState.usageLimits.map { "Usage updated \(Self.updatedText($0.updatedAt))" }
                    ?? "Refresh usage data"
            )

            Menu {
                SettingsLink {
                    Text("Settings...")
                }
                Button("Reinstall") {
                    try? HookManager.shared.install()
                }
                Divider()
                Button("Quit Upclaude") {
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        }
    }

    /// Open the panel as a floating window that stays on screen, or close that window.
    private func setFloatingWindow(_ isFloating: Bool) {
        let menuBarPanel = NSApp.keyWindow
        showFloatingWindow = isFloating
        guard isFloating else {
            dismissWindow(id: "main")
            return
        }
        openWindow(id: "main")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            menuBarPanel?.orderOut(nil)
            for window in NSApp.windows
            where window.title == "Upclaude" && window.level == .floating {
                window.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    static func updatedText(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 5 { return "just now" }
        if interval < 60 { return "\(Int(interval))s ago" }
        let minutes = Int(interval / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        return "\(hours)h ago"
    }
}

// MARK: - Status Count

/// Number of sessions in one state, shown with that state's mark. Hidden when zero.
struct StatusCount: View {
    let status: AgentStatus
    private let sessionCount: Int

    init(status: AgentStatus, count: Int) {
        self.status = status
        self.sessionCount = count
    }

    var body: some View {
        if sessionCount >= 1 {
            HStack(spacing: 3) {
                StatusMark(status: status)
                Text("\(sessionCount)")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .help("\(sessionCount) \(status.displayLabel.lowercased())")
        }
    }
}
