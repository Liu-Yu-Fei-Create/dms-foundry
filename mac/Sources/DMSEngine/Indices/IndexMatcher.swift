import Foundation

public struct IndexAssignment: Codable, Sendable {
    public var subID: String
    public var index5: IndexEntry
    public var index3: IndexEntry
    public var tmDiff: Double
}

public enum IndexMatcher {

    /// 为每个子库分配一对 index：避免与质粒/文库交叉，3′ 端唯一，Tm 尽量接近。
    public static func assign(sublibraries: [SubLibrary],
                              indices: IndexFile,
                              plasmid: String,
                              seed: UInt64,
                              candidatesPerSub: Int = 400) -> [IndexAssignment] {
        let plasmidU = plasmid.uppercased()
        let rcPlasmid = Seq.reverseComplement(plasmidU)

        // 先剔除与质粒高度重合的候选（15-mer 命中）
        func isClean(_ e: IndexEntry) -> Bool {
            let s = e.seq.uppercased()
            guard s.count >= 15 else { return false }
            let probes = [String(s.prefix(15)), String(s.suffix(15)),
                          String(Seq.reverseComplement(s).prefix(15))]
            return !probes.contains { plasmidU.contains($0) || rcPlasmid.contains($0) }
        }
        let clean = indices.indices.filter(isClean)
        guard clean.count >= sublibraries.count * 2 else { return [] }

        var rng = SplitMix64.stream(seed: seed, purpose: "index")
        var used = Set<String>()
        var out: [IndexAssignment] = []

        for sub in sublibraries {
            var best: IndexAssignment?
            var bestScore = -Double.infinity
            for _ in 0..<candidatesPerSub {
                guard let a = clean.randomElement(using: &rng),
                      let b = clean.randomElement(using: &rng),
                      a.seq != b.seq,
                      !used.contains(a.id), !used.contains(b.id) else { continue }
                let tmDiff = abs(a.tm - b.tm)
                if tmDiff > 2.0 { continue }
                let score = -tmDiff - hammingPenalty(a.seq, b.seq)
                if score > bestScore {
                    bestScore = score
                    best = IndexAssignment(subID: sub.id, index5: a, index3: b, tmDiff: tmDiff)
                }
            }
            if let b = best {
                used.insert(b.index5.id); used.insert(b.index3.id)
                out.append(b)
            }
        }
        return out
    }

    static func hammingPenalty(_ a: String, _ b: String) -> Double {
        let x = Array(a.uppercased()), y = Array(b.uppercased())
        guard x.count == y.count else { return 10 }
        let d = zip(x, y).filter { $0 != $1 }.count
        return d < 6 ? 5 : 0
    }
}
