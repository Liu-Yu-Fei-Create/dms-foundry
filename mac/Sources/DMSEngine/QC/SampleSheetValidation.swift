import Foundation

public struct SampleSheetIssue: Sendable {
    public enum Level: String, Sendable { case error, warning }
    public var level: Level
    public var message: String
    public init(level: Level, message: String) {
        self.level = level; self.message = message
    }
}

public enum SampleSheetValidator {

    /// index 只允许 ACGT、长度 6–12；两两汉明距离 ≥3（经验建议）。
    public static func validate(_ samples: [QCSampleSpec]) -> [SampleSheetIssue] {
        var issues: [SampleSheetIssue] = []
        var seenPairs = [String: String]()
        var indices: [(String, String, String)] = []   // (sample, i5, i3)

        for s in samples {
            let i5 = s.index5 ?? ""
            let i3 = s.index3 ?? ""
            if i5.isEmpty && i3.isEmpty { continue }

            for (label, seq) in [("index5", i5), ("index3", i3)] where !seq.isEmpty {
                if seq.count < 6 || seq.count > 12 {
                    issues.append(.init(level: .error, message: "\(s.name) 的 \(label) 长度 \(seq.count) 不在 6–12"))
                }
                if !seq.allSatisfy({ "ACGT".contains($0) }) {
                    issues.append(.init(level: .error, message: "\(s.name) 的 \(label) 含非 ACGT 字符"))
                }
            }

            let pair = "\(i5)+\(i3)"
            if let prev = seenPairs[pair] {
                issues.append(.init(level: .error, message: "index 组合重复：\(s.name) 与 \(prev)"))
            } else {
                seenPairs[pair] = s.name
                indices.append((s.name, i5, i3))
            }
        }

        // 两两汉明距离
        for i in 0..<indices.count {
            for j in (i + 1)..<indices.count {
                let (n1, a5, a3) = indices[i]
                let (n2, b5, b3) = indices[j]
                let d = max(hamming(a5, b5), hamming(a3, b3))
                if d < 3 {
                    issues.append(.init(level: .warning,
                                        message: "\(n1) 与 \(n2) 的 index 汉明距离 \(d) < 3，测序错误可能造成串样"))
                }
            }
        }
        return issues
    }

    public static func hamming(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        guard x.count == y.count else { return max(x.count, y.count) }
        return zip(x, y).reduce(0) { $0 + ($1.0 == $1.1 ? 0 : 1) }
    }
}
