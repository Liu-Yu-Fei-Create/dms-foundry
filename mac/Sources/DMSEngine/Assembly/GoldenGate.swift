import Foundation

public struct SublibraryPlan: Codable, Sendable {
    public var id: String
    public var aaStart: Int
    public var aaEnd: Int
    public var shift: Int
    public var overhang5: OverhangScore
    public var overhang3: OverhangScore
    public var frozenFullCodons: Int
    public var internalSites: [String]
    public var viable: Bool
    public var issues: [QCIssue]
}

public enum GoldenGatePlanner {

    public static func plan(coding: String,
                            codonStart: Int,
                            aaRange: ClosedRange<Int>,
                            stepNt: Int,
                            enzymeName: String,
                            enzyme: EnzymeSpec,
                            overhangs: OverhangTable,
                            maxShift: Int = 3) -> [SublibraryPlan] {
        let nominalLen = max(3, (stepNt - stepNt % 3) / 3)
        var plans: [SublibraryPlan] = []
        var cursor = aaRange.lowerBound

        while cursor <= aaRange.upperBound {
            let remaining = aaRange.upperBound - cursor + 1
            // 剩余太少就并入上一块，避免出现 <3 密码子的碎片
            if remaining < 3, !plans.isEmpty, let last = plans.popLast() {
                let merged = evaluate(id: last.id, aaStart: last.aaStart, aaEnd: aaRange.upperBound,
                                      shift: 0, coding: coding, codonStart: codonStart,
                                      enzymeName: enzymeName, enzyme: enzyme, overhangs: overhangs)
                plans.append(merged)
                break
            }
            let nominalEnd = cursor + nominalLen - 1
            var candidateEnds: [Int] = []
            if nominalEnd >= aaRange.upperBound {
                candidateEnds = [aaRange.upperBound]
            } else {
                for d in -maxShift...0 {   // 只允许缩短，保证步长仍是上限
                    let e = nominalEnd + d
                    if e >= cursor + 2 && e < aaRange.upperBound { candidateEnds.append(e) }
                }
                if candidateEnds.isEmpty { candidateEnds = [min(nominalEnd, aaRange.upperBound)] }
            }
            var best: SublibraryPlan?
            for e in candidateEnds {
                let p = evaluate(id: String(format: "SL%02d", plans.count + 1),
                                 aaStart: cursor, aaEnd: e, shift: e - nominalEnd,
                                 coding: coding, codonStart: codonStart,
                                 enzymeName: enzymeName, enzyme: enzyme, overhangs: overhangs)
                // 前瞻：下一块的 5′ overhang 由当前边界决定，一并纳入打分，避免把下一块逼进回文接口
                var look = 0.0
                if e + 1 <= aaRange.upperBound {
                    let nextOh = overhangAtStart(coding: coding, codonStart: codonStart, aaPos: e + 1)
                    let ev = OverhangEvaluator.evaluate(nextOh, table: overhangs)
                    look = (ev.fidelity ?? 0) - (ev.palindromic ? 5 : 0)
                }
                if best == nil || score(p) + look > score(best!) { best = p }
            }
            guard let chosen = best else { break }
            plans.append(chosen)
            cursor = chosen.aaEnd + 1
        }
        return plans
    }

    static func overhangAtStart(coding: String, codonStart: Int, aaPos: Int) -> String {
        let chars = Array(coding.uppercased())
        let off = max(0, codonStart - 1) + (aaPos - 1) * 3
        guard off >= 0, off + 4 <= chars.count else { return "" }
        return String(chars[off..<(off + 4)])
    }

    static func score(_ p: SublibraryPlan) -> Double {
        (p.overhang5.fidelity ?? 0) + (p.overhang3.fidelity ?? 0)
            - Double(p.internalSites.count) * 0.5
            - (p.overhang5.palindromic || p.overhang3.palindromic ? 10 : 0)
    }

