import Foundation

public struct RefineChange: Codable, Hashable, Sendable {
    public var position: Int      // CDS 内 1-based 密码子序号
    public var from: String
    public var to: String
    public var aminoAcid: String
}

public struct RefineResult: Codable, Sendable {
    public var coding: String
    public var changes: [RefineChange]
    public var remainingSites: [Int]
    public var iterations: Int
}

public enum Refiner {
    /// 对编码序列做同义替换，尽量消除 motif（含反向互补）命中；只在 allowedCodons 指定的密码子范围内改。
    public static func refine(coding: String,
                              codonStart: Int,
                              allowedCodons: ClosedRange<Int>,
                              motif: String,
                              table: CodonTable,
                              allowRare: Bool = true,
                              maxIterations: Int = 200) -> RefineResult {
        var seq = Array(coding.uppercased())
        var changes: [RefineChange] = []
        let offset = max(0, codonStart - 1)
        let codonCount = max(0, (seq.count - offset) / 3)

        func codonRange(_ i: Int) -> Range<Int> {
            let s = offset + (i - 1) * 3
            return s..<min(s + 3, seq.count)
        }
        func sites(in chars: [Character]) -> [Int] {
            EnzymeScanner.find(String(chars), motif: motif)
        }

        var iterations = 0
        while iterations < maxIterations {
            iterations += 1
            let hits = sites(in: seq)
            if hits.isEmpty { break }
            var improved = false

            outer: for hit in hits {
                let firstCodon = max(allowedCodons.lowerBound,
                                     (hit - offset) / 3 + 1)
                let lastCodon = min(allowedCodons.upperBound,
                                    (hit + motif.count - 1 - offset) / 3 + 1)
                guard firstCodon <= lastCodon, firstCodon >= 1, lastCodon <= codonCount else { continue }
                for ci in firstCodon...lastCodon {
                    let r = codonRange(ci)
                    guard r.count == 3 else { continue }
                    let current = String(seq[r])
                    guard let aa = table.aminoAcid(for: current) else { continue }
                    let options = table.codons(for: aa)
                        .filter { $0.codon != current && (allowRare || $0.freq >= 10) }
                        .map(\.codon)
                    let before = sites(in: seq)
                    for alt in options {
                        var trial = seq
                        trial.replaceSubrange(r, with: Array(alt))
                        let after = sites(in: trial)
                        if after.count < before.count {
                            seq = trial
                            changes.append(RefineChange(position: ci, from: current, to: alt, aminoAcid: aa))
                            improved = true
                            break outer
                        }
                    }
                }
            }
            if !improved { break }
        }
        let remaining = sites(in: seq)
        return RefineResult(coding: String(seq), changes: changes,
                            remainingSites: remaining, iterations: iterations)
    }
}
