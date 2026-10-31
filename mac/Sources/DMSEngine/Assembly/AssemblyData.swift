import Foundation

public struct EnzymeSpec: Codable, Sendable {
    public var recognition: String
    public var reverseComplement: String
    public var recognitionLength: Int
    public var spacer: Int
    public var overhangLength: Int
    public var overhangType: String
    public var cutTop: Int
    public var cutBottom: Int
    public var overhangStrand: String
    public var isPalindromic: Bool
    public var cutNotation: String
    public var sourceURL: String?
    public var notes: String?

    enum CodingKeys: String, CodingKey {
        case recognition
        case reverseComplement = "reverse_complement"
        case recognitionLength = "recognition_length"
        case spacer
        case overhangLength = "overhang_length"
        case overhangType = "overhang_type"
        case cutTop = "cut_top"
        case cutBottom = "cut_bottom"
        case overhangStrand = "overhang_strand"
        case isPalindromic = "is_palindromic"
        case cutNotation = "cut_notation"
        case sourceURL = "source_url"
        case notes
    }
}

public struct EnzymeTable: Codable, Sendable {
    public var version: Int
    public var source: String
    public var retrieved: String
    public var enzymes: [String: EnzymeSpec]

    public static func load() throws -> EnzymeTable {
        guard let url = EngineResources.url("enzymes", "json") else {
            throw SequenceError.rangeOutOfBounds("找不到 enzymes.json")
        }
        return try JSONDecoder().decode(EnzymeTable.self, from: Data(contentsOf: url))
    }
}

public struct OverhangEntry: Codable, Sendable {
    public var palindromic: Bool
    public var selfComplementary: Bool?
    public var fidelityRank: Int?
    public var fidelity: Double?
    public var totalLigations: Int?
    public var correctLigations: Int?
    public var mismatchLigations: Int?
    public var notes: String?

    enum CodingKeys: String, CodingKey {
        case palindromic
        case selfComplementary = "self_complementary"
        case fidelityRank = "fidelity_rank"
        case fidelity
        case totalLigations = "total_ligations"
        case correctLigations = "correct_ligations"
        case mismatchLigations = "mismatch_ligations"
        case notes
    }
}

public struct OverhangTable: Codable, Sendable {
    public var version: Int
    public var source: String
    public var dataStatus: String
    public var overhangs: [String: OverhangEntry]

    enum CodingKeys: String, CodingKey {
        case version, source, dataStatus = "data_status", overhangs
    }

    public static func load() throws -> OverhangTable {
        guard let url = EngineResources.url("overhangs_t4", "json") else {
            throw SequenceError.rangeOutOfBounds("找不到 overhangs_t4.json")
        }
        return try JSONDecoder().decode(OverhangTable.self, from: Data(contentsOf: url))
    }

    public func entry(_ seq: String) -> OverhangEntry? { overhangs[seq.uppercased()] }
}

public struct IndexEntry: Codable, Sendable {
    public var id: String
    public var seq: String
    public var gc: Double
    public var tm: Double
}

public struct IndexFile: Codable, Sendable {
    public var version: Int
    public var count: Int
    public var length: Int
    public var indices: [IndexEntry]

    public static func load() throws -> IndexFile {
        guard let url = EngineResources.url("indices_1024", "json") else {
            throw SequenceError.rangeOutOfBounds("找不到 indices_1024.json")
        }
        return try JSONDecoder().decode(IndexFile.self, from: Data(contentsOf: url))
    }
}
