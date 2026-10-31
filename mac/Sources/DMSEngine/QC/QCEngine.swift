import Foundation

// MARK: - 设计输入

public struct QCVariant: Codable, Sendable, Hashable {
    public var id: String
    public var sublibrary: String
    /// 密码子序号（1-based，相对 reference 起点）
    public var position: Int
    public var wtCodon: String
    public var mutCodon: String
    public var aaChange: String
    public init(id: String, sublibrary: String, position: Int,
                wtCodon: String, mutCodon: String, aaChange: String) {
        self.id = id; self.sublibrary = sublibrary; self.position = position
        self.wtCodon = wtCodon.uppercased(); self.mutCodon = mutCodon.uppercased()
        self.aaChange = aaChange
    }
}

public struct QCDesign: Codable, Sendable {
    public var reference: String
    public var anchor5: String?
    public var variants: [QCVariant]
    public init(reference: String, anchor5: String? = nil, variants: [QCVariant]) {
        self.reference = reference.uppercased()
        self.anchor5 = anchor5?.uppercased()
        self.variants = variants
    }
}

// MARK: - 计数结果

public struct QCErrorSpectrum: Codable, Sendable {
    public var wildType = 0
    public var knownSingle = 0
    public var unknownSingle = 0
    public var multi = 0
    public var unanchored = 0
}

public struct QCCountResult: Sendable {
    public var counts: [String: Int]          // variant.id -> reads
    public var sublibraryReads: [String: Int]
    public var totalReads: Int
    public var anchoredReads: Int
    public var spectrum: QCErrorSpectrum
    public var designed: [QCVariant]
}

struct Tally {
    let design: QCDesign
    var counts: [String: Int] = [:]
    var subReads: [String: Int] = [:]
    var spectrum = QCErrorSpectrum()
    var total = 0
    var anchored = 0
    let lookup: [String: QCVariant]
    let positions: [Int]
    let ref: [Character]

    init(design: QCDesign) {
        self.design = design
        var l: [String: QCVariant] = [:]
        for v in design.variants { l["\(v.position):\(v.mutCodon)"] = v }
        self.lookup = l
        self.positions = Set(design.variants.map(\.position)).sorted()
        self.ref = Array(design.reference)
    }

    mutating func add(_ sequence: String) -> Bool {
        total += 1
        guard let seg = QCCounter.locate(read: sequence, design: design) else {
            spectrum.unanchored += 1; return false
        }
        anchored += 1
        let s = Array(seg)
        guard s.count >= ref.count else { return false }
        var diffs: [(Int, String)] = []
        for p in positions {
            let lo = (p - 1) * 3
            guard lo + 3 <= s.count, lo + 3 <= ref.count else { continue }
            let codon = String(s[lo..<(lo + 3)])
            if codon != String(ref[lo..<(lo + 3)]) { diffs.append((p, codon)) }
        }
        if diffs.isEmpty { spectrum.wildType += 1 }
        else if diffs.count == 1, let v = lookup["\(diffs[0].0):\(diffs[0].1)"] {
            counts[v.id, default: 0] += 1
            subReads[v.sublibrary, default: 0] += 1
            spectrum.knownSingle += 1
        } else if diffs.count == 1 { spectrum.unknownSingle += 1 }
        else { spectrum.multi += 1 }
        return true
    }

    func finish() -> QCCountResult {
        QCCountResult(counts: counts, sublibraryReads: subReads,
                      totalReads: total, anchoredReads: anchored,
                      spectrum: spectrum, designed: design.variants)
    }
}

public struct QCSampleSpec: Codable, Sendable {
    public var name: String
    public var sublibrary: String
    public var replicate: Int
    public var condition: String
    public var r1: String
    public var r2: String?
    public var index5: String?
    public var index3: String?
    public init(name: String, sublibrary: String, replicate: Int,
                condition: String, r1: String, r2: String? = nil,
                index5: String? = nil, index3: String? = nil) {
        self.name = name; self.sublibrary = sublibrary; self.replicate = replicate
        self.condition = condition; self.r1 = r1; self.r2 = r2
        self.index5 = index5; self.index3 = index3
    }
}

public enum QCCounter {

    /// 单次读长覆盖整个插入片段的前提下，用锚点定位 + 逐密码子比对。
    public static func count(reads: [FastqRecord], design: QCDesign) -> QCCountResult {
        var counts: [String: Int] = [:]
        var subReads: [String: Int] = [:]
        var spectrum = QCErrorSpectrum()

        // (position, codon) -> variant
        var lookup: [String: QCVariant] = [:]
        for v in design.variants { lookup["\(v.position):\(v.mutCodon)"] = v }
        let positions = Set(design.variants.map(\.position))
        let ref = Array(design.reference)

        var anchored = 0
        for r in reads {
            guard let seg = locate(read: r.sequence, design: design) else {
                spectrum.unanchored += 1
                continue
            }
            anchored += 1
            let s = Array(seg)
            guard s.count >= ref.count else { continue }
            var diffs: [(Int, String)] = []
            var mismatchCodons = 0
            for p in positions.sorted() {
                let lo = (p - 1) * 3
                guard lo + 3 <= s.count, lo + 3 <= ref.count else { continue }
                let codon = String(s[lo..<(lo + 3)])
                let wt = String(ref[lo..<(lo + 3)])
                if codon != wt {
                    mismatchCodons += 1
                    diffs.append((p, codon))
                }
            }
            if diffs.isEmpty {
                spectrum.wildType += 1
                continue
            }
            if diffs.count == 1, let v = lookup["\(diffs[0].0):\(diffs[0].1)"] {
                counts[v.id, default: 0] += 1
                subReads[v.sublibrary, default: 0] += 1
                spectrum.knownSingle += 1
            } else if diffs.count == 1 {
                spectrum.unknownSingle += 1
            } else {
                spectrum.multi += 1
            }
        }

        return QCCountResult(counts: counts, sublibraryReads: subReads,
                             totalReads: reads.count, anchoredReads: anchored,
                             spectrum: spectrum, designed: design.variants)
    }

