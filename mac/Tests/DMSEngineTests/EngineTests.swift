import XCTest
@testable import DMSEngine

final class EngineTests: XCTestCase {

    let seq90 = "ATGGCTGCTGCTGCTGCTGCTGCTGCTGCT"   // 1..30  CDS1 (+)
              + "GATCGATCGATCGATCGATCGATCGATCGA"   // 31..60 spacer
              + "TTAGGCCTAGGCCTAGGCCTAGGCCTAGGC"   // 61..90 CDS2 (−)

    func plasmid() -> (Plasmid, Feature, Feature) {
        let f1 = Feature(type: .cds, label: "fwd", start: 0, end: 30)
        let f2 = Feature(type: .cds, label: "rev", start: 60, end: 90, strand: .reverse)
        return (Plasmid(name: "t", sequence: seq90, features: [f1, f2]), f1, f2)
    }

    // MARK: 坐标

    func testForwardRange() throws {
        let (_, f1, _) = plasmid()
        let r = try Coordinates.cdsRange(feature: f1, aaStart: 1, aaEnd: 10)
        XCTAssertEqual(r.start, 0); XCTAssertEqual(r.end, 30); XCTAssertEqual(r.strand, .forward)
    }

    func testReverseRange() throws {
        let (_, _, f2) = plasmid()
        let r = try Coordinates.cdsRange(feature: f2, aaStart: 1, aaEnd: 10)
        XCTAssertEqual(r.start, 60); XCTAssertEqual(r.end, 90); XCTAssertEqual(r.strand, .reverse)
    }

    func testCodonStartTwo() throws {
        let f = Feature(type: .cds, label: "cs2", start: 0, end: 30, codonStart: 2)
        XCTAssertEqual(f.codonCount, 9)
        let r = try Coordinates.cdsRange(feature: f, aaStart: 1, aaEnd: 9)
        XCTAssertEqual(r.start, 1); XCTAssertEqual(r.end, 28)
    }

    func testOutOfBounds() {
        let (_, f1, _) = plasmid()
        XCTAssertThrowsError(try Coordinates.cdsRange(feature: f1, aaStart: 1, aaEnd: 99))
    }

    // MARK: 解析

    func testFasta() throws {
        let p = try FastaParser.parse(contents: ">my plasmid\nATG GCT\nGCT\n")
        XCTAssertEqual(p.name, "my plasmid")
        XCTAssertEqual(p.sequence, "ATGGCTGCT")
    }

    func testGenBank() throws {
        let origin = stride(from: 0, to: seq90.count, by: 10).map { i -> String in
            let a = seq90.index(seq90.startIndex, offsetBy: i)
            let b = seq90.index(a, offsetBy: 10)
            return String(format: "%9d %@", i + 1, String(seq90[a..<b]))
        }.joined(separator: "\n")

        let gb = """
        LOCUS       demo        90 bp    DNA     circular
        FEATURES             Location/Qualifiers
             CDS             1..30
                             /gene="fwd"
                             /codon_start=1
             CDS             complement(61..90)
                             /gene="rev"
                             /transl_table=11
        ORIGIN
        \(origin)
        //
        """
        let p = try GenBankParser.parse(contents: gb)
        XCTAssertEqual(p.sequence.count, 90)
        XCTAssertEqual(p.topology, .circular)
        XCTAssertEqual(p.features.count, 2)
        XCTAssertEqual(p.features[0].strand, .forward)
        XCTAssertEqual(p.features[1].strand, .reverse)
        XCTAssertEqual(p.features[1].start, 60)
        XCTAssertEqual(p.features[1].end, 90)
    }

