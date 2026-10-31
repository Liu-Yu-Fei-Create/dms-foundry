import SwiftUI

/// position × aa 的效应热图：灰阶（深=正效应，浅=负效应）。
struct MissenseHeatmap: View {
    let effects: [String: Double]      // "position:aa" -> effect
    let positions: [Int]
    let aa: [String]

    private let cellW: CGFloat = 20
    private let cellH: CGFloat = 13

    var body: some View {
        let maxAbs = max(0.5, effects.values.map { abs($0) }.max() ?? 1)
        ScrollView([.horizontal, .vertical]) {
            Canvas { ctx, size in
                // 列头
                for (c, a) in aa.enumerated() {
                    let rect = CGRect(x: 44 + CGFloat(c) * cellW, y: 0, width: cellW, height: 16)
                    ctx.draw(Text(a).font(.system(size: 8, design: .monospaced)).foregroundColor(Theme.muted),
                             at: CGPoint(x: rect.midX, y: rect.midY))
                }
                for (r, p) in positions.enumerated() {
                    let y = 18 + CGFloat(r) * cellH
                    let label = CGRect(x: 0, y: y, width: 40, height: cellH)
                    ctx.draw(Text("\(p)").font(.system(size: 8, design: .monospaced)).foregroundColor(Theme.faint),
                             at: CGPoint(x: label.midX + 4, y: y + cellH / 2))
                    for (c, a) in aa.enumerated() {
                        let key = "\(p):\(a)"
                        let x = 44 + CGFloat(c) * cellW
                        let rect = CGRect(x: x, y: y, width: cellW - 1, height: cellH - 1)
                        if let e = effects[key] {
                            let t = min(abs(e) / maxAbs, 1)
                            let v = e >= 0 ? (1 - 0.75 * t) : (1 - 0.25 * t)
                            ctx.fill(Path(rect), with: .color(Color(white: v)))
                        } else {
                            ctx.fill(Path(rect), with: .color(Theme.zebra))
                        }
                    }
                }
            }
            .frame(width: 44 + CGFloat(aa.count) * cellW,
                   height: 18 + CGFloat(positions.count) * cellH)
        }
        .frame(maxHeight: 320)
    }
}
