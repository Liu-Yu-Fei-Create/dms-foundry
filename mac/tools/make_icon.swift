import AppKit

// DMS Foundry 图标：纯黑圆角底 + 几何化 DMS 字标
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

// 圆角黑底（纯色，不用渐变）
ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: W, height: W).insetBy(dx: 6, dy: 6),
                   cornerWidth: 228, cornerHeight: 228, transform: nil))
ctx.clip()
NSColor(calibratedWhite: 0.045, alpha: 1).setFill()
ctx.fill(CGRect(x: 0, y: 0, width: W, height: W))

NSColor.white.setStroke()

// 字标整体放大 14%，四周留白更接近 macOS 图标比例
ctx.saveGState()
ctx.translateBy(x: 512, y: 512)
ctx.scaleBy(x: 1.02, y: 1.22)
ctx.concatenate(CGAffineTransform(a: 1, b: 0, c: -0.10, d: 1, tx: 0, ty: 0))
ctx.translateBy(x: -512, y: -512)
let weight: CGFloat = 74

func stroke(_ p: NSBezierPath) {
    p.lineWidth = weight
    p.lineCapStyle = .round
    p.lineJoinStyle = .round
    p.stroke()
}

// D：竖 + 右半圆
let d = NSBezierPath()
d.move(to: NSPoint(x: 148, y: 372))
d.line(to: NSPoint(x: 148, y: 668))
d.curve(to: NSPoint(x: 150, y: 350),
        controlPoint1: NSPoint(x: 400, y: 690),
        controlPoint2: NSPoint(x: 400, y: 350))
stroke(d)

// M：折线
let m = NSBezierPath()
m.move(to: NSPoint(x: 410, y: 372))
m.line(to: NSPoint(x: 410, y: 668))
m.line(to: NSPoint(x: 520, y: 470))
m.line(to: NSPoint(x: 630, y: 668))
m.line(to: NSPoint(x: 630, y: 372))
stroke(m)

// S：两段贝塞尔
let s = NSBezierPath()
s.move(to: NSPoint(x: 878, y: 640))
s.curve(to: NSPoint(x: 726, y: 596),
        controlPoint1: NSPoint(x: 878, y: 700),
        controlPoint2: NSPoint(x: 760, y: 700))
s.curve(to: NSPoint(x: 846, y: 452),
        controlPoint1: NSPoint(x: 690, y: 500),
        controlPoint2: NSPoint(x: 846, y: 500))
s.curve(to: NSPoint(x: 700, y: 400),
        controlPoint1: NSPoint(x: 846, y: 404),
        controlPoint2: NSPoint(x: 760, y: 372))
stroke(s)

ctx.restoreGState()
NSGraphicsContext.restoreGraphicsState()
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: "tools/icon-1024.png"))
print("ok")
