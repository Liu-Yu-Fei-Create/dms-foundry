import SwiftUI
import DMSEngine

struct DesignWorkspace: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedFeatureID: UUID?

    @State private var hoverStep: Int? = nil
    @State private var qcBadge: String?

    private let stepTitles = [
        "项目", "导入", "参数", "质检", "组装", "index", "生成", "导出",
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            stepBar
            Divider()
            ScrollView {
                content
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                    .frame(maxWidth: Theme.contentMax, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .id(model.step)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity))
            }
            .animation(.easeOut(duration: 0.18), value: model.step)
        }
        .onAppear { refreshBadge() }
    }

    private func refreshBadge() {
        guard let id = model.current?.id,
              let rec = RunStore.shared.list(type: "qc", projectID: id).first,
              let payload = try? JSONDecoder().decode(QCRunPayload.self, from: rec.payload) else {
            qcBadge = nil; return
        }
        let rank = ["pass": 0, "warn": 1, "fail": 2]
        let worst = payload.samples.map(\.summary.verdict)
            .max { (rank[$0] ?? 0) < (rank[$1] ?? 0) } ?? "warn"
        let df = DateFormatter(); df.dateFormat = "MM/dd"
        qcBadge = "QC \(worst.uppercased()) · \(df.string(from: rec.createdAt))"
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.s4) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.current?.name ?? "").font(.system(size: 23, weight: .semibold))
                HStack(spacing: 8) {
                    Text(model.current?.host ?? "").foregroundStyle(Theme.muted)
                    if let p = model.current?.plasmid {
                        Text("·").foregroundStyle(Theme.faint)
                        Text("\(p.sequence.count) bp").font(.system(size: 12, design: .monospaced))
                        Text("·").foregroundStyle(Theme.faint)
                        Text(F("%d 个特征", p.features.count)).foregroundStyle(Theme.muted)
                    }
                    if let badge = qcBadge {
                        Button { model.section = .qc } label: {
                            Text(badge).font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(badge.contains("PASS") ? Theme.wash : Theme.ink)
                                .foregroundStyle(badge.contains("PASS") ? Theme.ink2 : Theme.paper)
                        }.buttonStyle(.plain)
                    }
                }.font(.system(size: 12))
            }
            Spacer()
            Button { model.isImporting = true } label: {
                Label(L("导入质粒"), systemImage: "square.and.arrow.down")
            }.buttonStyle(PrimaryButtonStyle())
            Button { model.save(); model.banner = L("已保存") } label: {
                Label(L("保存"), systemImage: "square.and.arrow.down.on.square")
            }.buttonStyle(SecondaryButtonStyle())
        }
        .padding(.horizontal, 28).padding(.vertical, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private var stepBar: some View {
        HStack(spacing: 0) {
            ForEach(1...8, id: \.self) { i in
                let done = i < model.step
                Button { withAnimation(.easeOut(duration: 0.18)) { model.step = i } } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text(String(format: "%02d", i))
                                .font(.system(size: 10, weight: i == model.step ? .semibold : .regular, design: .monospaced))
                            if done {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .semibold))
                            }
                        }
                        .foregroundStyle(i == model.step ? Theme.ink : Theme.faint)
                        Text(L(stepTitles[i - 1]))
                            .font(.system(size: 11, weight: i == model.step ? .semibold : .regular))
                            .lineLimit(1)
                            .foregroundStyle(i == model.step ? Theme.ink : Theme.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 9).padding(.horizontal, 10)
                    .background(i == model.step ? Theme.wash : (hoverStep == i ? Theme.hover : Color.clear))
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(i == model.step ? Theme.ink : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
                .onHover { hovering in hoverStep = hovering ? i : (hoverStep == i ? nil : hoverStep) }
            }
        }
        .padding(.horizontal, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    @ViewBuilder private var content: some View {
        switch model.step {
        case 1: ProjectInfoStep()
        case 2: ImportStep(selectedFeatureID: $selectedFeatureID)
        case 3: ParamsStep()
        case 4: QCStep()
        case 5: AssemblyStep()
        case 6: IndexStep()
        case 7: GenerateStep()
        default: ExportStep()
        }
    }
}

// MARK: - 步骤 1

struct ProjectInfoStep: View {
    @EnvironmentObject private var model: AppModel

