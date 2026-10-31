import Foundation

/// SnapGene .dna 最小解析器：文档头 + 块（0 = DNA，10 = features XML）
public enum SnapGeneParser {

    enum ParseError: Error, LocalizedError {
        case badHeader, badDocument, truncated
        var errorDescription: String? {
            switch self {
            case .badHeader: return "不是 SnapGene .dna 文件（文件头不匹配）"
            case .badDocument: return ".dna 文档属性块不完整"
            case .truncated: return ".dna 文件被截断"
            }
        }
    }

    public static func parse(data: Data) throws -> Plasmid {
        var i = data.startIndex
        func need(_ n: Int) throws {
            guard data.distance(from: i, to: data.endIndex) >= n else { throw ParseError.truncated }
        }
        func u8() throws -> UInt8 { try need(1); defer { i = data.index(after: i) }; return data[i] }
        func u16() throws -> UInt16 {
            try need(2); defer { i = data.index(i, offsetBy: 2) }
            return UInt16(data[i]) << 8 | UInt16(data[i + 1])
        }
        func u32() throws -> UInt32 {
            try need(4); defer { i = data.index(i, offsetBy: 4) }
            return (UInt32(data[i]) << 24) | (UInt32(data[i + 1]) << 16) | (UInt32(data[i + 2]) << 8) | UInt32(data[i + 3])
        }
        func bytes(_ n: Int) throws -> Data {
            try need(n); defer { i = data.index(i, offsetBy: n) }
            return data[i..<data.index(i, offsetBy: n)]
        }

        guard try u8() == 0x09 else { throw ParseError.badHeader }
        guard try u32() == 14 else { throw ParseError.badDocument }
        guard String(data: try bytes(8), encoding: .ascii) == "SnapGene" else { throw ParseError.badDocument }
        _ = try u16()   // isDNA
        _ = try u16()   // exportVersion
        _ = try u16()   // importVersion

        var sequence = ""
        var topology: Topology = .circular
        var features: [Feature] = []
        var sawSequence = false

        while i < data.endIndex {
            let type = try u8()
            let size = Int(try u32())
            let payload = try bytes(size)
            switch type {
            case 0:
                guard let first = payload.first else { break }
                topology = (first & 0x01) != 0 ? .circular : .linear
                let seq = String(decoding: payload.dropFirst(), as: UTF8.self)
                sequence = Seq.sequence(from: [seq])
                sawSequence = true
            case 10:
                features = SnapGeneFeatureXML.parse(payload)
            default:
                break
            }
        }
        guard sawSequence, !sequence.isEmpty else { throw ParseError.truncated }
        return Plasmid(name: "SnapGene 质粒", sequence: sequence, topology: topology, features: features)
    }
}

// MARK: - features XML

final class SnapGeneFeatureXML: NSObject, XMLParserDelegate {
    private struct Raw {
        var name = ""; var type = ""; var directionality = "0"
        var ranges: [(Int, Int)] = []
        var color: String?
    }
    private var raws: [Raw] = []
    private var current: Raw?
    private var segmentRange: String?
    private var segmentColor: String?

    static func parse(_ data: Data) -> [Feature] {
        let d = SnapGeneFeatureXML()
        let parser = XMLParser(data: data)
        parser.delegate = d
        parser.parse()
        return d.raws.compactMap { r -> Feature? in
            guard !r.ranges.isEmpty else { return nil }
            let start = (r.ranges.map(\.0).min() ?? 1) - 1
            let end = r.ranges.map(\.1).max() ?? start
            let strand: Strand = r.directionality == "2" ? .reverse : .forward
            let mapped = mapType(r.type, name: r.name)
            let subs = r.ranges.count > 1
                ? r.ranges.map { IntRange($0.0 - 1, $0.1) }
                : nil
            return Feature(type: mapped, label: r.name.isEmpty ? mapped.zh : r.name,
                           start: start, end: max(end, start + 1), strand: strand,
                           subRanges: subs, codonStart: 1, translTable: 11, source: .annotation)
        }
    }

    static func mapType(_ raw: String, name: String) -> FeatureType {
        switch raw.uppercased() {
        case "CDS": return .cds
        case "PROMOTER": return .promoter
        case "TERMINATOR": return .terminator
        case "REP_ORIGIN", "ORIGIN": return .origin
        default: break
        }
        let n = name.uppercased()
        if ["AMPR", "KANR", "TETR", "BLA", "CAMR", "ZEO", "SPECR"].contains(where: { n.contains($0) }) {
            return .resistance
        }
        return .other
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if elementName == "Feature" {
            var r = Raw()
            r.name = attributeDict["name"] ?? ""
            r.type = attributeDict["type"] ?? ""
            r.directionality = attributeDict["directionality"] ?? "0"
            current = r
        } else if elementName == "Segment" {
            segmentRange = attributeDict["range"]
            segmentColor = attributeDict["color"]
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "Segment", var c = current, let r = segmentRange {
            let parts = r.split(separator: "-").compactMap { Int($0) }
            if parts.count == 2 {
                c.ranges.append((min(parts[0], parts[1]), max(parts[0], parts[1])))
                c.color = c.color ?? segmentColor
            }
            current = c
            segmentRange = nil; segmentColor = nil
        } else if elementName == "Feature", let c = current {
            raws.append(c); current = nil
        }
    }
}
