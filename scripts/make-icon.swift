import AppKit
import Foundation

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let colors: [NSColor] = [NSColor(srgbRed: 0.98, green: 0.35, blue: 0.62, alpha: 1), .systemOrange, NSColor(srgbRed: 1, green: 0.83, blue: 0.30, alpha: 1), NSColor(srgbRed: 0.32, green: 0.83, blue: 0.70, alpha: 1), .systemCyan, NSColor(srgbRed: 0.61, green: 0.40, blue: 0.93, alpha: 1)]
func render(_ pixels: Int, at path: URL) throws {
    // Explicit pixel backing avoids lockFocus doubling dimensions on Retina Macs.
    guard let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw NSError(domain: "Icon", code: 1) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    let scale = CGFloat(pixels) / 1024
    ctx.scaleBy(x: scale, y: scale)
    let rect = NSRect(x: 32, y: 32, width: 960, height: 960)
    let bg = NSBezierPath(roundedRect: rect, xRadius: 220, yRadius: 220)
    NSGradient(starting: NSColor(srgbRed: 1, green: 0.85, blue: 0.93, alpha: 1), ending: NSColor(srgbRed: 0.80, green: 0.88, blue: 1, alpha: 1))?.draw(in: bg, angle: 60)
    for (index, color) in colors.enumerated() {
        let rainbow = NSBezierPath()
        rainbow.appendArc(withCenter: NSPoint(x: 512, y: 415), radius: CGFloat(335 - index * 32), startAngle: 12, endAngle: 168)
        rainbow.lineWidth = 36
        rainbow.lineCapStyle = .round
        color.setStroke()
        rainbow.stroke()
    }
    NSColor.white.setFill()
    for cloud in [NSRect(x: 132, y: 330, width: 280, height: 155), NSRect(x: 170, y: 370, width: 155, height: 170), NSRect(x: 630, y: 330, width: 270, height: 155), NSRect(x: 680, y: 380, width: 155, height: 170)] {
        NSBezierPath(ovalIn: cloud).fill()
    }
    ctx.saveGState()
    ctx.translateBy(x: 512, y: 420)
    ctx.rotate(by: -.pi / 6)
    let purple = NSColor(srgbRed: 0.37, green: 0.17, blue: 0.67, alpha: 1)
    purple.setFill()
    NSBezierPath(roundedRect: NSRect(x: -40, y: -220, width: 80, height: 270), xRadius: 30, yRadius: 30).fill()
    NSBezierPath(roundedRect: NSRect(x: 5, y: -190, width: 115, height: 58), xRadius: 18, yRadius: 18).fill()
    NSBezierPath(roundedRect: NSRect(x: 5, y: -100, width: 90, height: 55), xRadius: 18, yRadius: 18).fill()
    NSBezierPath(ovalIn: NSRect(x: -123, y: -20, width: 246, height: 246)).fill()
    NSColor(srgbRed: 1, green: 0.94, blue: 0.66, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: -77, y: 26, width: 154, height: 154)).fill()
    purple.setFill()
    NSBezierPath(ovalIn: NSRect(x: -40, y: 96, width: 18, height: 24)).fill()
    NSBezierPath(ovalIn: NSRect(x: 22, y: 96, width: 18, height: 24)).fill()
    let smile = NSBezierPath()
    smile.move(to: NSPoint(x: -25, y: 79))
    smile.curve(to: NSPoint(x: 25, y: 79), controlPoint1: NSPoint(x: -13, y: 59), controlPoint2: NSPoint(x: 13, y: 59))
    smile.lineWidth = 8; smile.lineCapStyle = .round; purple.setStroke(); smile.stroke()
    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    guard let rendered = ctx.makeImage(),
          let data = NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:])
    else { throw NSError(domain: "Icon", code: 2) }
    try data.write(to: path)
}
var entries: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(size)x\(size)@\(scale)x.png"
        try render(size * scale, at: destination.appendingPathComponent(name))
        entries.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": entries, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: destination.appendingPathComponent("Contents.json"))

// Bundle an explicit ICNS with every size, including Apple's required 512pt @2x.
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("Tuck-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }
for entry in entries {
    let name = entry["filename"]!
    try FileManager.default.copyItem(at: destination.appendingPathComponent(name),
                                    to: iconset.appendingPathComponent(name.replacingOccurrences(of: "@1x", with: "")))
}
let command = Process()
command.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
command.arguments = ["-c", "icns", iconset.path, "-o", destination.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Tuck.icns").path]
try command.run()
command.waitUntilExit()
guard command.terminationStatus == 0 else { throw NSError(domain: "Icon", code: 3) }