    private func applyHost(_ name: String) {
        model.current?.host = name
        if let option = HostCatalog.option(named: name), let table = option.table {
            model.current?.libraryParams.codonTable = table
        }
        model.save()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s4) {
            Text(L("项目信息")).font(.system(size: 20, weight: .semibold))
            Block("项目") {
                LabeledRow("名称") {
                    TextField("", text: Binding(
                        get: { model.current?.name ?? "" },
                        set: { model.current?.name = $0; model.save() }))
                        .textFieldStyle(.plain).font(.system(size: 13))
                }
                LabeledRow("宿主") {
                    Menu {
                        ForEach(HostCatalog.groups, id: \.self) { g in
                            Section(g) {
                                ForEach(HostCatalog.options.filter { $0.group == g }) { o in
                                    Button(o.name) { applyHost(o.name) }
                                }
                            }
                        }
                        Divider()
                        Button(L("其他（自定义）")) { applyHost("自定义") }
                    } label: {
                        HStack(spacing: 8) {
                            Text(model.current?.host ?? "E. coli BL21(DE3)")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(Theme.muted)
                        }
                        .padding(.horizontal, 10)
                        .frame(width: 260, height: 26, alignment: .leading)
                        .overlay(Rectangle().stroke(Theme.hairlineStrong, lineWidth: 1))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
            .frame(width: 720)

            Text(L("下一步：导入表达质粒（.gb 或 .fasta），然后在图上标注要突变的 CDS 与区段。"))
                .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
        }
    }
}

enum MapStyle: String, CaseIterable { case circular, linear }

private struct StepHoverKey: EnvironmentKey { static let defaultValue = false }

struct ImportStep: View {
    @EnvironmentObject private var model: AppModel
    @Binding var selectedFeatureID: UUID?
    @State private var mapStyle: MapStyle = .circular

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L("导入与标注")).font(.title3).bold()
                Spacer()
                Button { model.isImporting = true } label: { Label(L("导入 .gb / .fasta / .dna"), systemImage: "doc.badge.plus") }
            }

