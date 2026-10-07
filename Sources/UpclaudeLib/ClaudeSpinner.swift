import AppKit

/// Claude Code's asterisk, as the menu bar draws sessions that don't need a decision:
/// an orange spinner while one is working, and a grey asterisk once it is your turn.
public enum ClaudeSpinner {
    /// Claude orange, #D97757
    public static let color = NSColor(srgbRed: 0.851, green: 0.467, blue: 0.341, alpha: 1)

    /// Glyphs the spinner steps through, smallest to fullest.
    static let glyphs = ["·", "✢", "✳", "✶", "✻", "✽"]

    /// Glyph for an asterisk that isn't spinning: a session waiting on you, or a working one
    /// when Reduce Motion is on.
    public static let restingGlyph = "✻"

    /// Seconds each spinner frame is shown: Claude Code's own step.
    public static let frameInterval: TimeInterval = 0.12

    /// Seconds the spinner rests on its smallest and fullest glyphs before turning around.
    /// Claude Code lingers at both ends; without the rest the same step looks hurried.
    public static let endHold: TimeInterval = 0.36

    /// Side of the square each glyph is drawn in.
    public static let side: CGFloat = 12

    /// One full spinner cycle: out through the glyphs and back, with how long each frame is
    /// shown. The first frame and the fullest one are held longer.
    public static func cycle(scale: CGFloat) -> (frames: [CGImage], durations: [TimeInterval]) {
        let out = glyphs.compactMap { glyphImage($0, color: color, scale: scale) }
        guard out.count == glyphs.count else { return ([], []) }
        // Out to the fullest glyph, then back down, stopping short of repeating the first.
        let frames = out + out.dropFirst().dropLast().reversed()
        let durations = frames.indices.map { index in
            index == 0 || index == out.count - 1 ? endHold : frameInterval
        }
        return (frames, durations)
    }

    /// One glyph centered in a `side` square, at the given backing scale.
    public static func glyphImage(_ glyph: String, color: NSColor, scale: CGFloat) -> CGImage? {
        let pixels = Int((side * scale).rounded())
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: rep)?.cgContext
        else { return nil }
        context.scaleBy(x: scale, y: scale)

        let text = NSAttributedString(
            string: glyph,
            attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .bold), .foregroundColor: color])
        let line = CTLineCreateWithAttributedString(text)
        // Center on the glyph's ink, not its line box, so the frames don't jump around.
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        context.textPosition = CGPoint(
            x: (side - ink.width) / 2 - ink.minX, y: (side - ink.height) / 2 - ink.minY)
        CTLineDraw(line, context)
        return rep.cgImage
    }
}
