import Foundation

public struct DesignResult: Codable, Sendable {
    public var designVariants: [Variant]
    public var qcVariants: [Variant]
    public var regionVariants: [RegionVariant]
    public var sublibraries: [SubLibrary]
    public var ggPlans: [SublibraryPlan]
    public var gibsonPlans: [GibsonPlan]
    public var issues: [QCIssue]
    public var skippedQC: [String: String]

    public var totalVariants: Int { designVariants.count + qcVariants.count }
}

public enum DesignPipeline {

    public static func run(project: Project) throws -> DesignResult {
        guard let plasmid = project.plasmid,
              let target = project.target,
              let feature = plasmid.features.first(where: { $0.id == target.featureID }) else {
            throw SequenceError.rangeOutOfBounds("项目里还没有可用的质粒或突变目标")
        }
        let table = try CodonTable.load(project.libraryParams.codonTable)
        let context = CodingContext(plasmid: plasmid, feature: feature, coding: project.refinedCoding)
        guard context.codonCount >= 1 else {
            throw SequenceError.rangeOutOfBounds("目标 CDS 没有可用的密码子")
        }
        let aaRange = max(1, target.aaStart)...min(context.codonCount, target.aaEnd)
        guard aaRange.lowerBound <= aaRange.upperBound else {
            throw SequenceError.rangeOutOfBounds("突变区段不合法")
        }

        // 设计变体
        let design = try MutationEnumerator.enumerate(context: context, range: aaRange,
                                                      params: project.libraryParams, table: table,
                                                      seed: project.libraryParams.seed)

        // 子库切分
        let subs = Partitioner.split(aaRange: aaRange, codonStart: feature.codonStart,
                                     stepNt: project.libraryParams.stepNt)

        // 质检项
        let qc = QCPlanner.plan(context: context, params: project.libraryParams,
                                qc: project.qcOptions, table: table, aaRange: aaRange,
                                sublibraries: subs, seed: project.libraryParams.seed,
                                existingIDs: Set(design.map(\.id)))

        // 组装方案
        var ggPlans: [SublibraryPlan] = []
        var gibsonPlans: [GibsonPlan] = []
        var issues: [QCIssue] = []
        switch project.assembly.method {
        case .goldenGate:
            let enzymes = try EnzymeTable.load()
            guard let spec = enzymes.enzymes[project.assembly.enzyme] else {
                throw SequenceError.rangeOutOfBounds("找不到酶 \(project.assembly.enzyme)")
            }
            let oh = try OverhangTable.load()
            ggPlans = GoldenGatePlanner.plan(coding: context.coding, codonStart: feature.codonStart,
                                             aaRange: aaRange, stepNt: project.libraryParams.stepNt,
                                             enzymeName: project.assembly.enzyme, enzyme: spec, overhangs: oh)
            issues = ggPlans.flatMap(\.issues)
        case .gibson:
            gibsonPlans = GibsonPlanner.plan(coding: context.coding, codonStart: feature.codonStart,
                                             aaRange: aaRange, stepNt: project.libraryParams.stepNt,
                                             flanks: context.flanks(60),
                                             armLen: project.assembly.homologyArmNt)
            issues = gibsonPlans.flatMap(\.issues)
        }

        return DesignResult(designVariants: design, qcVariants: qc.variants,
                            regionVariants: qc.regionVariants, sublibraries: subs,
                            ggPlans: ggPlans, gibsonPlans: gibsonPlans,
                            issues: issues, skippedQC: qc.skipped)
    }
}
