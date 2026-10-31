import Foundation

public enum FastaParser {
    public static func parse(contents: String, fallbackName: String = "未命名质粒") throws -> Plasmid {
        let lines = contents.components(separatedBy: .newlines)
        let header = lines.first(where: { $0.hasPrefix(">") })
        let name = header.map { String($0.dropFirst()).trimmingCharacters(in: .whitespaces) } ?? fallbackName
        let seq = Seq.sequence(from: lines.filter { !$0.hasPrefix(">") })
        guard !seq.isEmpty else { throw SequenceError.emptySequence }
        return Plasmid(name: name.isEmpty ? fallbackName : name, sequence: seq, topology: .linear, features: [])
    }
}
