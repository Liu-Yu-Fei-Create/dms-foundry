import Foundation

public enum SequenceError: Error, LocalizedError {
    case invalidBase(Character, Int)
    case emptySequence
    case unsupportedMultiSegment
    case rangeOutOfBounds(String)

    public var errorDescription: String? {
        switch self {
        case .invalidBase(let c, let i): return "序列第 \(i + 1) 位出现非 ACGT 字符：\(c)"
        case .emptySequence: return "序列为空"
        case .unsupportedMultiSegment: return "首版暂不支持多段（join）CDS 的突变区换算"
        case .rangeOutOfBounds(let m): return m
        }
    }
}

public enum Seq {
    static let complement: [Character: Character] = [
        "A": "T", "T": "A", "G": "C", "C": "G", "N": "N",
        "a": "t", "t": "a", "g": "c", "c": "g", "n": "n",
    ]

    public static func reverseComplement(_ s: String) -> String {
        String(s.reversed().map { complement[$0] ?? $0 })
    }

    public static func gc(_ s: String) -> Double {
        guard !s.isEmpty else { return 0 }
        let n = s.uppercased().filter { $0 == "G" || $0 == "C" }.count
        return Double(n) / Double(s.count)
    }

    public static func longestHomopolymer(_ s: String) -> Int {
        var best = 0, cur = 0
        var prev: Character? = nil
        for ch in s.uppercased() {
            if ch == prev { cur += 1 } else { cur = 1; prev = ch }
            best = max(best, cur)
        }
        return best
    }

    public static func contains(_ haystack: String, _ needle: String) -> Bool {
        haystack.range(of: needle, options: .literal) != nil
    }

    public static func sequence(from lines: [String]) -> String {
        lines.joined().uppercased().filter { "ACGTN".contains($0) }
    }

    /// SantaLucia 1998 unified NN，50 mM Na+，CT = 0.25 µM
    public static func tm(_ s: String) -> Double {
        let seq = Array(s.uppercased())
        guard seq.count >= 2 else { return 0 }
        let dh: [String: Double] = [
            "AA": -7.9, "TT": -7.9, "AT": -7.2, "TA": -7.2,
            "CA": -8.5, "TG": -8.5, "GT": -8.4, "AC": -8.4,
            "CT": -7.8, "AG": -7.8, "GA": -8.2, "TC": -8.2,
            "CG": -10.6, "GC": -10.6, "GG": -8.0, "CC": -8.0,
        ]
        let ds: [String: Double] = [
            "AA": -22.2, "TT": -22.2, "AT": -20.4, "TA": -21.3,
            "CA": -22.7, "TG": -22.7, "GT": -22.4, "AC": -22.4,
            "CT": -21.0, "AG": -21.0, "GA": -22.2, "TC": -22.2,
            "CG": -27.2, "GC": -27.2, "GG": -19.9, "CC": -19.9,
        ]
        var h = 0.0, s = 0.0
        // initiation
        h += 0.2 * 2
        s += -5.7 * 2
        for i in 0..<(seq.count - 1) {
            let key = String([seq[i], seq[i + 1]])
            h += dh[key] ?? 0
            s += ds[key] ?? 0
        }
        let R = 1.987
        let ct = 0.25e-6
        let tmK = (1000.0 * h) / (s + R * log(ct / 4.0)) + 16.6 * log10(0.05)
        return tmK - 273.15
    }
}
