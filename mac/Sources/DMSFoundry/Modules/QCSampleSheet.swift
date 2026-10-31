import Foundation
import DMSEngine

/// 样本表：sample,sublibrary,replicate,condition,r1,r2
struct ParsedSampleSheet {
    var samples: [QCSampleSpec]
    var issues: [SampleSheetIssue]
    var errors: [SampleSheetIssue] { issues.filter { $0.level == .error } }
    var warnings: [SampleSheetIssue] { issues.filter { $0.level == .warning } }
}

enum QCSampleSheet {
    static func parse(url: URL) throws -> ParsedSampleSheet {
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" }).map(String.init)
        guard let head = lines.first else { throw SequenceError.rangeOutOfBounds("样本表为空") }
        let cols = head.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        func idx(_ n: String) -> Int? { cols.firstIndex(of: n) }
        guard let si = idx("sample"), let subi = idx("sublibrary"), let r1i = idx("r1") else {
            throw SequenceError.rangeOutOfBounds("样本表需要列：sample,sublibrary,r1[,replicate,condition,r2]")
        }
        let repi = idx("replicate"), condi = idx("condition"), r2i = idx("r2")
        let i5i = idx("index5"), i3i = idx("index3")
        let dir = url.deletingLastPathComponent()
        var out: [QCSampleSpec] = []
        var names = Set<String>()
        for line in lines.dropFirst() {
            let c = line.split(separator: ",", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard c.count > max(si, subi, r1i), !c[si].isEmpty else { continue }
            guard names.insert(c[si]).inserted else {
                throw SequenceError.rangeOutOfBounds("样本名重复：\(c[si])")
            }
            let r1 = resolve(c[r1i], dir: dir)
            let r2 = (r2i.map { c.count > $0 ? c[$0] : "" } ?? "").isEmpty
                ? nil : resolve(c[r2i!], dir: dir)
            let i5 = i5i.map { c.count > $0 ? c[$0].uppercased() : "" } ?? ""
            let i3 = i3i.map { c.count > $0 ? c[$0].uppercased() : "" } ?? ""
            out.append(QCSampleSpec(name: c[si], sublibrary: c[subi],
                                    replicate: repi.flatMap { c.count > $0 ? Int(c[$0]) : nil } ?? 1,
                                    condition: condi.map { c.count > $0 ? c[$0] : "" } ?? "",
                                    r1: r1, r2: r2,
                                    index5: i5.isEmpty ? nil : i5,
                                    index3: i3.isEmpty ? nil : i3))
        }
        guard !out.isEmpty else { throw SequenceError.rangeOutOfBounds("样本表没有数据行") }
        for s in out {
            guard FileManager.default.fileExists(atPath: s.r1) else {
                throw SequenceError.rangeOutOfBounds("找不到 FASTQ：\(s.r1)")
            }
            if let r2 = s.r2, !FileManager.default.fileExists(atPath: r2) {
                throw SequenceError.rangeOutOfBounds("找不到 FASTQ：\(r2)")
            }
        }
        let issues = SampleSheetValidator.validate(out)
        return ParsedSampleSheet(samples: out, issues: issues)
    }

    private static func resolve(_ p: String, dir: URL) -> String {
        if p.hasPrefix("/") { return p }
        return dir.appendingPathComponent(p).standardizedFileURL.path
    }
}