            if let plasmid = model.current?.plasmid {
                HStack {
                    Picker("视图", selection: $mapStyle) {
                        Text("环形").tag(MapStyle.circular)
                        Text("线性").tag(MapStyle.linear)
                    }.pickerStyle(.segmented).frame(width: 160)
                    Spacer()
                }
                if mapStyle == .circular {
                    PlasmidMapView(plasmid: plasmid, targetID: model.current?.target?.featureID,
                                   selectedID: $selectedFeatureID)
                        .frame(height: 360)
                } else {
                    SequenceTrackView(plasmid: plasmid, targetID: model.current?.target?.featureID,
                                      selectedID: $selectedFeatureID)
                        .frame(height: 150)
                }

                HStack(alignment: .top, spacing: 18) {
                    featureList(plasmid)
                    targetPanel()
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "square.dashed").font(.system(size: 38, weight: .light))
                    Text(L("还没有导入质粒")).font(.title3)
                    Text(L("支持 GenBank（.gb/.gbk，带注释）与 FASTA（仅序列）。")).foregroundStyle(.secondary)
                    Button(L("选择文件")) { model.isImporting = true }.buttonStyle(PrimaryButtonStyle())
                }
                .frame(maxWidth: .infinity).padding(40)
            }
        }
    }

    private func featureList(_ plasmid: Plasmid) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("特征")).font(.headline)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(plasmid.features) { f in
                        HStack(spacing: 8) {
                            Text(f.type.zh).font(.caption).frame(width: 64, alignment: .leading)
                            Text(f.label).lineLimit(1)
                            Spacer()
                            Text("\(f.start + 1)–\(f.end)").monospaced().font(.caption)
                            Text(f.strand == .forward ? "+" : "−").monospaced().font(.caption)
                        }
                        .padding(.vertical, 5).padding(.horizontal, 8)
                        .background(f.id == selectedFeatureID ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.18) : .clear)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedFeatureID = f.id }
                    }
                }
            }
            .frame(height: 210)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func targetPanel() -> some View {
        let cds = model.current?.plasmid?.features.filter { $0.type == .cds } ?? []
        VStack(alignment: .leading, spacing: 10) {
            Text(L("突变目标")).font(.headline)
            if cds.isEmpty {
                Text(L("没有 CDS 注释。FASTA 导入的序列需要手动添加 CDS。")).foregroundStyle(.secondary)
            } else {
                Picker(L("CDS"), selection: Binding(
                    get: { model.current?.target?.featureID ?? cds[0].id },
                    set: { id in
                        guard let f = cds.first(where: { $0.id == id }) else { return }
                        model.current?.target = Target(featureID: id, aaStart: 1, aaEnd: f.codonCount)
                        model.save()
                    })) {
                    ForEach(cds) { f in Text(f.label).tag(f.id) }
                }
                if let t = model.current?.target, let f = model.targetFeature {
                    Stepper(F("起始 aa %d", t.aaStart), value: Binding(
                        get: { t.aaStart },
                        set: { v in model.current?.target?.aaStart = max(1, min(v, t.aaEnd)); model.save() }),
                        in: 1...max(1, f.codonCount))
                    Stepper(F("结束 aa %d", t.aaEnd), value: Binding(
                        get: { t.aaEnd },
                        set: { v in model.current?.target?.aaEnd = min(max(v, t.aaStart), f.codonCount); model.save() }),
                        in: 1...max(1, f.codonCount))
                    Text(F("该 CDS 共 %d 个密码子 · 帧起点 %d · 表 %d", f.codonCount, f.codonStart, f.translTable))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 300, alignment: .leading)
    }
}

// MARK: - 步骤 3

struct ParamsStep: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var presetStore = PresetStore.shared
    @State private var showPresetName = false
    @State private var presetName = ""

    private var params: Binding<LibraryParams> {
        Binding(get: { model.current?.libraryParams ?? LibraryParams() },
                set: { model.current?.libraryParams = $0; model.save() })
    }

    var body: some View {
        let subs = model.subLibraries()
        let variants = model.variantCount()
        let stepNt = params.wrappedValue.stepNt
        let oligoLen = LengthBudget.oligoLength(stepNt: stepNt,
                                               method: model.current?.assembly.method ?? .goldenGate)
        VStack(alignment: .leading, spacing: Theme.s5) {
            HStack {
                Text(L("文库参数")).font(.system(size: 20, weight: .semibold))
                Spacer()
                Menu(L("预设")) {
                    ForEach(presetStore.presets) { p in
                        Button(p.name) { model.applyPreset(p.payload) }
                    }
                    if presetStore.presets.isEmpty {
                        Text(L("还没有预设"))
                    }
                    Divider()
                    Button(L("保存当前为预设…")) {
                        presetName = model.current.map { "\($0.name) 预设" } ?? ""
                        showPresetName = true
                    }
                    Button(L("用当前参数更新新项目默认值")) {
                        if let payload = model.currentPayload() { presetStore.setDefaults(payload) }
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            HStack(alignment: .top, spacing: Theme.s4) {
                Block("突变与密码子") {
                    LabeledRow("突变集合") {
                        Picker("", selection: params.mutationMode) {
                            Text(L("全部 19 种氨基酸")).tag(MutationMode.all)
                            Text(L("仅指定氨基酸")).tag(MutationMode.subset)
                        }.labelsHidden().frame(width: 220)
                    }
                    if params.wrappedValue.mutationMode == .subset {
                        LabeledRow("仅指定氨基酸") {
                            HStack(spacing: 4) {
                                ForEach(Array("ACDEFGHIKLMNPQRSTVWY").map(String.init), id: \.self) { aa in
                                    Toggle(aa, isOn: aaBinding(aa))
                                        .toggleStyle(.button)
                                        .font(.system(size: 11, design: .monospaced))
                                }
                            }
                        }
                    }
                    LabeledRow("包含同义突变（同 aa 换密码子）") {
                        Toggle("", isOn: params.includeSynonymous).labelsHidden().toggleStyle(InkToggleStyle())
                    }
                    LabeledRow("保留稀有密码子") {
                        Toggle("", isOn: params.keepRare).labelsHidden().toggleStyle(InkToggleStyle())
                    }
                    LabeledRow("把终止密码子作为突变类型") {
                        Toggle("", isOn: params.includeStop).labelsHidden().toggleStyle(InkToggleStyle())
                    }
                    LabeledRow("保留野生型对照") {
                        Toggle("", isOn: params.includeWT).labelsHidden().toggleStyle(InkToggleStyle())
                    }
                    LabeledRow("密码子策略") {
                        Picker("", selection: params.codonPolicy) {
                            Text(L("最优密码子")).tag(CodonPolicy.optimal)
                            Text(L("随机密码子")).tag(CodonPolicy.random)
                            Text(L("避开稀有后的随机")).tag(CodonPolicy.randomNonRare)
                        }.labelsHidden().frame(width: 220)
                    }
                    LabeledRow("密码子表") {
                        Picker("", selection: params.codonTable) {
                            Text("E. coli").tag(TableID.ecoli)
                            Text(L("人")).tag(TableID.human)
                        }.labelsHidden().frame(width: 140)
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: Theme.s4) {
                    Block("子库与预算") {
                        HStack(spacing: 0) {
                            MetricCell(label: "子库", value: "\(subs.count)")
                            dividerCell
                            MetricCell(label: "变体（设计阶段）", value: "\(variants)")
                            dividerCell
                            MetricCell(label: "每条 oligo 约", value: "\(oligoLen) nt")
                            dividerCell
                            MetricCell(label: "上限", value: "\(LengthBudget.vendorMax) nt")
                        }
                        .padding(Theme.s3)
                        LabeledRow("子库步长 (nt)") {
                            HStack(spacing: Theme.s1) {
                                TextField("", value: params.stepNt, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 90)
                                Text(String(stepNt % 3 == 0 ? L("3 的倍数 ✓") : L("必须是 3 的倍数")))
                                    .font(.system(size: 11))
                                    .foregroundStyle(stepNt % 3 == 0 ? Theme.muted : Color.red)
                            }
                        }
                        if oligoLen > LengthBudget.vendorMax {
                            Text(F("超出合成上限：建议把步长降到 %d nt 以下。",
                                   LengthBudget.maxStep(method: .goldenGate)))
                                .font(.system(size: 12))
                                .foregroundStyle(.red)
                                .padding(Theme.s3)
                        }
                    }
                    Block("子库切分") {
                        HStack {
                            Text(L("子库")).frame(width: 56, alignment: .leading)
                            Text("aa " + L("范围")).frame(maxWidth: .infinity, alignment: .leading)
                            Text("长度").frame(width: 70, alignment: .trailing)
                        }
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, Theme.s3).padding(.vertical, 6)
                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
                        ForEach(Array(subs.enumerated()), id: \.element.id) { idx, sub in
                            HStack {
                                Text(sub.id).font(.system(size: 11, design: .monospaced))
                                    .frame(width: 56, alignment: .leading)
                                Text("\(sub.aaStart)–\(sub.aaEnd)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("\(sub.ntLength) nt")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Theme.muted)
                                    .frame(width: 70, alignment: .trailing)
                            }
                            .frame(height: 26)
                            .padding(.horizontal, Theme.s3)
                            .background(idx % 2 == 1 ? Theme.zebra : Color.clear)
                        }
                    }
                }
                .frame(width: 430)
            }
        }
        .alert(L("命名预设"), isPresented: $showPresetName) {
            TextField(L("预设名称"), text: $presetName)
            Button(L("取消"), role: .cancel) {}
            Button(L("保存")) {
                if let payload = model.currentPayload() {
                    presetStore.addPreset(name: presetName, payload: payload)
                }
            }
        } message: {
            Text(L("只保存参数，不包含质粒与突变目标。"))
        }
    }

    private var dividerCell: some View {
        Rectangle().fill(Theme.hairline).frame(width: 1, height: 34)
    }

    private func aaBinding(_ aa: String) -> Binding<Bool> {
        Binding(
            get: { model.current?.libraryParams.allowedAA.contains(aa) ?? false },
            set: { on in
                guard var p = model.current?.libraryParams else { return }
                var s = Set(p.allowedAA)
                if on { s.insert(aa) } else { s.remove(aa) }
                p.allowedAA = Array(s).sorted()
                model.current?.libraryParams = p
                model.save()
            })
    }
}

struct PlannedStep: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3).bold()
            Text(L("本版未实现")).font(.callout).foregroundStyle(.secondary)
            Text(detail).foregroundStyle(.secondary)
        }
    }
}


