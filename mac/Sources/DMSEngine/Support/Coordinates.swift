import Foundation

public struct NTRange {
    public var start: Int   // 0-based inclusive, 质粒坐标
    public var end: Int     // 0-based exclusive
    public var strand: Strand
    public var length: Int { end - start }
}

public enum Coordinates {
    /// 把 CDS 内的 1-based 氨基酸区间换算成质粒上的 nt 区间。
    /// 首版只支持单段 CDS；反向链按互补方向计算。
    public static func cdsRange(feature: Feature, aaStart: Int, aaEnd: Int) throws -> NTRange {
        guard aaStart >= 1, aaEnd >= aaStart else {
            throw SequenceError.rangeOutOfBounds("氨基酸区间不合法：\(aaStart)..\(aaEnd)")
        }
        guard aaStart >= 1, aaEnd <= feature.codonCount else {
            throw SequenceError.rangeOutOfBounds("氨基酸区间超出 CDS：该 CDS 共 \(feature.codonCount) 个密码子")
        }
        if let sub = feature.subRanges, sub.count > 1 { throw SequenceError.unsupportedMultiSegment }

        let aaCount = aaEnd - aaStart + 1
        let codingOffset = (feature.codonStart - 1) + (aaStart - 1) * 3
        let ntLen = aaCount * 3
        if codingOffset + ntLen > feature.length {
            throw SequenceError.rangeOutOfBounds("区间超出 CDS 长度")
        }
        let baseStart = feature.start
        switch feature.strand {
        case .forward:
            let s = baseStart + codingOffset
            return NTRange(start: s, end: s + ntLen, strand: .forward)
        case .reverse:
            let s = feature.end - codingOffset - ntLen
            return NTRange(start: s, end: s + ntLen, strand: .reverse)
        }
    }
}
