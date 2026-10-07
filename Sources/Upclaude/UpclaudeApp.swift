import AppKit
import ServiceManagement
import SwiftUI
import UpclaudeLib

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Register as login item only when running as a bundled .app
        // (skip in development when launched via `swift run` from terminal)
        if Bundle.main.bundlePath.hasSuffix(".app"),
            SMAppService.mainApp.status != .enabled
        {
            try? SMAppService.mainApp.register()
        }

        installCLISymlink()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Self.checkAndInstallHooks()
        }
    }

    /// Installs a wrapper script at /usr/local/bin/upclaude that opens the .app bundle.
    /// A direct symlink to the binary won't work because Bundle.main wouldn't resolve
    /// to the .app, breaking SPM resource bundle lookup.
    private func installCLISymlink() {
        let scriptPath = "/usr/local/bin/upclaude"
        let appPath = Bundle.main.bundleURL.path
        let script = "#!/bin/sh\nopen \"\(appPath)\"\n"

        // Already correct
        if let existing = try? String(contentsOfFile: scriptPath, encoding: .utf8),
            existing == script
        {
            return
        }

        try? script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        chmod(scriptPath, 0o755)
    }

    static func checkAndInstallHooks() {
        let hookManager = HookManager.shared

        // Always update hook script (idempotent)
        try? hookManager.installHookScript()
        // Keep already-installed iTerm2 scripts in step with this build.
        if ITerm2Installer.isInstalled { try? ITerm2Installer.install() }

        // If all expected hooks are registered, nothing more to do
        guard !hookManager.isInstalled else { return }

        let alert = NSAlert()
        alert.messageText = "Install Session Tracking Hooks?"
        alert.informativeText = """
            Upclaude needs to add hooks to your Claude Code settings \
            (~/.claude/settings.json) to track session status in real-time.

            This enables:
            • Detecting when sessions start and end
            • Knowing when a session is waiting for your input
            • Tracking context usage and cost per session

            Your existing Claude settings will be preserved. \
            You can remove hooks anytime from Upclaude settings.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install Hooks")
        alert.addButton(withTitle: "Not Now")

        NSApp.activate(ignoringOtherApps: true)

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            do {
                try hookManager.installHooksInSettings()
            } catch {
                let errorAlert = NSAlert()
                errorAlert.messageText = "Hook Installation Failed"
                errorAlert.informativeText = error.localizedDescription
                errorAlert.alertStyle = .warning
                errorAlert.runModal()
            }
        }
    }
}

@main
struct UpclaudeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState: AppState = {
        let state = AppState()
        state.start()
        MenuBarPulseAnimator.shared.start(appState: state)
        return state
    }()
    var body: some Scene {
        Window("Upclaude", id: "main") {
            ZStack {
                Color.clear
                    .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
                    .background(.thinMaterial)
                    .ignoresSafeArea()

                DetachedPanelView()
                    .environment(appState)
            }
            .background(WindowConfigurator())
        }
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 420, height: 520)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)

        MenuBarExtra {
            PanelView()
                .environment(appState)
        } label: {
            MenuBarLabelWithLauncher(appState: appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appState)
                .background(SettingsWindowConfigurator())
        }
    }
}

/// Sets the hosting window to float above normal windows so it stays always visible.
/// Resets the "showFloatingWindow" preference when the window is closed via the X button.
private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.level = .floating
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                window.titlebarAppearsTransparent = true
                window.isOpaque = false
                window.backgroundColor = .clear
                window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                window.standardWindowButton(.zoomButton)?.isHidden = true

                context.coordinator.observe(window)
                Self.setupInitialState(window: window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Animate close button, toolbar menu button, and title on hover.
    static func setHoverState(window: NSWindow, hovering: Bool) {
        let alpha: CGFloat = hovering ? 1 : 0

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2

            // Close button — snap visibility (system widget doesn't animate alpha cleanly)
            window.standardWindowButton(.closeButton)?.isHidden = !hovering

            // Title — use alphaValue so it animates on the same curve as the menu button
            findView(in: window, matching: "ToolbarTitleView")?.animator().alphaValue =
                hovering ? 1.0 : 0.3

            // Toolbar item viewers (refresh + menu button)
            for view in findAllViews(in: window, matching: "ToolbarItemViewer") {
                view.animator().alphaValue = alpha
            }
        }
    }

    /// Initial setup: dim title, hide buttons, permanently hide the glass pill.
    static func setupInitialState(window: NSWindow) {
        window.standardWindowButton(.closeButton)?.isHidden = true

        findView(in: window, matching: "ToolbarTitleView")?.alphaValue = 0.3

        func setup(_ view: NSView) {
            let name = String(describing: type(of: view))
            if name.contains("ToolbarPlatterView") {
                view.isHidden = true
                return
            }
            if name.contains("ToolbarItemViewer") {
                view.alphaValue = 0
                return
            }
            for sub in view.subviews { setup(sub) }
        }

        if let container = window.standardWindowButton(.closeButton)?.superview?.superview {
            setup(container)
        }

        // Pin the title view to full width so toolbar layout changes don't shift it
        if let titleView = findView(in: window, matching: "ToolbarTitleView") {
            titleView.translatesAutoresizingMaskIntoConstraints = false
            if let superview = titleView.superview {
                NSLayoutConstraint.activate([
                    titleView.centerXAnchor.constraint(equalTo: superview.centerXAnchor),
                    titleView.centerYAnchor.constraint(equalTo: superview.centerYAnchor),
                ])
            }
        }
    }

    /// Recursively find a view whose class name contains the given string.
    private static func findView(in window: NSWindow, matching className: String) -> NSView? {
        findAllViews(in: window, matching: className).first
    }

    /// Recursively find all views whose class name contains the given string.
    private static func findAllViews(in window: NSWindow, matching className: String) -> [NSView] {
        guard let root = window.standardWindowButton(.closeButton)?.superview?.superview
        else { return [] }
        var results: [NSView] = []
        func search(_ view: NSView) {
            if String(describing: type(of: view)).contains(className) {
                results.append(view)
                return
            }
            for sub in view.subviews { search(sub) }
        }
        search(root)
        return results
    }

    final class Coordinator: NSObject {
        private var observation: Any?

        func observe(_ window: NSWindow) {
            observation = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window, queue: .main
            ) { _ in
                UserDefaults.standard.set(false, forKey: "showFloatingWindow")
            }

            // Add a tracking view to detect mouse enter/exit on the window
            guard let contentView = window.contentView else { return }
            let tracker = ToolbarHoverTracker(window: window)
            tracker.frame = contentView.bounds
            tracker.autoresizingMask = [.width, .height]
            contentView.addSubview(tracker)
        }

        deinit { observation.map(NotificationCenter.default.removeObserver) }
    }
}

/// Invisible tracking view that shows/hides toolbar items on window hover.
private final class ToolbarHoverTracker: NSView {
    weak var trackedWindow: NSWindow?

    init(window: NSWindow) {
        self.trackedWindow = window
        super.init(frame: .zero)
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // Pass all clicks through to the views below
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func mouseEntered(with event: NSEvent) {
        guard let window = trackedWindow else { return }
        WindowConfigurator.setHoverState(window: window, hovering: true)
    }

    override func mouseExited(with event: NSEvent) {
        guard let window = trackedWindow else { return }
        WindowConfigurator.setHoverState(window: window, hovering: false)
    }
}

/// Ensures the Settings window floats above other windows.
private struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.level = .floating
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Thin wrapper around MenuBarLabel that optionally opens the floating window at launch.
struct MenuBarLabelWithLauncher: View {
    let appState: AppState
    @AppStorage("showFloatingWindow") private var showFloatingWindow = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenuBarLabel(appState: appState)
            .task {
                if showFloatingWindow {
                    openWindow(id: "main")
                }
            }
    }
}

/// Menu bar label rendered as an NSImage so we get proper SF Symbols + text.
/// SwiftUI MenuBarExtra labels don't reliably render complex view hierarchies,
/// but a single Image backed by a rendered NSImage works perfectly.
struct MenuBarLabel: View {
    let appState: AppState
    @AppStorage("useRedYellowMode") private var useRedYellowMode = true
    @AppStorage("usageRingThreshold") private var usageRingThreshold = 50
    @AppStorage(WorkingDotStyle.storageKey) private var workingDotStyle = WorkingDotStyle.blue
    @State private var menuBarAppearanceObserver = MenuBarAppearanceObserver()

    /// Seconds for one full fade-out/fade-in cycle of the "working" dots.
    static let pulsePeriod: TimeInterval = 4.0
    /// Lowest opacity the "working" dots fade to.
    static let pulseMinAlpha: CGFloat = 0.3

    static let dotSize: CGFloat = 8
    static let dotSpacing: CGFloat = 4
    static let maxDots = 8
    static let ringDiameter: CGFloat = 14
    static let ringSpacing: CGFloat = 6

    /// Usage fill percentage (0–100) from the 5-hour usage limit, nil if unavailable.
    private var usagePct: CGFloat? {
        guard let limits = appState.usageLimits else { return nil }
        return CGFloat(limits.fiveHour.utilization)
    }

    /// Whether the usage ring should be shown (above threshold).
    private var showRing: Bool {
        guard let pct = usagePct else { return false }
        return pct >= CGFloat(usageRingThreshold)
    }

    var body: some View {
        let approval = appState.needsApprovalCount
        let waiting = appState.waitingCount
        // Working sessions get no dot when the style is hidden.
        let working = workingDotStyle.color == nil ? 0 : appState.workingCount
        // Read to establish SwiftUI dependency so we redraw on appearance changes
        let _ = menuBarAppearanceObserver.isDark  // swiftlint:disable:this redundant_discardable_let

        if approval == 0 && waiting == 0 && working == 0 {
            // No active sessions - just show the terminal icon
            if showRing, let pct = usagePct,
                let img = Self.renderRingOnly(pct: pct)
            {
                Image(nsImage: img)
            } else if let icon = Self.menuBarIcon {
                Image(nsImage: icon)
            }
        } else if let image = Self.renderDotsImage(
            approval: approval, waiting: waiting, working: working,
            // Working dots are drawn at their dimmest; MenuBarPulseAnimator fades a full-strength
            // copy in and out on top of them.
            workingAlpha: MenuBarPulseAnimator.reduceMotion ? 1 : Self.pulseMinAlpha,
            workingColor: workingDotStyle.color ?? .systemBlue,
            useRedYellowMode: useRedYellowMode,
            usagePct: showRing ? usagePct : nil
        ) {
            Image(nsImage: image)
        }
    }

    // MARK: - Ring Drawing

    /// Draw a circular progress ring into the current graphics context.
    /// Uses the provided foreground color for the arc and a faded version for the track.
    private static func drawRing(
        center: NSPoint, radius: CGFloat, lineWidth: CGFloat, pct: CGFloat,
        color: NSColor = .black
    ) {
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        color.withAlphaComponent(0.2).setStroke()
        track.lineWidth = lineWidth
        track.stroke()

        if pct > 0 {
            let endAngle: CGFloat = 90 - (min(pct, 100) / 100) * 360
            let arc = NSBezierPath()
            arc.appendArc(
                withCenter: center, radius: radius,
                startAngle: 90, endAngle: endAngle, clockwise: true
            )
            color.setStroke()
            arc.lineWidth = lineWidth
            arc.lineCapStyle = .round
            arc.stroke()
        }
    }

    /// Create a bitmap rep for menu bar rendering at Retina scale.
    private static func makeMenuBarRep(size: NSSize) -> (NSBitmapImageRep, NSSize) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let pixelSize = NSSize(width: size.width * scale, height: size.height * scale)
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(pixelSize.width),
                pixelsHigh: Int(pixelSize.height),
                bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0
            )
        else {
            fatalError("Failed to create NSBitmapImageRep for menu bar icon")
        }
        rep.size = size
        return (rep, size)
    }

    /// Menu bar icon rendered from the bundled SVG, used as a template image.
    private static let menuBarIcon: NSImage? = {
        let svg = """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 17.31 16.35">
              <path fill="#fff" d="M14,.4H3.4C1.57.4.09,1.89.09,3.71v6.62c0,1.83,1.48,3.31,3.31,3.31v1.31c0,.36.3.66.66.66h.66c.36,0,.66-.3.66-.66v-1.31h2.1v1.31c0,.36.3.66.66.66h.66c.36,0,.66-.3.66-.66v-1.31h2.1v1.31c0,.36.3.66.66.66h.66c.36,0,.66-.3.66-.66v-1.31h.43c1.83,0,3.31-1.48,3.31-3.31V3.71c0-1.83-1.48-3.31-3.31-3.31ZM5.39,7.36c0,.55-.44.99-.99.99h-1.99c-.55,0-.99-.44-.99-.99v-1.99c0-.55.44-.99.99-.99h1.99c.55,0,.99.44.99.99v1.99ZM10.68,7.36c0,.55-.44.99-.99.99h-1.99c-.55,0-.99-.44-.99-.99v-1.99c0-.55.44-.99.99-.99h1.99c.55,0,.99.44.99.99v1.99ZM15.98,7.36c0,.55-.44.99-.99.99h-1.99c-.55,0-.99-.44-.99-.99v-1.99c0-.55.44-.99.99-.99h1.99c.55,0,.99.44.99.99v1.99Z"/>
              <rect fill="#fff" x="2.57" y="5.54" width="1.65" height="1.65" rx=".55" ry=".55"/>
              <rect fill="#fff" x="7.87" y="5.54" width="1.65" height="1.65" rx=".55" ry=".55"/>
              <rect fill="#fff" x="13.17" y="5.54" width="1.65" height="1.65" rx=".46" ry=".46"/>
            </svg>
            """
        guard let data = svg.data(using: .utf8),
            let image = NSImage(data: data)
        else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 17)
        return image
    }()

    /// Render a standalone usage ring for idle state. Always template.
    private static func renderRingOnly(pct: CGFloat) -> NSImage? {
        let menuBarHeight = NSStatusBar.system.thickness
        let ringDiameter: CGFloat = 14
        let imageSize = NSSize(width: ringDiameter, height: menuBarHeight)

        let (rep, _) = makeMenuBarRep(size: imageSize)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

        drawRing(
            center: NSPoint(x: ringDiameter / 2, y: menuBarHeight / 2),
            radius: ringDiameter / 2 - 2, lineWidth: 2.5, pct: pct
        )

        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: imageSize)
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }

    /// Render one colored dot per active session, ordered by urgency.
    /// Caps at maxDots to keep menu bar compact.
    /// The usage ring is drawn using the resolved menu bar foreground color
    /// so it adapts to wallpaper-driven tinting while dots keep their colors.
    static func renderDotsImage(
        approval: Int, waiting: Int, working: Int,
        workingAlpha: CGFloat,
        workingColor: NSColor = .systemBlue,
        useRedYellowMode: Bool,
        usagePct: CGFloat? = nil
    ) -> NSImage? {
        // Build dot list: most urgent first.
        // Red (approval) and green (waiting) need the user; working dots pulse via workingAlpha.
        var dots: [NSColor] = []
        for _ in 0..<approval { dots.append(.systemRed) }
        for _ in 0..<waiting { dots.append(.systemGreen) }
        for _ in 0..<working { dots.append(workingColor.withAlphaComponent(workingAlpha)) }
        guard !dots.isEmpty else { return nil }

        let capped = dots.prefix(maxDots)
        let menuBarHeight = NSStatusBar.system.thickness

        let hasRing = usagePct != nil
        let ringExtra: CGFloat = hasRing ? (ringSpacing + ringDiameter) : 0

        let dotsWidth = CGFloat(capped.count) * dotSize + CGFloat(capped.count - 1) * dotSpacing
        let imageSize = NSSize(
            width: dotsWidth + ringExtra,
            height: menuBarHeight
        )
        let (rep, _) = makeMenuBarRep(size: imageSize)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

        // Draw dots
        let dotY = (menuBarHeight - dotSize) / 2
        for (index, color) in capped.enumerated() {
            let x = CGFloat(index) * (dotSize + dotSpacing)
            let dotRect = NSRect(x: x, y: dotY, width: dotSize, height: dotSize)
            color.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        }

        // Draw the usage ring using the menu bar's resolved foreground color,
        // derived from the NSStatusBarWindow's effectiveAppearance which
        // accounts for wallpaper-driven tinting — not just system dark mode.
        if let pct = usagePct {
            let ringColor = statusBarForegroundColor()
            let ringX = dotsWidth + ringSpacing + ringDiameter / 2
            drawRing(
                center: NSPoint(x: ringX, y: menuBarHeight / 2),
                radius: ringDiameter / 2 - 2, lineWidth: 2.5, pct: pct,
                color: ringColor
            )
        }

        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: imageSize)
        image.addRepresentation(rep)
        image.isTemplate = false
        return image
    }

    /// Resolve the correct foreground color for menu bar items.
    /// Finds the NSStatusBarWindow (created by macOS for each status item) and reads
    /// its effectiveAppearance, which is set based on the wallpaper behind the menu bar
    /// — not just system-wide dark/light mode.
    private static func statusBarForegroundColor() -> NSColor {
        for window in NSApp.windows
        where String(describing: type(of: window)).contains("StatusBar") {
            let appearance = window.effectiveAppearance
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? .white : .black
        }
        // Fallback: use app-level appearance
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? .white : .black
    }
}

/// Pulses the "working" dots with a Core Animation overlay on the status item's button.
///
/// The SwiftUI label must stay static: updating a MenuBarExtra label at animation rates makes
/// the status item stop responding to clicks, and swapping the button's image from a timer
/// flickers because SwiftUI keeps re-applying its own image. So the label draws the working
/// dots at their dimmest, and this overlay fades full-strength dots in and out on top.
final class MenuBarPulseAnimator {
    static let shared = MenuBarPulseAnimator()

    private weak var appState: AppState?
    private var timer: Timer?
    private var overlay: PulseOverlayView?
    private var layout: Layout?

    /// Everything the overlay's geometry depends on; the overlay is rebuilt when it changes.
    private struct Layout: Equatable {
        let firstWorkingIndex: Int
        let workingDots: Int
        let style: WorkingDotStyle
        let imageWidth: CGFloat
        let buttonSize: CGSize
    }

    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func start(appState: AppState) {
        self.appState = appState
        guard timer == nil else { return }
        // Only keeps the overlay in step with session counts; the fade itself runs in Core Animation.
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.sync()
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func sync() {
        let style = WorkingDotStyle.current()
        guard let appState, appState.workingCount > 0, !Self.reduceMotion,
            let color = style.color,
            let button = Self.statusBarButton()
        else {
            removeOverlay()
            return
        }

        let urgent = appState.needsApprovalCount + appState.waitingCount
        let total = min(urgent + appState.workingCount, MenuBarLabel.maxDots)
        let firstWorking = min(urgent, MenuBarLabel.maxDots)

        let threshold = UserDefaults.standard.object(forKey: "usageRingThreshold") as? Int ?? 50
        let hasRing = appState.usageLimits.map { $0.fiveHour.utilization >= Double(threshold) } ?? false
        let step = MenuBarLabel.dotSize + MenuBarLabel.dotSpacing
        let dotsWidth = CGFloat(total) * step - MenuBarLabel.dotSpacing
        let ringExtra = hasRing ? MenuBarLabel.ringSpacing + MenuBarLabel.ringDiameter : 0

        let newLayout = Layout(
            firstWorkingIndex: firstWorking,
            workingDots: total - firstWorking,
            style: style,
            imageWidth: dotsWidth + ringExtra,
            buttonSize: button.bounds.size
        )
        if newLayout == layout, overlay?.superview === button { return }
        removeOverlay()
        guard newLayout.workingDots > 0 else { return }

        let view = PulseOverlayView(frame: button.bounds)
        view.autoresizingMask = [.width, .height]
        // The button centers its image, so the dots start this far in.
        let originX = (button.bounds.width - newLayout.imageWidth) / 2
        let dotY = (button.bounds.height - MenuBarLabel.dotSize) / 2
        for index in newLayout.firstWorkingIndex..<(newLayout.firstWorkingIndex + newLayout.workingDots) {
            let dot = CALayer()
            dot.frame = CGRect(
                x: originX + CGFloat(index) * step, y: dotY,
                width: MenuBarLabel.dotSize, height: MenuBarLabel.dotSize)
            dot.cornerRadius = MenuBarLabel.dotSize / 2
            dot.backgroundColor = color.cgColor
            view.layer?.addSublayer(dot)
        }

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = MenuBarLabel.pulsePeriod / 2
        fade.autoreverses = true
        fade.repeatCount = .infinity
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        view.layer?.add(fade, forKey: "pulse")

        button.addSubview(view)
        overlay = view
        layout = newLayout
    }

    private func removeOverlay() {
        overlay?.removeFromSuperview()
        overlay = nil
        layout = nil
    }

    /// The button macOS creates for our status item, found through its NSStatusBarWindow.
    private static func statusBarButton() -> NSStatusBarButton? {
        for window in NSApp.windows
        where String(describing: type(of: window)).contains("StatusBar") {
            if let button = findButton(in: window.contentView) { return button }
        }
        return nil
    }

    private static func findButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let button = findButton(in: subview) { return button }
        }
        return nil
    }
}

/// Layer-backed view holding the pulsing dots. Ignores clicks so the status item still opens.
private final class PulseOverlayView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Observes the NSStatusBarWindow's effectiveAppearance via KVO so SwiftUI
/// redraws the menu bar label when the wallpaper-driven tinting changes.
@Observable
final class MenuBarAppearanceObserver: NSObject {
    var isDark: Bool = false
    private var kvoToken: NSKeyValueObservation?
    private weak var observedWindow: NSWindow?

    override init() {
        super.init()
        // Defer so the status bar window exists
        DispatchQueue.main.async { [weak self] in
            self?.attachObserver()
        }
    }

    private func attachObserver() {
        guard
            let window = NSApp.windows.first(where: {
                String(describing: type(of: $0)).contains("StatusBar")
            })
        else {
            debugLog("[MenuBarAppearance] No StatusBarWindow found, will retry")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.attachObserver()
            }
            return
        }

        observedWindow = window
        let currentlyDark =
            window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        isDark = currentlyDark
        debugLog("[MenuBarAppearance] Attached to StatusBarWindow, isDark=\(isDark)")

        kvoToken = window.observe(\.effectiveAppearance, options: [.new]) { [weak self] window, _ in
            let newDark =
                window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            debugLog("[MenuBarAppearance] Appearance changed, isDark=\(newDark)")
            DispatchQueue.main.async {
                self?.isDark = newDark
            }
        }
    }

    deinit {
        kvoToken?.invalidate()
    }
}