// MARK: - 步骤 4：质检项

struct QCStep: View {
    @EnvironmentObject private var model: AppModel

    private var qc: Binding<QCOptions> {
        Binding(get: { model.current?.qcOptions ?? QCOptions() },
                set: { model.current?.qcOptions = $0; model.save() })
    }

    var body: some View {
        let result = model.design()
        VStack(alignment: .leading, spacing: 16) {
            Text(L("质检项")).font(.title3).bold()
            Text(L("这些变体会额外加入文库，用于验证文库的构建与检测链路；与设计变体统一去重编号。"))
                .font(.callout).foregroundStyle(.secondary)

            Form {
                Section(L("① 终止密码子质检")) {
                    Toggle(L("加入终止密码子变体"), isOn: qc.stop.enabled)
                    if qc.stop.wrappedValue.enabled {
                        Picker(L("选择方式"), selection: qc.stop.mode) {
                            Text(L("随机")).tag(QCItemMode.random)
                            Text(L("指定位置")).tag(QCItemMode.specified)
                        }
                        Stepper(F("数量 %d", qc.stop.wrappedValue.count), value: qc.stop.count, in: 0...500)
                        HStack {
                            Stepper(F("范围 %d–%d", qc.stop.wrappedValue.aaRangeStart, qc.stop.wrappedValue.aaRangeEnd),
                                    value: qc.stop.aaRangeStart, in: 1...max(1, model.codingContext?.codonCount ?? 1))
                            Stepper(L(""), value: qc.stop.aaRangeEnd, in: 1...max(1, model.codingContext?.codonCount ?? 1))
                                .labelsHidden()
                        }
                    }
                    if let why = result?.skippedQC["stop"] {
                        Text(why).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section(L("② 同义突变质检")) {
                    Toggle(L("加入同义突变变体"), isOn: qc.synonymous.enabled)
                    if qc.synonymous.wrappedValue.enabled {
                        Picker(L("选择方式"), selection: qc.synonymous.mode) {
                            Text(L("随机")).tag(QCItemMode.random)
                            Text(L("指定位置")).tag(QCItemMode.specified)
                        }
                        Stepper(F("数量 %d", qc.synonymous.wrappedValue.count), value: qc.synonymous.count, in: 0...500)
                    }
                    if let why = result?.skippedQC["synonymous"] {
                        Text(why).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section(L("③ 脯氨酸质检（突变集合不含 Pro 时可用）")) {
                    Toggle(L("加入脯氨酸变体"), isOn: qc.proline.enabled)
                    if qc.proline.wrappedValue.enabled {
                        Picker(L("选择方式"), selection: qc.proline.mode) {
                            Text(L("随机")).tag(QCItemMode.random)
                            Text(L("指定位置")).tag(QCItemMode.specified)
                        }
                        Stepper(F("数量 %d", qc.proline.wrappedValue.count), value: qc.proline.count, in: 0...500)
                    }
                    if let why = result?.skippedQC["proline"] {
                        Text(why).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section(L("④ 随机区质检")) {
                    Toggle(L("把整段突变区替换为随机序列"), isOn: qc.randomRegion.enabled)
                    if qc.randomRegion.wrappedValue.enabled {
                        Picker(L("模式"), selection: qc.randomRegion.mode) {
                            Text(L("完全随机 nt（可含 stop）")).tag(RandomRegionMode.pureRandomNt)
                            Text(L("保帧随机密码子")).tag(RandomRegionMode.framePreservingCodons)
                        }
                        Stepper(F("每个子库数量 %d", qc.randomRegion.wrappedValue.countPerSublibrary),
                                value: qc.randomRegion.countPerSublibrary, in: 1...10)
                    }
                }
            }.formStyle(.grouped).frame(height: 480)

            if let r = result {
                HStack(spacing: 26) {
                    metric(L("设计变体"), "\(r.designVariants.count)")
                    metric(L("质检新增"), "\(r.qcVariants.count)")
                    metric(L("随机区"), "\(r.regionVariants.count)")
                    metric(L("合计"), "\(r.totalVariants)")
                }
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3).monospacedDigit()
        }
    }
}

// MARK: - 步骤 5：组装方式

private func gradeColor(_ grade: OverhangGrade) -> Color {
    switch grade {
    case .good: return .primary
    case .marginal: return .orange
    case .bad: return .red
    case .unknown: return .secondary
    }
}

struct AssemblyStep: View {
    @EnvironmentObject private var model: AppModel
    @State private var refine: RefineResult?

    private var assembly: Binding<Assembly> {
        Binding(get: { model.current?.assembly ?? Assembly() },
                set: { model.current?.assembly = $0; model.save() })
    }

    var body: some View {
        let result = model.design()
        VStack(alignment: .leading, spacing: 16) {
            Text(L("组装方式")).font(.title3).bold()
            Form {
                Picker(L("构建方式"), selection: assembly.method) {
                    Text(L("Golden Gate")).tag(AssemblyMethod.goldenGate)
                    Text(L("Gibson")).tag(AssemblyMethod.gibson)
                }
                if assembly.wrappedValue.method == .goldenGate {
                    Picker(L("Type IIS 酶"), selection: assembly.enzyme) {
                        ForEach(["BsaI", "BsmBI", "BbsI", "SapI", "BspQI", "AarI"], id: \.self) { Text($0) }
                    }
                }
            }.formStyle(.grouped).frame(height: 110)

            if let r = result, !r.ggPlans.isEmpty {
                Text(L("子库接口（overhang 由 WT 边界决定，只能打分与平移边界）")).font(.headline)
                VStack(spacing: 0) {
                    HStack {
                        Text(L("子库")); Text(L("aa 范围")); Text(L("5′ OH")); Text(L("3′ OH")); Text(L("保真度")); Text(L("内部位点")); Text(L("判定"))
                    }.font(.caption).foregroundStyle(.secondary).padding(.vertical, 4)
                    ForEach(r.ggPlans, id: \.id) { p in
                        HStack {
                            Text(p.id).monospaced()
                            Text("\(p.aaStart)–\(p.aaEnd)").monospaced()
                            Text(p.overhang5.sequence).monospaced()
                                .foregroundStyle(gradeColor(p.overhang5.grade))
                            Text(p.overhang3.sequence).monospaced()
                                .foregroundStyle(gradeColor(p.overhang3.grade))
                            Text(String(format: "%.2f / %.2f", p.overhang5.fidelity ?? 0, p.overhang3.fidelity ?? 0)).monospaced()
                            Text(p.internalSites.isEmpty ? "—" : "\(p.internalSites.count)").monospaced()
                            Text(p.viable ? "可用" : "阻断").foregroundStyle(p.viable ? Color.secondary : Color.red)
                        }.font(.system(size: 12)).padding(.vertical, 3)
                    }
                }
            }
            if let r = result, !r.gibsonPlans.isEmpty {
                Text(L("Gibson 同源臂")).font(.headline)
                ForEach(r.gibsonPlans, id: \.id) { p in
                    HStack {
                        Text(p.id).monospaced()
                        Text("\(p.aaStart)–\(p.aaEnd)").monospaced()
                        Text("L \(p.leftArm.count) nt / R \(p.rightArm.count) nt").monospaced()
                        Text(String(format: "Tm %.1f / %.1f", p.leftTm, p.rightTm)).monospaced()
                        Text(p.viable ? "可用" : "阻断").foregroundStyle(p.viable ? Color.secondary : Color.red)
                    }.font(.system(size: 12))
                }
            }

            if let r = result, !r.issues.isEmpty {
                Text(F("警告与阻断（%d）", r.issues.count)).font(.headline)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(r.issues.enumerated()), id: \.offset) { _, issue in
                        HStack(spacing: 8) {
                            Text(issue.severity == .error ? "阻断" : "警告")
                                .font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                                .background(issue.severity == .error ? Color.red.opacity(0.15) : Color.orange.opacity(0.15))
                            Text(issue.message).font(.callout)
                        }
                    }
                }
            }

            HStack {
                Button(L("Refine 预览（同义替换消除内部位点）")) { refine = model.refinePreview() }
                Button(L("应用 Refine")) { model.applyRefine(); refine = nil }
                if model.current?.refinedCoding != nil {
                    Text(F("模板已 Refine（%d 处）", model.current?.refineChangeCount ?? 0))
                        .font(.callout).foregroundStyle(.secondary)
                    Button(L("撤销 Refine")) { model.resetRefine() }
                }
                if let r = refine {
                    Text(F("可改 %d 处，剩余位点 %d 个", r.changes.count, r.remainingSites.count))
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            if let r = refine, !r.changes.isEmpty {
                Text(r.changes.prefix(8).map { "aa\($0.position) \($0.from)→\($0.to)" }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}


// MARK: - 步骤 6：子库 index

struct IndexStep: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let design = model.design()
        let assigns = design.map { model.indexAssignments(design: $0) } ?? []
        VStack(alignment: .leading, spacing: 14) {
            Text(L("子库 index")).font(.title3).bold()
            Text(L("index 是子库特异的扩增/拆分手柄：15–25 nt、两两不交叉、3′ 端唯一。GG 装配后不进入产物；如未来需要产物内条形码，走载体侧方案。"))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if assigns.isEmpty {
                Text(L("还没有可分配的子库（先完成第 3 步文库参数）")).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(L("子库")).frame(width: 44, alignment: .leading)
                        Text(L("5′ index")).frame(width: 72, alignment: .leading)
                        Text(L("序列")).frame(width: 150, alignment: .leading)
                        Text(L("3′ index")).frame(width: 72, alignment: .leading)
                        Text(L("序列")).frame(width: 150, alignment: .leading)
                        Text(L("ΔTm")).frame(width: 64, alignment: .trailing)
                    }.font(.caption).foregroundStyle(.secondary).padding(.vertical, 4)
                    ForEach(assigns, id: \.subID) { a in
                        HStack(spacing: 8) {
                            Text(a.subID).monospaced().frame(width: 44, alignment: .leading)
                            Text(a.index5.id).monospaced().frame(width: 72, alignment: .leading)
                            Text(a.index5.seq).monospaced().lineLimit(1)
                                .truncationMode(.middle).frame(width: 150, alignment: .leading)
                            Text(a.index3.id).monospaced().frame(width: 72, alignment: .leading)
                            Text(a.index3.seq).monospaced().lineLimit(1)
                                .truncationMode(.middle).frame(width: 150, alignment: .leading)
                            Text(String(format: "%.1f °C", a.tmDiff)).monospaced().frame(width: 64, alignment: .trailing)
                        }.font(.system(size: 10))
                    }
                }
                HStack {
                    Button(L("重新分配")) { model.reassignIndices() }
                    Text(F("已用 %d / 1024 条冻结候选", assigns.count * 2)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - 步骤 7：生成与 QC

struct GenerateStep: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s4) {
            HStack(alignment: .center) {
                Text(L("生成与 QC")).font(.system(size: 20, weight: .semibold))
                Spacer()
                Button { model.generateLibrary() } label: { Label(L("生成文库"), systemImage: "gearshape.2") }
                    .buttonStyle(PrimaryButtonStyle())
            }
            Text(L("拼装每条 oligo（index + Type IIS 接头 + 插入片段），逐条做长度/GC/同聚物/内部位点检查，并按位点做覆盖对账。"))
                .font(.system(size: 12.5)).foregroundStyle(Theme.muted)

            if let lib = model.generated {
                Block("结果") {
                    HStack(spacing: 0) {
                        MetricCell(label: "oligo", value: "\(lib.oligos.count)")
                        dividerCell
                        MetricCell(label: "阻断", value: "\(lib.summary["errors"] ?? 0)", accent: true)
                        dividerCell
                        MetricCell(label: "警告", value: "\(lib.summary["warnings"] ?? 0)")
                        dividerCell
                        MetricCell(label: "覆盖缺口", value: "\(lib.summary["coverageGaps"] ?? 0)")
                    }
                    .padding(.horizontal, Theme.s3)
                    .padding(.bottom, Theme.s3)
                }

                let allIssues = lib.oligos.flatMap(\.issues)
                if !allIssues.isEmpty {
                    Block("问题分布") {
                        HStack {
                            Text("级别").frame(width: 60, alignment: .leading)
                            Text("代码").frame(maxWidth: .infinity, alignment: .leading)
                            Text("条数").frame(width: 70, alignment: .trailing)
                        }
                        .font(.system(size: 10.5)).foregroundStyle(Theme.muted)
                        .padding(.horizontal, Theme.s3).padding(.vertical, 6)
                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
                        let grouped = Dictionary(grouping: allIssues, by: { $0.code })
                        ForEach(Array(grouped.keys.sorted().enumerated()), id: \.element) { idx, code in
                            let items = grouped[code] ?? []
                            let isError = items.contains { $0.severity == .error }
                            HStack {
                                HStack(spacing: 5) {
                                    Rectangle().fill(isError ? Theme.ink : Theme.hairlineStrong)
                                        .frame(width: 6, height: 6)
                                    Text(isError ? "阻断" : "警告")
                                        .font(.system(size: 10.5, weight: isError ? .semibold : .regular))
                                        .foregroundStyle(isError ? Theme.ink : Theme.muted)
                                }
                                .frame(width: 60, alignment: .leading)
                                Text(code).font(.system(size: 11, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("\(items.count)").font(.system(size: 11, design: .monospaced))
                                    .frame(width: 70, alignment: .trailing)
                            }
                            .frame(height: 26)
                            .padding(.horizontal, Theme.s3)
                            .background(idx % 2 == 1 ? Theme.zebra : Color.clear)
                        }
                    }
                }

                Block("前 5 条 oligo") {
                    HStack {
                        Text("名称").frame(width: 150, alignment: .leading)
                        Text("长度").frame(width: 70, alignment: .trailing)
                        Text(L("子库")).frame(width: 56, alignment: .leading)
                        Text(L("突变目标")).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.system(size: 10.5)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, Theme.s3).padding(.vertical, 6)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
                    ForEach(Array(lib.oligos.prefix(5).enumerated()), id: \.element.id) { idx, o in
                        HStack {
                            Text(o.name).font(.system(size: 11, design: .monospaced))
                                .frame(width: 150, alignment: .leading)
                            Text("\(o.sequence.count) nt").font(.system(size: 11, design: .monospaced))
                                .frame(width: 70, alignment: .trailing)
                            Text(o.subID).font(.system(size: 11, design: .monospaced))
                                .frame(width: 56, alignment: .leading)
                            Text(o.mutationAA).font(.system(size: 11))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 26)
                        .padding(.horizontal, Theme.s3)
                        .background(idx % 2 == 1 ? Theme.zebra : Color.clear)
                    }
                }
            } else {
                VStack(spacing: Theme.s2) {
                    Image(systemName: "square.stack.3d.up").font(.system(size: 30, weight: .light))
                        .foregroundStyle(Theme.faint)
                    Text(L("还没有生成。点击右上角「生成文库」。")).foregroundStyle(Theme.muted)
                    Button(L("生成文库")) { model.generateLibrary() }.buttonStyle(PrimaryButtonStyle())
                }
                .frame(maxWidth: .infinity).padding(.vertical, 50)
                .overlay(Rectangle().stroke(Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
            }
        }
    }

    private var dividerCell: some View {
        Rectangle().fill(Theme.hairline).frame(width: 1, height: 34)
    }
}

struct ExportStep: View {
    @EnvironmentObject private var model: AppModel
    @State private var recent: [RecentExport] = []

    struct RecentExport: Identifiable {
        let id: String
        let url: URL
        let files: Int
        let bytes: Int
        let date: Date
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s4) {
            Text(L("导出")).font(.system(size: 20, weight: .semibold))
            Text(L("订单表（pool/name/sequence）+ 审计表（含 index、overhang、问题代码）+ FASTA + manifest。CSV 带 BOM，Excel 打开中文不乱码。"))
                .font(.system(size: 12.5)).foregroundStyle(Theme.muted)

            HStack(alignment: .top, spacing: Theme.s4) {
                Block("当前项目") {
                    VStack(alignment: .leading, spacing: Theme.s3) {
                        HStack(spacing: Theme.s2) {
                            Button { model.exportLibrary() } label: { Label(L("导出四件套"), systemImage: "square.and.arrow.up") }
                                .buttonStyle(PrimaryButtonStyle())
                                .disabled(model.generated == nil)
                            if model.generated == nil {
                                Button(L("去第 7 步生成")) { model.step = 7 }.buttonStyle(SecondaryButtonStyle())
                            }
                        }
                        if let e = model.exported {
                            Text(L("已写入")).font(.system(size: 11)).foregroundStyle(Theme.muted)
                            ForEach(e.files, id: \.self) { f in
                                HStack(spacing: Theme.s1) {
                                    Text(f.lastPathComponent).font(.system(size: 11, design: .monospaced))
                                    Spacer()
                                    Text(byteText(f)).font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(Theme.faint)
                                }
                                .frame(height: 24)
                            }
                            Button(L("在 Finder 中显示")) {
                                NSWorkspace.shared.activateFileViewerSelecting(e.files)
                            }.buttonStyle(SecondaryButtonStyle()).padding(.top, Theme.s1)
                        }
                    }
                    .padding(.horizontal, Theme.s3)
                    .padding(.bottom, Theme.s3)
                }
                .frame(maxWidth: .infinity)

                Block("最近导出") {
                    if recent.isEmpty {
                        Text(L("还没有导出记录")).font(.system(size: 12)).foregroundStyle(Theme.faint)
                            .padding(Theme.s3)
                    } else {
                        ForEach(Array(recent.enumerated()), id: \.element.id) { idx, r in
                            HStack(spacing: Theme.s2) {
                                Text(r.date, format: .dateTime.month().day().hour().minute())
                                    .font(.system(size: 11, design: .monospaced))
                                    .frame(width: 110, alignment: .leading)
                                Text("\(r.files) 个文件").font(.system(size: 11))
                                Spacer()
                                Text(byteText(r.bytes)).font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(Theme.faint)
                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting([r.url])
                                } label: { Image(systemName: "folder") }
                                    .buttonStyle(.plain)
                            }
                            .frame(height: 26)
                            .padding(.horizontal, Theme.s3)
                            .background(idx % 2 == 1 ? Theme.zebra : Color.clear)
                        }
                    }
                }
                .frame(width: 430)
            }

            Block("导出前检查") {
                HStack(spacing: 0) {
                    MetricCell(label: "oligo", value: model.generated.map { "\($0.oligos.count)" } ?? "—")
                    Rectangle().fill(Theme.hairline).frame(width: 1, height: 34)
                    MetricCell(label: "阻断", value: model.generated.map { "\($0.summary["errors"] ?? 0)" } ?? "—", accent: true)
                    Rectangle().fill(Theme.hairline).frame(width: 1, height: 34)
                    MetricCell(label: "警告", value: model.generated.map { "\($0.summary["warnings"] ?? 0)" } ?? "—")
                    Rectangle().fill(Theme.hairline).frame(width: 1, height: 34)
                    MetricCell(label: "覆盖缺口", value: model.generated.map { "\($0.summary["coverageGaps"] ?? 0)" } ?? "—")
                }
                .padding(.horizontal, Theme.s3)
                .padding(.bottom, Theme.s3)
            }
            .frame(maxWidth: 780)

            Block("导出内容") {
                ForEach(Array([
                    ("order.csv", "pool / name / sequence，一行一条 oligo，带 UTF-8 BOM"),
                    ("audit.csv", "完整审计列：index、overhang、突变、来源、error/warning 代码"),
                    ("library.fasta", "同样内容的 FASTA，便于直接交给合成商或归档"),
                    ("manifest.json", "引擎版本、酶、步长、计数、覆盖缺口、问题清单、几何约定"),
                ].enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .top, spacing: Theme.s2) {
                        Text(item.0).font(.system(size: 11, design: .monospaced))
                            .frame(width: 120, alignment: .leading)
                        Text(L(item.1)).font(.system(size: 11.5)).foregroundStyle(Theme.ink2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, Theme.s3).padding(.vertical, 7)
                    .background(idx % 2 == 1 ? Theme.zebra : Color.clear)
                }
            }
        }
        .onAppear(perform: loadRecent)
    }

    private func loadRecent() {
        guard let id = model.current?.id else { recent = []; return }
        let dir = ProjectStore.shared.projectDir(id).appendingPathComponent("exports")
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        recent = items.compactMap { url in
            guard let files = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return nil }
            let bytes = files.reduce(0) { sum, f in
                let size = (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return sum + size
            }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            return RecentExport(id: url.lastPathComponent, url: url, files: files.count, bytes: bytes, date: date)
        }.sorted { $0.date > $1.date }.prefix(6).map { $0 }
    }

    private func byteText(_ url: URL) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return byteText(size)
    }
    private func byteText(_ size: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}
