import Foundation

public struct SubLibrary: Codable, Identifiable, Sendable {
    public var id: String
    public var aaStart: Int
    public var aaEnd: Int
    public var ntOffset: Int   // 相对 CDS 编码链起点（0-based）
    public var ntLength: Int
    public init(id: String, aaStart: Int, aaEnd: Int, ntOffset: Int, ntLength: Int) {
        self.id = id; self.aaStart = aaStart; self.aaEnd = aaEnd
        self.ntOffset = ntOffset; self.ntLength = ntLength
    }
}

public enum Partitioner {
    /// 按 stepNt 切分（必须是 3 的倍数），不切断密码子、不重叠
    public static func split(aaRange: ClosedRange<Int>, codonStart: Int, stepNt: Int) -> [SubLibrary] {
        let step = max(3, stepNt - stepNt % 3)
        let codonsPerBlock = max(1, step / 3)
        var out: [SubLibrary] = []
        var start = aaRange.lowerBound
        var n = 1
        while start <= aaRange.upperBound {
            let end = min(aaRange.upperBound, start + codonsPerBlock - 1)
            let ntOffset = (codonStart - 1) + (start - 1) * 3
            let ntLength = (end - start + 1) * 3
            out.append(SubLibrary(id: String(format: "SL%02d", n),
                                  aaStart: start, aaEnd: end,
                                  ntOffset: ntOffset, ntLength: ntLength))
            start = end + 1; n += 1
        }
        return out
    }
}

public enum LengthBudget {
    public static let indexLen = 20
    public static let spacer = 6
    public static let enzymeFootprint = 13   // 识别位点 6 + spacer + overhang 4
    public static let vendorMax = 300

    public static func oligoLength(stepNt: Int, method: AssemblyMethod, homologyArmNt: Int = 25) -> Int {
        switch method {
        case .goldenGate:
            return indexLen + spacer + enzymeFootprint + stepNt + enzymeFootprint + spacer + indexLen
        case .gibson:
            return indexLen + homologyArmNt + stepNt + homologyArmNt + indexLen
        }
    }

    public static func maxStep(method: AssemblyMethod, homologyArmNt: Int = 25) -> Int {
        var s = vendorMax
        while s > 30 {
            if oligoLength(stepNt: s, method: method, homologyArmNt: homologyArmNt) <= vendorMax { return s }
            s -= 3
        }
        return 30
    }
}
