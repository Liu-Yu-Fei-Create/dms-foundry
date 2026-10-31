import Foundation

/// 跨组联合分析：用组内 WT 对照的 fold-change 做基线归一，再合并成一个蛋白层面的数据集。
public enum JointAnalysis {

    public struct GroupView: Sendable {
        public var group: String
        public var effects: [VariantEffect]
        public var wtBaseline: Double
        public var wtCount: Int
    }

    /// 组内 WT 对照（mut == wt 的变体）的平均 effect 作为基线；返回平移后的效应。
    public static func normalizeWt(_ effects: [VariantEffect], wtIDs: Set<String>) -> (rows: [VariantEffect], baseline: Double, wtCount: Int) {
        let wt = effects.filter { wtIDs.contains($0.variant) && $0.effect.isFinite }
        guard !wt.isEmpty else { return (effects, 0, 0) }
        let baseline = wt.map(\.effect).reduce(0, +) / Double(wt.count)
        let shifted = effects.map { e -> VariantEffect in
            var x = e; x.effect -= baseline; x.ciLow -= baseline; x.ciHigh -= baseline
            return x
        }
        return (shifted, baseline, wt.count)
    }

    /// 逆方差加权合并同一变体在多个分组里的归一后效应。
    public static func merge(_ groups: [String: [VariantEffect]],
                             synonymous: Set<String> = []) -> [VariantEffect] {
        var byVariant: [String: [(VariantEffect, String)]] = [:]
        for (g, rows) in groups {
            for r in rows where r.se.isFinite && r.effect.isFinite {
                byVariant[r.variant, default: []].append((r, g))
            }
        }
        var out: [VariantEffect] = []
        for (v, items) in byVariant {
            let ws = items.map { 1.0 / max($0.0.se * $0.0.se, 1e-9) }
            let sumW = ws.reduce(0, +)
            guard sumW > 0 else { continue }
            let mean = zip(items, ws).map { $0.0.0.effect * $0.1 }.reduce(0, +) / sumW
            let se = sqrt(1 / sumW)
            out.append(VariantEffect(variant: v, effect: mean, se: se,
                                     ciLow: mean - 1.96 * se, ciHigh: mean + 1.96 * se,
                                     z: 0, p: 1, q: 1, flag: "OK", replicates: items.count))
        }
        // 同义变体做 null；不足 3 个时用中位 SE 作为保守尺度
        let nullValues = out.filter { synonymous.contains($0.variant) }.map(\.effect)
        var mu = 0.0, sd = 0.0
        if nullValues.count >= 3 {
            mu = nullValues.reduce(0, +) / Double(nullValues.count)
            let varSum = nullValues.map { pow($0 - mu, 2) }.reduce(0, +) / Double(nullValues.count - 1)
            sd = sqrt(varSum)
        } else {
            let ses = out.map(\.se).filter { $0.isFinite }.sorted()
            sd = ses.isEmpty ? 0 : ses[ses.count / 2]
        }
        for i in out.indices {
            let e = out[i]
            let denom = sd > 0 ? sqrt(e.se * e.se + sd * sd) : e.se
            let z = denom > 0 ? (e.effect - mu) / denom : 0
            let p = 2 * (1 - AnalysisEngine.normalCDF(abs(z)))
            out[i].z = z
            out[i].p = p
        }
        // BH-FDR
        let order = out.indices.sorted { out[$0].p < out[$1].p }
        let m = Double(out.count)
        var prev = 1.0
        for (rank, idx) in order.enumerated().reversed() {
            let q = min(prev, out[idx].p * m / Double(rank + 1))
            out[idx].q = q
            prev = q
        }
        return out.sorted { $0.variant < $1.variant }
    }

    /// 组间相关矩阵：只统计多个分组都测到的变体（Pearson r）。
    public static func correlation(_ groups: [String: [VariantEffect]]) -> (names: [String], matrix: [[Double]]) {
        let names = groups.keys.sorted()
        guard names.count > 1 else { return (names, []) }
        var maps: [String: [String: Double]] = [:]
        for (g, rows) in groups {
            maps[g] = Dictionary(uniqueKeysWithValues: rows.map { ($0.variant, $0.effect) })
        }
        var matrix = Array(repeating: Array(repeating: 0.0, count: names.count), count: names.count)
        for i in names.indices {
            matrix[i][i] = 1
            for j in names.indices where j > i {
                let a = maps[names[i]] ?? [:], b = maps[names[j]] ?? [:]
                let shared = Set(a.keys).intersection(b.keys)
                let r = pearson(shared.map { a[$0]! }, shared.map { b[$0]! })
                matrix[i][j] = r; matrix[j][i] = r
            }
        }
        return (names, matrix)
    }

    static func pearson(_ x: [Double], _ y: [Double]) -> Double {
        let n = Double(x.count)
        guard n > 2 else { return .nan }
        let mx = x.reduce(0, +) / n, my = y.reduce(0, +) / n
        var sxy = 0.0, sxx = 0.0, syy = 0.0
        for i in x.indices {
            let dx = x[i] - mx, dy = y[i] - my
            sxy += dx * dy; sxx += dx * dx; syy += dy * dy
        }
        guard sxx > 0, syy > 0 else { return .nan }
        return sxy / sqrt(sxx * syy)
    }
}
