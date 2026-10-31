import SwiftUI
import DMSEngine

enum SettingsTab: String, CaseIterable, Identifiable {
    case defaults, presets, appearance
    var id: String { rawValue }
    var title: String {
        switch self {
        case .defaults: return "默认值"
        case .presets: return "命名预设"
        case .appearance: return "外观"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var store = PresetStore.shared
    @State private var tab: SettingsTab = .defaults
    @State private var hover: SettingsTab?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(SettingsTab.allCases) { t in
                    Button { tab = t } label: {
                        Text(L(t.title))
                            .font(.system(size: 12.5, weight: tab == t ? .semibold : .regular))
                            .foregroundStyle(tab == t ? Theme.ink : Theme.muted)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(tab == t ? Color.clear : (hover == t ? Theme.hover : Color.clear))
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(tab == t ? Theme.ink : Color.clear).frame(height: 2)
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .onHover { hover = $0 ? t : (hover == t ? nil : hover) }
                }
            }
            .background(Theme.paperAlt)
            Rectangle().fill(Theme.hairline).frame(height: 1)

            Group {
                switch tab {
                case .defaults: DefaultsTab(store: store)
                case .presets: PresetsTab(store: store)
                case .appearance: AppearanceTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.paper)
        .frame(width: 660, height: 560)
    }
}

// MARK: - 默认值

private struct DefaultsTab: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: PresetStore
    @State private var pendingRoot: URL?
    @State private var showMoveConfirm = false
    @State private var draft = PresetPayload.standard
    @State private var loaded = false

    private let enzymes: [(String, String)] = {
        guard let table = try? EnzymeTable.load() else { return [] }
        return table.enzymes.map { ($0.key, $0.key) }.sorted { $0.1 < $1.1 }
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            Text(L("新项目默认值")).font(.system(size: 15, weight: .semibold))
            Text(L("新建项目时自动带入；不影响已存在的项目。"))
                .font(.system(size: 11.5)).foregroundStyle(Theme.muted)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.s4) {
                    Block("宿主") {
                        HStack(spacing: Theme.s2) {
                            Menu {
                                ForEach(HostCatalog.groups, id: \.self) { g in
                                    Section(g) {
                                        ForEach(HostCatalog.options.filter { $0.group == g }) { o in
                                            Button(o.name) { draft.host = o.name }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Text(draft.host).font(.system(size: 12.5)).foregroundStyle(Theme.ink)
                                    Spacer(minLength: 4)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 8, weight: .semibold))
                                        .foregroundStyle(Theme.muted)
                                }
                                .padding(.horizontal, 10)
                                .frame(width: 260, height: 26)
                                .overlay(Rectangle().stroke(Theme.hairlineStrong, lineWidth: 1))
                            }
                            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                            .focusEffectDisabled()
                            Spacer()
                        }
                        .frame(height: Theme.rowHeight)
                    }

                    Block("文库参数") {
                        LabeledRow("包含同义突变（同 aa 换密码子）") {
                            Toggle("", isOn: $draft.library.includeSynonymous).labelsHidden().toggleStyle(InkToggleStyle())
                        }
                        LabeledRow("保留稀有密码子") {
                            Toggle("", isOn: $draft.library.keepRare).labelsHidden().toggleStyle(InkToggleStyle())
                        }
                        LabeledRow("把终止密码子作为突变类型") {
                            Toggle("", isOn: $draft.library.includeStop).labelsHidden().toggleStyle(InkToggleStyle())
                        }
                        LabeledRow("保留野生型对照") {
                            Toggle("", isOn: $draft.library.includeWT).labelsHidden().toggleStyle(InkToggleStyle())
                        }
                        LabeledRow("密码子策略") {
                            Picker("", selection: $draft.library.codonPolicy) {
                                Text(L("最优密码子")).tag(CodonPolicy.optimal)
                                Text(L("随机密码子")).tag(CodonPolicy.random)
                                Text(L("避开稀有后的随机")).tag(CodonPolicy.randomNonRare)
                            }.labelsHidden().frame(width: 200)
                        }
                        LabeledRow("密码子表") {
                            Picker("", selection: $draft.library.codonTable) {
                                Text("E. coli").tag(TableID.ecoli)
                                Text(L("人")).tag(TableID.human)
                            }.labelsHidden().frame(width: 140)
                        }
                        LabeledRow("子库步长 (nt)") {
                            TextField("", value: $draft.library.stepNt, format: .number)
                                .textFieldStyle(.roundedBorder).frame(width: 90)
                        }
                    }

                    Block("组装") {
                        LabeledRow("构建方式") {
                            Picker("", selection: $draft.assembly.method) {
                                Text("Golden Gate").tag(AssemblyMethod.goldenGate)
                                Text("Gibson").tag(AssemblyMethod.gibson)
                            }.labelsHidden().frame(width: 160)
                        }
                        if draft.assembly.method == .goldenGate {
                            LabeledRow("Type IIS 酶") {
                                Picker("", selection: $draft.assembly.enzyme) {
                                    ForEach(enzymes, id: \.0) { name, display in
                                        Text(display).tag(name)
                                    }
                                }.labelsHidden().frame(width: 200)
                            }
                        }
                    }

                    Block("数据存储") {
                        LabeledRow("当前位置") {
                            Text(AppPaths.root.path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.ink2).lineLimit(1).truncationMode(.middle)
                        }
                        HStack(spacing: Theme.s2) {
                            Button(L("更改位置…")) { chooseFolder() }
                                .buttonStyle(SecondaryButtonStyle())
                            Text(L("迁移 projects、runs.sqlite 与 presets.json；期间主界面关闭，完成后自动重启。"))
                                .font(.system(size: 11)).foregroundStyle(Theme.faint)
                        }
                        .padding(.top, 6)
                    }

                    Block("外部工具") {
                        LabeledRow("FASTQ 分析前用 fastp 过滤") {
                            Toggle("", isOn: Binding(
                                get: { UserDefaults.standard.object(forKey: "fastpEnabled") as? Bool ?? true },
                                set: { UserDefaults.standard.set($0, forKey: "fastpEnabled") }))
                                .labelsHidden().toggleStyle(InkToggleStyle())
                        }
                        LabeledRow("fastp 路径") {
                            TextField("/opt/homebrew/bin/fastp", text: Binding(
                                get: { UserDefaults.standard.string(forKey: "fastpPath") ?? "/opt/homebrew/bin/fastp" },
                                set: { UserDefaults.standard.set($0, forKey: "fastpPath") }))
                                .textFieldStyle(.roundedBorder).frame(width: 320)
                        }
                        LabeledRow("fastp 额外参数") {
                            TextField("--qualified_quality_phred 15", text: Binding(
                                get: { UserDefaults.standard.string(forKey: "fastpArgs") ?? "--qualified_quality_phred 15 --length_required 30" },
                                set: { UserDefaults.standard.set($0, forKey: "fastpArgs") }))
                                .textFieldStyle(.roundedBorder).frame(width: 320)
                        }
                    }

                    Block("质检项默认") {
                        LabeledRow("终止密码子变体数") { countField($draft.qc.stop.count) }
                        LabeledRow("同义突变变体数") { countField($draft.qc.synonymous.count) }
                        LabeledRow("脯氨酸变体数") { countField($draft.qc.proline.count) }
                        LabeledRow("随机区（每子库）") { countField($draft.qc.randomRegion.countPerSublibrary) }
                    }
                }
            }

