import Foundation

public enum GenBankParser {

    public static func parse(contents: String) throws -> Plasmid {
        let lines = contents.components(separatedBy: .newlines)
        guard let locusIndex = lines.firstIndex(where: { $0.hasPrefix("LOCUS") }) else {
            throw SequenceError.emptySequence
        }
        let locus = lines[locusIndex].split(whereSeparator: { $0 == " " })
        let name = locus.count > 1 ? String(locus[1]) : "未命名质粒"
        let topology: Topology = lines[locusIndex].lowercased().contains("circular") ? .circular : .linear

        let features = parseFeatures(lines)
        let sequence = parseOrigin(lines)
        guard !sequence.isEmpty else { throw SequenceError.emptySequence }
        return Plasmid(name: name, sequence: sequence, topology: topology, features: features)
    }

    // MARK: FEATURES

    struct RawFeature { var key: String; var location: String; var qualifiers: [String: String] }

    static func parseFeatures(_ lines: [String]) -> [Feature] {
        guard let start = lines.firstIndex(where: { $0.hasPrefix("FEATURES") }) else { return [] }
        var raw: [RawFeature] = []
        var current: RawFeature?

        for line in lines[(start + 1)...] {
            if line.hasPrefix("ORIGIN") || line.hasPrefix("BASE COUNT") || line.hasPrefix("//") { break }
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }

            let leading = line.prefix(while: { $0 == " " }).count
            if leading == 5 {
                if let c = current { raw.append(c) }
                let rest = line.dropFirst(5)
                let key = rest.prefix(while: { !$0.isWhitespace })
                let loc = rest.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
                current = RawFeature(key: String(key), location: loc, qualifiers: [:])
            } else if leading >= 21, var c = current {
                let body = line.dropFirst(21)
                if body.hasPrefix("/") {
                    let q = body.dropFirst()
                    if let eq = q.firstIndex(of: "=") {
                        let k = String(q[..<eq])
                        var v = String(q[q.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                        if v.hasPrefix("\"") {
                            v = v.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                        }
                        c.qualifiers[k] = v
                    } else {
                        c.qualifiers[String(q)] = ""
                    }
                    current = c
                } else {
                    c.location += body.trimmingCharacters(in: .whitespaces)
                    current = c
                }
            }
        }
        if let c = current { raw.append(c) }

        return raw.compactMap { toFeature($0) }
    }

    static func toFeature(_ r: RawFeature) -> Feature? {
        guard let loc = LocationParser.parse(r.location) else { return nil }
        let type = mapType(r.key, gene: r.qualifiers["gene"] ?? r.qualifiers["product"] ?? "")
        let label = r.qualifiers["label"] ?? r.qualifiers["gene"] ?? r.qualifiers["product"] ?? type.zh
        let codonStart = Int(r.qualifiers["codon_start"] ?? "1") ?? 1
        let table = Int(r.qualifiers["transl_table"] ?? "11") ?? 11
        return Feature(type: type, label: label,
                       start: loc.start, end: loc.end, strand: loc.strand,
                       subRanges: loc.subRanges, codonStart: codonStart,
                       translTable: table, source: .annotation)
    }

    static func mapType(_ key: String, gene: String) -> FeatureType {
        switch key.uppercased() {
        case "CDS": return .cds
        case "PROMOTER": return .promoter
        case "TERMINATOR": return .terminator
        case "REP_ORIGIN", "ORIGIN": return .origin
        case "GENE": return .other
        default: break
        }
        let g = gene.uppercased()
        if ["AMPR", "KANR", "TETR", "BLA", "CAMR", "SPECR", "ZEO"].contains(where: { g.contains($0) }) { return .resistance }
        return .other
    }

    // MARK: ORIGIN

    static func parseOrigin(_ lines: [String]) -> String {
        guard let start = lines.firstIndex(where: { $0.hasPrefix("ORIGIN") }) else { return "" }
        var parts: [String] = []
        for line in lines[(start + 1)...] {
            if line.hasPrefix("//") { break }
            parts.append(line)
        }
        return Seq.sequence(from: parts)
    }
}

// MARK: - Location 解析

public struct ParsedLocation {
    public var start: Int
    public var end: Int
    public var strand: Strand
    public var subRanges: [IntRange]?
}

enum LocationParser {
    static func parse(_ raw: String) -> ParsedLocation? {
        var s = raw.replacingOccurrences(of: " ", with: "")
        guard !s.isEmpty else { return nil }
        var strand: Strand = .forward
        if s.hasPrefix("complement(") && s.hasSuffix(")") {
            strand = .reverse
            s = String(s.dropFirst("complement(".count).dropLast())
        }
        if s.hasPrefix("join(") && s.hasSuffix(")") {
            let inner = String(s.dropFirst("join(".count).dropLast())
            let parts = splitTopLevel(inner)
            let ranges = parts.compactMap { parseSimple($0) }
            guard !ranges.isEmpty else { return nil }
            let start = ranges.map(\.start).min() ?? 0
            let end = ranges.map(\.end).max() ?? 0
            let merged = ranges.count > 1 ? ranges : nil
            return ParsedLocation(start: start, end: end, strand: strand,
                                  subRanges: strand == .reverse ? merged?.reversed() : merged)
        }
        guard let r = parseSimple(s) else { return nil }
        return ParsedLocation(start: r.start, end: r.end, strand: strand, subRanges: nil)
    }

    static func parseSimple(_ s: String) -> IntRange? {
        let cleaned = s.replacingOccurrences(of: "<", with: "").replacingOccurrences(of: ">", with: "")
        if cleaned.contains("..") {
            let p = cleaned.components(separatedBy: "..")
            guard p.count == 2, let a = Int(p[0]), let b = Int(p[1]) else { return nil }
            return IntRange(a - 1, b)
        }
        guard let a = Int(cleaned) else { return nil }
        return IntRange(a - 1, a)
    }

    static func splitTopLevel(_ s: String) -> [String] {
        var out: [String] = [], depth = 0, cur = ""
        for ch in s {
            if ch == "(" { depth += 1 }
            if ch == ")" { depth -= 1 }
            if ch == "," && depth == 0 { out.append(cur); cur = "" }
            else { cur.append(ch) }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }
}
