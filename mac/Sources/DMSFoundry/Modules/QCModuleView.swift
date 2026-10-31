import SwiftUI
import AppKit
import UniformTypeIdentifiers
import DMSEngine

struct QCSampleResult: Codable, Identifiable {
    var name: String
    var sublibrary: String
    var summary: QCSummary
    var rows: [QCVariantRow]
    var id: String { name }
}

struct QCRunPayload: Codable {
    var samples: [QCSampleResult]
    var context: DesignContextInfo?
}

struct QCModuleView: View {
    @EnvironmentObject private var model: AppModel

    @State private var subID: String = ""
    @State private var fastqURL: URL?
    @State private var isRunning = false
    @State private var result: QCCountResult?
    @State private var rows: [QCVariantRow] = []
    @State private var summary: QCSummary?
    @State private var errorText: String?
    @State private var showImporter = false
    @State private var sheetURL: URL?
    @State private var showSheetImporter = false
    @State private var sampleResults: [QCSampleResult] = []
    @State private var selectedSample: String?
    @State private var runs: [RunRecord] = []
    @State private var sheetIssues: [SampleSheetIssue] = []
    @State private var rollup: [QCSublibraryMetric] = []
    @State private var designCtx: DesignContextInfo?
    @State private var runCtx: DesignContextInfo?

    private var planes: [SubLibrary] {
        model.design()?.sublibraries ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.s4) {
                header
                designContextBlock
                whyBlock
                runBlock

                if let s = summary {
                    headlineBlock(s)
                    metricsBlock(s)
                    findingsBlock(s)
                }
                if !rows.isEmpty || !sampleResults.isEmpty {
                    detailsBlock
                }
                if !sampleResults.isEmpty {
                    sampleTable
                }
                if !sheetIssues.isEmpty {
                    issuesBlock
                }
                if !rollup.isEmpty {
                    rollupBlock
                }
                if !runs.isEmpty {
                    recentRuns
                }
                if let e = errorText {
                    Text(e).font(.system(size: 12)).foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 40)
            .frame(maxWidth: Theme.contentMax, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Theme.paper)
        .onAppear {
            if ProcessInfo.processInfo.environment["DMS_QC_DEMO"] == "1", summary == nil {
                if subID.isEmpty { subID = planes.first?.id ?? "" }
                runDemo()
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: fastqTypes, allowsMultipleSelection: false) { res in
            if case .success(let urls) = res { fastqURL = urls.first }
        }
        .fileImporter(isPresented: $showSheetImporter, allowedContentTypes: [.commaSeparatedText, .plainText, .data],
                      allowsMultipleSelection: false) { res in
            if case .success(let urls) = res { sheetURL = urls.first }
        }
        .onAppear {
            loadRuns()
            refreshContext()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("文库质控")).font(.system(size: 20, weight: .semibold))
            Text(L("导入扩增子 FASTQ，按设计清单逐变体对账：锚定率、覆盖、缺失与均一性。"))
                .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
        }
    }

