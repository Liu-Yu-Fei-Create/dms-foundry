import Foundation

/// 双端 overlap 合并：R2 反向互补后与 R1 找最长重叠，拼成一条覆盖插入片段的序列。
public enum OverlapMerger {
    public struct Result: Sendable {
        public var sequence: String
        public var overlap: Int
        public var mismatches: Int
    }

    public static func merge(r1: String, r2: String,
                             minOverlap: Int = 20,
                             maxMismatchRate: Double = 0.10) -> Result? {
        let a = Array(r1.uppercased())
        let b = Array(Seq.reverseComplement(r2).uppercased())
        guard !a.isEmpty, !b.isEmpty else { return nil }
        let maxL = min(a.count, b.count)
        guard maxL >= minOverlap else { return nil }

        for L in stride(from: maxL, through: minOverlap, by: -1) {
            let left = a.suffix(L)
            let right = b.prefix(L)
            var mismatches = 0
            for (x, y) in zip(left, right) where x != y { mismatches += 1 }
            let allowed = max(1, Int(Double(L) * maxMismatchRate))
            if mismatches <= allowed {
                let merged = String(a) + String(b.dropFirst(L))
                return Result(sequence: merged, overlap: L, mismatches: mismatches)
            }
        }
        return nil
    }
}
