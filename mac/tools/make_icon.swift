import AppKit

// DMS Foundry 图标：纯黑圆角底 + 规整的 DMS 字标（系统 SF 字体，无手绘变形）
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

// 圆角黑底
ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: W, height: W).insetBy(dx: 6, dy: 6),
                   cornerWidth: 228, cornerHeight: 228, transform: nil))
ctx.clip()
NSColor(calibratedWhite: 0.045, alpha: 1).setFill()
ctx.fill(CGRect(x: 0, y: 0, width: W, height: W))

// 字标：SF 系统字体 Heavy，负字距收紧
let font = NSFont.systemFont(ofSize: 380, weight: .heavy)
let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white,
    .kern: -6,
]
let text = NSAttributedString(string: "DMS", attributes: attrs)
let bounds = text.boundingRect(with: NSSize(width: 2000, height: 1000),
                               options: [.usesLineFragmentOrigin, .usesFontLeading])
let drawAt = NSPoint(x: (W - bounds.width) / 2,
                     y: (W - bounds.height) / 2 - bounds.origin.y + 10)
text.draw(at: drawAt)

NSGraphicsContext.restoreGraphicsState()
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: "tools/icon-1024.png"))
print("ok")
