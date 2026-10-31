import Foundation

public struct PDBAtom {
    public var chain: String
    public var resSeq: Int
    public var resName: String
    public var x: Float
    public var y: Float
    public var z: Float
    public init(chain: String, resSeq: Int, resName: String, x: Float, y: Float, z: Float) {
        self.chain = chain; self.resSeq = resSeq; self.resName = resName
        self.x = x; self.y = y; self.z = z
    }
}

public enum PDBParser {
    /// 只取 CA 原子；支持多链（同源二聚体等）。
    public static func atoms(url: URL) throws -> [PDBAtom] {
        let text = try String(contentsOf: url, encoding: .utf8)
        var out: [PDBAtom] = []
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
            let l = String(line)
            guard l.hasPrefix("ATOM"), l.count > 54 else { continue }
            let name = String(l.dropFirst(12).prefix(4)).trimmingCharacters(in: .whitespaces)
            guard name == "CA" else { continue }
            let alt = String(l.dropFirst(16).prefix(1))
            if !alt.isEmpty && alt != " " && alt != "A" { continue }
            let resName = String(l.dropFirst(17).prefix(3)).trimmingCharacters(in: .whitespaces)
            let chain = String(l.dropFirst(21).prefix(1))
            let resStr = String(l.dropFirst(22).prefix(4)).trimmingCharacters(in: .whitespaces)
            guard let resSeq = Int(resStr),
                  let x = Float(l.dropFirst(30).prefix(8).trimmingCharacters(in: .whitespaces)),
                  let y = Float(l.dropFirst(38).prefix(8).trimmingCharacters(in: .whitespaces)),
                  let z = Float(l.dropFirst(46).prefix(8).trimmingCharacters(in: .whitespaces)) else { continue }
            out.append(PDBAtom(chain: chain, resSeq: resSeq, resName: resName, x: x, y: y, z: z))
        }
        return out
    }

    public static func chains(_ atoms: [PDBAtom]) -> [String] { Array(Set(atoms.map(\.chain))).sorted() }

    /// 序列完全相同的链（同源二聚体/多聚体），返回成组的链名。
    public static func identicalChainGroups(_ atoms: [PDBAtom]) -> [[String]] {
        let byChain = Dictionary(grouping: atoms, by: \.chain)
        var bySig: [String: [String]] = [:]
        for (chain, list) in byChain {
            let sig = list.sorted { $0.resSeq < $1.resSeq }
                .map { "\($0.resSeq):\($0.resName)" }.joined(separator: ",")
            bySig[sig, default: []].append(chain)
        }
        return bySig.values.filter { $0.count > 1 }.map { $0.sorted() }
    }
}