    /// TEM-1 成熟蛋白 263 aa：用最优密码子回译后，全位点枚举应恰好 4,997 条（263 × 19）
    func testTEM1FullEnumeration() throws {
        let tem1 = "HPETLVKVKDAEDQLGARVGYIELDLNSGKILESFRPEERFPMMSTFKVLLCGAVLSRVDAGQEQLGRRIHYSQNDLVEYSPVTEKH"
                 + "LTDGMTVRELCSAAITMSDNTAANLLLTTIGGPKELTAFLHNMGDHVTRLDRWEPELNEAIPNDERDTTMPAAMATTLRKLLTGEL"
                 + "LTLASRQQLIDWMEADKVAGPLLRSALPAGWFIADKSGAGERGSRGIIAALGPDGKPSRIVVIYTTGSQATMDERNRQIAEIGAS"
                 + "LIKHW"
        let table = try CodonTable.load(.ecoli)
        var dna = ""
        for aa in tem1 {
            guard let codon = table.optimal(for: String(aa)) else { return XCTFail("无密码子 \(aa)") }
            dna += codon
        }
        XCTAssertEqual(tem1.count, 263)
        XCTAssertEqual(dna.count, 789)
        let f = Feature(type: .cds, label: "TEM-1", start: 0, end: dna.count)
        let plasmid = Plasmid(name: "TEM-1", sequence: dna, features: [f])
        let ctx = CodingContext(plasmid: plasmid, feature: f)
        XCTAssertEqual(ctx.codonCount, 263)
        let vars = try MutationEnumerator.enumerate(context: ctx, range: 1...263,
                                                    params: LibraryParams(), table: table, seed: 1)
        XCTAssertEqual(vars.count, 263 * 19)
        XCTAssertEqual(Set(vars.map(\.id)).count, vars.count)   // 无重复
    }

    // MARK: 密码子表

    func testCodonTableLoads() throws {
        let t = try CodonTable.load(.ecoli)
        XCTAssertEqual(t.file.codons.count, 64)
        XCTAssertNotNil(t.optimal(for: "M"))
        XCTAssertEqual(t.aminoAcid(for: "TAA"), "*")
    }

    // MARK: 枚举

    func testEnumeratesAllSubstitutions() throws {
        let (p, f1, _) = plasmid()
        let ctx = CodingContext(plasmid: p, feature: f1)
        let table = try CodonTable.load(.ecoli)
        let vars = try MutationEnumerator.enumerate(context: ctx, range: 1...1,
                                                    params: LibraryParams(), table: table, seed: 1)
        XCTAssertEqual(vars.count, 19)   // 1 个位点 × 19 种替换
        XCTAssertTrue(vars.allSatisfy { $0.source == .design })
    }

    func testStopIncluded() throws {
        let (p, f1, _) = plasmid()
        let ctx = CodingContext(plasmid: p, feature: f1)
        let table = try CodonTable.load(.ecoli)
        var params = LibraryParams(); params.includeStop = true
        let vars = try MutationEnumerator.enumerate(context: ctx, range: 1...1, params: params, table: table, seed: 1)
        XCTAssertEqual(vars.count, 20)
        XCTAssertTrue(vars.contains { $0.mut == "*" && $0.codon == "TAA" })
    }

    func testDeterminism() throws {
        let (p, f1, _) = plasmid()
        let ctx = CodingContext(plasmid: p, feature: f1)
        let table = try CodonTable.load(.ecoli)
        let a = try MutationEnumerator.enumerate(context: ctx, range: 1...10, params: LibraryParams(), table: table, seed: 42)
        let b = try MutationEnumerator.enumerate(context: ctx, range: 1...10, params: LibraryParams(), table: table, seed: 42)
        XCTAssertEqual(a.map(\.id), b.map(\.id))
    }

    // MARK: 切分与预算

    func testPartition263() {
        let subs = Partitioner.split(aaRange: 1...263, codonStart: 1, stepNt: 150)
        XCTAssertEqual(subs.count, 6)
        XCTAssertEqual(subs[0].aaStart, 1); XCTAssertEqual(subs[0].aaEnd, 50)
        XCTAssertEqual(subs[5].aaStart, 251); XCTAssertEqual(subs[5].aaEnd, 263)
        XCTAssertEqual(subs.reduce(0) { $0 + $1.ntLength }, 263 * 3)
    }

    func testLengthBudget() {
        XCTAssertEqual(LengthBudget.oligoLength(stepNt: 150, method: .goldenGate), 228)
        XCTAssertEqual(LengthBudget.oligoLength(stepNt: 150, method: .gibson), 240)
        XCTAssertTrue(LengthBudget.oligoLength(stepNt: 300, method: .goldenGate) > LengthBudget.vendorMax)
    }

    func testPRNGStreamsDiffer() {
        var a = SplitMix64.stream(seed: 7, purpose: "design")
        var b = SplitMix64.stream(seed: 7, purpose: "qc.stop")
        XCTAssertNotEqual(a.next(), b.next())
    }
}

