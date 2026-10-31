import Foundation

public struct EnzymeHit: Codable, Hashable, Sendable {
    public var enzyme: String
    public var start: Int      // 0-based，识别序列起点
    public var end: Int
    public var strand: Strand
    public var site: String
}

public enum EnzymeScanner {
    /// 在给定序列上扫描酶的识别位点（双链）
    public static func scan(_ sequence: String, name: String, enzyme: EnzymeSpec) -> [EnzymeHit] {
        let seq = sequence.uppercased()
        let rc = Seq.reverseComplement(enzyme.recognition.uppercased())
        var hits: [EnzymeHit] = []
        for (site, strand) in [(enzyme.recognition.uppercased(), Strand.forward), (rc, Strand.reverse)] {
            var searchStart = seq.startIndex
            while let r = seq.range(of: site, range: searchStart..<seq.endIndex) {
                let start = seq.distance(from: seq.startIndex, to: r.lowerBound)
                let end = seq.distance(from: seq.startIndex, to: r.upperBound)
                hits.append(EnzymeHit(enzyme: name, start: start, end: end,
                                      strand: strand, site: site))
                searchStart = seq.index(after: r.lowerBound)
            }
        }
        return hits.sorted { $0.start < $1.start }
    }

    /// 以任意 6-mer 识别字符串扫描（Refiner 用）
    public static func find(_ sequence: String, motif: String) -> [Int] {
        let seq = sequence.uppercased(), m = motif.uppercased()
        guard m.count >= 4 else { return [] }
        var out: [Int] = []
        var idx = seq.startIndex
        while let r = seq.range(of: m, range: idx..<seq.endIndex) {
            out.append(seq.distance(from: seq.startIndex, to: r.lowerBound))
            idx = seq.index(after: r.lowerBound)
        }
        // 反向互补
        let rc = Seq.reverseComplement(m)
        if rc != m {
            idx = seq.startIndex
            while let r = seq.range(of: rc, range: idx..<seq.endIndex) {
                out.append(seq.distance(from: seq.startIndex, to: r.lowerBound))
                idx = seq.index(after: r.lowerBound)
            }
        }
        return out.sorted()
    }
}

