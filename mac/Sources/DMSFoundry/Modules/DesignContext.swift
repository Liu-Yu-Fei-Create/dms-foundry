import Foundation
import CryptoKit
import DMSEngine

/// 设计模块交给 QC / 分析模块的“上下文指纹”。
struct DesignContextInfo: Codable {
    var projectName: String
    var target: String
    var enzyme: String
    var stepNt: Int
    var variants: Int
    var sublibraries: Int
    var hash: String
}

enum DesignContext {
    static func make(project: Project, design: DesignResult) -> DesignContextInfo {
        let sub = design.sublibraries.map { "\($0.id):\($0.aaStart)-\($0.aaEnd)" }.joined(separator: ",")
        let ids = (design.designVariants + design.qcVariants).map(\.id).sorted().joined(separator: ",")
        let payload = [
            project.name, project.host, project.assembly.enzyme,
            String(project.libraryParams.stepNt), sub, ids,
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(payload.utf8))
        let hash = digest.prefix(6).map { String(format: "%02x", $0) }.joined()
        return DesignContextInfo(projectName: project.name,
                                 target: project.target.map { "aa \($0.aaStart)–\($0.aaEnd)" } ?? "—",
                                 enzyme: project.assembly.enzyme,
                                 stepNt: project.libraryParams.stepNt,
                                 variants: design.designVariants.count + design.qcVariants.count,
                                 sublibraries: design.sublibraries.count,
                                 hash: hash)
    }
}
