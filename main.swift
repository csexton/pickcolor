// pickcolor: show the system color loupe, copy the clicked pixel's color to the clipboard.
// While hovering, a label next to the loupe shows the color under the cursor (needs Screen Recording access).
// Exit 0 when a color was picked, 1 when cancelled (Esc).
import AppKit
import ScreenCaptureKit

enum Format: String, CaseIterable {
    case hex, css, rgb, hsl
}

let usage = """
usage: pickcolor [-f hex|css|rgb|hsl] [--display]
  Click a pixel to copy its color to the clipboard and print it. Esc cancels (exit 1).
  -f, --format  hex  B896DB (default)
                css  #B896DB
                rgb  rgb(184, 150, 219)
                hsl  hsl(270, 49%, 72%)
  --display     use the display's native color space instead of sRGB
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("pickcolor: \(message)\n\(usage)\n".data(using: .utf8)!)
    exit(2)
}

var format = Format.hex
var useDisplaySpace = false
var args = CommandLine.arguments.dropFirst()
while let arg = args.popFirst() {
    switch arg {
    case "-h", "--help":
        print(usage)
        exit(0)
    case "--display":
        useDisplaySpace = true
    case "-f", "--format":
        guard let value = args.popFirst() else { fail("\(arg) needs a value") }
        guard let f = Format(rawValue: value.lowercased()) else { fail("unknown format '\(value)'") }
        format = f
    case _ where arg.hasPrefix("--format="):
        let value = String(arg.dropFirst("--format=".count))
        guard let f = Format(rawValue: value.lowercased()) else { fail("unknown format '\(value)'") }
        format = f
    default:
        fail("unknown option '\(arg)'")
    }
}

func formatted(_ color: NSColor) -> String? {
    let rgb = useDisplaySpace
        ? (color.type == .componentBased && color.colorSpace.colorSpaceModel == .rgb ? color : color.usingColorSpace(.deviceRGB))
        : color.usingColorSpace(.sRGB)
    guard let rgb else { return nil }
    let (r, g, b) = (min(max(rgb.redComponent, 0), 1), min(max(rgb.greenComponent, 0), 1), min(max(rgb.blueComponent, 0), 1))
    func byte(_ v: CGFloat) -> Int { Int((v * 255).rounded()) }

    switch format {
    case .hex:
        return String(format: "%02X%02X%02X", byte(r), byte(g), byte(b))
    case .css:
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    case .rgb:
        return "rgb(\(byte(r)), \(byte(g)), \(byte(b)))"
    case .hsl:
        let maxC = max(r, g, b), minC = min(r, g, b), delta = maxC - minC
        let l = (maxC + minC) / 2
        let s = delta == 0 ? 0 : delta / (1 - abs(2 * l - 1))
        var h: CGFloat = 0
        if delta != 0 {
            switch maxC {
            case r: h = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            case g: h = 60 * ((b - r) / delta + 2)
            default: h = 60 * ((r - g) / delta + 4)
            }
        }
        let hue = (Int(h.rounded()) % 360 + 360) % 360
        return "hsl(\(hue), \(Int((s * 100).rounded()))%, \(Int((l * 100).rounded()))%)"
    }
}

/// Floating label beside the system loupe showing the color of the pixel under the cursor.
@MainActor
final class ColorOverlay {
    static let loupeRadius: CGFloat = 61 // the system loupe is 122pt across, centered on the cursor
    static let gap: CGFloat = 8

    private let panel: NSPanel
    private let swatch = NSView()
    private let label = NSTextField(labelWithString: "      ")
    private var filterContent: SCShareableContent?
    private var captureInFlight = false
    private var lastLocation = CGPoint(x: -1, y: -1)
    private var timer: Timer?

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 112, height: 30),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.sharingType = .none // keep the label out of our own screen captures
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let background = NSVisualEffectView(frame: panel.contentLayoutRect)
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.masksToBounds = true

        swatch.frame = NSRect(x: 9, y: 8, width: 14, height: 14)
        swatch.wantsLayer = true
        swatch.layer?.cornerRadius = 3
        swatch.layer?.borderWidth = 1
        swatch.layer?.borderColor = NSColor.white.withAlphaComponent(0.6).cgColor

        label.font = .monospacedSystemFont(ofSize: 15, weight: .medium)
        label.textColor = .labelColor
        label.frame = NSRect(x: 30, y: 5, width: 76, height: 20)

        background.addSubview(swatch)
        background.addSubview(label)
        panel.contentView = background
    }

    func start() {
        guard CGPreflightScreenCaptureAccess() else { return }
        Task { await loadShareableContent() }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { _ in
            MainActor.assumeIsolated { self.tick() }
        }
    }

    /// Fetch windows/apps so captures can exclude the loupe; the ColorSampler process may take a moment to appear.
    private func loadShareableContent() async {
        for _ in 0..<10 {
            let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            filterContent = content
            if content?.applications.contains(where: { $0.applicationName == "ColorSampler" }) == true { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func tick() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) else { return }
        position(at: mouse, on: screen)
        guard mouse != lastLocation, !captureInFlight, let content = filterContent else { return }
        lastLocation = mouse
        captureInFlight = true
        Task {
            defer { captureInFlight = false }
            guard let color = await sample(at: mouse, on: screen, content: content), let text = formatted(color) else { return }
            if text.count != label.stringValue.count { resize(for: text) }
            label.stringValue = text
            swatch.layer?.backgroundColor = color.cgColor
            if !panel.isVisible { panel.orderFrontRegardless() }
        }
    }

    /// Fit the panel to the text; monospaced, so width only changes with character count.
    private func resize(for text: String) {
        label.stringValue = text
        label.sizeToFit()
        label.setFrameOrigin(NSPoint(x: 30, y: 5))
        panel.setContentSize(NSSize(width: label.frame.maxX + 10, height: 30))
    }

    private func position(at mouse: CGPoint, on screen: NSScreen) {
        let size = panel.frame.size
        var x = mouse.x + Self.loupeRadius + Self.gap
        if x + size.width > screen.frame.maxX { x = mouse.x - Self.loupeRadius - Self.gap - size.width }
        let y = min(max(mouse.y - size.height / 2, screen.frame.minY), screen.frame.maxY - size.height)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func sample(at mouse: CGPoint, on screen: NSScreen, content: SCShareableContent) async -> NSColor? {
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return nil }
        let excluded = content.applications.filter {
            $0.applicationName == "ColorSampler" || $0.processID == getpid()
        }
        let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])

        let config = SCStreamConfiguration()
        let localX = (mouse.x - screen.frame.minX).rounded(.down)
        let localY = min((screen.frame.maxY - mouse.y).rounded(.down), screen.frame.height - 1)
        config.sourceRect = CGRect(x: localX, y: localY, width: 1, height: 1)
        let scale = Int(screen.backingScaleFactor)
        config.width = scale
        config.height = scale
        config.showsCursor = false

        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else { return nil }
        return NSBitmapImageRep(cgImage: image).colorAt(x: 0, y: 0)
    }
}

// The loupe grabs the mouse, so the Screen Recording prompt can't be clicked while picking.
// The first time this copy runs without access, ask for it and quit instead of picking.
// Later runs without access pick colors without the live label.
let askedKey = "askedForScreenCapture:\(Bundle.main.executablePath ?? CommandLine.arguments[0])"
if !CGPreflightScreenCaptureAccess() && !UserDefaults.standard.bool(forKey: askedKey) {
    UserDefaults.standard.set(true, forKey: askedKey)
    CGRequestScreenCaptureAccess()
    FileHandle.standardError.write("pickcolor: allow Screen Recording in System Settings, then run pickcolor again\n".data(using: .utf8)!)
    exit(1)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
DispatchQueue.main.async {
    let overlay = ColorOverlay()
    app.activate(ignoringOtherApps: true)
    NSColorSampler().show { color in
        guard let color, let text = formatted(color) else { exit(1) }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        print(text)
        exit(0)
    }
    overlay.start()
}

app.run()
