import SwiftUI
import DMSEngine

struct SequenceTrackView: View {
    let plasmid: Plasmid
    let targetID: UUID?
    @Binding var selectedID: UUID?

    @State private var lanes: [UUID: Int] = [:]

    private let leftPad: CGFloat = 18
    private let rightPad: CGFloat = 18
    private let laneHeight: CGFloat = 26

    var body: some View {
        GeometryReader { geo in
            let w = max(10, geo.size.width - leftPad - rightPad)
            Canvas { ctx, size in
                draw(ctx: &ctx, size: size, width: w)
            }
            .gesture(SpatialTapGesture().onEnded { v in
                select(at: v.location.x, width: w)
            })
        }
        .background(Theme.paper)
        .overlay(Rectangle().stroke(Theme.hairline, lineWidth: 1))
    }

    private func x(for pos: Int, width: CGFloat) -> CGFloat {
        let n = max(1, plasmid.sequence.count)
        return leftPad + CGFloat(pos) / CGFloat(n) * width
    }

    private func lane(for f: Feature) -> Int {
        if let l = lanes[f.id] { return l }
        return 0
    }

    private func assignLanes() {
        var used: [Int: [(Int, Int)]] = [:]
        for f in plasmid.features {
            var lane = 0
            while used[lane, default: []].contains(where: { !($0.1 <= f.start || $0.0 >= f.end) }) { lane += 1 }
            used[lane, default: []].append((f.start, f.end))
            lanes[f.id] = min(lane, 2)
        }
    }

    private func draw(ctx: inout GraphicsContext, size: CGSize, width: CGFloat) {
        if lanes.isEmpty { assignLanes() }
        let baseY = size.height * 0.62
        // 基线
        var line = Path()
        line.move(to: CGPoint(x: leftPad, y: baseY))
        line.addLine(to: CGPoint(x: leftPad + width, y: baseY))
        ctx.stroke(line, with: .color(.secondary.opacity(0.6)), lineWidth: 1)

        // 刻度
        let n = max(1, plasmid.sequence.count)
        let step = tickStep(for: n)
        var p = 0
        while p <= n {
            let px = x(for: p, width: width)
            var tick = Path()
            tick.move(to: CGPoint(x: px, y: baseY - 3))
            tick.addLine(to: CGPoint(x: px, y: baseY + 3))
            ctx.stroke(tick, with: .color(.secondary.opacity(0.5)), lineWidth: 1)
            if p % (step * 2) == 0 {
                ctx.draw(Text("\(p)").font(.system(size: 8)).foregroundColor(.secondary),
                         at: CGPoint(x: px, y: baseY + 12))
            }
            p += step
        }

        // 特征
        for f in plasmid.features {
            let laneY = 12 + CGFloat(lane(for: f)) * laneHeight
            let x0 = x(for: f.start, width: width)
            let x1 = x(for: max(f.end, f.start + 1), width: width)
            let rect = CGRect(x: x0, y: laneY, width: max(2, x1 - x0), height: 16)
            let color = color(for: f.type)
            let isTarget = f.id == targetID
            let isSelected = f.id == selectedID
            var path = Path(roundedRect: rect, cornerRadius: 2)
            if f.strand == .reverse, rect.width > 8 {
                var p = Path()
                p.move(to: CGPoint(x: rect.minX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.minX + 6, y: rect.midY))
                p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                p.closeSubpath()
                path.addPath(p)
            }
            ctx.fill(path, with: .color(color.opacity(isTarget ? 0.9 : 0.55)))
            ctx.stroke(path, with: .color(isSelected ? .primary : color.opacity(0.9)),
                       lineWidth: isSelected ? 2 : 1)
            if isTarget {
                var bar = Path()
                bar.move(to: CGPoint(x: rect.minX, y: rect.maxY + 3))
                bar.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY + 3))
                ctx.stroke(bar, with: .color(.primary), lineWidth: 2)
            }
            if rect.width > 44 {
                ctx.draw(Text(f.label).font(.system(size: 9)).foregroundColor(.white),
                         at: CGPoint(x: rect.midX, y: rect.midY))
            }
        }
    }

    private func tickStep(for n: Int) -> Int {
        let candidates = [50, 100, 200, 500, 1000, 2000, 5000, 10000]
        for c in candidates where n / c <= 14 { return c }
        return 20000
    }

    private func color(for type: FeatureType) -> Color {
        switch type {
        case .promoter: return Color(red: 0.16, green: 0.42, blue: 0.40)
        case .terminator: return Color(red: 0.52, green: 0.34, blue: 0.16)
        case .cds: return Color(red: 0.16, green: 0.29, blue: 0.48)
        case .origin: return Color(red: 0.42, green: 0.42, blue: 0.42)
        case .resistance: return Color(red: 0.48, green: 0.16, blue: 0.22)
        case .other: return Color(red: 0.58, green: 0.58, blue: 0.58)
        }
    }

    private func select(at px: CGFloat, width: CGFloat) {
        let n = max(1, plasmid.sequence.count)
        let pos = Int(max(0, min(1, (px - leftPad) / width)) * CGFloat(n))
        if let f = plasmid.features.first(where: { pos >= $0.start && pos < $0.end }) {
            selectedID = f.id
        } else {
            selectedID = nil
        }
    }
}