            HStack {
                let v = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                let b = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
                Text("DMS Foundry \(v) (build \(b))")
                    .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.faint)
                Spacer()
                Button(L("恢复出厂默认")) { store.resetDefaults(); draft = store.defaults }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button(L("保存为默认值")) { store.setDefaults(draft) }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(Theme.s4)
        .onAppear { if !loaded { draft = store.defaults; loaded = true } }
        .alert(L("迁移数据？"), isPresented: $showMoveConfirm) {
            Button(L("取消"), role: .cancel) {}
            Button(L("开始迁移"), role: .destructive) {
                if let url = pendingRoot { model.beginMigration(to: url) }
            }
        } message: {
            Text(F("将把数据迁移到 %@，迁移期间主界面会关闭，完成后自动重启。", pendingRoot?.path ?? ""))
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L("选择目录")
        if panel.runModal() == .OK, let url = panel.url {
            pendingRoot = url
            showMoveConfirm = true
        }
    }

    private func countField(_ binding: Binding<Int>) -> some View {
        TextField("", value: binding, format: .number)
            .textFieldStyle(.roundedBorder).frame(width: 80)
    }
}

// MARK: - 外观

private struct AppearanceTab: View {
    @ObservedObject private var appearance = AppearanceController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            Text(L("外观")).font(.system(size: 15, weight: .semibold))
            Text(L("跟随系统会在 macOS 切换浅色/深色时实时更新，无需重启。"))
                .font(.system(size: 11.5)).foregroundStyle(Theme.muted)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(AppearanceMode.allCases) { m in
                    Button { appearance.mode = m } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .stroke(appearance.mode == m ? Theme.ink : Theme.hairlineStrong, lineWidth: 1)
                                .overlay {
                                    if appearance.mode == m {
                                        Circle().fill(Theme.ink).frame(width: 7, height: 7)
                                    }
                                }
                                .frame(width: 14, height: 14)
                            Text(L(m.title)).font(.system(size: 12.5))
                                .foregroundStyle(appearance.mode == m ? Theme.ink : Theme.ink2)
                            if m == .system {
                                Text(F("（当前 %@）", L(appearance.systemIsDark ? "深色" : "浅色")))
                                    .font(.system(size: 10.5)).foregroundStyle(Theme.faint)
                            }
                            Spacer()
                        }
                        .frame(height: 28)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                }
            }

            Spacer()
        }
        .padding(Theme.s4)
    }
}

