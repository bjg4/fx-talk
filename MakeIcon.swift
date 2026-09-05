import AppKit

let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let transform = NSAffineTransform(); transform.scale(by: CGFloat(pixels) / 1024); transform.concat()
        NSColor(calibratedRed: 0.95, green: 0.31, blue: 0.08, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 30, y: 30, width: 964, height: 964), xRadius: 220, yRadius: 220).fill()
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 332, y: 335, width: 360, height: 490), xRadius: 180, yRadius: 180).fill()
        NSColor(calibratedWhite: 0.13, alpha: 1).setStroke()
        let outline = NSBezierPath(); outline.lineWidth = 44; outline.lineCapStyle = .round
        outline.move(to: NSPoint(x: 248, y: 492))
        outline.curve(to: NSPoint(x: 776, y: 492), controlPoint1: NSPoint(x: 248, y: 195), controlPoint2: NSPoint(x: 776, y: 195))
        outline.stroke()
        let stand = NSBezierPath(); stand.lineWidth = 44; stand.lineCapStyle = .round
        stand.move(to: NSPoint(x: 512, y: 265)); stand.line(to: NSPoint(x: 512, y: 184))
        stand.move(to: NSPoint(x: 403, y: 182)); stand.line(to: NSPoint(x: 621, y: 182)); stand.stroke()
        for y in [530, 620, 710] {
            let line = NSBezierPath(); line.lineWidth = 27; line.lineCapStyle = .round
            line.move(to: NSPoint(x: 432, y: y)); line.line(to: NSPoint(x: 592, y: y)); line.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let path = "\(destination)/icon_\(points)x\(points)\(suffix).png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    }
}
