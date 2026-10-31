import Foundation

// MARK: - 基础

public enum Strand: Int, Codable, Sendable { case forward = 1, reverse = -1 }

public struct IntRange: Codable, Hashable, Sendable {
    public var start: Int   // 0-based inclusive
    public var end: Int     // 0-based exclusive
    public init(_ start: Int, _ end: Int) { self.start = start; self.end = end }
    public var length: Int { max(0, end - start) }
}

public enum FeatureType: String, Codable, CaseIterable, Sendable {
    case promoter, terminator, cds, origin, resistance, other

    public var zh: String {
        switch self {
        case .promoter: return "启动子"
        case .terminator: return "终止子"
        case .cds: return "CDS"
        case .origin: return "复制起点"
        case .resistance: return "抗性基因"
        case .other: return "其他"
        }
    }
    public var en: String { rawValue.uppercased() }
}

public enum FeatureSource: String, Codable, Sendable { case annotation, motif, manual }

public struct Feature: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var type: FeatureType
    public var label: String
    public var start: Int          // 0-based inclusive
    public var end: Int            // 0-based exclusive
    public var strand: Strand
    public var subRanges: [IntRange]?  // join() 用；nil 表示单段
    public var codonStart: Int     // 1/2/3
    public var translTable: Int
    public var source: FeatureSource

    public init(id: UUID = UUID(), type: FeatureType, label: String,
                start: Int, end: Int, strand: Strand = .forward,
                subRanges: [IntRange]? = nil, codonStart: Int = 1,
                translTable: Int = 11, source: FeatureSource = .annotation) {
        self.id = id; self.type = type; self.label = label
        self.start = start; self.end = end; self.strand = strand
        self.subRanges = subRanges; self.codonStart = codonStart
        self.translTable = translTable; self.source = source
    }

    public var length: Int { subRanges?.reduce(0) { $0 + $1.length } ?? max(0, end - start) }
    public var codonCount: Int { max(0, (length - (codonStart - 1)) / 3) }
}

public enum Topology: String, Codable, Sendable { case linear, circular }

public struct Plasmid: Codable, Sendable {
    public var name: String
    public var sequence: String
    public var topology: Topology
    public var features: [Feature]

    public init(name: String, sequence: String, topology: Topology = .circular, features: [Feature] = []) {
        self.name = name; self.sequence = sequence.uppercased()
        self.topology = topology; self.features = features
    }
}

public struct Target: Codable, Sendable {
    public var featureID: UUID
    public var aaStart: Int   // 1-based inclusive
    public var aaEnd: Int     // 1-based inclusive
    public init(featureID: UUID, aaStart: Int, aaEnd: Int) {
        self.featureID = featureID; self.aaStart = aaStart; self.aaEnd = aaEnd
    }
}

// MARK: - 参数

public enum MutationMode: String, Codable, Sendable { case all, subset }
public enum CodonPolicy: String, Codable, Sendable { case optimal, random, randomNonRare }
public enum TableID: String, Codable, Sendable { case ecoli, human }

public struct LibraryParams: Codable, Sendable {
    public var mutationMode: MutationMode = .all
    public var allowedAA: [String] = []          // 单字母，subset 时生效
    public var includeWT: Bool = false
    public var includeSynonymous: Bool = false
    public var keepRare: Bool = true
    public var includeStop: Bool = false
    public var codonPolicy: CodonPolicy = .randomNonRare
    public var codonTable: TableID = .ecoli
    public var rareThreshold: Double = 10.0      // per thousand
    public var stepNt: Int = 150
    public var seed: UInt64 = 20261102
    public init() {}
}