// MARK: - 命名预设

private struct PresetsTab: View {
    @ObservedObject var store: PresetStore
    @EnvironmentObject private var model: AppModel
    @State private var newName = ""
    @State private var showName = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            HStack {
                Text(L("命名预设")).font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(L("从当前项目保存为预设")) {
                    newName = model.current.map { "\($0.name) 预设" } ?? ""
                    showName = true
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.current == nil)
            }
            Text(L("预设只包含参数（宿主、文库参数、组装、质检项），不包含质粒与突变目标。"))
                .font(.system(size: 11.5)).foregroundStyle(Theme.muted)

            if store.presets.isEmpty {
                VStack(spacing: 8) {
                    Text(L("还没有预设")).font(.system(size: 13)).foregroundStyle(Theme.muted)
                    Text(L("在某个项目里调好参数后，点右上角保存。")).font(.system(size: 11)).foregroundStyle(Theme.faint)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 40)
                .overlay(Rectangle().stroke(Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.presets) { p in
                            HStack(spacing: Theme.s2) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name).font(.system(size: 12.5, weight: .medium))
                                    Text("\(p.payload.host) · 步长 \(p.payload.library.stepNt) nt · \(p.createdAt, format: .dateTime.month().day().hour().minute())")
                                        .font(.system(size: 10.5)).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                Button(L("应用到当前项目")) { model.applyPreset(p.payload) }
                                    .buttonStyle(SecondaryButtonStyle())
                                    .disabled(model.current == nil)
                                Button {
                                    store.deletePreset(id: p.id)
                                } label: { Image(systemName: "trash") }
                                    .buttonStyle(.plain)
                                    .help(L("删除预设"))
                            }
                            .padding(.horizontal, Theme.s3)
                            .frame(height: 52)
                            .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
                            .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(Theme.s4)
        .alert(L("命名预设"), isPresented: $showName) {
            TextField(L("预设名称"), text: $newName)
            Button(L("取消"), role: .cancel) {}
            Button(L("保存")) {
                if let payload = model.currentPayload() {
                    store.addPreset(name: newName, payload: payload)
                }
            }
        } message: {
            Text(L("只保存参数，不包含质粒与突变目标。"))
        }
    }
}
