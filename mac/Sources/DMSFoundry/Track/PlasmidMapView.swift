import SwiftUI
import DMSEngine

/// 环形质粒图：特征画成弧段，支持点选；目标区段加粗并带边界刻度。
struct PlasmidMapView: View {
    let plasmid: Plasmid
    let targetID: UUID?
    @Binding var selectedID: UUID?

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                draw(ctx: &ctx, size: size)
            }
            .gesture(SpatialTapGesture().onEnded { v in
                select(at: v.location, size: geo.size)
            })
        }
        .background(Theme.paper)
        .overlay(Rectangle().stroke(Theme.hairline, lineWidth: 1))
    }

    private func draw(ctx: inout GraphicsContext, size: CGSize) {
        let n = max(1, plasmid.sequence.count)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = max(20, min(size.width, size.height) / 2 - 56)

        // 外圈
        var ring = Path()
        ring.addArc(center: center, radius: radius, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
        ctx.stroke(ring, with: .color(Theme.hairlineStrong), lineWidth: 1)

        // 刻度
        let step = tickStep(for: n)
        var p = 0
        while p <= n {
            let ang = angle(for: p, n: n)
            let major = p % (step * 2) == 0
            var tick = Path()
            tick.move(to: point(center: center, radius: radius - (major ? 7 : 3), degrees: ang))
            tick.addLine(to: point(center: center, radius: radius + (major ? 6 : 3), degrees: ang))
            ctx.stroke(tick, with: .color(major ? Theme.ink2 : Theme.hairlineStrong), lineWidth: 1)
            if major && p > 0 {
                let pos = point(center: center, radius: radius + 16, degrees: ang)
                ctx.draw(Text("\(p)").font(.system(size: 8.5, design: .monospaced))
                            .foregroundColor(Theme.faint), at: pos)
            }
            p += step
        }

        // 目标区段扇形
        if let target = plasmid.features.first(where: { $0.id == targetID }) {
            var a0 = angle(for: target.start, n: n)
            var a1 = angle(for: target.end, n: n)
            if a1 < a0 { a1 += 360 }
            var wedge = Path()
            wedge.move(to: center)
            wedge.addArc(center: center, radius: radius - 14, startAngle: .degrees(a0), endAngle: .degrees(a1), clockwise: false)
            wedge.closeSubpath()
            ctx.fill(wedge, with: .color(Theme.wedge))
        }

        // 特征弧
        for f in plasmid.features {
            let isTarget = f.id == targetID
            let isSelected = f.id == selectedID
            let color = color(for: f.type)
            var a0 = angle(for: f.start, n: n)
            var a1 = angle(for: f.end, n: n)
            if a1 < a0 { a1 += 360 }
            let r = radius - (isTarget ? 12 : 6)
            var arc = Path()
            arc.addArc(center: center, radius: r, startAngle: .degrees(a0), endAngle: .degrees(a1), clockwise: false)
            ctx.stroke(arc, with: .color(color.opacity(isTarget ? 0.95 : 0.62)),
                       lineWidth: isTarget ? 11 : (isSelected ? 8 : 5.5))
            if isSelected && !isTarget {
                ctx.stroke(arc, with: .color(Theme.ink), lineWidth: 1.5)
            }
            if isTarget {
                for edge in [a0, a1] {
                    var line = Path()
                    line.move(to: point(center: center, radius: radius - 24, degrees: edge))
                    line.addLine(to: point(center: center, radius: radius + 3, degrees: edge))
                    ctx.stroke(line, with: .color(Theme.ink), lineWidth: 2)
                }
            }
            // 箭头
            let edge = f.strand == .forward ? a1 : a0
            let dir = f.strand == .forward ? 1.0 : -1.0
            var head = Path()
            head.move(to: point(center: center, radius: r, degrees: edge))
            head.addLine(to: point(center: center, radius: r + 5 * dir, degrees: edge - 1.5 * dir))
            head.addLine(to: point(center: center, radius: r + 5 * dir, degrees: edge + 1.5 * dir))
            head.closeSubpath()
            ctx.fill(head, with: .color(color.opacity(0.9)))
        }

        // 标签：按角度排序，靠得太近就换一档半径
        struct Slot { var feature: Feature; var mid: Double; var r: CGFloat }
        var slots: [Slot] = plasmid.features.compactMap { f in
            var a0 = angle(for: f.start, n: n)
            var a1 = angle(for: f.end, n: n)
            if a1 < a0 { a1 += 360 }
            guard a1 - a0 > 6 else { return nil }
            return Slot(feature: f, mid: (a0 + a1) / 2, r: radius + 26)
        }.sorted { $0.mid < $1.mid }

        var lastMid = -999.0
        var lastR = radius + 26
        for idx in slots.indices {
            let mid = slots[idx].mid
            var r = radius + 26
            if mid - lastMid < 11 { r = (abs(lastR - (radius + 26)) < 1) ? radius + 42 : radius + 26 }
            slots[idx].r = r
            lastMid = mid; lastR = r

            let anchor = point(center: center, radius: radius - 2, degrees: mid)
            let labelPos = point(center: center, radius: r, degrees: mid)
            var leader = Path()
            leader.move(to: anchor)
            leader.addLine(to: point(center: center, radius: r - 8, degrees: mid))
            ctx.stroke(leader, with: .color(Theme.hairlineStrong), lineWidth: 0.8)
            ctx.draw(Text(slots[idx].feature.label)
                        .font(.system(size: 9.5))
                        .foregroundColor(slots[idx].feature.id == targetID ? Theme.ink : Theme.ink2),
                     at: labelPos)
        }

        // 中心信息
        let name = plasmid.name.count > 18 ? String(plasmid.name.prefix(17)) + "…" : plasmid.name
        ctx.draw(Text(name).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.ink),
                 at: CGPoint(x: center.x, y: center.y - 18))
        ctx.draw(Text("\(n) bp").font(.system(size: 11, design: .monospaced)).foregroundColor(Theme.ink2),
                 at: CGPoint(x: center.x, y: center.y + 1))
        ctx.draw(Text(plasmid.topology == .circular ? L("环形") : L("线性"))
                    .font(.system(size: 9)).foregroundColor(Theme.faint),
                 at: CGPoint(x: center.x, y: center.y + 17))
    }

    private func angle(for pos: Int, n: Int) -> Double {
        Double(pos) / Double(n) * 360.0 - 90.0
    }

    private func point(center: CGPoint, radius: CGFloat, degrees: Double) -> CGPoint {
        let r = degrees * Double.pi / 180
        return CGPoint(x: center.x + radius * CGFloat(cos(r)),
                       y: center.y + radius * CGFloat(sin(r)))
    }

    private func tickStep(for n: Int) -> Int {
        for c in [50, 100, 200, 500, 1000, 2000, 5000, 10000] where n / c <= 14 { return c }
        return 20000
    }

    private func color(for type: FeatureType) -> Color {
        switch type {
        case .promoter: return Theme.featPromoter
        case .terminator: return Theme.featTerminator
        case .cds: return Theme.featCDS
        case .origin: return Theme.featOrigin
        case .resistance: return Theme.featResistance
        case .other: return Theme.featOther
        }
    }

    private func select(at location: CGPoint, size: CGSize) {
        let n = max(1, plasmid.sequence.count)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dx = location.x - center.x, dy = location.y - center.y
        guard dx != 0 || dy != 0 else { return }
        var deg = atan2(Double(dy), Double(dx)) * 180 / .pi + 90
        if deg < 0 { deg += 360 }
        if deg > 360 { deg -= 360 }
        let pos = Int(deg / 360 * Double(n))
        if let f = plasmid.features.first(where: { pos >= $0.start && pos < $0.end }) {
            selectedID = f.id
        } else {
            selectedID = nil
        }
    }
}
