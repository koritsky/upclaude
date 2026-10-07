import SwiftUI

/// Main sessions list grouped by GitHub repo (or project name for local repos).
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

    /// Sessions grouped alphabetically (stable order).
    private var groupedSessions: [(key: String, sessions: [AgentSession])] {
        let dict = Dictionary(grouping: appState.sortedSessions) { session in
            session.githubRepo ?? session.projectName
        }
        return
            dict
            .map { (key: $0.key, sessions: $0.value) }
            .sorted { $0.key < $1.key }
    }

    public var body: some View {
        let groups = groupedSessions
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(groups, id: \.key) { group in
                    let isCollapsed = appState.collapsedGroups.contains(group.key)
                    let displayName =
                        group.key.split(separator: "/").last.map(String.init) ?? group.key

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
                            Text(displayName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
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
                            let hasiTerm2 = session.iterm2SessionId != nil
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