    /// 流式读 FASTQ（.gz 自动解压），内存恒定。
    public static func count(fastqURL: URL, design: QCDesign, maxReads: Int? = nil) throws -> QCCountResult {
        let reader = try FastqReader(url: fastqURL)
        defer { reader.close() }
        var counts: [String: Int] = [:]
        var subReads: [String: Int] = [:]
        var spectrum = QCErrorSpectrum()
        var lookup: [String: QCVariant] = [:]
        for v in design.variants { lookup["\(v.position):\(v.mutCodon)"] = v }
        let positions = Set(design.variants.map(\.position)).sorted()
        let ref = Array(design.reference)
        var total = 0
        var anchored = 0

        while let r = try reader.next() {
            if let cap = maxReads, total >= cap { break }
            total += 1
            guard let seg = locate(read: r.sequence, design: design) else {
                spectrum.unanchored += 1; continue
            }
            anchored += 1
            let s = Array(seg)
            guard s.count >= ref.count else { continue }
            var diffs: [(Int, String)] = []
            for p in positions {
                let lo = (p - 1) * 3
                guard lo + 3 <= s.count, lo + 3 <= ref.count else { continue }
                let codon = String(s[lo..<(lo + 3)])
                if codon != String(ref[lo..<(lo + 3)]) { diffs.append((p, codon)) }
            }
            if diffs.isEmpty { spectrum.wildType += 1 }
            else if diffs.count == 1, let v = lookup["\(diffs[0].0):\(diffs[0].1)"] {
                counts[v.id, default: 0] += 1
                subReads[v.sublibrary, default: 0] += 1
                spectrum.knownSingle += 1
            } else if diffs.count == 1 { spectrum.unknownSingle += 1 }
            else { spectrum.multi += 1 }
        }
        return QCCountResult(counts: counts, sublibraryReads: subReads,
                             totalReads: total, anchoredReads: anchored,
                             spectrum: spectrum, designed: design.variants)
    }

    /// 多样本 / 双端：每个样本一个 (R1, R2)，R1 锚不上时用 R2 的反向互补。
    public static func count(samples: [QCSampleSpec],
                             designFor: (String) -> QCDesign?,
                             progress: ((Int, Int) -> Void)? = nil) throws -> [String: QCCountResult] {
        var out: [String: QCCountResult] = [:]
        for (i, s) in samples.enumerated() {
            guard let design = designFor(s.sublibrary) else { continue }
            let r1 = URL(fileURLWithPath: s.r1)
            let r2 = s.r2.flatMap { URL(fileURLWithPath: $0) }
            out[s.name] = try countPaired(r1: r1, r2: r2, design: design)
            progress?(i + 1, samples.count)
        }
        return out
    }

    public static func countPaired(r1: URL, r2: URL?, design: QCDesign) throws -> QCCountResult {
        var tally = Tally(design: design)
        let a = try FastqReader(url: r1)
        var b: FastqReader? = try r2.map { try FastqReader(url: $0) }
        defer { a.close(); b?.close() }
        while let ra = try a.next() {
            guard let rb = try b?.next() else {
                _ = tally.add(ra.sequence)
                continue
            }
            if let merged = OverlapMerger.merge(r1: ra.sequence, r2: rb.sequence) {
                _ = tally.add(merged.sequence)
            } else if !tally.add(ra.sequence) {
                _ = tally.add(Seq.reverseComplement(rb.sequence))
            }
        }
        return tally.finish()
    }

    /// R2 与 R1 互为反向互补时，用 R2 重建整条片段（仅当长度一致）。
    static func SequenceTrackRC(_ r1: String, _ r2: String) -> String {
        r2.count >= r1.count ? Seq.reverseComplement(r2) : r1
    }