    static func evaluate(id: String, aaStart: Int, aaEnd: Int, shift: Int,
                         coding: String, codonStart: Int,
                         enzymeName: String, enzyme: EnzymeSpec,
                         overhangs: OverhangTable) -> SublibraryPlan {
        let offset = max(0, codonStart - 1) + (aaStart - 1) * 3
        let length = (aaEnd - aaStart + 1) * 3
        let chars = Array(coding.uppercased())
        let slice: String = (offset >= 0 && offset + length <= chars.count)
            ? String(chars[offset..<(offset + length)]) : ""
        let oh5 = String(slice.prefix(4))
        let oh3 = String(slice.suffix(4))
        let s5 = OverhangEvaluator.evaluate(oh5, table: overhangs)
        let s3 = OverhangEvaluator.evaluate(oh3, table: overhangs)

        var issues: [QCIssue] = []
        if s5.palindromic || s3.palindromic {
            issues.append(QCIssue("gg.palindrome", .error, "接口 overhang 是回文/自互补，不能用于一锅法连接"))
        }
        if oh5 == oh3 || oh5 == Seq.reverseComplement(oh3) {
            issues.append(QCIssue("gg.same-ends", .error, "片段两端 overhang 相同或互补，会自连"))
        }
        if let f = s5.fidelity {
            if f < 0.6 {
                issues.append(QCIssue("gg.low-fidelity-5", .error, String(format: "5′ overhang %@ 保真度 %.2f 过低（<0.60），错接风险高", oh5, f)))
            } else if f < 0.8 {
                issues.append(QCIssue("gg.low-fidelity-5", .warning, String(format: "5′ overhang %@ 保真度 %.2f 偏低", oh5, f)))
            }
        }
        if let f = s3.fidelity {
            if f < 0.6 {
                issues.append(QCIssue("gg.low-fidelity-3", .error, String(format: "3′ overhang %@ 保真度 %.2f 过低（<0.60），错接风险高", oh3, f)))
            } else if f < 0.8 {
                issues.append(QCIssue("gg.low-fidelity-3", .warning, String(format: "3′ overhang %@ 保真度 %.2f 偏低", oh3, f)))
            }
        }
        let hits = EnzymeScanner.scan(slice, name: enzymeName, enzyme: enzyme)
        if !hits.isEmpty {
            issues.append(QCIssue("gg.internal-site", .error,
                                  "突变区内有 \(hits.count) 个 \(enzymeName) 位点（可用 Refine 尝试同义替换）"))
        }
        return SublibraryPlan(id: id, aaStart: aaStart, aaEnd: aaEnd, shift: shift,
                              overhang5: s5, overhang3: s3,
                              frozenFullCodons: length >= 6 ? 2 : 0,
                              internalSites: hits.map { "\($0.enzyme)@\($0.start)" },
                              viable: !issues.contains { $0.severity == .error },
                              issues: issues)
    }
}

public struct GibsonPlan: Codable, Sendable {
    public var id: String
    public var aaStart: Int
    public var aaEnd: Int
    public var leftArm: String
    public var rightArm: String
    public var leftTm: Double
    public var rightTm: Double
    public var leftArmCount: Int
    public var rightArmCount: Int
    public var viable: Bool
    public var issues: [QCIssue]
}

public enum GibsonPlanner {
    public static func plan(coding: String, codonStart: Int,
                            aaRange: ClosedRange<Int>, stepNt: Int,
                            flanks: (upstream: String, downstream: String) = ("", ""),
                            armLen: Int = 25) -> [GibsonPlan] {
        let blocks = Partitioner.split(aaRange: aaRange, codonStart: codonStart, stepNt: stepNt)
        let upCount = flanks.upstream.count
        let extended = flanks.upstream + coding + flanks.downstream
        let chars = Array(extended.uppercased())
        return blocks.map { b in
            let offset = upCount + max(0, codonStart - 1) + (b.aaStart - 1) * 3
            let length = (b.aaEnd - b.aaStart + 1) * 3
            let l0 = max(0, offset - armLen), l1 = offset
            let r0 = offset + length, r1 = min(chars.count, offset + length + armLen)
            let left = String(chars[l0..<l1])
            let right = String(chars[r0..<r1])
            let whole = String(chars)
            let leftCount = EnzymeScanner.find(whole, motif: left.count >= 6 ? String(left.suffix(12)) : left).count
            let rightCount = EnzymeScanner.find(whole, motif: right.count >= 6 ? String(right.prefix(12)) : right).count
            var issues: [QCIssue] = []
            if left.count < armLen || right.count < armLen {
                issues.append(QCIssue("gibson.arm-short", .error, "片段贴近 CDS 末端，同源臂不足 \(armLen) nt"))
            }
            if leftCount > 1 || rightCount > 1 {
                issues.append(QCIssue("gibson.arm-repeat", .warning, "同源臂在模板里出现多次，可能错配"))
            }
            let tmDiff = abs(Seq.tm(left) - Seq.tm(right))
            if tmDiff > 5 { issues.append(QCIssue("gibson.tm", .warning, String(format: "两侧臂 Tm 差 %.1f °C", tmDiff))) }
            return GibsonPlan(id: b.id, aaStart: b.aaStart, aaEnd: b.aaEnd,
                              leftArm: left, rightArm: right,
                              leftTm: Seq.tm(left), rightTm: Seq.tm(right),
                              leftArmCount: leftCount, rightArmCount: rightCount,
                              viable: !issues.contains { $0.severity == .error },
                              issues: issues)
        }
    }
}
