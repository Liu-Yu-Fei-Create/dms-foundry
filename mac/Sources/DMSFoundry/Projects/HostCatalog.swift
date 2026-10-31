import Foundation
import DMSEngine

struct HostOption: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let group: String
    let table: TableID?
}

enum HostCatalog {
    static let groups = ["克隆菌株（E. coli）", "表达菌株（E. coli）", "酵母", "哺乳动物细胞", "无细胞", "其他"]

    static let options: [HostOption] = [
        // 克隆
        .init(name: "E. coli DH5α", group: groups[0], table: .ecoli),
        .init(name: "E. coli TOP10", group: groups[0], table: .ecoli),
        .init(name: "E. coli DH10B", group: groups[0], table: .ecoli),
        .init(name: "E. coli NEB 5-alpha", group: groups[0], table: .ecoli),
        .init(name: "E. coli JM109", group: groups[0], table: .ecoli),
        .init(name: "E. coli Stbl3", group: groups[0], table: .ecoli),
        .init(name: "E. coli XL1-Blue", group: groups[0], table: .ecoli),
        .init(name: "E. coli Mach1-T1", group: groups[0], table: .ecoli),
        .init(name: "E. coli AG1", group: groups[0], table: .ecoli),
        .init(name: "E. coli HB101", group: groups[0], table: .ecoli),
        .init(name: "E. coli SCS110 (dam−/dcm−)", group: groups[0], table: .ecoli),
        .init(name: "E. coli GM2163 (dam−)", group: groups[0], table: .ecoli),
        // 表达
        .init(name: "E. coli BL21(DE3)", group: groups[1], table: .ecoli),
        .init(name: "E. coli BL21(DE3)pLysS", group: groups[1], table: .ecoli),
        .init(name: "E. coli BL21(DE3)Star", group: groups[1], table: .ecoli),
        .init(name: "E. coli Rosetta(DE3)", group: groups[1], table: .ecoli),
        .init(name: "E. coli Lemo21(DE3)", group: groups[1], table: .ecoli),
        .init(name: "E. coli Origami B(DE3)", group: groups[1], table: .ecoli),
        .init(name: "E. coli SHuffle T7", group: groups[1], table: .ecoli),
        .init(name: "E. coli C41(DE3)", group: groups[1], table: .ecoli),
        .init(name: "E. coli C43(DE3)", group: groups[1], table: .ecoli),
        .init(name: "E. coli ArcticExpress", group: groups[1], table: .ecoli),
        // 酵母
        .init(name: "S. cerevisiae BY4741", group: groups[2], table: nil),
        .init(name: "S. cerevisiae INVSc1", group: groups[2], table: nil),
        .init(name: "P. pastoris GS115", group: groups[2], table: nil),
        .init(name: "P. pastoris X-33", group: groups[2], table: nil),
        // 哺乳动物
        .init(name: "Expi293F", group: groups[3], table: .human),
        .init(name: "HEK293T", group: groups[3], table: .human),
        .init(name: "CHO-S", group: groups[3], table: .human),
        .init(name: "CHO-K1", group: groups[3], table: .human),
        .init(name: "HeLa", group: groups[3], table: .human),
        .init(name: "NIH/3T3", group: groups[3], table: .human),
        // 无细胞
        .init(name: "PURExpress", group: groups[4], table: .ecoli),
        .init(name: "无细胞体系", group: groups[4], table: .ecoli),
    ]

    static func option(named: String) -> HostOption? { options.first { $0.name == named } }
}
