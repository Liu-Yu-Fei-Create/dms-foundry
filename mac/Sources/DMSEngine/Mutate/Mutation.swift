import Foundation

public enum VariantSource: String, Codable, Sendable {
    case design, stopQC, synQC, proQC, randomRegion
}

public struct Variant: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var position: Int      // 1-based，CDS 内氨基酸序号
    public var wt: String
    public var mut: String        // "*" 表示终止
    public var codon: String
    public var source: VariantSource
    public init(id: String, position: Int, wt: String, mut: String, codon: String, source: VariantSource) {
        self.id = id; self.position = position; self.wt = wt; self.mut = mut
        self.codon = codon; self.source = source
    }
}

/// 编码链上下文：把质粒上的 CDS 按方向整理成可直接按密码子寻址的序列
public struct CodingContext {
    public let feature: Feature
    public let coding: String
    private let plasmidSequence: String
    public init(plasmid: Plasmid, feature: Feature) {
        self.init(plasmid: plasmid, feature: feature, coding: nil)
    }

    public init(plasmid: Plasmid, feature: Feature, coding: String?) {
        self.feature = feature
        self.plasmidSequence = plasmid.sequence.uppercased()
        if let coding, !coding.isEmpty {
            self.coding = coding.uppercased()
            return
        }
        let bases = Array(plasmid.sequence)
        let lo = max(0, min(feature.start, bases.count))
        let hi = max(lo, min(feature.end, bases.count))
        let slice = String(bases[lo..<hi])
        self.coding = feature.strand == .reverse ? Seq.reverseComplement(slice) : slice
    }

    public var codonCount: Int { max(0, (coding.count - (feature.codonStart - 1)) / 3) }

    /// 编码方向上的上下游侧翼（从质粒取，够长时截断）
    public func flanks(_ n: Int) -> (upstream: String, downstream: String) {
        let bases = Array(plasmidSequence)
        let start = max(0, min(feature.start, bases.count))
        let end = max(start, min(feature.end, bases.count))
        let upStart = max(0, start - n), downEnd = min(bases.count, end + n)
        let upRaw = String(bases[upStart..<start])
        let downRaw = String(bases[end..<downEnd])
        return feature.strand == .reverse
            ? (Seq.reverseComplement(downRaw), Seq.reverseComplement(upRaw))
            : (upRaw, downRaw)
    }

    public func codon(at position: Int) -> String? {
        let off = (feature.codonStart - 1) + (position - 1) * 3
        guard off >= 0, off + 3 <= coding.count else { return nil }
        let s = coding.index(coding.startIndex, offsetBy: off)
        let e = coding.index(s, offsetBy: 3)
        return String(coding[s..<e])
    }
}

public enum MutationEnumerator {

    /// 单点突变枚举。顺序固定：候选 → 策略取样 → 过滤 → 去重 → 编号。
    public static func enumerate(context: CodingContext,
                                 range: ClosedRange<Int>,
                                 params: LibraryParams,
                                 table: CodonTable,
                                 seed: UInt64) throws -> [Variant] {
        var rng = SplitMix64.stream(seed: seed, purpose: "design")
        var seen = Set<String>()
        var out: [Variant] = []

        let allowed = Set(params.allowedAA.map { $0.uppercased() })
        let targetsAll: [String] = Array("ACDEFGHIKLMNPQRSTVWY").map(String.init)

        for pos in range {
            guard let wtCodon = context.codon(at: pos),
                  let wtAA = table.aminoAcid(for: wtCodon) else { continue }

            var targets = params.mutationMode == .all ? targetsAll : targetsAll.filter { allowed.contains($0) }
            targets.removeAll { $0 == wtAA }
            if params.includeStop { targets.append("*") }

            for target in targets {
                guard let codon = pickCodon(target: target, params: params, table: table, rng: &rng) else { continue }
                if !params.keepRare, target != "*",
                   table.frequency(of: codon) < params.rareThreshold { continue }
                append(&out, seen: &seen, pos: pos, wt: wtAA, mut: target,
                       codon: codon, source: .design)
            }

            if params.includeSynonymous {
                for entry in table.codons(for: wtAA) where entry.codon != wtCodon {
                    if !params.keepRare && entry.freq < params.rareThreshold { continue }
                    append(&out, seen: &seen, pos: pos, wt: wtAA, mut: wtAA,
                           codon: entry.codon, source: .design)
                }
            }

            if params.includeWT {
                append(&out, seen: &seen, pos: pos, wt: wtAA, mut: wtAA,
                       codon: wtCodon, source: .design)
            }
        }
        return out
    }

    static func pickCodon(target: String, params: LibraryParams, table: CodonTable,
                          rng: inout SplitMix64) -> String? {
        if target == "*" { return "TAA" }
        let all = table.codons(for: target)
        guard !all.isEmpty else { return nil }
        switch params.codonPolicy {
        case .optimal:
            return all.first?.codon
        case .random:
            return all.randomElement(using: &rng)?.codon
        case .randomNonRare:
            let nonRare = all.filter { $0.freq >= params.rareThreshold }
            if let pick = nonRare.randomElement(using: &rng) { return pick.codon }
            return all.first?.codon   // 回退：该 aa 没有非稀有密码子时保留最高频的
        }
    }

    static func append(_ out: inout [Variant], seen: inout Set<String>,
                       pos: Int, wt: String, mut: String, codon: String,
                       source: VariantSource) {
        var id = "\(wt)\(pos)\(mut)"
        if !seen.insert(id).inserted {
            let alt = "\(id)-\(codon)"
            guard seen.insert(alt).inserted else { return }
            id = alt
        }
        out.append(Variant(id: id, position: pos, wt: wt, mut: mut, codon: codon, source: source))
    }
}
