import AppKit

// DMS Foundry 图标（1024×1024）：黑色圆角方块 + 白色双螺旋 + 突变标记
let S = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: S, pixelsHigh: S,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: S, height: S)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let W = CGFloat(S)

// 背景圆角方块
let rect = CGRect(x: 0, y: 0, width: W, height: W)
ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 6, dy: 6),
                   cornerWidth: 228, cornerHeight: 228, transform: nil))
ctx.clip()
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [NSColor(calibratedWhite: 0.12, alpha: 1).cgColor,
                               NSColor(calibratedWhite: 0.015, alpha: 1).cgColor] as CFArray,
                      locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: W), end: CGPoint(x: W, y: 0), options: [])

// 螺旋
func strand(phase: CGFloat, alpha: CGFloat) {
    let p = NSBezierPath()
    p.lineWidth = 52
    p.lineCapStyle = .round
    p.lineJoinStyle = .round
    let n = 260
    for i in 0...n {
        let t = CGFloat(i) / CGFloat(n)
        let y = 176 + t * 672
        let x = W / 2 + 150 * sin(t * .pi * 3.2 + phase)
        if i == 0 { p.move(to: NSPoint(x: x, y: y)) } else { p.line(to: NSPoint(x: x, y: y)) }
    }
    NSColor(calibratedWhite: 1.0, alpha: alpha).setStroke()
    p.stroke()
}
strand(phase: 0, alpha: 1.0)
strand(phase: .pi, alpha: 1.0)

// 碱基连接（细线，避免糊成一团）
NSColor(calibratedWhite: 1.0, alpha: 0.45).setStroke()
for k in 0..<6 {
    let t = 0.13 + CGFloat(k) * 0.15
    let y = 176 + t * 672
    let x1 = W / 2 + 150 * sin(t * .pi * 3.2)
    let x2 = W / 2 + 150 * sin(t * .pi * 3.2 + .pi)
    let p = NSBezierPath()
    p.lineWidth = 18
    p.lineCapStyle = .round
    p.move(to: NSPoint(x: min(x1, x2), y: y))
    p.line(to: NSPoint(x: max(x1, x2), y: y))
    p.stroke()
}

// 突变标记
let outer = NSBezierPath(ovalIn: NSRect(x: W/2 - 54, y: W/2 - 54, width: 108, height: 108))
NSColor(calibratedWhite: 0.015, alpha: 1).setFill(); outer.fill()
let inner = NSBezierPath(ovalIn: NSRect(x: W/2 - 36, y: W/2 - 36, width: 72, height: 72))
NSColor.white.setFill(); inner.fill()

NSGraphicsContext.restoreGraphicsState()
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: "tools/icon-1024.png"))
print("ok \(rep.pixelsWide)x\(rep.pixelsHigh)")
