import Foundation

public struct OligoRecord: Codable, Identifiable, Sendable {
    public var id: String
    public var subID: String
    public var name: String
    public var sequence: String
    public var index5ID: String
    public var index5: String
    public var index3ID: String
    public var index3: String
    public var overhang5: String
    public var overhang3: String
    public var mutationAA: String
    public var codon: String
    public var source: String
    public var issues: [QCIssue]
}

public struct CoverageRow: Codable, Sendable {
    public var position: Int
    public var expected: Int
    public var actual: Int
    public var sources: [String: Int]
}

public struct GeneratedLibrary: Codable, Sendable {
    public var oligos: [OligoRecord]
    public var regionOligos: [OligoRecord]
    public var coverage: [CoverageRow]
    public var issues: [QCIssue]
    public var summary: [String: Int]
}

public enum LibraryGenerator {

    public static func generate(project: Project,
                                design: DesignResult,
                                indices: IndexFile,
                                indexAssignments: [IndexAssignment],
                                enzymes: EnzymeTable) throws -> GeneratedLibrary {
        guard let plasmid = project.plasmid, let target = project.target,
              let feature = plasmid.features.first(where: { $0.id == target.featureID }) else {
            throw SequenceError.rangeOutOfBounds("缺少质粒或目标")
        }
        let table = try CodonTable.load(project.libraryParams.codonTable)
        let ctx = CodingContext(plasmid: plasmid, feature: feature, coding: project.refinedCoding)
        let coding = Array(ctx.coding.uppercased())
        let enzymeName = project.assembly.enzyme
        let spec = enzymes.enzymes[enzymeName]
        let assignments = Dictionary(uniqueKeysWithValues: indexAssignments.map { ($0.subID, $0) })

        var issues: [QCIssue] = []
        var oligos: [OligoRecord] = []

        // 设计变体 + 质检变体，按子库归类
        let allVariants = design.designVariants + design.qcVariants
        for sub in design.sublibraries {
            guard let assign = assignments[sub.id] else {
                issues.append(QCIssue("gen.no-index", .error, "\(sub.id) 没有分配到 index"))
                continue
            }
            let blockOffset = max(0, feature.codonStart - 1) + (sub.aaStart - 1) * 3
            let blockLen = (sub.aaEnd - sub.aaStart + 1) * 3
            guard blockOffset + blockLen <= coding.count else { continue }
            let block = Array(coding[blockOffset..<(blockOffset + blockLen)])

            for v in allVariants where v.position >= sub.aaStart && v.position <= sub.aaEnd {
                var insert = block
                let rel = (v.position - sub.aaStart) * 3
                if rel + 3 <= insert.count {
                    insert.replaceSubrange(rel..<(rel + 3), with: Array(v.codon))
                }
                let rec = assemble(id: v.id, sub: sub, insert: String(insert),
                                   assign: assign, enzyme: spec, enzymeName: enzymeName,
                                   mutationAA: "\(v.wt)→\(v.mut)", codon: v.codon, source: v.source.rawValue,
                                   table: table)
                oligos.append(rec)
            }

            for rv in design.regionVariants where rv.subID == sub.id {
                let rec = assemble(id: rv.id, sub: sub, insert: rv.sequence,
                                   assign: assign, enzyme: spec, enzymeName: enzymeName,
                                   mutationAA: "random-region", codon: "—", source: "randomRegion",
                                   table: table)
                oligos.append(rec)
            }
        }

        // 覆盖对账：按位点统计
        var coverage: [CoverageRow] = []
        let expectedPerPos = expectedCount(project: project, design: design)
        for pos in target.aaStart...target.aaEnd {
            let here = allVariants.filter { $0.position == pos }
            var sources: [String: Int] = [:]
            for v in here { sources[v.source.rawValue, default: 0] += 1 }
            coverage.append(CoverageRow(position: pos,
                                        expected: expectedPerPos,
                                        actual: here.count,
                                        sources: sources))
        }

        // 全局问题
        let dupes = Dictionary(grouping: oligos, by: \.sequence).filter { $0.value.count > 1 }
        if !dupes.isEmpty {
            issues.append(QCIssue("gen.duplicate", .error, "\(dupes.count) 条 oligo 序列重复"))
        }
        let blocked = oligos.filter { $0.issues.contains { $0.severity == .error } }
        if !blocked.isEmpty {
            issues.append(QCIssue("gen.blocked", .error, "\(blocked.count) 条 oligo 有阻断级问题"))
        }

        let summary = [
            "oligos": oligos.count,
            "sublibraries": design.sublibraries.count,
            "errors": oligos.filter { $0.issues.contains { $0.severity == .error } }.count,
            "warnings": oligos.filter { $0.issues.contains { $0.severity == .warning } }.count,
            "coverageGaps": coverage.filter { $0.actual < $0.expected }.count,
        ]
        return GeneratedLibrary(oligos: oligos, regionOligos: [], coverage: coverage,
                                issues: issues, summary: summary)
    }

