import AppKit

/// How "working" sessions are drawn in the menu bar.
public enum WorkingDotStyle: String, CaseIterable, Identifiable {
    case blue
    case orange
    case hidden

    public static let storageKey = "workingDotStyle"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .blue: return "Blue"
        case .orange: return "Orange"
        case .hidden: return "None"
        }
    }

    /// Dot color, or nil when working sessions get no dot.
    public var color: NSColor? {
        switch self {
        case .blue: return .systemBlue
        // Claude orange, #D97757
        case .orange: return NSColor(srgbRed: 0.851, green: 0.467, blue: 0.341, alpha: 1)
        case .hidden: return nil
        }
    }

    /// The style stored in `defaults`, falling back to blue.
    public static func current(in defaults: UserDefaults = .standard) -> WorkingDotStyle {
        defaults.string(forKey: storageKey).flatMap(WorkingDotStyle.init) ?? .blue
    }
}