    /// 在 read 中定位插入片段：优先 5′ 锚点，其次 reference 前 20 nt；都不是就试反向互补。
    static func locate(read: String, design: QCDesign) -> String? {
        let bases = Array(read.uppercased())
        let needle = design.anchor5 ?? String(design.reference.prefix(20))
        let n = Array(needle)
        func search(_ hay: [Character]) -> Int? {
            guard hay.count >= n.count else { return nil }
            for i in 0...(hay.count - n.count) where Array(hay[i..<(i + n.count)]) == n { return i }
            return nil
        }
        if let i = search(bases) {
            let start = i + n.count
            guard start + design.reference.count <= bases.count else { return nil }
            return String(bases[start..<(start + design.reference.count)])
        }
        let rc = Array(Seq.reverseComplement(read).uppercased())
        if let i = search(rc) {
            let start = i + n.count
            guard start + design.reference.count <= rc.count else { return nil }
            return String(rc[start..<(start + design.reference.count)])
        }
        return nil
    }
}

// MARK: - 报告

public struct QCVariantRow: Codable, Sendable {
    public var id: String
    public var sublibrary: String
    public var position: Int
    public var wtCodon: String
    public var mutCodon: String
    public var aaChange: String
    public var observed: Int
    public var flag: String   // OK / LOW / ZERO
}

public struct QCSublibraryMetric: Codable, Sendable {
    public var sublibrary: String
    public var reads: Int
    public var designed: Int
    public var observed: Int
    public var medianCoverage: Double
    public init(sublibrary: String, reads: Int, designed: Int, observed: Int, medianCoverage: Double) {
        self.sublibrary = sublibrary; self.reads = reads; self.designed = designed
        self.observed = observed; self.medianCoverage = medianCoverage
    }
}

public struct QCSummary: Codable, Sendable {
    public var totalReads: Int
    public var anchoredReads: Int
    public var anchoredRate: Double
    public var designedVariants: Int
    public var observedVariants: Int
    public var observedRate: Double
    public var zeroCount: Int
    public var medianCoverage: Double
    public var gini: Double
    public var spectrum: QCErrorSpectrum
    public var sublibrary: [QCSublibraryMetric]
    public var verdict: String   // pass / warn / fail
}

public enum QCReport {

    public static func rows(_ result: QCCountResult) -> [QCVariantRow] {
        result.designed.map { v in
            let n = result.counts[v.id] ?? 0
            let flag = n == 0 ? "ZERO" : (n < 10 ? "LOW" : "OK")
            return QCVariantRow(id: v.id, sublibrary: v.sublibrary, position: v.position,
                                wtCodon: v.wtCodon, mutCodon: v.mutCodon,
                                aaChange: v.aaChange, observed: n, flag: flag)
        }.sorted { $0.id < $1.id }
    }

    public static func summarize(_ result: QCCountResult, rows: [QCVariantRow]) -> QCSummary {
        let counts = rows.map(\.observed)
        let observed = counts.filter { $0 > 0 }.count
        let designed = rows.count
        let median = medianValue(counts)
        let g = gini(counts)
        let anchoredRate = result.totalReads == 0 ? 0 : Double(result.anchoredReads) / Double(result.totalReads)
        let observedRate = designed == 0 ? 0 : Double(observed) / Double(designed)

        var bySub: [String: [QCVariantRow]] = [:]
        for r in rows { bySub[r.sublibrary, default: []].append(r) }
        let subMetrics = bySub.keys.sorted().map { key -> QCSublibraryMetric in
            let rs = bySub[key] ?? []
            let c = rs.map(\.observed)
            return QCSublibraryMetric(sublibrary: key,
                                      reads: result.sublibraryReads[key] ?? c.reduce(0, +),
                                      designed: rs.count,
                                      observed: c.filter { $0 > 0 }.count,
                                      medianCoverage: medianValue(c))
        }

        let worst: String
        if observedRate < 0.90 || median < 20 { worst = "fail" }
        else if observedRate < 0.95 || median < 100 || g > 0.5 { worst = "warn" }
        else { worst = "pass" }

        return QCSummary(totalReads: result.totalReads,
                         anchoredReads: result.anchoredReads,
                         anchoredRate: anchoredRate,
                         designedVariants: designed,
                         observedVariants: observed,
                         observedRate: observedRate,
                         zeroCount: designed - observed,
                         medianCoverage: median,
                         gini: g,
                         spectrum: result.spectrum,
                         sublibrary: subMetrics,
                         verdict: worst)
    }

    public static func medianValue(_ xs: [Int]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        let m = s.count / 2
        return s.count % 2 == 1 ? Double(s[m]) : Double(s[m - 1] + s[m]) / 2
    }

    public static func gini(_ xs: [Int]) -> Double {
        let v = xs.map(Double.init).sorted()
        let n = v.count
        guard n > 0, v.reduce(0, +) > 0 else { return 0 }
        var cum = 0.0
        for (i, x) in v.enumerated() { cum += Double(i + 1) * x }
        let sum = v.reduce(0, +)
        return (2 * cum) / (Double(n) * sum) - Double(n + 1) / Double(n)
    }

    public static func rowsCSV(_ rows: [QCVariantRow]) -> String {
        var out = "variant_id,sublibrary,position,wt_codon,mut_codon,aa_change,observed,flag\n"
        for r in rows {
            out += "\(r.id),\(r.sublibrary),\(r.position),\(r.wtCodon),\(r.mutCodon),\(r.aaChange),\(r.observed),\(r.flag)\n"
        }
        return out
    }
}