// MARK: - M3：酶扫描 / overhang / 组装 / 质检项 / Refine

extension EngineTests {

    func tem1Plasmid() throws -> (Plasmid, Feature, CodonTable) {
        let tem1 = "HPETLVKVKDAEDQLGARVGYIELDLNSGKILESFRPEERFPMMSTFKVLLCGAVLSRVDAGQEQLGRRIHYSQNDLVEYSPVTEKH"
                 + "LTDGMTVRELCSAAITMSDNTAANLLLTTIGGPKELTAFLHNMGDHVTRLDRWEPELNEAIPNDERDTTMPAAMATTLRKLLTGEL"
                 + "LTLASRQQLIDWMEADKVAGPLLRSALPAGWFIADKSGAGERGSRGIIAALGPDGKPSRIVVIYTTGSQATMDERNRQIAEIGAS"
                 + "LIKHW"
        let table = try CodonTable.load(.ecoli)
        var dna = ""
        for aa in tem1 { dna += table.optimal(for: String(aa))! }
        // 两侧各加 60 nt 恒定侧翼，模拟真实质粒（用于 Gibson 同源臂）
        let up = "GATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATC"
        let down = "TAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGC"
        let full = up + dna + down
        let f = Feature(type: .cds, label: "TEM-1", start: up.count, end: up.count + dna.count)
        return (Plasmid(name: "TEM-1", sequence: full, features: [f]), f, table)
    }

