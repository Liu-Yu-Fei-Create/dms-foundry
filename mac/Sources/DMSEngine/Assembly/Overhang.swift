import Foundation

public struct OverhangScore: Codable, Sendable {
    public var sequence: String
    public var palindromic: Bool
    public var fidelity: Double?
    public var rank: Int?
    public var grade: OverhangGrade
    public var note: String
}

public enum OverhangGrade: String, Codable, Sendable { case good, marginal, bad, unknown }

public enum OverhangEvaluator {
    public static func evaluate(_ seq: String, table: OverhangTable) -> OverhangScore {
        let s = seq.uppercased()
        guard s.count == 4 else {
            return OverhangScore(sequence: s, palindromic: false, fidelity: nil, rank: nil,
                                 grade: .unknown, note: "overhang 长度不是 4 nt")
        }
        guard let e = table.entry(s) else {
            return OverhangScore(sequence: s, palindromic: false, fidelity: nil, rank: nil,
                                 grade: .unknown, note: "不在 256 条保真度表中")
        }
        let f = e.fidelity
        var grade: OverhangGrade = .unknown
        var note = e.notes ?? ""
        if e.palindromic {
            grade = .bad
            note = "回文/自互补 overhang，一锅法里会自连，不能用作接口"
        } else if let f {
            if f >= 0.80 { grade = .good }
            else if f >= 0.60 { grade = .marginal }
            else { grade = .bad }
            note = String(format: "实测保真度 %.3f（rank %@）", f, e.fidelityRank.map(String.init) ?? "—")
        }
        return OverhangScore(sequence: s, palindromic: e.palindromic,
                             fidelity: f, rank: e.fidelityRank, grade: grade, note: note)
    }
}
