import SwiftUI
import AppKit
import UniformTypeIdentifiers
import DMSEngine

enum AnalysisInputMode: String, CaseIterable { case counts, fastq }
enum AnalysisViewMode: String, CaseIterable { case perGroup, joint }

struct GroupResult: Codable, Identifiable {
    var name: String
    var effects: [VariantEffect]
    var wtBaseline: Double
    var id: String { name }
}

struct AnalysisPayload: Codable {
    var joint: [VariantEffect]
    var groups: [GroupResult]
    var context: DesignContextInfo?
}

struct AnalysisModuleView: View {
    @EnvironmentObject private var model: AppModel

    @State private var mode: AnalysisInputMode = .counts
    @State private var viewMode: AnalysisViewMode = .perGroup
    @State private var countsURL: URL?
    @State private var sheetURL: URL?
    @State private var showImporter = false
    @State private var showSheetImporter = false
    @State private var isRunning = false
    @State private var errorText: String?
    @State private var rows: [VariantEffect] = []
    @State private var groups: [GroupResult] = []
    @State private var selectedGroup: String?
    @State private var variantCount = 0
    @State private var sampleCount = 0
    @State private var cutoff: Double = 1.0
    @State private var runs: [RunRecord] = []
    @State private var designCtx: DesignContextInfo?
    @State private var runCtx: DesignContextInfo?
    @State private var pdbAtoms: [PDBAtom] = []
    @State private var pdbChains: Set<String> = []
    @State private var pdbName: String?
    @State private var showPDBImporter = false
    @State private var scheme: StructureColorScheme = .gray
    @State private var identicalNote: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.s4) {
                    header
                    designContextBlock
                    inputBlock
                    if !groups.isEmpty || !rows.isEmpty {
                        viewSwitch
                        if viewMode == .perGroup { perGroupView } else { jointView }
                    }
                    if let e = errorText { Text(e).font(.system(size: 12)).foregroundStyle(.red) }
                    if !runs.isEmpty { recentRuns }
                }
                .padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 40)
                .frame(maxWidth: Theme.contentMax, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(Theme.paper)
            .onAppear {
                model.ensureScreeningPlan()
                if let p = model.current, let d = model.design() {
                    designCtx = DesignContext.make(project: p, design: d)
                }
                if ProcessInfo.processInfo.environment["DMS_ANALYSIS_MODE"] == "fastq" { mode = .fastq }
                if ProcessInfo.processInfo.environment["DMS_ANALYSIS_VIEW"] == "joint" { viewMode = .joint }
                if ProcessInfo.processInfo.environment["DMS_STRUCTURE_DEMO"] == "1" {
                    loadDemoStructure()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation { proxy.scrollTo("structure", anchor: .top) }
                    }
                }
                if ProcessInfo.processInfo.environment["DMS_ANALYSIS_DEMO"] == "1", rows.isEmpty { runDemo() }
                loadRuns()
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.commaSeparatedText, .plainText, .data],
                          allowsMultipleSelection: false) { res in
                if case .success(let urls) = res { countsURL = urls.first }
            }
            .fileImporter(isPresented: $showSheetImporter, allowedContentTypes: [.commaSeparatedText, .plainText, .data],
                          allowsMultipleSelection: false) { res in
                if case .success(let urls) = res { sheetURL = urls.first }
            }
            .fileImporter(isPresented: $showPDBImporter, allowedContentTypes: [.data, .plainText],
                          allowsMultipleSelection: false) { res in
                if case .success(let urls) = res, let url = urls.first {
                    let isCIF = ["cif", "mmcif"].contains(url.pathExtension.lowercased())
                    let atoms = isCIF ? ((try? CIFParser.atoms(url: url)) ?? [])
                                      : ((try? PDBParser.atoms(url: url)) ?? [])
                    if !atoms.isEmpty {
                        pdbAtoms = atoms
                        let groups = PDBParser.identicalChainGroups(atoms)
                        identicalNote = groups.isEmpty ? nil
                            : L("检测到相同链组：\(groups.map { $0.joined(separator: "/") }.joined(separator: "、"))（默认只映射每组第一条）")
                        let reps = groups.compactMap { $0.first }
                        pdbChains = Set(reps.isEmpty ? [PDBParser.chains(atoms).first ?? "A"] : reps)
                        pdbName = url.lastPathComponent
                    } else {
                        errorText = L("没有从该文件解析到 CA 原子（支持 PDB 与 mmCIF）")
                    }
                }
            }
        }
    }

    // MARK: header / context

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("数据分析")).font(.system(size: 20, weight: .semibold))
            Text(L("两种输入（FASTQ 样本表 / counts 长表），两种视角：逐组解析与跨组归一。"))
                .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
        }
    }

    private var designContextBlock: some View {
        Block("设计上下文") {
            if let c = designCtx {
                HStack(spacing: 10) {
                    Text(c.projectName).font(.system(size: 12, weight: .medium))
                    Text("· \(c.target)").font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                    Text("· \(c.variants) 变体 / \(c.sublibraries) 子库").font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                    Text("· 指纹 \(c.hash)").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.faint)
                    if let plan = model.current?.screeningPlan, !plan.groups.isEmpty {
                        Text("· \(plan.groups.count) 个筛选分组").font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Button(L("打开文库设计")) { model.section = .design }.buttonStyle(SecondaryButtonStyle())
                    Button(L("筛选方案")) { model.section = .screening }.buttonStyle(SecondaryButtonStyle())
                }
                if let loaded = runCtx, loaded.hash != c.hash {
                    Text(L("这份结果基于旧设计，当前设计已变化。"))
                        .font(.system(size: 11)).foregroundStyle(.red).padding(.top, 4)
                }
            } else {
                Text(L("还没有可用的设计。")).font(.system(size: 11.5)).foregroundStyle(Theme.muted)
            }
        }
    }

    // MARK: input

    private var inputBlock: some View {
        Block("输入") {
            Picker("", selection: $mode) {
                Text(L("Counts 表格")).tag(AnalysisInputMode.counts)
                Text(L("FASTQ 样本表")).tag(AnalysisInputMode.fastq)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 240).padding(.bottom, 10)

            if mode == .counts {
                HStack(spacing: Theme.s2) {
                    Button(L("选择 counts CSV")) { showImporter = true }.buttonStyle(SecondaryButtonStyle())
                    Text(countsURL?.lastPathComponent ?? L("未选择"))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(countsURL == nil ? Theme.faint : Theme.ink2)
                    Spacer()
                    Button(L("下载模板")) { exportTemplate() }.buttonStyle(SecondaryButtonStyle())
                    Button(L("运行分析")) { run() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(countsURL == nil || isRunning)
                }
                Text(L("长表：variant_id, sample, reads, condition, replicate, sublibrary, class（class=synonymous 时作为 null）。"))
                    .font(.system(size: 11)).foregroundStyle(Theme.faint).padding(.top, 6)
            } else {
                HStack(spacing: Theme.s2) {
                    Button(L("选择样本表")) { showSheetImporter = true }.buttonStyle(SecondaryButtonStyle())
                    Text(sheetURL?.lastPathComponent ?? L("未选择"))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(sheetURL == nil ? Theme.faint : Theme.ink2)
                    Spacer()
                    Toggle(L("fastp 过滤"), isOn: Binding(
                        get: { FastpRunner.enabled },
                        set: { UserDefaults.standard.set($0, forKey: "fastpEnabled") }))
                        .toggleStyle(InkToggleStyle())
                    Button(L("FASTQ → 效应")) { runFastq() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(sheetURL == nil || isRunning || model.design() == nil)
                }
                Text(L("样本表列：sample,sublibrary,replicate,condition,r1,r2；condition 用 input/selected。"))
                    .font(.system(size: 11)).foregroundStyle(Theme.faint).padding(.top, 6)
                if FastpRunner.enabled && !FastpRunner.available() {
                    Text(F("未找到 fastp（%@），请在设置里改路径或关闭 fastp。", FastpRunner.binaryPath))
                        .font(.system(size: 11)).foregroundStyle(.red)
                }
            }
            HStack {
                Spacer()
                Button(L("运行演示")) { runDemo() }.buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    // MARK: view switch

    private var viewSwitch: some View {
        Block("视角") {
            Picker("", selection: $viewMode) {
                Text(L("逐组解析")).tag(AnalysisViewMode.perGroup)
                Text(L("跨组归一")).tag(AnalysisViewMode.joint)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 260)
            Text(viewMode == .perGroup
                 ? L("只分析单个分组及其重复；结论仅在该分组的筛选范围内成立。")
                 : L("各组按 WT 对照的 fold-change 归一，合并成一个蛋白层面的数据集，并给出组间相关。"))
                .font(.system(size: 11.5)).foregroundStyle(Theme.muted).padding(.top, 6)
        }
    }

    // MARK: per group

    private var perGroupView: some View {
        let g = groups.first { $0.name == selectedGroup } ?? groups.first
        return VStack(alignment: .leading, spacing: Theme.s4) {
            if groups.isEmpty {
                Text(L("没有可用的分组结果。")).foregroundStyle(Theme.muted)
            } else {
                Block("分组") {
                    HStack(spacing: 6) {
                        ForEach(groups) { item in
                            Button { selectedGroup = item.name } label: {
                                Text(item.name)
                                    .font(.system(size: 11.5, weight: (g?.name == item.name) ? .semibold : .regular))
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(g?.name == item.name ? Theme.ink : Color.clear)
                                    .foregroundStyle(g?.name == item.name ? Theme.paper : Theme.ink2)
                                    .overlay(Rectangle().stroke(Theme.hairlineStrong, lineWidth: 1))
                            }.buttonStyle(.plain)
                        }
                        Spacer()
                    }
                    if let g {
                        Text(F("分组 %@：基线（WT 对照平均 effect）= %.3f，变体 %d 个", g.name, g.wtBaseline, g.effects.count))
                            .font(.system(size: 11)).foregroundStyle(Theme.muted).padding(.top, 6)
                        Text(F("结论仅适用于 %@ 的筛选范围，不能直接与其他分组比较。", g.name))
                            .font(.system(size: 11)).foregroundStyle(Theme.faint)
                    }
                }
                if let g {
                    effectsTable(g.effects.filter { $0.flag != "INSUFFICIENT" }, title: g.name)
                    structureBlock(g.effects).id("structure")
                }
            }
        }
    }

    // MARK: joint

    private var jointView: some View {
        VStack(alignment: .leading, spacing: Theme.s4) {
            Block("联合结果") {
                HStack(spacing: 0) {
                    MetricCell(label: "合并变体", value: "\(rows.count)")
                    divider
                    MetricCell(label: "分组", value: "\(groups.count)")
                    divider
                    MetricCell(label: "显著 (q<0.05)", value: "\(rows.filter { $0.q < 0.05 }.count)")
                    divider
                    MetricCell(label: "中位 |effect|", value: String(format: "%.2f", medianAbs()))
                }
                .padding(.vertical, 4)
                if groups.count > 1 {
                    Text(L("已按各组 WT 对照归一；跨组比较建议同时看下方的组间相关。"))
                        .font(.system(size: 11)).foregroundStyle(Theme.muted).padding(.top, 6)
                }
            }
            effectsTable(rows.sorted { abs($0.effect) > abs($1.effect) }, title: L("联合"))
            if groups.count > 1 { correlationBlock }
            if !hits.isEmpty { hitsBlock }
            if !heatmapData.positions.isEmpty { heatmapBlock }
            structureBlock(rows).id("structure")
        }
    }

    private func structureBlock(_ effects: [VariantEffect]) -> some View {
        Block("结构映射") {
            if pdbAtoms.isEmpty {
                HStack(spacing: Theme.s2) {
                    Button(L("导入结构文件 (PDB)")) { showPDBImporter = true }
                        .buttonStyle(SecondaryButtonStyle())
                    Text(L("可选：把归一后的 effect 映射到结构上，用于看突变在结构中的分布。"))
                        .font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                }
            } else {
                HStack(spacing: 8) {
                    Text(pdbName ?? "PDB").font(.system(size: 12, weight: .medium))
                    Text(L("选择要映射的链（同源二聚体可只选一条）")).font(.system(size: 11)).foregroundStyle(Theme.muted)
                    ForEach(PDBParser.chains(pdbAtoms), id: \.self) { ch in
                        let on = pdbChains.contains(ch)
                        Button {
                            if on { pdbChains.remove(ch) } else { pdbChains.insert(ch) }
                        } label: {
                            Text(ch).font(.system(size: 11, design: .monospaced))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(on ? Theme.ink : Color.clear)
                                .foregroundStyle(on ? Theme.paper : Theme.ink2)
                                .overlay(Rectangle().stroke(Theme.hairlineStrong, lineWidth: 1))
                        }.buttonStyle(.plain)
                    }
                    Spacer()
                    Button(L("重新选择")) { showPDBImporter = true }.buttonStyle(SecondaryButtonStyle())
                }
                HStack(spacing: 8) {
                    Text(L("配色")).font(.system(size: 11)).foregroundStyle(Theme.muted)
                    Picker("", selection: $scheme) {
                        ForEach(StructureColorScheme.allCases, id: \.self) { sc in
                            Text(L(sc.title)).tag(sc)
                        }
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 180)
                    Spacer()
                    Button(L("导出 PNG")) {
                        exportStructurePNG(effects)
                    }.buttonStyle(SecondaryButtonStyle())
                }
                if let note = identicalNote {
                    Text(note).font(.system(size: 10.5)).foregroundStyle(Theme.faint)
                }
                StructureMapView(atoms: pdbAtoms, effectByResidue: effectByResidue(effects),
                                 chains: pdbChains, scheme: scheme)
                    .frame(height: 360)
                    .overlay(Rectangle().stroke(Theme.hairline, lineWidth: 1))
                HStack(spacing: 6) {
                    Text("−2").font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.faint)
                    ForEach([-2.0, 0.0, 2.0], id: \.self) { v in
                        Rectangle()
                            .fill(Color(nsColor: StructureSceneBuilder.color(for: v, scheme: scheme)))
                            .frame(width: 28, height: 8)
                    }
                    Text("+2").font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.faint)
                    Text(L("拖拽旋转、滚轮缩放；灰色 = 无数据。"))
                        .font(.system(size: 10.5)).foregroundStyle(Theme.faint)
                }.padding(.top, 4)
            }
        }
    }

    private func effectByResidue(_ effects: [VariantEffect]) -> [Int: Double] {
        guard let d = model.design() else { return [:] }
        var pos: [String: Int] = [:]
        for v in d.designVariants + d.qcVariants { pos[v.id] = v.position }
        var out: [Int: Double] = [:]
        for r in effects { if let p = pos[r.variant] { out[p] = r.effect } }
        return out
    }

    private var correlationBlock: some View {
        let data = JointAnalysis.correlation(Dictionary(uniqueKeysWithValues: groups.map { ($0.name, $0.effects) }))
        return Block("组间相关（共享变体的 Pearson r）") {
            if data.names.count < 2 {
                Text(L("需要至少两个分组才能计算组间相关。")).font(.system(size: 11.5)).foregroundStyle(Theme.muted)
            } else {
                Grid(horizontalSpacing: 1, verticalSpacing: 1) {
                    GridRow {
                        Text("").frame(width: 90)
                        ForEach(data.names, id: \.self) { n in
                            Text(n).font(.system(size: 9.5, design: .monospaced))
                                .frame(width: 64, height: 22)
                        }
                    }
                    ForEach(data.names.indices, id: \.self) { i in
                        GridRow {
                            Text(data.names[i]).font(.system(size: 9.5, design: .monospaced))
                                .frame(width: 90, height: 22, alignment: .leading)
                            ForEach(data.names.indices, id: \.self) { j in
                                let r = data.matrix[i][j]
                                Text(r.isNaN ? "—" : String(format: "%.2f", r))
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .frame(width: 64, height: 22)
                                    .background(Color(white: 1 - 0.18 * max(0, r)))
                                    .foregroundStyle(r.isNaN ? Theme.faint : Theme.ink)
                            }
                        }
                    }
                }
            }
        }
    }

    private func effectsTable(_ list: [VariantEffect], title: String) -> some View {
        Block(F("%@ · 变体效应", title)) {
            HStack {
                Text("variant").frame(width: 150, alignment: .leading)
                Text("effect").frame(width: 80, alignment: .trailing)
                Text("CI").frame(width: 160, alignment: .trailing)
                Text("q").frame(width: 80, alignment: .trailing)
                Text("flag").frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.system(size: 10.5)).foregroundStyle(Theme.muted).padding(.vertical, 6)
            ForEach(Array(list.prefix(300).enumerated()), id: \.element.variant) { idx, r in
                HStack {
                    Text(r.variant).font(.system(size: 11, design: .monospaced)).frame(width: 150, alignment: .leading)
                    Text(String(format: "%.3f", r.effect)).font(.system(size: 11, design: .monospaced)).frame(width: 80, alignment: .trailing)
                    Text(ciText(r)).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.muted)
                        .frame(width: 160, alignment: .trailing)
                    Text(String(format: "%.3f", r.q)).font(.system(size: 11, design: .monospaced)).frame(width: 80, alignment: .trailing)
                    Text(r.flag).font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(r.q < 0.05 ? Theme.ink : Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(height: 26)
                .background(idx % 2 == 1 ? Theme.zebra : Color.clear)
            }
        }
    }

    private var hitsBlock: some View {
        Block("命中（|effect| ≥ cutoff 且 q < 0.05）") {
            HStack(spacing: Theme.s3) {
                Text(L("cutoff")).font(.system(size: 12)).foregroundStyle(Theme.muted)
                Slider(value: $cutoff, in: 0.5...3.0, step: 0.1).frame(width: 220)
                Text(String(format: "%.1f", cutoff)).font(.system(size: 12, design: .monospaced))
                Spacer()
                Text(F("%d 个命中", hits.count)).font(.system(size: 12)).foregroundStyle(Theme.muted)
            }.padding(.vertical, 8)
            ForEach(Array(hits.prefix(50).enumerated()), id: \.element.variant) { idx, r in
                HStack {
                    Text(r.variant).font(.system(size: 11, design: .monospaced)).frame(width: 150, alignment: .leading)
                    Text(String(format: "%.3f", r.effect)).font(.system(size: 11, design: .monospaced)).frame(width: 80, alignment: .trailing)
                    Text(ciText(r)).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.muted)
                        .frame(width: 160, alignment: .trailing)
                    Text(String(format: "%.4f", r.q)).font(.system(size: 11, design: .monospaced)).frame(width: 80, alignment: .trailing)
                    Spacer()
                }.frame(height: 24).background(idx % 2 == 1 ? Theme.zebra : Color.clear)
            }
        }
    }

    private var heatmapBlock: some View {
        Block("效应热图（position × aa）") {
            let data = heatmapData
            MissenseHeatmap(effects: data.effects, positions: data.positions,
                            aa: Array("ACDEFGHIKLMNPQRSTVWY").map(String.init) + ["*"])
                .padding(.top, 6)
        }
    }

    private var recentRuns: some View {
        Block("最近运行") {
            ForEach(Array(runs.enumerated()), id: \.element.id) { idx, r in
                HStack(spacing: Theme.s2) {
                    Text(r.title).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                    Text(r.createdAt, format: .dateTime.month().day().hour().minute())
                        .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.muted)
                    Button(L("载入")) { loadRun(r) }.buttonStyle(SecondaryButtonStyle())
                    Button { RunStore.shared.delete(r.id); loadRuns() } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain)
                }
                .frame(height: 34).background(idx % 2 == 1 ? Theme.zebra : Color.clear)
            }
        }
    }

    // MARK: computed

    private var hits: [VariantEffect] {
        rows.filter { abs($0.effect) >= cutoff && $0.q < 0.05 }.sorted { abs($0.effect) > abs($1.effect) }
    }

    private var heatmapData: (positions: [Int], effects: [String: Double]) {
        guard let d = model.design() else { return ([], [:]) }
        var meta: [String: (Int, String)] = [:]
        for v in d.designVariants + d.qcVariants { meta[v.id] = (v.position, v.mut) }
        var effects: [String: Double] = [:]
        var positions = Set<Int>()
        for r in rows {
            guard let m = meta[r.variant] else { continue }
            effects["\(m.0):\(m.1)"] = r.effect
            positions.insert(m.0)
        }
        return (positions.sorted(), effects)
    }

    private var divider: some View { Rectangle().fill(Theme.hairline).frame(width: 1, height: 34) }

    private func ciText(_ r: VariantEffect) -> String {
        guard r.ciLow.isFinite, r.ciHigh.isFinite else { return "—" }
        return String(format: "[%.2f, %.2f]", r.ciLow, r.ciHigh)
    }

    private func medianAbs() -> Double {
        let xs = rows.map { abs($0.effect) }.sorted()
        guard !xs.isEmpty else { return 0 }
        return xs[xs.count / 2]
    }

    // MARK: run

    private func groupsFor(_ samples: [CountsSample]) -> [GroupResult] {
        let plan = model.current?.screeningPlan
        var map: [String: [CountsSample]] = [:]
        if let plan, !plan.groups.isEmpty {
            for g in plan.groups {
                let set = Set(g.sublibraryIDs)
                let ss = samples.filter { set.contains($0.sublibrary) }
                if !ss.isEmpty { map[g.name] = ss }
            }
            let covered = Set(plan.groups.flatMap(\.sublibraryIDs))
            let rest = samples.filter { !covered.contains($0.sublibrary) }
            if !rest.isEmpty { map["未分组"] = rest }
        } else {
            map["全部"] = samples
        }
        let d = model.design()
        let wt = Set((d?.designVariants ?? []).filter { $0.mut == $0.wt }.map(\.id))
        return map.keys.sorted().map { name in
            let ss = map[name] ?? []
            let eff = AnalysisEngine.run(samples: ss, variants: variantList(), synonymous: synSet())
            let norm = JointAnalysis.normalizeWt(eff.filter { $0.flag == "OK" }, wtIDs: wt)
            return GroupResult(name: name, effects: norm.rows, wtBaseline: norm.baseline)
        }
    }

    private func variantList() -> [String] {
        guard let d = model.design() else { return [] }
        return (d.designVariants + d.qcVariants).map(\.id)
    }

    private func synSet() -> Set<String> {
        Set((model.design()?.qcVariants ?? []).filter { $0.source == .synQC }.map(\.id))
    }

    private func finish(samples: [CountsSample]) {
        groups = groupsFor(samples)
        selectedGroup = groups.first?.name
        let merged = JointAnalysis.merge(Dictionary(uniqueKeysWithValues: groups.map { ($0.name, $0.effects) }),
                                         synonymous: synSet())
        rows = merged
        variantCount = merged.count
        sampleCount = samples.count
        isRunning = false
        runCtx = designCtx
    }

    private func run() {
        guard let url = countsURL else { return }
        do {
            let parsed = try CountsCSV.parse(url: url)
            finish(samples: parsed.samples)
            saveRun(title: "analysis \(url.deletingPathExtension().lastPathComponent)")
        } catch { errorText = "\(error)"; isRunning = false }
    }

    private func runDemo() {
        let variants = variantList()
        guard !variants.isEmpty else { return }
        var ids: [String] = []
        var seen = Set<Int>()
        if let d = model.design() {
            for v in d.designVariants where !seen.contains(v.position) {
                seen.insert(v.position); ids.append(v.id)
                if ids.count == 6 { break }
            }
        }
        let syn = Array(synSet()).sorted()
        let all = ids + syn
        let synS = synSet()
        func counts(_ enriched: Bool) -> [String: Int] {
            var c: [String: Int] = [:]
            for (i, v) in all.enumerated() {
                if synS.contains(v) { c[v] = 1000; continue }
                switch i {
                case 0: c[v] = enriched ? 480 : 120
                case 1: c[v] = enriched ? 60 : 100
                case 2: c[v] = enriched ? 200 : 90
                default: c[v] = 100
                }
            }
            return c
        }
        var ins: [CountsSample] = [], sels: [CountsSample] = []
        for rep in 1...3 {
            ins.append(CountsSample(name: "in\(rep)", condition: "input", replicate: rep,
                                    sublibrary: "SL01", counts: counts(false)))
            sels.append(CountsSample(name: "sel\(rep)", condition: "selected", replicate: rep,
                                     sublibrary: "SL01", counts: counts(true)))
        }
        finish(samples: ins + sels)
        saveRun(title: "analysis demo")
    }

    private func runFastq() {
        guard let url = sheetURL, model.design() != nil else { return }
        do {
            let parsed = try QCSampleSheet.parse(url: url)
            if !parsed.errors.isEmpty {
                errorText = parsed.errors.map(\.message).joined(separator: "；")
                return
            }
            let specs = parsed.samples
            let designs: [String: QCDesign] = Dictionary(uniqueKeysWithValues:
                model.design()!.sublibraries.compactMap { s -> (String, QCDesign)? in
                    guard let q = model.qcDesign(for: s.id) else { return nil }
                    return (s.id, q)
                })
            isRunning = true; errorText = nil
            let useFastp = FastpRunner.enabled
            Task.detached {
                do {
                    let tmp = FileManager.default.temporaryDirectory
                        .appendingPathComponent("dms-fastp-\(UUID().uuidString)")
                    if useFastp { try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true) }
                    var samples: [CountsSample] = []
                    for spec in specs {
                        guard let design = designs[spec.sublibrary] else { continue }
                        var r1 = URL(fileURLWithPath: spec.r1)
                        var r2 = spec.r2.map { URL(fileURLWithPath: $0) }
                        if useFastp {
                            r1 = try FastpRunner.trim(r1, into: tmp)
                            r2 = try r2.map { try FastpRunner.trim($0, into: tmp) }
                        }
                        let res = try QCCounter.countPaired(r1: r1, r2: r2, design: design)
                        samples.append(CountsSample(name: spec.name, condition: spec.condition,
                                                    replicate: spec.replicate, sublibrary: spec.sublibrary,
                                                    counts: res.counts, librarySize: res.anchoredReads))
                    }
                    let collected = samples
                    await MainActor.run {
                        finish(samples: collected)
                        saveRun(title: "FASTQ \(url.lastPathComponent)")
                    }
                } catch {
                    await MainActor.run { errorText = "\(error)"; isRunning = false }
                }
            }
        } catch { errorText = "\(error)" }
    }

    private func exportTemplate() {
        let csv = """
        variant_id,sample,reads,condition,replicate,sublibrary,class
        H1A,libA_T0_rep1,120,input,1,SL01,missense
        H1A,libA_T1_rep1,480,selected,1,SL01,missense
        SYN-1,libA_T0_rep1,1000,input,1,SL01,synonymous
        SYN-1,libA_T1_rep1,950,selected,1,SL01,synonymous
        """
        let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dms_counts_template.csv")
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func exportEffects() {
        guard let p = model.current else { return }
        let dir = ProjectStore.shared.projectDir(p.id)
            .appendingPathComponent("exports/analysis-\(Int(Date().timeIntervalSince1970))")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var csv = "variant,effect,se,ci_low,ci_high,q,flag,groups\n"
        for r in rows {
            csv += "\(r.variant),\(r.effect),\(r.se),\(r.ciLow),\(r.ciHigh),\(r.q),\(r.flag),joint\n"
        }
        try? csv.write(to: dir.appendingPathComponent("effects.csv"), atomically: true, encoding: .utf8)
        NSWorkspace.shared.activateFileViewerSelecting([dir])
        model.banner = F("已导出 %d 个文件", 1)
    }

    private func loadDemoStructure() {
        guard pdbAtoms.isEmpty else { return }
        var atoms: [PDBAtom] = []
        for chain in ["A", "B"] {
            let off: Float = chain == "A" ? 0 : 6
            for i in 1...60 {
                let t = Double(i) * 0.35
                atoms.append(PDBAtom(chain: chain, resSeq: i, resName: "ALA",
                                     x: Float(cos(t) * 8) + off,
                                     y: Float(sin(t) * 8) + (chain == "B" ? 6 : 0),
                                     z: Float(t * 1.5)))
            }
        }
        pdbAtoms = atoms
        pdbChains = ["A"]
        pdbName = "demo-helix.pdb"
        identicalNote = L("检测到相同链组：A/B（默认只映射 A）")
    }

    private func exportStructurePNG(_ effects: [VariantEffect]) {
        guard let p = model.current,
              let image = StructureMapView.snapshot(atoms: pdbAtoms,
                                                    effectByResidue: effectByResidue(effects),
                                                    chains: pdbChains, scheme: scheme) else { return }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        let dir = ProjectStore.shared.projectDir(p.id)
            .appendingPathComponent("exports/structure-\(Int(Date().timeIntervalSince1970))")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? png.write(to: dir.appendingPathComponent("structure.png"))
        NSWorkspace.shared.activateFileViewerSelecting([dir])
        model.banner = F("已导出 %d 个文件", 1)
    }

    private func loadRuns() {
        var seen = Set<String>()
        runs = RunStore.shared.list(type: "analysis", projectID: model.current?.id).filter {
            seen.insert($0.title).inserted
        }
    }

    private func loadRun(_ r: RunRecord) {
        guard let payload = try? JSONDecoder().decode(AnalysisPayload.self, from: r.payload) else { return }
        rows = payload.joint.filter { $0.flag != "INSUFFICIENT" }
        groups = payload.groups
        selectedGroup = payload.groups.first?.name
        runCtx = payload.context
        variantCount = payload.joint.count
    }

    private func saveRun(title: String) {
        if let last = runs.first, last.title == title, Date().timeIntervalSince(last.createdAt) < 300 { return }
        let payload = AnalysisPayload(joint: rows, groups: groups, context: runCtx ?? designCtx)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        RunStore.shared.save(type: "analysis", projectID: model.current?.id, title: title, payload: data)
        loadRuns()
    }
}