    func testEnzymeScan() throws {
        let spec = try EnzymeTable.load().enzymes["BsaI"]!
        let hits = EnzymeScanner.scan("AAAGGTCTCAAA", name: "BsaI", enzyme: spec)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].start, 3)
        let rcHits = EnzymeScanner.scan("TTTGAGACCAAA", name: "BsaI", enzyme: spec)
        XCTAssertEqual(rcHits.count, 1)
        XCTAssertEqual(rcHits[0].strand, .reverse)
    }

    func testOverhangEvaluation() throws {
        let table = try OverhangTable.load()
        XCTAssertEqual(table.overhangs.count, 256)
        XCTAssertEqual(table.dataStatus, "measured")
        let pal = OverhangEvaluator.evaluate("GATC", table: table)
        XCTAssertTrue(pal.palindromic)
        XCTAssertEqual(pal.grade, .bad)
        let good = OverhangEvaluator.evaluate("AAAA", table: table)
        XCTAssertFalse(good.palindromic)
        XCTAssertEqual(good.grade, .good)
        XCTAssertNotNil(good.fidelity)
    }

    func testGoldenGatePlanTEM1() throws {
        let (plasmid, f, _) = try tem1Plasmid()
        let ctx = CodingContext(plasmid: plasmid, feature: f)
        let enzymes = try EnzymeTable.load()
        let oh = try OverhangTable.load()
        let plans = GoldenGatePlanner.plan(coding: ctx.coding, codonStart: 1,
                                           aaRange: 1...263, stepNt: 150,
                                           enzymeName: "BsaI", enzyme: enzymes.enzymes["BsaI"]!,
                                           overhangs: oh)
        XCTAssertEqual(plans.count, 6)
        // 覆盖必须连续且完整
        XCTAssertEqual(plans.first?.aaStart, 1)
        XCTAssertEqual(plans.last?.aaEnd, 263)
        for i in 1..<plans.count {
            XCTAssertEqual(plans[i].aaStart, plans[i - 1].aaEnd + 1, "子库之间不能有缺口或重叠")
        }
        XCTAssertEqual(plans.reduce(0) { $0 + ($1.aaEnd - $1.aaStart + 1) }, 263)
        for p in plans {
            XCTAssertEqual(p.overhang5.sequence.count, 4)
            XCTAssertEqual(p.overhang3.sequence.count, 4)
            // 回文接口允许出现（由 WT 序列决定），但必须被标成不可用
            if p.overhang5.palindromic || p.overhang3.palindromic {
                XCTAssertFalse(p.viable)
            }
        }
    }

    func testGibsonPlanTEM1() throws {
        let (plasmid, f, _) = try tem1Plasmid()
        let ctx = CodingContext(plasmid: plasmid, feature: f)
        let plans = GibsonPlanner.plan(coding: ctx.coding, codonStart: 1, aaRange: 1...263,
                                       stepNt: 150, flanks: ctx.flanks(60))
        XCTAssertEqual(plans.count, 6)
        XCTAssertEqual(plans[0].leftArm.count, 25)
        XCTAssertEqual(plans[0].rightArm.count, 25)
    }

    func testQCStopAndSynonymous() throws {
        let (plasmid, f, table) = try tem1Plasmid()
        let ctx = CodingContext(plasmid: plasmid, feature: f)
        var qc = QCOptions()
        qc.stop.enabled = true
        qc.stop.mode = .random
        qc.stop.count = 5
        qc.stop.aaRangeStart = 1
        qc.stop.aaRangeEnd = 20
        qc.synonymous.enabled = true
        qc.synonymous.mode = .random
        qc.synonymous.count = 4
        qc.synonymous.aaRangeStart = 1
        qc.synonymous.aaRangeEnd = 60

        let res = QCPlanner.plan(context: ctx, params: LibraryParams(), qc: qc, table: table,
                                 aaRange: 1...263,
                                 sublibraries: Partitioner.split(aaRange: 1...263, codonStart: 1, stepNt: 150),
                                 seed: 7, existingIDs: [])
        let stops = res.variants.filter { $0.source == .stopQC }
        XCTAssertEqual(stops.count, 5)
        XCTAssertTrue(stops.allSatisfy { $0.mut == "*" && $0.codon == "TAA" })
        let syn = res.variants.filter { $0.source == .synQC }
        XCTAssertLessThanOrEqual(syn.count, 4)
        XCTAssertTrue(syn.allSatisfy { $0.wt == $0.mut })
    }

    func testQCSkipWhenIncluded() throws {
        let (plasmid, f, table) = try tem1Plasmid()
        let ctx = CodingContext(plasmid: plasmid, feature: f)
        var params = LibraryParams(); params.includeStop = true
        var qc = QCOptions(); qc.stop.enabled = true
        let res = QCPlanner.plan(context: ctx, params: params, qc: qc, table: table,
                                 aaRange: 1...50,
                                 sublibraries: Partitioner.split(aaRange: 1...50, codonStart: 1, stepNt: 150),
                                 seed: 1, existingIDs: [])
        XCTAssertEqual(res.variants.count, 0)
        XCTAssertNotNil(res.skipped["stop"])
    }

    func testRefinerRemovesSite() throws {
        let table = try CodonTable.load(.ecoli)
        // GGT GCT GGTCTC ... 其中 GGTCTC 是 BsaI 位点；第一个 GGT (Gly) 可同义换成 GGC 破坏位点
        let coding = "GGT" + "GCT" + "GGTCTC"
        let res = Refiner.refine(coding: coding, codonStart: 1, allowedCodons: 1...3,
                                 motif: "GGTCTC", table: table)
        XCTAssertTrue(res.remainingSites.isEmpty, "应能通过同义替换消除 BsaI 位点")
        XCTAssertFalse(res.changes.isEmpty)
    }

    func testFullPipelineTEM1() throws {
        let (plasmid, f, _) = try tem1Plasmid()
        var project = Project(name: "t", host: "E. coli")
        project.plasmid = plasmid
        project.target = Target(featureID: f.id, aaStart: 1, aaEnd: 263)
        let res = try DesignPipeline.run(project: project)
        XCTAssertEqual(res.designVariants.count, 263 * 19)
        XCTAssertEqual(res.sublibraries.count, 6)
        XCTAssertEqual(res.ggPlans.count, 6)
        XCTAssertEqual(res.totalVariants, res.designVariants.count + res.qcVariants.count)
    }
}

// MARK: - M4：index 匹配 / 生成 / 导出

extension EngineTests {

    func testIndexAssignment() throws {
        let (plasmid, f, _) = try tem1Plasmid()
        var project = Project(name: "t", host: "E. coli")
        project.plasmid = plasmid
        project.target = Target(featureID: f.id, aaStart: 1, aaEnd: 263)
        let design = try DesignPipeline.run(project: project)
        let indices = try IndexFile.load()
        XCTAssertEqual(indices.count, 1024)
        let assigns = IndexMatcher.assign(sublibraries: design.sublibraries, indices: indices,
                                          plasmid: plasmid.sequence, seed: 1)
        XCTAssertEqual(assigns.count, design.sublibraries.count)
        let ids = assigns.flatMap { [$0.index5.id, $0.index3.id] }
        XCTAssertEqual(Set(ids).count, ids.count, "同一个 index 不能分配给两个子库")
        for a in assigns { XCTAssertLessThanOrEqual(a.tmDiff, 2.0) }
    }