    static func expectedCount(project: Project, design: DesignResult) -> Int {
        // 设计阶段每个位点的期望变体数：按允许的替换集合估算
        let base = project.libraryParams.mutationMode == .all ? 19 : project.libraryParams.allowedAA.count
        return base + (project.libraryParams.includeStop ? 1 : 0)
    }

    static func assemble(id: String, sub: SubLibrary, insert: String,
                         assign: IndexAssignment, enzyme: EnzymeSpec?,
                         enzymeName: String, mutationAA: String, codon: String,
                         source: String, table: CodonTable) -> OligoRecord {
        var seq = ""
        var issues: [QCIssue] = []
        if let e = enzyme {
            let spacerCount = e.spacer
            let filler = "CGATCG"
            seq = assign.index5.seq + filler
                + e.recognition.uppercased() + String(repeating: "A", count: spacerCount)
                + insert
                + String(repeating: "A", count: spacerCount)
                + Seq.reverseComplement(e.recognition.uppercased()) + filler
                + assign.index3.seq

            let hits = EnzymeScanner.scan(seq, name: enzymeName, enzyme: e)
            let insertStart = assign.index5.seq.count + filler.count + e.recognition.count + spacerCount
            let insertEnd = insertStart + insert.count
            for h in hits where h.start >= insertStart && h.start < insertEnd {
                issues.append(QCIssue("oligo.internal-site", .error,
                                      "\(enzymeName) 位点落在突变区内（\(h.start)）"))
            }
        } else {
            seq = assign.index5.seq + insert + assign.index3.seq
            issues.append(QCIssue("oligo.no-enzyme", .warning, "找不到酶 \(enzymeName)，未加组装接头"))
        }

        if seq.count > LengthBudget.vendorMax {
            issues.append(QCIssue("oligo.too-long", .error, "长度 \(seq.count) nt 超过合成上限"))
        }
        if seq.count < 60 {
            issues.append(QCIssue("oligo.too-short", .error, "长度 \(seq.count) nt 过短"))
        }
        let gc = Seq.gc(seq)
        if gc < 0.3 || gc > 0.7 {
            issues.append(QCIssue("oligo.gc", .warning, String(format: "GC %.2f 超出 0.30–0.70", gc)))
        }
        if Seq.longestHomopolymer(seq) >= 6 {
            issues.append(QCIssue("oligo.homopolymer", .warning, "存在 ≥6 的同聚物"))
        }

        let name = sanitize("\(sub.id)-\(id)")
        return OligoRecord(id: id, subID: sub.id, name: name, sequence: seq,
                           index5ID: assign.index5.id, index5: assign.index5.seq,
                           index3ID: assign.index3.id, index3: assign.index3.seq,
                           overhang5: String(insert.prefix(4)),
                           overhang3: String(insert.suffix(4)),
                           mutationAA: mutationAA, codon: codon, source: source, issues: issues)
    }

    static func sanitize(_ s: String) -> String {
        let ok = s.uppercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }
        return String(String.UnicodeScalarView(ok)).prefix(25).description
    }
}
