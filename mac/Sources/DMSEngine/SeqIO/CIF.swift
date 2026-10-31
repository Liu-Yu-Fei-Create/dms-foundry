import Foundation

/// mmCIF（.cif/.mmcif）的 _atom_site 解析：只取 CA，chain 优先 auth_asym_id。
public enum CIFParser {
    public static func atoms(url: URL) throws -> [PDBAtom] {
        let text = try String(contentsOf: url, encoding: .utf8)
        var columns: [String] = []
        var inAtomLoop = false
        var out: [PDBAtom] = []

        for raw in text.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("loop_") { inAtomLoop = true; columns = []; continue }
            if inAtomLoop && line.hasPrefix("_atom_site.") {
                columns.append(String(line.dropFirst("_atom_site.".count)))
                continue
            }
            if inAtomLoop && !columns.isEmpty && !line.hasPrefix("_") && !line.hasPrefix("#") && !line.isEmpty {
                let vals = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
                guard vals.count >= columns.count else { continue }
                func col(_ names: [String]) -> Int? {
                    for n in names { if let i = columns.firstIndex(of: n) { return i } }
                    return nil
                }
                guard let groupI = col(["group_PDB"]), vals[groupI] == "ATOM",
                      let atomI = col(["label_atom_id"]), vals[atomI] == "CA" else { continue }
                let alt = col(["label_alt_id"]).map { vals[$0] } ?? "."
                if alt != "." && alt != "A" && alt != "?" { continue }

                let chain = (col(["auth_asym_id"]) ?? col(["label_asym_id"])).map { vals[$0] } ?? "A"
                let resName = col(["auth_comp_id", "label_comp_id"]).map { vals[$0] } ?? "UNK"
                let seqStr = (col(["auth_seq_id"]) ?? col(["label_seq_id"])).map { vals[$0] } ?? "0"
                guard let resSeq = Int(seqStr),
                      let xi = col(["Cartn_x"]), let yi = col(["Cartn_y"]), let zi = col(["Cartn_z"]),
                      let x = Float(vals[xi]), let y = Float(vals[yi]), let z = Float(vals[zi]) else { continue }
                out.append(PDBAtom(chain: chain == "?" ? "A" : chain, resSeq: resSeq,
                                   resName: resName, x: x, y: y, z: z))
            }
            if inAtomLoop && !columns.isEmpty && line.hasPrefix("#") { break }
        }
        return out
    }
}