    func testGenerateAndExport() throws {
        let (plasmid, f, _) = try tem1Plasmid()
        var project = Project(name: "gen-test", host: "E. coli")
        project.plasmid = plasmid
        project.target = Target(featureID: f.id, aaStart: 1, aaEnd: 263)
        let design = try DesignPipeline.run(project: project)
        let indices = try IndexFile.load()
        let enzymes = try EnzymeTable.load()
        let assigns = IndexMatcher.assign(sublibraries: design.sublibraries, indices: indices,
                                          plasmid: plasmid.sequence, seed: 1)
        let lib = try LibraryGenerator.generate(project: project, design: design,
                                                indices: indices, indexAssignments: assigns,
                                                enzymes: enzymes)
        XCTAssertEqual(lib.oligos.count, design.designVariants.count + design.qcVariants.count)
        XCTAssertEqual(Set(lib.oligos.map(\.sequence)).count, lib.oligos.count, "oligo 序列不能重复")
        for o in lib.oligos.prefix(200) {
            XCTAssertLessThanOrEqual(o.sequence.count, LengthBudget.vendorMax)
            XCTAssertTrue(o.sequence.hasPrefix(o.index5), "5′ index 必须在序列开头")
            XCTAssertTrue(o.sequence.hasSuffix(o.index3), "3′ index 必须在序列结尾")
        }

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ProjectStore(root: tmp)
        let res = try Exporter.write(library: lib, project: project, store: store)
        XCTAssertEqual(res.files.count, 4)
        for u in res.files { XCTAssertTrue(FileManager.default.fileExists(atPath: u.path), "缺文件 \(u.lastPathComponent)") }
        let orderData = try Data(contentsOf: res.files[0])
        XCTAssertEqual(Array(orderData.prefix(3)), [0xEF, 0xBB, 0xBF], "CSV 必须有 UTF-8 BOM")
        let order = String(decoding: orderData.dropFirst(3), as: UTF8.self)
        XCTAssertTrue(order.hasPrefix("pool,name,sequence"))
        let lines = order.split(separator: "\n")
        XCTAssertEqual(lines.count, lib.oligos.count + 1)
        let fasta = try String(contentsOf: res.files[2], encoding: .utf8)
        XCTAssertEqual(fasta.components(separatedBy: ">").count - 1, lib.oligos.count)
        try? FileManager.default.removeItem(at: tmp)
    }
}

// MARK: - SnapGene .dna

