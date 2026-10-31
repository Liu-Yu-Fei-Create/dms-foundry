import Foundation

public enum Exporter {

    public struct ExportResult: Sendable {
        public var files: [URL]
        public var directory: URL
    }

    public static func write(library: GeneratedLibrary,
                             project: Project,
                             generatedAt: Date = Date(),
                             store: ProjectStore = .shared) throws -> ExportResult {
        let fm = FileManager.default
        let stamp = ISO8601DateFormatter().string(from: generatedAt)
            .replacingOccurrences(of: ":", with: "-")
        let dir = store.projectDir(project.id)
            .appendingPathComponent("exports/\(stamp)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let orderURL = dir.appendingPathComponent("order.csv")
        let auditURL = dir.appendingPathComponent("audit.csv")
        let fastaURL = dir.appendingPathComponent("library.fasta")
        let manifestURL = dir.appendingPathComponent("manifest.json")

        try csv(orderHeader, library.oligos.map(orderRow)).write(to: orderURL, atomically: true, encoding: .utf8)
        try csv(auditHeader, library.oligos.map(auditRow)).write(to: auditURL, atomically: true, encoding: .utf8)

        let fasta = library.oligos.map { ">\($0.name) \($0.subID) len=\($0.sequence.count)\n\(wrap($0.sequence))" }
            .joined(separator: "\n")
        try fasta.write(to: fastaURL, atomically: true, encoding: .utf8)

        let manifest = Manifest(
            engineVersion: Version.engine,
            appVersion: Version.app,
            project: project.name,
            host: project.host,
            generatedAt: generatedAt,
            seed: project.libraryParams.seed,
            codonTable: project.libraryParams.codonTable.rawValue,
            enzyme: project.assembly.enzyme,
            stepNt: project.libraryParams.stepNt,
            counts: library.summary,
            coverageGaps: library.coverage.filter { $0.actual < $0.expected }
                .map { ["position": $0.position, "expected": $0.expected, "actual": $0.actual] },
            issues: library.issues.map { ["severity": $0.severity.rawValue, "code": $0.code, "message": $0.message] },
            notes: ["geometry": "识别位点在插入片段外侧，中间为酶 spacer；序列为设计稿，下单前请按当前克隆方案核对接头几何"]
        )
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(manifest).write(to: manifestURL)

        return ExportResult(files: [orderURL, auditURL, fastaURL, manifestURL], directory: dir)
    }

    // MARK: 列定义

    static let orderHeader = ["pool", "name", "sequence", "length", "gc", "enzyme", "overhang5", "overhang3"]
    static let auditHeader = ["pool", "name", "sequence", "length", "gc", "enzyme",
                              "index5_id", "index5", "index3_id", "index3",
                              "overhang5", "overhang3", "mutation_aa", "codon", "source",
                              "errors", "warnings"]

    static func orderRow(_ o: OligoRecord) -> [String] {
        [o.subID, o.name, o.sequence, "\(o.sequence.count)",
         String(format: "%.3f", Seq.gc(o.sequence)), o.enzymeName, o.overhang5, o.overhang3]
    }

    static func auditRow(_ o: OligoRecord) -> [String] {
        let errors = o.issues.filter { $0.severity == .error }.map(\.code).joined(separator: ";")
        let warnings = o.issues.filter { $0.severity == .warning }.map(\.code).joined(separator: ";")
        return [o.subID, o.name, o.sequence, "\(o.sequence.count)",
                String(format: "%.3f", Seq.gc(o.sequence)), o.enzymeName,
                o.index5ID, o.index5, o.index3ID, o.index3,
                o.overhang5, o.overhang3, o.mutationAA, o.codon, o.source,
                errors, warnings]
    }

    static func csv(_ header: [String], _ rows: [[String]]) -> String {
        let head = header.joined(separator: ",")
        let body = rows.map { row in
            row.map { field in
                field.contains(",") || field.contains("\"")
                    ? "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\"" : field
            }.joined(separator: ",")
        }.joined(separator: "\n")
        return "\u{FEFF}" + head + "\n" + body + "\n"
    }

    static func wrap(_ s: String, width: Int = 60) -> String {
        stride(from: 0, to: s.count, by: width).map { i -> String in
            let a = s.index(s.startIndex, offsetBy: i)
            let b = s.index(a, offsetBy: min(width, s.count - i))
            return String(s[a..<b])
        }.joined(separator: "\n")
    }

    struct Manifest: Codable {
        var engineVersion: String
        var appVersion: String
        var project: String
        var host: String
        var generatedAt: Date
        var seed: UInt64
        var codonTable: String
        var enzyme: String
        var stepNt: Int
        var counts: [String: Int]
        var coverageGaps: [[String: Int]]
        var issues: [[String: String]]
        var notes: [String: String]
    }
}

public enum Version {
    public static let engine = "0.3.0"
    public static let app = "0.3.0"
}

extension OligoRecord {
    var enzymeName: String {
        issues.first { $0.code.hasPrefix("oligo.internal") }?.message.components(separatedBy: " ").first ?? ""
    }
}
