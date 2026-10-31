import Foundation

public struct CountsSample: Sendable {
    public var name: String
    public var condition: String     // input / selected / ...
    public var replicate: Int
    public var sublibrary: String
    public var counts: [String: Int] // variantID -> reads
    /// 文库大小（含 WT 与非设计 reads）；为 nil 时用变体计数之和
    public var librarySize: Int?
    public init(name: String, condition: String, replicate: Int,
                sublibrary: String = "", counts: [String: Int], librarySize: Int? = nil) {
        self.name = name; self.condition = condition
        self.replicate = replicate; self.sublibrary = sublibrary
        self.counts = counts; self.librarySize = librarySize
    }
    public var total: Int { librarySize ?? counts.values.reduce(0, +) }
}

public struct VariantEffect: Codable, Sendable {
    public var variant: String
    public var effect: Double
    public var se: Double
    public var ciLow: Double
    public var ciHigh: Double
    public var z: Double
    public var p: Double
    public var q: Double
    public var flag: String     // OK / LOW_COUNT / INSUFFICIENT
    public var replicates: Int
}

public enum AnalysisEngine {

    /// log2 富集比（CPM 归一 + 伪计数 0.5），delta 法给 SE。
    public static func log2Ratio(selected: Double, input: Double,
                                 selectedTotal: Double, inputTotal: Double,
                                 pseudo: Double = 0.5) -> (effect: Double, se: Double) {
        let ns = max(selectedTotal, 1)
        let ni = max(inputTotal, 1)
        let a = (selected + pseudo) / ns
        let b = (input + pseudo) / ni
        let effect = log2(a / b)
        let varLog = (1.0 / (selected + pseudo) + 1.0 / (input + pseudo)) / pow(log(2.0), 2)
        return (effect, sqrt(max(varLog, 0)))
    }

    /// 逆方差加权合并 replicate
    public static func merge(_ estimates: [(effect: Double, se: Double)]) -> (effect: Double, se: Double) {
        let valid = estimates.filter { $0.se.isFinite && $0.se > 0 }
        guard !valid.isEmpty else { return (0, .infinity) }
        let ws = valid.map { 1.0 / ($0.se * $0.se) }
        let sumW = ws.reduce(0, +)
        guard sumW > 0 else { return (0, .infinity) }
        let mean = zip(valid, ws).map { $0.0.effect * $0.1 }.reduce(0, +) / sumW
        return (mean, sqrt(1.0 / sumW))
    }

    /// 对每个变体：按 (sublibrary, replicate) 配对 input/selected，合并，再用同义变体做 null。
    public static func run(samples: [CountsSample],
                           variants: [String],
                           selectedCondition: String = "selected",
                           inputCondition: String = "input",
                           synonymous: Set<String> = [],
                           pseudo: Double = 0.5) -> [VariantEffect] {
        let sels = samples.filter { $0.condition == selectedCondition }
        let ins = samples.filter { $0.condition == inputCondition }
        var raw: [String: (effect: Double, se: Double, reps: Int)] = [:]

        for v in variants {
            var estimates: [(effect: Double, se: Double)] = []
            for s in sels {
                let candidates = ins.filter { $0.replicate == s.replicate && $0.sublibrary == s.sublibrary }
                let fallback = ins.filter { $0.sublibrary == s.sublibrary }
                guard let i = (candidates.first ?? fallback.first) else { continue }
                let e = log2Ratio(selected: Double(s.counts[v] ?? 0),
                                  input: Double(i.counts[v] ?? 0),
                                  selectedTotal: Double(s.total),
                                  inputTotal: Double(i.total),
                                  pseudo: pseudo)
                estimates.append(e)
            }
            guard !estimates.isEmpty else { continue }
            let m = merge(estimates)
            raw[v] = (m.effect, m.se, estimates.count)
        }

        // null：同义变体（若为空则用全部变体的稳健尺度）
        let nullValues = variants.filter { synonymous.contains($0) }.compactMap { raw[$0]?.effect }
        let (mu, sd): (Double, Double) = {
            if nullValues.count >= 3 {
                let m = nullValues.reduce(0, +) / Double(nullValues.count)
                let varSum = nullValues.map { pow($0 - m, 2) }.reduce(0, +) / Double(max(nullValues.count - 1, 1))
                return (m, sqrt(varSum))
            }
            let all = raw.values.map(\.effect)
            guard all.count >= 3 else { return (0, 0) }
            let med = QCReport.medianValue(all.map { Int(($0 * 1e6).rounded()) }) / 1e6
            let mad = all.map { abs($0 - med) }
            let mm = QCReport.medianValue(mad.map { Int(($0 * 1e6).rounded()) }) / 1e6
            return (0, max(1.4826 * mm, 1e-6))
        }()

        var rows: [VariantEffect] = []
        for v in variants {
            guard let r = raw[v] else {
                rows.append(VariantEffect(variant: v, effect: 0, se: .infinity,
                                          ciLow: -.infinity, ciHigh: .infinity,
                                          z: 0, p: 1, q: 1, flag: "INSUFFICIENT", replicates: 0))
                continue
            }
            // 同义 null 退化为常数时，用该变体自身的标准误作为尺度
            let denom = sd > 0 ? sqrt(r.se * r.se + sd * sd) : r.se
            let z = denom.isFinite && denom > 0 ? (r.effect - mu) / denom : 0
            let p = 2 * (1 - normalCDF(abs(z)))
            let low = r.effect - 1.96 * r.se
            let high = r.effect + 1.96 * r.se
            let totalReads = samples.reduce(0) { $0 + ($1.counts[v] ?? 0) }
            rows.append(VariantEffect(variant: v, effect: r.effect, se: r.se,
                                      ciLow: low, ciHigh: high,
                                      z: z, p: p, q: 1,
                                      flag: totalReads < 10 ? "LOW_COUNT" : "OK",
                                      replicates: r.reps))
        }

        // BH-FDR
        let order = rows.indices.sorted { rows[$0].p < rows[$1].p }
        let m = Double(rows.count)
        var prev = 1.0
        for (rank, idx) in order.enumerated().reversed() {
            let q = min(prev, rows[idx].p * m / Double(rank + 1))
            rows[idx].q = q
            prev = q
        }
        return rows
    }

    public static func normalCDF(_ x: Double) -> Double {
        0.5 * (1 + erf(x / sqrt(2)))
    }

    public static func effectsCSV(_ rows: [VariantEffect]) -> String {
        var out = "variant,effect,se,ci_low,ci_high,z,p,q,flag,replicates\n"
        for r in rows {
            out += "\(r.variant),\(fmt(r.effect)),\(fmt(r.se)),\(fmt(r.ciLow)),\(fmt(r.ciHigh)),\(fmt(r.z)),\(fmt(r.p)),\(fmt(r.q)),\(r.flag),\(r.replicates)\n"
        }
        return out
    }

    private static func fmt(_ x: Double) -> String {
        guard x.isFinite else { return "" }
        return String(format: "%.6f", x)
    }
}
