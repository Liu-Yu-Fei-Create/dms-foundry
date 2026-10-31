import Foundation

public struct CodonEntry: Codable, Sendable {
    public var aa: String
    public var freq: Double
}

public struct CodonTableFile: Codable, Sendable {
    public var id: String
    public var name: String
    public var source: String
    public var source_url: String?
    public var retrieved: String?
    public var unit: String
    public var notes: String?
    public var data_status: String?
    public var codons: [String: CodonEntry]
}

public final class CodonTable {
    public let file: CodonTableFile
    public init(file: CodonTableFile) { self.file = file }

    public static func load(_ id: TableID) throws -> CodonTable {
        let name = id == .ecoli ? "codons_ecoli" : "codons_human"
        guard let url = EngineResources.url(name, "json") else {
            throw SequenceError.rangeOutOfBounds("找不到密码子表 \(name).json")
        }
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(CodonTableFile.self, from: data)
        return CodonTable(file: file)
    }

    /// 某氨基酸的所有密码子，按频率从高到低
    public func codons(for aa: String) -> [(codon: String, freq: Double)] {
        file.codons.filter { $0.value.aa == aa }
            .map { (codon: $0.key, freq: $0.value.freq) }
            .sorted { $0.freq > $1.freq }
    }

    public func optimal(for aa: String) -> String? {
        codons(for: aa).first?.codon
    }

    public func nonRare(for aa: String, threshold: Double) -> [String] {
        codons(for: aa).filter { $0.freq >= threshold }.map(\.codon)
    }

    public func aminoAcid(for codon: String) -> String? {
        file.codons[codon.uppercased()]?.aa
    }

    public func frequency(of codon: String) -> Double {
        file.codons[codon.uppercased()]?.freq ?? 0
    }
}
