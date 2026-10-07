import SwiftUI

/// Main sessions list, grouped by project and by where the sessions run.
public struct SessionsTab: View {
    @Environment(AppState.self) private var appState
    @State private var contentHeight: CGFloat = 0

    /// When true the list grows to fit its content (up to `maxFittedHeight`) instead of
    /// filling the available space. Used by the menu bar panel, which sizes itself to its content.
    private let fitsContent: Bool

    public init(fitsContent: Bool = false) {
        self.fitsContent = fitsContent
    }

    /// Tallest the fitted list may get before it starts scrolling: 60% of the screen's usable height.
    private var maxFittedHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 800) * 0.6
    }

    /// A header and the sessions under it: one project in one working directory on one machine.
    struct SessionGroup {
        /// GitHub repo slug, or the project name for repos without a GitHub remote.
        let project: String
        /// Remote host the sessions run on, nil for this machine.
        let host: String?
        /// Directory the sessions work in.
        let path: String
        let sessions: [AgentSession]

        /// Identifies the group, e.g. for remembering that it is collapsed.
        var key: String { "\(project)|\(host ?? "")|\(path)" }

        /// Header text: the repo name without its owner.
        var displayName: String {
            project.split(separator: "/").last.map(String.init) ?? project
        }

        /// Where the sessions work, shown after the name: `~/code/app` on this machine,
        /// `host:~/code/app` on a remote one. The home directory is shortened to `~` using
        /// the home the session reported; for local sessions that predate it, this user's.
        var location: String {
            let home = sessions.lazy.compactMap(\.home).first ?? (host == nil ? NSHomeDirectory() : nil)
            var shown = path
            if let home, !home.isEmpty {
                if path == home {
                    shown = "~"
                } else if path.hasPrefix(home + "/") {
                    shown = "~" + path.dropFirst(home.count)
                }
            }
            return host.map { "\($0):\(shown)" } ?? shown
        }
    }

    /// Sessions grouped by project, machine, and working directory, in a stable alphabetical
    /// order. The same repo checked out in two places, or on two machines, gets a header for
    /// each, so the header can say where its sessions run.
    static func groups(for sessions: [AgentSession]) -> [SessionGroup] {
        let grouped = Dictionary(grouping: sessions) { session in
            [session.githubRepo ?? session.projectName, session.remoteHost ?? "", session.cwd]
        }
        return grouped.map { key, sessions in
            SessionGroup(
                project: key[0], host: key[1].isEmpty ? nil : key[1], path: key[2], sessions: sessions)
        }
        .sorted { ($0.displayName.lowercased(), $0.key) < ($1.displayName.lowercased(), $1.key) }
    }

    public var body: some View {
        let groups = Self.groups(for: appState.sortedSessions)
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(groups, id: \.key) { group in
                    let isCollapsed = appState.collapsedGroups.contains(group.key)

                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            appState.toggleGroupCollapsed(group.key)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(
                                systemName: isCollapsed
                                    ? "chevron.right" : "chevron.down"
                            )
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            Text(group.displayName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .fixedSize()
                            // Where these sessions work. Paths are case-sensitive, so this is
                            // not uppercased; long ones lose their middle.
                            Text(group.location)
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .padding(.leading, 4)
                                .help(group.location)
                            Spacer()
                            if isCollapsed {
                                Text("\(group.sessions.count)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 8)
                    .padding(.trailing, 4)
                    .padding(.top, group.key == groups.first?.key ? 0 : 10)

                    if !isCollapsed {
                        ForEach(group.sessions) { session in
                            let hasiTerm2 = appState.canFocusInTerminal(session)
                            let lockInfo = appState.ideLockInfo(for: session)
                            let hasIDE = lockInfo != nil

                            AgentRow(
                                session: session,
                                isExpanded: appState.expandedSessionId == session.id,
                                onActivate: {
                                    if hasiTerm2 {
                                        appState.focusITerm2Session(session)
                                    } else if hasIDE {
                                        appState.focusIDESession(session)
                                    } else {
                                        appState.toggleExpanded(sessionId: session.id)
                                    }
                                },
                                onToggle: {
                                    appState.toggleExpanded(sessionId: session.id)
                                },
                                onFocusiTerm2: hasiTerm2
                                    ? { appState.focusITerm2Session(session) }
                                    : nil,
                                onFocusIDE: hasIDE
                                    ? { appState.focusIDESession(session) }
                                    : nil,
                                ideName: lockInfo?.ideName,
                                onDelete: { appState.deleteSession(session.id) }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                contentHeight = height
            }
        }
        .frame(height: fitsContent ? min(contentHeight, maxFittedHeight) : nil)
        .scrollBounceBehavior(.basedOnSize)
        .mask(
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: 8)
                Color.black
            }
        )
    }
}
