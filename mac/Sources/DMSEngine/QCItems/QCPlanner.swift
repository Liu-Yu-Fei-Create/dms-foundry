import Foundation

public struct RegionVariant: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var subID: String
    public var aaStart: Int
    public var aaEnd: Int
    public var sequence: String
    public var mode: RandomRegionMode
}

public struct QCPlanResult: Sendable {
    public var variants: [Variant] = []
    public var regionVariants: [RegionVariant] = []
    public var skipped: [String: String] = [:]
    public var added: [String: Int] = [:]
}

public enum QCPlanner {

    public static func plan(context: CodingContext,
                            params: LibraryParams,
                            qc: QCOptions,
                            table: CodonTable,
                            aaRange: ClosedRange<Int>,
                            sublibraries: [SubLibrary],
                            seed: UInt64,
                            existingIDs: Set<String>) -> QCPlanResult {
        var out = QCPlanResult()
        var seen = existingIDs

        func positions(_ item: QCItem, purpose: String, codonCount: Int) -> [Int] {
            let lo = max(aaRange.lowerBound, min(item.aaRangeStart, item.aaRangeEnd))
            let hi = min(aaRange.upperBound, max(item.aaRangeStart, item.aaRangeEnd))
            guard lo <= hi else { return [] }
            switch item.mode {
            case .specified:
                return item.positions.filter { $0 >= lo && $0 <= hi }.sorted()
            case .random:
                var rng = SplitMix64.stream(seed: seed, purpose: purpose)
                let pool = Array(lo...hi)
                let n = max(0, min(item.count, pool.count))
                return Array(pool.shuffled(using: &rng).prefix(n)).sorted()
            }
        }

        // ① 终止密码子质检
        if params.includeStop {
            out.skipped["stop"] = "突变类型已包含终止密码子"
        } else if qc.stop.enabled {
            let ps = positions(qc.stop, purpose: "qc.stop", codonCount: context.codonCount)
            for p in ps {
                guard let wtCodon = context.codon(at: p), let wtAA = table.aminoAcid(for: wtCodon) else { continue }
                let id = "\(wtAA)\(p)*"
                guard seen.insert(id).inserted else { continue }
                out.variants.append(Variant(id: id, position: p, wt: wtAA, mut: "*", codon: "TAA", source: .stopQC))
            }
            out.added["stop"] = ps.count
        }

        // ② 同义突变质检
        if params.includeSynonymous {
            out.skipped["synonymous"] = "突变类型已包含同义突变"
        } else if qc.synonymous.enabled {
            let candidates = (aaRange.lowerBound...aaRange.upperBound).filter { p in
                guard let c = context.codon(at: p), let aa = table.aminoAcid(for: c) else { return false }
                return table.nonRare(for: aa, threshold: params.rareThreshold).count >= 2
            }
            let chosen = Set(positions(qc.synonymous, purpose: "qc.syn", codonCount: context.codonCount))
                .intersection(candidates)
            var rng = SplitMix64.stream(seed: seed, purpose: "qc.syn.pick")
            for p in chosen.sorted() {
                guard let wtCodon = context.codon(at: p), let aa = table.aminoAcid(for: wtCodon) else { continue }
                let options = table.nonRare(for: aa, threshold: params.rareThreshold).filter { $0 != wtCodon }
                guard let pick = options.randomElement(using: &rng) else { continue }
                let id = "\(aa)\(p)\(aa)-\(pick)"
                guard seen.insert(id).inserted else { continue }
                out.variants.append(Variant(id: id, position: p, wt: aa, mut: aa, codon: pick, source: .synQC))
            }
            out.added["synonymous"] = chosen.count
        }

        // ③ 脯氨酸质检（突变集合不含 Pro 时）
        let includesPro = params.mutationMode == .all || params.allowedAA.contains("P")
        if includesPro {
            out.skipped["proline"] = "突变集合已包含脯氨酸"
        } else if qc.proline.enabled {
            let ps = positions(qc.proline, purpose: "qc.pro", codonCount: context.codonCount)
                .filter { p in
                    guard let c = context.codon(at: p) else { return false }
                    return table.aminoAcid(for: c) != "P"
                }
            var rng = SplitMix64.stream(seed: seed, purpose: "qc.pro.pick")
            for p in ps {
                guard let wtCodon = context.codon(at: p), let wtAA = table.aminoAcid(for: wtCodon) else { continue }
                let options = table.nonRare(for: "P", threshold: params.rareThreshold)
                let codon = options.randomElement(using: &rng) ?? table.optimal(for: "P") ?? "CCG"
                let id = "\(wtAA)\(p)P"
                guard seen.insert(id).inserted else { continue }
                out.variants.append(Variant(id: id, position: p, wt: wtAA, mut: "P", codon: codon, source: .proQC))
            }
            out.added["proline"] = ps.count
        }

        // ④ 随机区质检
        if qc.randomRegion.enabled {
            var rng = SplitMix64.stream(seed: seed, purpose: "qc.rand")
            for sub in sublibraries {
                let offset = max(0, context.feature.codonStart - 1) + (sub.aaStart - 1) * 3
                let length = (sub.aaEnd - sub.aaStart + 1) * 3
                let chars = Array(context.coding.uppercased())
                guard offset + length <= chars.count else { continue }
                for k in 1...max(1, qc.randomRegion.countPerSublibrary) {
                    let seq: String
                    switch qc.randomRegion.mode {
                    case .pureRandomNt:
                        seq = String((0..<length).map { _ in ["A", "C", "G", "T"].randomElement(using: &rng)! })
                    case .framePreservingCodons:
                        var s = ""
                        for _ in 0..<(length / 3) {
                            let aa = String("ACDEFGHIKLMNPQRSTVWY".randomElement(using: &rng)!)
                            let opts = table.nonRare(for: aa, threshold: params.rareThreshold)
                            s += opts.randomElement(using: &rng) ?? (table.optimal(for: aa) ?? "GCT")
                        }
                        seq = s
                    }
                    out.regionVariants.append(RegionVariant(id: "\(sub.id)-RND\(k)", subID: sub.id,
                                                            aaStart: sub.aaStart, aaEnd: sub.aaEnd,
                                                            sequence: seq, mode: qc.randomRegion.mode))
                }
            }
            out.added["randomRegion"] = out.regionVariants.count
        }
        return out
    }
}