extension EngineTests {
    func makeDNA(sequence: String, circular: Bool, xml: String) -> Data {
        var d = Data()
        func be32(_ v: Int) { var x = UInt32(v).bigEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func be16(_ v: Int) { var x = UInt16(v).bigEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        d.append(0x09)
        be32(14)
        d.append(contentsOf: Array("SnapGene".utf8))
        be16(1); be16(1); be16(1)
        // DNA block
        var payload = Data([circular ? 0x01 : 0x00])
        payload.append(contentsOf: Array(sequence.utf8))
        d.append(0x00); be32(payload.count); d.append(payload)
        // features block
        let xmlData = Data(xml.utf8)
        d.append(0x0A); be32(xmlData.count); d.append(xmlData)
        return d
    }

    func testSnapGeneParse() throws {
        let seq = "ATGGCTGCTGCTGCTGCTGCTGCTGCTGCTGATCGATCGATCGATCGATCGA"
        let xml = """
        <Features>
          <Feature name="bla" type="CDS" directionality="1"><Segment range="1-30" color="#ff0000"/></Feature>
          <Feature name="promoter" type="promoter" directionality="2"><Segment range="31-51" color="#00ff00"/></Feature>
        </Features>
        """
        let data = makeDNA(sequence: seq, circular: true, xml: xml)
        let p = try SnapGeneParser.parse(data: data)
        XCTAssertEqual(p.sequence, seq)
        XCTAssertEqual(p.topology, .circular)
        XCTAssertEqual(p.features.count, 2)
        XCTAssertEqual(p.features[0].type, .cds)
        XCTAssertEqual(p.features[0].label, "bla")
        XCTAssertEqual(p.features[0].start, 0)
        XCTAssertEqual(p.features[0].end, 30)
        XCTAssertEqual(p.features[0].strand, .forward)
        XCTAssertEqual(p.features[1].type, .promoter)
        XCTAssertEqual(p.features[1].start, 30)
        XCTAssertEqual(p.features[1].end, 51)
        XCTAssertEqual(p.features[1].strand, .reverse)
    }

    func testSnapGeneBadHeader() {
        XCTAssertThrowsError(try SnapGeneParser.parse(data: Data("not a dna".utf8)))
    }
}

// MARK: - QC engine

extension EngineTests {
    func writeFastq(_ records: [(String, String)], to url: URL) throws {
        var s = ""
        for (i, r) in records.enumerated() {
            s += "@read\(i)\n\(r.1)\n+\n\(String(repeating: "I", count: r.1.count))\n"
        }
        try s.write(to: url, atomically: true, encoding: .utf8)
    }

    func testFastqReaderAndGzip() throws {
        let dir = FileManager.default.temporaryDirectory
        let plain = dir.appendingPathComponent("qc_test.fastq")
        try writeFastq([("x", "ACGTACGTAC"), ("y", "TTTTGGGGCC")], to: plain)

        let reader = try FastqReader(url: plain)
        var seqs: [String] = []
        while let r = try reader.next() { seqs.append(r.sequence) }
        XCTAssertEqual(seqs, ["ACGTACGTAC", "TTTTGGGGCC"])

        // gzip 版本
        let gz = dir.appendingPathComponent("qc_test.fastq.gz")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        p.arguments = ["-c", plain.path]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        try pipe.fileHandleForReading.readToEnd()?.write(to: gz)
        let gzReader = try FastqReader(url: gz)
        var gzSeqs: [String] = []
        while let r = try gzReader.next() { gzSeqs.append(r.sequence) }
        XCTAssertEqual(gzSeqs, ["ACGTACGTAC", "TTTTGGGGCC"])
    }

    func makeQCDesign() -> QCDesign {
        let ref = "ATGGCTGCTGCTGCTGCTGCTGCTGCTGCTG"   // 30 nt, 10 codons
        let variants = [
            QCVariant(id: "V1", sublibrary: "SL01", position: 1, wtCodon: "ATG", mutCodon: "GTG", aaChange: "M1V"),
            QCVariant(id: "V2", sublibrary: "SL01", position: 3, wtCodon: "GCT", mutCodon: "GAT", aaChange: "A3D"),
            QCVariant(id: "V3", sublibrary: "SL02", position: 5, wtCodon: "GCT", mutCodon: "CCT", aaChange: "A5P"),
            QCVariant(id: "V4", sublibrary: "SL02", position: 7, wtCodon: "GCT", mutCodon: "TCT", aaChange: "A7S"),
        ]
        return QCDesign(reference: ref, anchor5: "ACGTACGT", variants: variants)
    }

    func testQCCounting() {
        let design = makeQCDesign()
        var ref = Array(design.reference)
        // 造两条 V1 突变 reads
        var v1 = ref; v1[0] = "G"; v1[1] = "T"; v1[2] = "G"
        // 造一条 V2 突变 reads
        var v2 = ref; v2[6] = "G"; v2[7] = "A"; v2[8] = "T"
        let reads = [
            FastqRecord(name: "a", sequence: "ACGTACGT" + String(v1), quality: ""),
            FastqRecord(name: "b", sequence: "ACGTACGT" + String(v1), quality: ""),
            FastqRecord(name: "c", sequence: "ACGTACGT" + String(v2), quality: ""),
            FastqRecord(name: "d", sequence: "ACGTACGT" + String(ref), quality: ""),
        ]
        let result = QCCounter.count(reads: reads, design: design)
        XCTAssertEqual(result.totalReads, 4)
        XCTAssertEqual(result.anchoredReads, 4)
        XCTAssertEqual(result.counts["V1"], 2)
        XCTAssertEqual(result.counts["V2"], 1)
        XCTAssertEqual(result.spectrum.wildType, 1)

        let rows = QCReport.rows(result)
        let summary = QCReport.summarize(result, rows: rows)
        XCTAssertEqual(summary.designedVariants, 4)
        XCTAssertEqual(summary.observedVariants, 2)
        XCTAssertEqual(summary.zeroCount, 2)
        XCTAssertEqual(summary.verdict, "fail")
        XCTAssertTrue(QCReport.rowsCSV(rows).hasPrefix("variant_id,sublibrary"))
    }

    func testQCGiniAndMedian() {
        XCTAssertEqual(QCReport.medianValue([1, 2, 3]), 2)
        XCTAssertEqual(QCReport.medianValue([1, 2, 3, 4]), 2.5)
        XCTAssertEqual(QCReport.gini([10, 10, 10, 10]), 0, accuracy: 1e-9)
        XCTAssertGreaterThan(QCReport.gini([0, 0, 0, 100]), 0.5)
    }
}

// MARK: - Analysis engine

extension EngineTests {
    func testLog2RatioAndMerge() {
        let e = AnalysisEngine.log2Ratio(selected: 1000, input: 500,
                                         selectedTotal: 1_000_000, inputTotal: 1_000_000)
        XCTAssertEqual(e.effect, log2(1000.5 / 500.5), accuracy: 1e-9)
        XCTAssertEqual(e.se, sqrt((1.0/1000.5 + 1.0/500.5) / pow(log(2), 2)), accuracy: 1e-9)

        let m = AnalysisEngine.merge([(1.0, 0.1), (1.0, 0.2)])
        XCTAssertEqual(m.effect, 1.0, accuracy: 1e-9)
        XCTAssertEqual(m.se, 1.0 / sqrt(100 + 25), accuracy: 1e-9)
    }

    func testAnalysisRun() {
        let variants = ["V1", "V2", "S1", "S2", "S3"]
        func sample(_ name: String, _ cond: String, _ rep: Int, _ counts: [String: Int]) -> CountsSample {
            CountsSample(name: name, condition: cond, replicate: rep,
                         sublibrary: "SL01", counts: counts)
        }
        var ins: [CountsSample] = []
        var sels: [CountsSample] = []
        for rep in 1...3 {
            ins.append(sample("in\(rep)", "input", rep,
                              ["V1": 100, "V2": 100, "S1": 1000, "S2": 1000, "S3": 1000]))
            sels.append(sample("sel\(rep)", "selected", rep,
                               ["V1": 400, "V2": 100, "S1": 900, "S2": 900, "S3": 900]))
        }
        let rows = AnalysisEngine.run(samples: ins + sels, variants: variants,
                                      synonymous: ["S1", "S2", "S3"])
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.variant, $0) })
        XCTAssertEqual(byID["V1"]!.effect, log2(400.5 / 100.5), accuracy: 1e-6)
        XCTAssertEqual(byID["V2"]!.effect, 0.0, accuracy: 1e-9)
        XCTAssertEqual(byID["V1"]!.replicates, 3)
        XCTAssertLessThan(byID["V1"]!.q, 0.05)
        XCTAssertGreaterThan(byID["V2"]!.q, 0.3)
        XCTAssertTrue(AnalysisEngine.effectsCSV(rows).contains("variant,effect,se"))
    }
}