public enum QCItemMode: String, Codable, Sendable { case random, specified }
public struct QCItem: Codable, Sendable {
    public var enabled: Bool = false
    public var mode: QCItemMode = .random
    public var count: Int = 0
    public var aaRangeStart: Int = 1
    public var aaRangeEnd: Int = 1
    public var positions: [Int] = []
    public init() {}
}
public enum RandomRegionMode: String, Codable, Sendable { case pureRandomNt, framePreservingCodons }
public struct RandomRegionQC: Codable, Sendable {
    public var enabled: Bool = false
    public var mode: RandomRegionMode = .pureRandomNt
    public var countPerSublibrary: Int = 2
    public init() {}
}
public struct ScreeningGroup: Codable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var sublibraryIDs: [String]
    public var replicates: Int
    public var note: String
    public init(name: String, sublibraryIDs: [String], replicates: Int = 3, note: String = "") {
        self.id = UUID(); self.name = name
        self.sublibraryIDs = sublibraryIDs; self.replicates = replicates; self.note = note
    }
}

public struct ScreeningPlan: Codable, Sendable {
    public var groups: [ScreeningGroup]
    public init(groups: [ScreeningGroup] = []) { self.groups = groups }
}

public struct QCOptions: Codable, Sendable {
    public var stop = QCItem()
    public var synonymous = QCItem()
    public var proline = QCItem()
    public var randomRegion = RandomRegionQC()
    public init() {}
}

public enum AssemblyMethod: String, Codable, Sendable { case goldenGate, gibson }
public struct Assembly: Codable, Sendable {
    public var method: AssemblyMethod = .goldenGate
    public var enzyme: String = "BsaI"
    public var homologyArmNt: Int = 25
    public var indexSeed: UInt64? = nil
    public init() {}
}

// MARK: - 产物

public enum IssueSeverity: String, Codable, Sendable { case error, warning, info }
public struct QCIssue: Codable, Hashable, Sendable {
    public var code: String
    public var severity: IssueSeverity
    public var message: String
    public init(_ code: String, _ severity: IssueSeverity, _ message: String) {
        self.code = code; self.severity = severity; self.message = message
    }
}
public enum VariantStatus: String, Codable, Sendable { case ok, warn, drop }
public struct VariantVerdict: Codable, Sendable {
    public var status: VariantStatus = .ok
    public var reasons: [QCIssue] = []
    public init() {}
}

public struct Oligo: Codable, Identifiable, Sendable {
    public var id: String
    public var subID: String
    public var name: String
    public var sequence: String
    public var index5: String
    public var index3: String
    public var overhang5: String
    public var overhang3: String
    public var mutationAA: String
    public var codon: String
    public var source: String
    public var verdict: VariantVerdict
    public var gc: Double
    public var tm: Double
    public init(id: String, subID: String, name: String, sequence: String,
                index5: String = "", index3: String = "", overhang5: String = "",
                overhang3: String = "", mutationAA: String = "", codon: String = "",
                source: String = "design", verdict: VariantVerdict = VariantVerdict(),
                gc: Double = 0, tm: Double = 0) {
        self.id = id; self.subID = subID; self.name = name; self.sequence = sequence
        self.index5 = index5; self.index3 = index3
        self.overhang5 = overhang5; self.overhang3 = overhang3
        self.mutationAA = mutationAA; self.codon = codon
        self.source = source; self.verdict = verdict; self.gc = gc; self.tm = tm
    }
}

// MARK: - 项目

public struct Project: Codable, Identifiable, Sendable {
    public var id: UUID
    public var schemaVersion: Int
    public var name: String
    public var host: String
    public var createdAt: Date
    public var updatedAt: Date
    public var plasmid: Plasmid?
    public var target: Target?
    public var libraryParams: LibraryParams
    public var qcOptions: QCOptions
    public var assembly: Assembly
    public var paramsHash: String?
    public var refinedCoding: String?
    public var refineChangeCount: Int?
    public var screeningPlan: ScreeningPlan?

    public init(name: String, host: String) {
        self.id = UUID(); self.schemaVersion = 1
        self.name = name; self.host = host
        self.createdAt = Date(); self.updatedAt = Date()
        self.libraryParams = LibraryParams()
        self.qcOptions = QCOptions()
        self.assembly = Assembly()
    }
}
