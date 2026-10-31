import Foundation
import SwiftUI
import DMSEngine
import AppKit
import UniformTypeIdentifiers

enum AppSection: String, CaseIterable, Identifiable {
    case design, qc, screening, analysis
    var id: String { rawValue }
    var title: String {
        switch self {
        case .design: return "文库设计"
        case .qc: return "文库质控"
        case .screening: return "筛选方案"
        case .analysis: return "筛选分析"
        }
    }
    var icon: String {
        switch self {
        case .design: return "square.and.pencil"
        case .qc: return "checklist"
        case .screening: return "square.grid.2x2"
        case .analysis: return "chart.bar"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var projects: [Project] = []
    @Published var current: Project?
    @Published var section: AppSection = .design
    @Published var step: Int = 1
    @Published var banner: String?
    @Published var isImporting = false
    @Published var showNewProject = false

    let store = ProjectStore.shared

    init() { reload() }

    func reload() {
        projects = store.list()
        if current == nil { current = projects.first }
    }

    func create(name: String, host: String) {
        let d = PresetStore.shared.defaults
        var p = Project(name: name.isEmpty ? "未命名项目" : name, host: host.isEmpty ? d.host : host)
        p.libraryParams = d.library
        p.assembly = d.assembly
        p.qcOptions = d.qc
        current = p
        step = 1
        save()
        projects = store.list()
    }

    func save() {
        guard let p = current else { return }
        do { try store.save(p); projects = store.list() }
        catch { banner = "保存失败：\(error.localizedDescription)" }
    }

    func open(_ p: Project) { current = p; step = 1 }

    /// 内置示例：TEM-1 成熟 CDS（真实序列，E. coli 最优密码子回译）
    func loadSampleDNA() {
        guard let url = EngineResources.url("tem1_cds", "dna") else {
            banner = "找不到内置示例 tem1_cds.dna"; return
        }
        do {
            let plasmid = try SnapGeneParser.parse(data: try Data(contentsOf: url))
            if current == nil { create(name: "TEM-1 示例（.dna）", host: "E. coli BL21(DE3)") }
            current?.plasmid = plasmid
            if let cds = plasmid.features.first(where: { $0.type == .cds }) {
                current?.target = Target(featureID: cds.id, aaStart: 1, aaEnd: cds.codonCount)
            }
            step = 2
            save()
            banner = F("已载入示例：%@ · %d bp", plasmid.name, plasmid.sequence.count)
        } catch {
            banner = F("导入失败：%@", error.localizedDescription)
        }
    }

    func loadSample() {
        guard let url = EngineResources.url("tem1_cds", "gb") else {
            banner = "找不到内置示例 tem1_cds.gb"; return
        }
        do {
            let plasmid = try GenBankParser.parse(contents: try String(contentsOf: url, encoding: .utf8))
            if current == nil { create(name: "TEM-1 示例", host: "E. coli BL21(DE3)") }
            current?.plasmid = plasmid
            if let cds = plasmid.features.first(where: { $0.type == .cds }) {
                current?.target = Target(featureID: cds.id, aaStart: 1, aaEnd: cds.codonCount)
            }
            step = 2
            save()
            banner = F("已载入示例：%@ · %d bp", plasmid.name, plasmid.sequence.count)
        } catch {
            banner = "载入示例失败：\(error.localizedDescription)"
        }
    }

    func importPlasmid(url: URL) {
        let gotAccess = url.startAccessingSecurityScopedResource()
        defer { if gotAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let ext = url.pathExtension.lowercased()
            let plasmid: Plasmid
            if ext == "dna" {
                plasmid = try SnapGeneParser.parse(data: try Data(contentsOf: url))
            } else {
                let text = try String(contentsOf: url, encoding: .utf8)
                if ["gb", "gbk", "genbank"].contains(ext) {
                    plasmid = try GenBankParser.parse(contents: text)
                } else {
                    plasmid = try FastaParser.parse(contents: text, fallbackName: url.deletingPathExtension().lastPathComponent)
                }
            }
            current?.plasmid = plasmid
            if let firstCDS = plasmid.features.first(where: { $0.type == .cds }) {
                current?.target = Target(featureID: firstCDS.id, aaStart: 1, aaEnd: firstCDS.codonCount)
            }
            step = 2
            save()
            banner = F("已载入示例：%@ · %d bp", plasmid.name, plasmid.sequence.count)
        } catch {
            banner = F("导入失败：%@", error.localizedDescription)
        }
    }

    var targetFeature: Feature? {
        guard let t = current?.target else { return nil }
        return current?.plasmid?.features.first { $0.id == t.featureID }
    }

    var codingContext: CodingContext? {
        guard let p = current, let plasmid = p.plasmid, let f = targetFeature else { return nil }
        return CodingContext(plasmid: plasmid, feature: f)
    }

    func variantCount() -> Int {
        guard let ctx = codingContext, let p = current, ctx.codonCount > 0 else { return 0 }
        let table = (try? CodonTable.load(p.libraryParams.codonTable)) ?? nil
        guard let t = table else { return 0 }
        let range = 1...ctx.codonCount
        return (try? MutationEnumerator.enumerate(context: ctx, range: range,
                                                  params: p.libraryParams, table: t,
                                                  seed: p.libraryParams.seed).count) ?? 0
    }

    enum UpdatePhase: Equatable {
        case idle, checking
        case upToDate(String)
        case available(String, String)
        case downloading
        case ready(String)
        case failed(String)
    }

    @Published var updatePhase: UpdatePhase = .idle
    @Published var showUpdateSheet = false
    @Published var updateFeedURL: String =
        UserDefaults.standard.string(forKey: "updateFeedURL") ?? UpdateChecker.defaultFeedURL
    private var pendingUpdate: UpdateCheckResult?
    struct MigrationState { var fraction: Double; var text: String; var failed: String? }
    @Published var migration: MigrationState?
    func beginMigration(to destination: URL) {
        migration = MigrationState(fraction: 0, text: "准备…", failed: nil)
        let source = AppPaths.root
        let model = self
        Task.detached {
            do {
                try DataMigration.migrate(from: source, to: destination) { fraction, text in
                    Task { @MainActor in
                        model.migration = MigrationState(fraction: fraction, text: text, failed: nil)
                    }
                }
                await MainActor.run {
                    AppPaths.setRoot(destination)
                    model.migration = MigrationState(fraction: 1, text: "完成，正在重启…", failed: nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        let cfg = NSWorkspace.OpenConfiguration()
                        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL,
                                                           configuration: cfg) { _, _ in
                            DispatchQueue.main.async { NSApp.terminate(nil) }
                        }
                    }
                }
            } catch {
                await MainActor.run { model.migration?.failed = error.localizedDescription }
            }
        }
    }

    @Published var generated: GeneratedLibrary?
    @Published var exported: Exporter.ExportResult?
    @Published var exportError: String?

    func indexAssignments(design: DesignResult) -> [IndexAssignment] {
        guard let plasmid = current?.plasmid else { return [] }
        guard let indices = try? IndexFile.load() else { return [] }
        let seed = current?.assembly.indexSeed ?? 1
        return IndexMatcher.assign(sublibraries: design.sublibraries, indices: indices,
                                   plasmid: plasmid.sequence, seed: seed)
    }

    func reassignIndices() {
        current?.assembly.indexSeed = (current?.assembly.indexSeed ?? 1) + 1
        generated = nil
        save()
    }

    func generateLibrary() {
        guard let p = current, let design = design() else { return }
        do {
            let indices = try IndexFile.load()
            let enzymes = try EnzymeTable.load()
            let assigns = indexAssignments(design: design)
            generated = try LibraryGenerator.generate(project: p, design: design, indices: indices,
                                                      indexAssignments: assigns, enzymes: enzymes)
        } catch {
            generated = nil
            banner = F("生成失败：%@", error.localizedDescription)
        }
    }

    func exportLibrary() {
        guard let p = current, let lib = generated else { return }
        do {
            exported = try Exporter.write(library: lib, project: p)
            banner = F("已导出 %d 个文件", exported?.files.count ?? 0)
        } catch {
            exportError = error.localizedDescription
            banner = F("导出失败：%@", error.localizedDescription)
        }
    }

    func checkUpdates() async {
        UserDefaults.standard.set(updateFeedURL, forKey: "updateFeedURL")
        updatePhase = .checking
        do {
            let result = try await UpdateChecker.check(feedURL: updateFeedURL)
            pendingUpdate = result
            if result.isNewer {
                let notes = result.manifest.latest.notes
                updatePhase = .available(result.manifest.latest.version,
                                         notes?.zh ?? notes?.en ?? "")
            } else {
                updatePhase = .upToDate(result.manifest.latest.version)
            }
        } catch {
            updatePhase = .failed(error.localizedDescription)
        }
    }

    func downloadUpdate() async {
        guard let r = pendingUpdate else { return }
        updatePhase = .downloading
        do {
            let url = try await UpdateChecker.download(r, publicKeyBase64: UpdateChecker.publicKeyBase64)
            updatePhase = .ready(url.path)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            updatePhase = .failed(error.localizedDescription)
        }
    }

    var appVersionText: String {
        "v\(UpdateChecker.currentVersion) (\(UpdateChecker.currentBuild))"
    }

    func design() -> DesignResult? {
        guard let p = current else { return nil }
        return try? DesignPipeline.run(project: p)
    }

    func refinePreview() -> RefineResult? {
        guard let ctx = codingContext, let p = current else { return nil }
        guard let enzymes = try? EnzymeTable.load(),
              let spec = enzymes.enzymes[p.assembly.enzyme],
              let table = try? CodonTable.load(p.libraryParams.codonTable) else { return nil }
        return Refiner.refine(coding: ctx.coding, codonStart: ctx.feature.codonStart,
                              allowedCodons: 1...max(1, ctx.codonCount),
                              motif: spec.recognition.uppercased(),
                              table: table, allowRare: p.libraryParams.keepRare)
    }

    func applyRefine() {
        guard let ctx = codingContext, let p = current,
              let enzymes = try? EnzymeTable.load(),
              let spec = enzymes.enzymes[p.assembly.enzyme],
              let table = try? CodonTable.load(p.libraryParams.codonTable) else { return }
        let base = p.refinedCoding ?? ctx.coding
        let result = Refiner.refine(coding: base, codonStart: ctx.feature.codonStart,
                                    allowedCodons: 1...max(1, ctx.codonCount),
                                    motif: spec.recognition.uppercased(),
                                    table: table, allowRare: p.libraryParams.keepRare)
        current?.refinedCoding = result.coding
        current?.refineChangeCount = result.changes.count
        generated = nil
        save()
        banner = F("已应用 Refine：%d 处同义替换，剩余内部位点 %d 个", result.changes.count, result.remainingSites.count)
    }

    func resetRefine() {
        current?.refinedCoding = nil
        current?.refineChangeCount = nil
        generated = nil
        save()
    }

    /// 从当前项目的设计结果构建某个子库的 QC 设计（reference=该子库的 WT 插入片段）
    /// 默认筛选方案：一个子库一个分组（各自筛各自的），每个分组 3 个重复。
    func ensureScreeningPlan() {
        guard let d = design() else { return }
        let existing = current?.screeningPlan?.groups ?? []
        if existing.isEmpty {
            var plan = ScreeningPlan()
            plan.groups = d.sublibraries.map {
                ScreeningGroup(name: $0.id, sublibraryIDs: [$0.id], replicates: 3)
            }
            current?.screeningPlan = plan
            save()
        }
    }

    func qcDesign(for subID: String) -> QCDesign? {
        guard let p = current, let ctx = codingContext, let d = design(),
              let s = d.sublibraries.first(where: { $0.id == subID }) else { return nil }
        let coding = Array(p.refinedCoding ?? ctx.coding)
        let start = (s.aaStart - 1) * 3
        let end = min(coding.count, s.aaEnd * 3)
        guard start >= 0, end > start else { return nil }
        let insert = String(coding[start..<end])
        let anchor: String? = start >= 20 ? String(coding[(start - 20)..<start]) : nil
        let variants = (d.designVariants + d.qcVariants)
            .filter { $0.position >= s.aaStart && $0.position <= s.aaEnd }
            .map { v -> QCVariant in
                let idx = (v.position - s.aaStart) * 3
                let wtCodon = String(coding[start + idx ..< start + idx + 3])
                return QCVariant(id: v.id, sublibrary: s.id,
                                 position: v.position - s.aaStart + 1,
                                 wtCodon: wtCodon, mutCodon: v.codon,
                                 aaChange: "\(v.wt)\(v.position)\(v.mut)")
            }
        return QCDesign(reference: insert, anchor5: anchor, variants: variants)
    }

    func currentPayload() -> PresetPayload? {
        guard let p = current else { return nil }
        return PresetPayload(host: p.host, library: p.libraryParams,
                             assembly: p.assembly, qc: p.qcOptions)
    }

    func applyPreset(_ payload: PresetPayload) {
        current?.host = payload.host
        current?.libraryParams = payload.library
        current?.assembly = payload.assembly
        current?.qcOptions = payload.qc
        generated = nil
        save()
        banner = L("已应用预设")
    }

    func subLibraries() -> [SubLibrary] {
        guard let ctx = codingContext, let p = current, ctx.codonCount > 0 else { return [] }
        return Partitioner.split(aaRange: 1...ctx.codonCount,
                                 codonStart: ctx.feature.codonStart,
                                 stepNt: p.libraryParams.stepNt)
    }
}