// MARK: - Overlap merge / sample sheet validation

extension EngineTests {
    func testOverlapMerge() {
        let insert = "ATGGCTGCTGCTGCTGCTGCTGCTGCTGCTGATCGATCGATCGATCGA"
        let a = Array(insert)
        let r1 = String(a[0..<40])
        let r2 = Seq.reverseComplement(String(a[20..<a.count]))
        let merged = OverlapMerger.merge(r1: r1, r2: r2)
        XCTAssertNotNil(merged)
        XCTAssertEqual(merged?.sequence, insert)
        XCTAssertEqual(merged?.overlap, 20)

        XCTAssertNil(OverlapMerger.merge(r1: "AAAA", r2: "CCCC"))
    }

    func testSampleSheetValidation() throws {
        let s1 = QCSampleSpec(name: "a", sublibrary: "SL01", replicate: 1, condition: "input",
                              r1: "/tmp/x", index5: "ACGTAC", index3: "TTGGCC")
        let s2 = QCSampleSpec(name: "b", sublibrary: "SL01", replicate: 2, condition: "input",
                              r1: "/tmp/x", index5: "ACGTAC", index3: "TTGGCC")
        let s3 = QCSampleSpec(name: "c", sublibrary: "SL01", replicate: 3, condition: "input",
                              r1: "/tmp/x", index5: "ACGTAC", index3: "TTGGC")
        let issues = SampleSheetValidator.validate([s1, s2, s3])
        XCTAssertTrue(issues.contains { $0.level == .error && $0.message.contains("重复") })
        XCTAssertTrue(issues.contains { $0.level == .error && $0.message.contains("长度") })
        XCTAssertEqual(SampleSheetValidator.hamming("ACGTAC", "ACGTAG"), 1)
        XCTAssertEqual(SampleSheetValidator.hamming("ACGTAC", "ACGTAC"), 0)
    }
}