enum CountsCSV {
    struct Parsed {
        var samples: [CountsSample]
        var variants: [String]
        var synonymous: Set<String>
    }

    static func parse(url: URL) throws -> Parsed {
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" }).map(String.init)
        guard let headerLine = lines.first else {
            throw SequenceError.rangeOutOfBounds("counts CSV 为空")
        }
        let header = headerLine.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        func idx(_ name: String) -> Int? { header.firstIndex(of: name) }
        guard let vi = idx("variant_id"), let si = idx("sample"), let ri = idx("reads") else {
            throw SequenceError.rangeOutOfBounds("counts CSV 需要列：variant_id, sample, reads")
        }
        let ci = idx("condition"), repi = idx("replicate"), subi = idx("sublibrary"), cli = idx("class")

        var bySample: [String: CountsSample] = [:]
        var variants = Set<String>()
        var synonymous = Set<String>()

        for line in lines.dropFirst() {
            let cols = line.split(separator: ",", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard cols.count > max(vi, si, ri) else { continue }
            let v = cols[vi], sample = cols[si]
            guard let reads = Int(cols[ri]) else { continue }
            variants.insert(v)
            if let cli, cols.count > cli, cols[cli].lowercased().hasPrefix("syn") { synonymous.insert(v) }
            if bySample[sample] == nil {
                let cond = (ci.map { cols.count > $0 ? cols[$0] : "" } ?? "").isEmpty
                    ? (sample.lowercased().contains("input") || sample.contains("T0") ? "input" : "selected")
                    : cols[ci!]
                let rep = (repi.flatMap { cols.count > $0 ? Int(cols[$0]) : nil })
                    ?? Int(sample.suffix(1)) ?? 1
                let sub = subi.map { cols.count > $0 ? cols[$0] : "" } ?? ""
                bySample[sample] = CountsSample(name: sample, condition: cond, replicate: rep,
                                                sublibrary: sub, counts: [:])
            }
            bySample[sample]?.counts[v, default: 0] += reads
        }
        guard !bySample.isEmpty else { throw SequenceError.rangeOutOfBounds("counts CSV 没有数据行") }
        return Parsed(samples: Array(bySample.values), variants: Array(variants), synonymous: synonymous)
    }
}