    private var designContextBlock: some View {
        Block("设计上下文") {
            if let c = designCtx {
                HStack(spacing: 10) {
                    Text(c.projectName).font(.system(size: 12, weight: .medium))
                    Text("· \(c.target)").font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                    Text("· \(c.enzyme) · \(c.stepNt) nt").font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                    Text("· \(c.variants) 变体 / \(c.sublibraries) 子库").font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                    Text("· 指纹 \(c.hash)").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.faint)
                    Spacer()
                    Button(L("打开文库设计")) { model.section = .design }
                        .buttonStyle(SecondaryButtonStyle())
                }
                if let loaded = runCtx, loaded.hash != c.hash {
                    Text(L("这份结果基于旧设计（指纹 \(loaded.hash)），当前设计已变化，请重跑。"))
                        .font(.system(size: 11)).foregroundStyle(.red).padding(.top, 4)
                }
            } else {
                Text(L("还没有可用的设计：请先在设计与生成文库。"))
                    .font(.system(size: 11.5)).foregroundStyle(Theme.muted)
            }
        }
    }

    private var whyBlock: some View {
        Block("为什么先做这一步") {
            VStack(alignment: .leading, spacing: 8) {
                reasonRow("文库全不全？", "每个设计变体是否真的被合成/克隆进池子——缺失的变体在下游永远没有数据。")
                reasonRow("测得够不够深？", "每个变体的 reads 是否支撑效应估计；100× 以下弱效应会被噪声淹没。")
                reasonRow("分布均不均？", "少数变体是否垄断了测序量；不均一会让部分变体被系统性低估。")
                Text("跳过这一步的代价：花几周做筛选与测序，最后才发现一半变体根本不在文库里。")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                    .padding(.top, 4)
            }
        }
    }

    private func reasonRow(_ q: String, _ a: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle().fill(Theme.ink).frame(width: 4, height: 4).padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(q).font(.system(size: 12.5, weight: .medium))
                Text(a).font(.system(size: 11.5)).foregroundStyle(Theme.muted)
            }
        }
    }

    private func headlineBlock(_ s: QCSummary) -> some View {
        Block("结论") {
            HStack(alignment: .top, spacing: 12) {
                Text(s.verdict.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(s.verdict == "pass" ? Theme.wash : Theme.ink)
                    .foregroundStyle(s.verdict == "pass" ? Theme.ink : Theme.paper)
                Text(QCDiagnosis.headline(s))
                    .font(.system(size: 14, weight: .medium))
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    private func metricsBlock(_ s: QCSummary) -> some View {
        Block("关键指标") {
            HStack(spacing: 0) {
                MetricCell(label: "reads", value: "\(s.totalReads)")
                divider
                MetricCell(label: "锚定率", value: pct(s.anchoredRate))
                divider
                MetricCell(label: "观测率", value: pct(s.observedRate), accent: s.observedRate < 0.95)
                divider
                MetricCell(label: "零计数", value: "\(s.zeroCount)")
                divider
                MetricCell(label: "中位覆盖", value: String(format: "%.0f×", s.medianCoverage))
                divider
                MetricCell(label: "Gini", value: String(format: "%.2f", s.gini))
            }
            .padding(.vertical, 6)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(QCDiagnosis.metricMeaning, id: \.0) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Text(item.0).font(.system(size: 11, weight: .medium))
                            .frame(width: 60, alignment: .leading)
                        Text(item.1).font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                }
            }
            .padding(.top, 6)
        }
    }

    private func findingsBlock(_ s: QCSummary) -> some View {
        let findings = QCDiagnosis.findings(s, spectrum: s.spectrum)
        return Block("诊断与建议") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(findings.enumerated()), id: \.offset) { _, f in
                    HStack(alignment: .top, spacing: 10) {
                        Text(badge(f.severity))
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .frame(width: 44, alignment: .leading)
                            .foregroundStyle(f.severity == .pass ? Theme.muted : Theme.ink)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(f.title).font(.system(size: 12.5, weight: .medium))
                            Text(f.detail).font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                            HStack(spacing: 4) {
                                Text("→").font(.system(size: 11)).foregroundStyle(Theme.faint)
                                Text(f.action).font(.system(size: 11.5))
                            }
                        }
                    }
                    .padding(.bottom, 2)
                }
                HStack(spacing: Theme.s2) {
                    Button(L("导出报告")) { exportReport() }
                        .buttonStyle(SecondaryButtonStyle())
                    Button(L("导出缺失清单")) { exportMissing() }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(missingRows.isEmpty)
                    Button(L("补测建议：约 \(QCDiagnosis.readsFor100x(designed: s.designedVariants, anchoredRate: s.anchoredRate)) 条 reads")) {}
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(true)
                }
            }
        }
    }

    private func badge(_ s: QCFinding.Severity) -> String {
        switch s {
        case .block: return "阻断"
        case .warn: return "警告"
        case .info: return "提示"
        case .pass: return "通过"
        }
    }

    private var missingRows: [QCVariantRow] { rows.filter { $0.observed < 10 } }

    private var detailsBlock: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: Theme.s3) {
                if let s = summary { sublibraryTable(s) }
                if !rows.isEmpty { variantTable }
                if !sampleResults.isEmpty { sampleTable }
            }
            .padding(.top, 8)
        } label: {
            Text(L("明细数据")).font(.system(size: 12, weight: .semibold))
        }
    }

    private var runBlock: some View {
        Block("运行") {
            HStack(spacing: Theme.s3) {
                LabeledRow("子库") {
                    Picker("", selection: $subID) {
                        ForEach(planes) { s in
                            Text("\(s.id)  aa \(s.aaStart)–\(s.aaEnd)").tag(s.id)
                        }
                    }
                    .labelsHidden().frame(width: 220)
                }
                .frame(width: 380)
            }
            HStack(spacing: Theme.s2) {
                Button(L("选择 FASTQ")) { showImporter = true }
                    .buttonStyle(SecondaryButtonStyle())
                Text(sheetURL?.lastPathComponent ?? fastqURL?.lastPathComponent ?? L("未选择"))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(fastqURL == nil ? Theme.faint : Theme.ink2)
                Spacer()
                if isRunning { ProgressView().controlSize(.small) }
                Button(L("运行质控")) { run() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(fastqURL == nil || isRunning || subID.isEmpty || model.design() == nil)
                if summary != nil {
                    Button(L("导出报告")) { exportReport() }
                        .buttonStyle(SecondaryButtonStyle())
                }
                Button(L("选择样本表")) { showSheetImporter = true }
                    .buttonStyle(SecondaryButtonStyle())
                Button(L("运行样本表")) { runSheet() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(sheetURL == nil || isRunning || model.design() == nil)
                Button(L("运行演示")) { runDemo() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(isRunning || subID.isEmpty || model.design() == nil)
            }
            .padding(.top, 10)

            if model.design() == nil {
                Text(L("需要先在设计模块生成文库。"))
                    .font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.top, 6)
            }
        }
    }

    private func overview(_ s: QCSummary) -> some View {
        Block("总览") {
            HStack(spacing: 0) {
                MetricCell(label: "reads", value: "\(s.totalReads)")
                divider
                MetricCell(label: "锚定率", value: pct(s.anchoredRate))
                divider
                MetricCell(label: "观测率", value: pct(s.observedRate), accent: s.observedRate < 0.95)
                divider
                MetricCell(label: "零计数", value: "\(s.zeroCount)")
                divider
                MetricCell(label: "中位覆盖", value: String(format: "%.0f×", s.medianCoverage))
                divider
                MetricCell(label: "Gini", value: String(format: "%.2f", s.gini))
                divider
                MetricCell(label: "判定", value: s.verdict.uppercased(), accent: s.verdict != "pass")
            }
            .padding(.vertical, 4)
            Text(L("错误谱：WT \(s.spectrum.wildType) · 已知单点 \(s.spectrum.knownSingle) · 未知单点 \(s.spectrum.unknownSingle) · 多点 \(s.spectrum.multi) · 未锚定 \(s.spectrum.unanchored)"))
                .font(.system(size: 11)).foregroundStyle(Theme.muted).padding(.top, 8)
        }
    }

    private func sublibraryTable(_ s: QCSummary) -> some View {
        Block("子库") {
            HStack {
                Text(L("子库")).frame(width: 70, alignment: .leading)
                Text("reads").frame(width: 90, alignment: .trailing)
                Text(L("设计")).frame(width: 70, alignment: .trailing)
                Text(L("观测")).frame(width: 70, alignment: .trailing)
                Text(L("中位覆盖")).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.system(size: 10.5)).foregroundStyle(Theme.muted)
            .padding(.vertical, 6)
            ForEach(Array(s.sublibrary.enumerated()), id: \.offset) { idx, m in
                HStack {
                    Text(m.sublibrary).font(.system(size: 11, design: .monospaced)).frame(width: 70, alignment: .leading)
                    Text("\(m.reads)").font(.system(size: 11, design: .monospaced)).frame(width: 90, alignment: .trailing)
                    Text("\(m.designed)").font(.system(size: 11, design: .monospaced)).frame(width: 70, alignment: .trailing)
                    Text("\(m.observed)").font(.system(size: 11, design: .monospaced)).frame(width: 70, alignment: .trailing)
                    Text(String(format: "%.0f×", m.medianCoverage)).font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(height: 26)
                .background(idx % 2 == 1 ? Theme.zebra : Color.clear)
            }
        }
    }

    private var variantTable: some View {
        Block("变体对账（前 300 条）") {
            HStack {
                Text("variant").frame(width: 150, alignment: .leading)
                Text(L("位置")).frame(width: 60, alignment: .trailing)
                Text(L("突变")).frame(width: 90, alignment: .leading)
                Text("observed").frame(width: 90, alignment: .trailing)
                Text("flag").frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.system(size: 10.5)).foregroundStyle(Theme.muted).padding(.vertical, 6)
            ForEach(Array(rows.prefix(300).enumerated()), id: \.element.id) { idx, r in
                HStack {
                    Text(r.id).font(.system(size: 11, design: .monospaced)).frame(width: 150, alignment: .leading)
                    Text("\(r.position)").font(.system(size: 11, design: .monospaced)).frame(width: 60, alignment: .trailing)
                    Text(r.aaChange).font(.system(size: 11)).frame(width: 90, alignment: .leading)
                    Text("\(r.observed)").font(.system(size: 11, design: .monospaced)).frame(width: 90, alignment: .trailing)
                    Text(r.flag).font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(r.flag == "OK" ? Theme.muted : Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(height: 26)
                .background(idx % 2 == 1 ? Theme.zebra : Color.clear)
            }
        }
    }

    private var divider: some View { Rectangle().fill(Theme.hairline).frame(width: 1, height: 34) }

    private func pct(_ x: Double) -> String { String(format: "%.1f%%", x * 100) }

    private var fastqTypes: [UTType] {
        var t: [UTType] = []
        for ext in ["fastq", "fq", "gz", "fastq.gz"] {
            if let u = UTType(filenameExtension: ext) { t.append(u) }
        }
        return t.isEmpty ? [.data] : t
    }

    private func run() {
        guard let url = fastqURL, let design = model.qcDesign(for: subID) else {
            errorText = L("无法构建该子库的 QC 设计（先在设计模块生成文库）"); return
        }
        isRunning = true; errorText = nil
        Task.detached {
            do {
                let res = try QCCounter.count(fastqURL: url, design: design)
                let rws = QCReport.rows(res)
                let sum = QCReport.summarize(res, rows: rws)
                await MainActor.run {
                    result = res; rows = rws; summary = sum; isRunning = false
                }
            } catch {
                await MainActor.run { errorText = "\(error)"; isRunning = false }
            }
        }
    }

    private func runDemo() {
        guard let design = model.qcDesign(for: subID) else { return }
        var reads: [FastqRecord] = []
        let anchor = design.anchor5 ?? String(design.reference.prefix(20))
        var ref = Array(design.reference)
        // 每个变体 100 条 reads；每 20 个留一个缺失（模拟 ~95% 观测率）
        for (i, v) in design.variants.enumerated() where i % 20 != 0 {
            var mut = ref
            let lo = (v.position - 1) * 3
            for (k, ch) in v.mutCodon.enumerated() where lo + k < mut.count { mut[lo + k] = ch }
            for _ in 0..<20 {
                reads.append(FastqRecord(name: "demo", sequence: anchor + String(mut), quality: ""))
            }
        }
        for _ in 0..<1000 {
            reads.append(FastqRecord(name: "wt", sequence: anchor + String(ref), quality: ""))
        }
        let res = QCCounter.count(reads: reads, design: design)
        rows = QCReport.rows(res)
        summary = QCReport.summarize(res, rows: rows)
        result = res

        // 演示样本表：两个样本，第二个少 20% reads
        func mk(_ name: String, _ sub: String, _ factor: Double) -> QCSampleResult {
            let scaled = Array(reads.prefix(Int(Double(reads.count) * factor)))
            let r = QCCounter.count(reads: scaled, design: design)
            let rws = QCReport.rows(r)
            return QCSampleResult(name: name, sublibrary: sub,
                                  summary: QCReport.summarize(r, rows: rws), rows: rws)
        }
        let sub = design.variants.first?.sublibrary ?? "SL01"
        Task.detached {
            let a = mk("demo_rep1", sub, 1.0)
            let b = mk("demo_rep2", sub, 0.8)
            await MainActor.run {
                sampleResults = [a, b]
                selectedSample = a.name
                saveRun(title: "QC demo")
                loadRuns()
            }
        }
    }

    private var sampleTable: some View {
        Block("样本") {
            HStack {
                Text("sample").frame(width: 170, alignment: .leading)
                Text(L("子库")).frame(width: 70, alignment: .leading)
                Text("reads").frame(width: 90, alignment: .trailing)
                Text(L("锚定")).frame(width: 70, alignment: .trailing)
                Text(L("观测")).frame(width: 70, alignment: .trailing)
                Text(L("中位覆盖")).frame(width: 90, alignment: .trailing)
                Text(L("判定")).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.system(size: 10.5)).foregroundStyle(Theme.muted).padding(.vertical, 6)
            ForEach(Array(sampleResults.enumerated()), id: \.element.name) { idx, r in
                Button {
                    selectedSample = r.name
                } label: {
                    HStack {
                        Text(r.name).font(.system(size: 11, design: .monospaced)).frame(width: 170, alignment: .leading)
                        Text(r.sublibrary).font(.system(size: 11, design: .monospaced)).frame(width: 70, alignment: .leading)
                        Text("\(r.summary.totalReads)").font(.system(size: 11, design: .monospaced)).frame(width: 90, alignment: .trailing)
                        Text(pct(r.summary.anchoredRate)).font(.system(size: 11, design: .monospaced)).frame(width: 70, alignment: .trailing)
                        Text(pct(r.summary.observedRate)).font(.system(size: 11, design: .monospaced)).frame(width: 70, alignment: .trailing)
                        Text(String(format: "%.0f×", r.summary.medianCoverage)).font(.system(size: 11, design: .monospaced)).frame(width: 90, alignment: .trailing)
                        Text(r.summary.verdict.uppercased()).font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(r.summary.verdict == "pass" ? Theme.muted : Theme.ink)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .foregroundStyle(Theme.ink)
                    .frame(height: 28)
                    .background(selectedSample == r.name ? Theme.hover : (idx % 2 == 1 ? Theme.zebra : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if let sel = selectedSample, let r = sampleResults.first(where: { $0.name == sel }) {
                Text(F("样本 %@ 的变体（前 200 条）", sel))
                    .font(.system(size: 11)).foregroundStyle(Theme.muted).padding(.top, 12)
                ForEach(Array(r.rows.prefix(200).enumerated()), id: \.element.id) { idx, row in
                    HStack {
                        Text(row.id).font(.system(size: 11, design: .monospaced)).frame(width: 150, alignment: .leading)
                        Text(row.aaChange).font(.system(size: 11)).frame(width: 90, alignment: .leading)
                        Text("\(row.observed)").font(.system(size: 11, design: .monospaced)).frame(width: 90, alignment: .trailing)
                        Text(row.flag).font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(row.flag == "OK" ? Theme.muted : Theme.ink)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .frame(height: 24)
                    .background(idx % 2 == 1 ? Theme.zebra : Color.clear)
                }
            }
        }
    }

    private var issuesBlock: some View {
        Block("样本表检查") {
            ForEach(Array(sheetIssues.enumerated()), id: \.offset) { _, issue in
                HStack(alignment: .top, spacing: 8) {
                    Text(issue.level == .error ? "阻断" : "警告")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .frame(width: 40, alignment: .leading)
                        .foregroundStyle(issue.level == .error ? Theme.ink : Theme.muted)
                    Text(issue.message).font(.system(size: 11.5))
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var rollupBlock: some View {
        Block("子库汇总（批量）") {
            HStack {
                Text(L("子库")).frame(width: 70, alignment: .leading)
                Text("reads").frame(width: 90, alignment: .trailing)
                Text(L("设计")).frame(width: 70, alignment: .trailing)
                Text(L("观测")).frame(width: 70, alignment: .trailing)
                Text(L("中位覆盖")).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.system(size: 10.5)).foregroundStyle(Theme.muted).padding(.vertical, 6)
            ForEach(Array(rollup.enumerated()), id: \.element.sublibrary) { idx, m in
                HStack {
                    Text(m.sublibrary).font(.system(size: 11, design: .monospaced)).frame(width: 70, alignment: .leading)
                    Text("\(m.reads)").font(.system(size: 11, design: .monospaced)).frame(width: 90, alignment: .trailing)
                    Text("\(m.designed)").font(.system(size: 11, design: .monospaced)).frame(width: 70, alignment: .trailing)
                    Text("\(m.observed)").font(.system(size: 11, design: .monospaced)).frame(width: 70, alignment: .trailing)
                    Text(String(format: "%.0f×", m.medianCoverage)).font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(height: 26)
                .background(idx % 2 == 1 ? Theme.zebra : Color.clear)
            }
        }
    }

    static func rollup(_ results: [QCSampleResult]) -> [QCSublibraryMetric] {
        let bySub = Dictionary(grouping: results, by: \.sublibrary)
        return bySub.keys.sorted().map { sub in
            let rs = bySub[sub] ?? []
            let designed = rs.first?.summary.designedVariants ?? 0
            let reads = rs.reduce(0) { $0 + $1.summary.totalReads }
            let observedIDs = Set(rs.flatMap { $0.rows.filter { $0.observed > 0 }.map(\.id) })
            let median = rs.map(\.summary.medianCoverage).sorted()[safe: rs.count / 2] ?? 0
            return QCSublibraryMetric(sublibrary: sub, reads: reads, designed: designed,
                                      observed: observedIDs.count, medianCoverage: median)
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
                .frame(height: 34)
                .background(idx % 2 == 1 ? Theme.zebra : Color.clear)
            }
        }
    }

    private func runSheet() {
        guard let url = sheetURL else { return }
        do {
            let parsed = try QCSampleSheet.parse(url: url)
            var issues = parsed.issues
            if let d = model.design() {
                let assigns = model.indexAssignments(design: d)
                var designed: [String: String] = [:]
                for a in assigns { designed[a.subID] = "\(a.index5.seq)+\(a.index3.seq)" }
                for smp in parsed.samples where smp.index5 != nil || smp.index3 != nil {
                    let got = "\(smp.index5 ?? "")+\(smp.index3 ?? "")"
                    if let want = designed[smp.sublibrary], got != want {
                        issues.append(SampleSheetIssue(level: .warning,
                            message: "\(smp.name) 的 index 与设计不符（期望 \(want)）"))
                    }
                }
            }
            sheetIssues = issues
            if !parsed.errors.isEmpty {
                errorText = parsed.errors.map(\.message).joined(separator: "；")
                return
            }
            let specs = parsed.samples
            var designs: [String: QCDesign] = [:]
            for p in planes { if let d = model.qcDesign(for: p.id) { designs[p.id] = d } }
            isRunning = true; errorText = nil
            Task.detached {
                do {
                    var results: [QCSampleResult] = []
                    for spec in specs {
                        guard let d = designs[spec.sublibrary] else { continue }
                        let res = try QCCounter.countPaired(r1: URL(fileURLWithPath: spec.r1),
                                                            r2: spec.r2.flatMap { URL(fileURLWithPath: $0) },
                                                            design: d)
                        let rws = QCReport.rows(res)
                        results.append(QCSampleResult(name: spec.name, sublibrary: spec.sublibrary,
                                                      summary: QCReport.summarize(res, rows: rws), rows: rws))
                    }
                    await MainActor.run {
                        sampleResults = results
                        selectedSample = results.first?.name
                        rollup = Self.rollup(results)
                        runCtx = designCtx
                        isRunning = false
                        saveRun(title: "QC \(url.lastPathComponent)")
                        loadRuns()
                    }
                } catch {
                    await MainActor.run { errorText = "\(error)"; isRunning = false }
                }
            }
        } catch { errorText = "\(error)" }
    }

    private func saveRun(title: String) {
        let payload = QCRunPayload(samples: sampleResults, context: runCtx ?? designCtx)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        RunStore.shared.save(type: "qc", projectID: model.current?.id, title: title, payload: data)
    }

    private func refreshContext() {
        if let p = model.current, let d = model.design() {
            designCtx = DesignContext.make(project: p, design: d)
        }
    }

    private func loadRuns() {
        var seen = Set<String>()
        runs = RunStore.shared.list(type: "qc", projectID: model.current?.id).filter {
            seen.insert($0.title).inserted
        }
    }

    private func loadRun(_ r: RunRecord) {
        guard let payload = try? JSONDecoder().decode(QCRunPayload.self, from: r.payload) else { return }
        sampleResults = payload.samples
        selectedSample = payload.samples.first?.name
        runCtx = payload.context
        rows = []
        summary = nil
    }

    private func exportMissing() {
        guard let p = model.current else { return }
        let dir = ProjectStore.shared.projectDir(p.id)
            .appendingPathComponent("exports/qc-missing-\(Int(Date().timeIntervalSince1970))")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let csv = QCReport.rowsCSV(missingRows)
        try? csv.write(to: dir.appendingPathComponent("missing_variants.csv"), atomically: true, encoding: .utf8)
        NSWorkspace.shared.activateFileViewerSelecting([dir])
        model.banner = F("已导出 %d 个文件", 1)
    }

    private func exportReport() {
        guard let rows = summary != nil ? rows : nil, let s = summary, let p = model.current else { return }
        let dir = ProjectStore.shared.projectDir(p.id)
            .appendingPathComponent("exports/qc-\(Int(Date().timeIntervalSince1970))")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? QCReport.rowsCSV(rows).write(to: dir.appendingPathComponent("qc_report.csv"), atomically: true, encoding: .utf8)
        if let data = try? JSONEncoder().encode(s) {
            try? data.write(to: dir.appendingPathComponent("qc_summary.json"))
        }
        NSWorkspace.shared.activateFileViewerSelecting([dir])
        model.banner = F("已导出 %d 个文件", 2)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