// MARK: - Joint analysis

extension EngineTests {
    func makeEffect(_ v: String, _ e: Double, _ se: Double = 0.1) -> VariantEffect {
        VariantEffect(variant: v, effect: e, se: se, ciLow: e - 1.96 * se, ciHigh: e + 1.96 * se,
                      z: 0, p: 1, q: 1, flag: "OK", replicates: 2)
    }

    func testJointNormalizeAndMerge() {
        let rows = [makeEffect("WT1", 0.5), makeEffect("WT2", 0.5), makeEffect("V1", 1.7)]
        let norm = JointAnalysis.normalizeWt(rows, wtIDs: ["WT1", "WT2"])
        XCTAssertEqual(norm.baseline, 0.5, accuracy: 1e-9)
        XCTAssertEqual(norm.rows.first { $0.variant == "V1" }!.effect, 1.2, accuracy: 1e-9)

        let merged = JointAnalysis.merge(["A": [makeEffect("V1", 1.0, 0.1)],
                                          "B": [makeEffect("V1", 1.0, 0.2)]])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].effect, 1.0, accuracy: 1e-9)
        XCTAssertEqual(merged[0].se, 1 / sqrt(100 + 25), accuracy: 1e-9)
    }

    func testJointCorrelation() {
        let a = [makeEffect("V1", 1.0), makeEffect("V2", -1.0), makeEffect("V3", 2.0)]
        let b = [makeEffect("V1", 2.0), makeEffect("V2", -2.0), makeEffect("V3", 4.0)]
        let c = JointAnalysis.correlation(["A": a, "B": b])
        XCTAssertEqual(c.names, ["A", "B"])
        XCTAssertEqual(c.matrix[0][1], 1.0, accuracy: 1e-9)
    }
}

// MARK: - CIF / joint null

extension EngineTests {
    func testCIFParser() throws {
        let cif = """
        data_test
        loop_
        _atom_site.group_PDB
        _atom_site.label_atom_id
        _atom_site.label_alt_id
        _atom_site.label_asym_id
        _atom_site.auth_asym_id
        _atom_site.label_comp_id
        _atom_site.auth_seq_id
        _atom_site.Cartn_x
        _atom_site.Cartn_y
        _atom_site.Cartn_z
        ATOM CA . A A ALA 1 1.0 2.0 3.0
        ATOM CA . A A GLY 2 4.0 5.0 6.0
        HETATM O . A A HOH 3 7.0 8.0 9.0
        #
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("t.cif")
        try cif.write(to: url, atomically: true, encoding: .utf8)
        let atoms = try CIFParser.atoms(url: url)
        XCTAssertEqual(atoms.count, 2)
        XCTAssertEqual(atoms[0].chain, "A")
        XCTAssertEqual(atoms[0].resSeq, 1)
        XCTAssertEqual(atoms[1].resName, "GLY")
    }

    func testJointMergeSignificance() {
        let syn = Set(["S1", "S2", "S3"])
        let a = [makeEffect("V1", 2.0, 0.1)] + syn.map { makeEffect($0, 0.0, 0.05) }
        let b = [makeEffect("V1", 2.0, 0.1)] + syn.map { makeEffect($0, 0.0, 0.05) }
        let merged = JointAnalysis.merge(["A": a, "B": b], synonymous: syn)
        let v1 = merged.first { $0.variant == "V1" }!
        XCTAssertEqual(v1.effect, 2.0, accuracy: 1e-9)
        XCTAssertLessThan(v1.q, 0.01)
        XCTAssertEqual(merged.first { $0.variant == "S1" }!.q, 1.0, accuracy: 0.2)
    }
}
