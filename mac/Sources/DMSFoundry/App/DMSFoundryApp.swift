import SwiftUI
import Foundation
import DMSEngine

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppDelegate.ensureMainWindow()
        return true
    }

    static func ensureMainWindow() {
        if NSApp.windows.contains(where: { $0.isVisible && $0.title.contains("DMS Foundry") && !$0.title.contains("设置") }) {
            NSApp.windows.first(where: { $0.isVisible && $0.title.contains("DMS Foundry") && !$0.title.contains("设置") })?.makeKeyAndOrderFront(nil)
            return
        }
        if let item = findMenuItem("显示主窗口"), let action = item.action {
            NSApp.sendAction(action, to: item.target, from: item)
        }
    }

    static func findMenuItem(_ title: String) -> NSMenuItem? {
        func search(_ menu: NSMenu?) -> NSMenuItem? {
            guard let menu else { return nil }
            for item in menu.items {
                if item.title == title { return item }
                if let sub = item.submenu, let found = search(sub) { return found }
            }
            return nil
        }
        return search(NSApp.mainMenu)
    }
}

@main
struct DMSFoundryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var appearance = AppearanceController.shared
    @Environment(\.openWindow) private var openWindow

    init() {
        // QC 引擎自检：合成 FASTQ → 计数 → 对账
        if ProcessInfo.processInfo.environment["DMS_QC_SELFTEST"] == "1" {
            let ref = "ATGGCTGCTGCTGCTGCTGCTGCTGCTGCTG"
            let design = QCDesign(reference: ref, anchor5: "ACGTACGT", variants: [
                QCVariant(id: "V1", sublibrary: "SL01", position: 1, wtCodon: "ATG", mutCodon: "GTG", aaChange: "M1V"),
                QCVariant(id: "V2", sublibrary: "SL01", position: 3, wtCodon: "GCT", mutCodon: "GAT", aaChange: "A3D"),
                QCVariant(id: "V3", sublibrary: "SL02", position: 5, wtCodon: "GCT", mutCodon: "CCT", aaChange: "A5P"),
                QCVariant(id: "V4", sublibrary: "SL02", position: 7, wtCodon: "GCT", mutCodon: "TCT", aaChange: "A7S"),
            ])
            var lines = ""
            var r = Array(ref)
            r[0] = "G"; r[1] = "T"; r[2] = "G"
            let v1 = String(r)
            r = Array(ref); r[6] = "G"; r[7] = "A"; r[8] = "T"
            let v2 = String(r)
            for i in 0..<120 {
                let seq: String
                if i % 3 == 0 { seq = "ACGTACGT" + v1 }
                else if i % 3 == 1 { seq = "ACGTACGT" + v2 }
                else { seq = "ACGTACGT" + ref }
                lines += "@r\(i)\n\(seq)\n+\n\(String(repeating: "I", count: seq.count))\n"
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("qc_selftest.fastq")
            try? lines.write(to: url, atomically: true, encoding: .utf8)
            do {
                let res = try QCCounter.count(fastqURL: url, design: design)
                let rows = QCReport.rows(res)
                let sum = QCReport.summarize(res, rows: rows)
                print("qc_reads=\(sum.totalReads) anchored=\(sum.anchoredReads) designed=\(sum.designedVariants) observed=\(sum.observedVariants) zero=\(sum.zeroCount)")
                print("qc_median=\(sum.medianCoverage) gini=\(String(format: "%.3f", sum.gini)) verdict=\(sum.verdict) wildtype=\(res.spectrum.wildType)")
                print("qc_top=\(rows.filter { $0.observed > 0 }.map { "\($0.id):\($0.observed)" }.joined(separator: ","))")
            } catch {
                print("QC_SELFTEST FAILED: \(error)")
            }
            exit(0)
        }

        // FASTQ → 分析 的端到端自检（样本表 + 双端字段 + 计数 + 效应）
        if ProcessInfo.processInfo.environment["DMS_ANALYSIS_FASTQ_SELFTEST"] == "1" {
            let ref = "ATGGCTGCTGCTGCTGCTGCTGCTGCTGCTG"
            let design = QCDesign(reference: ref, anchor5: "ACGTACGT", variants: [
                QCVariant(id: "V1", sublibrary: "SL01", position: 1, wtCodon: "ATG", mutCodon: "GTG", aaChange: "M1V"),
                QCVariant(id: "V2", sublibrary: "SL01", position: 3, wtCodon: "GCT", mutCodon: "GAT", aaChange: "A3D"),
            ])
            func reads(_ v: QCVariant, _ n: Int) -> String {
                var mut = Array(ref)
                let lo = (v.position - 1) * 3
                for (k, ch) in v.mutCodon.enumerated() where lo + k < mut.count { mut[lo + k] = ch }
                let seq = "ACGTACGT" + String(mut)
                return (0..<n).map { "@r\($0)\n\(seq)\n+\n\(String(repeating: "I", count: seq.count))\n" }.joined()
            }
            let dir = FileManager.default.temporaryDirectory
            func write(_ name: String, _ s: String) -> String {
                let u = dir.appendingPathComponent(name)
                try? s.write(to: u, atomically: true, encoding: .utf8)
                return u.path
            }
            let wtSeq = "ACGTACGT" + ref
            let wtReads = (0..<30).map { "@w\($0)\n\(wtSeq)\n+\n\(String(repeating: "I", count: wtSeq.count))\n" }.joined()
            let inputReads = reads(design.variants[0], 10) + reads(design.variants[1], 10) + wtReads
            let selReads = reads(design.variants[0], 40) + reads(design.variants[1], 10)
            let specs: [QCSampleSpec] = [
                QCSampleSpec(name: "in1", sublibrary: "SL01", replicate: 1, condition: "input",
                             r1: write("in1.fastq", inputReads)),
                QCSampleSpec(name: "in2", sublibrary: "SL01", replicate: 2, condition: "input",
                             r1: write("in2.fastq", inputReads)),
                QCSampleSpec(name: "sel1", sublibrary: "SL01", replicate: 1, condition: "selected",
                             r1: write("sel1.fastq", selReads)),
                QCSampleSpec(name: "sel2", sublibrary: "SL01", replicate: 2, condition: "selected",
                             r1: write("sel2.fastq", selReads)),
            ]
            do {
                let results = try QCCounter.count(samples: specs, designFor: { _ in design })
                var samples: [CountsSample] = []
                for spec in specs {
                    guard let res = results[spec.name] else { continue }
                    samples.append(CountsSample(name: spec.name, condition: spec.condition,
                                                replicate: spec.replicate, sublibrary: spec.sublibrary,
                                                counts: res.counts, librarySize: res.anchoredReads))
                }
                let effects = AnalysisEngine.run(samples: samples,
                                                 variants: ["V1", "V2"],
                                                 synonymous: [])
                for e in effects {
                    print("fastq_effect \(e.variant): \(String(format: "%.3f", e.effect)) reps=\(e.replicates) q=\(String(format: "%.3f", e.q))")
                }
            } catch { print("ANALYSIS_FASTQ_SELFTEST FAILED: \(error)") }
            exit(0)
        }

        // 分析引擎自检
        if ProcessInfo.processInfo.environment["DMS_ANALYSIS_SELFTEST"] == "1" {
            var ins: [CountsSample] = []
            var sels: [CountsSample] = []
            for rep in 1...3 {
                ins.append(CountsSample(name: "in\(rep)", condition: "input", replicate: rep, sublibrary: "SL01",
                                        counts: ["V1": 100, "V2": 100, "S1": 1000, "S2": 1000, "S3": 1000]))
                sels.append(CountsSample(name: "sel\(rep)", condition: "selected", replicate: rep, sublibrary: "SL01",
                                         counts: ["V1": 400, "V2": 100, "S1": 900, "S2": 900, "S3": 900]))
            }
            let rows = AnalysisEngine.run(samples: ins + sels, variants: ["V1", "V2", "S1", "S2", "S3"],
                                          synonymous: ["S1", "S2", "S3"])
            for r in rows {
                print("effect \(r.variant): \(String(format: "%.3f", r.effect)) ci=[\(String(format: "%.3f", r.ciLow)),\(String(format: "%.3f", r.ciHigh))] q=\(String(format: "%.4f", r.q)) reps=\(r.replicates)")
            }
            exit(0)
        }

        // 外观自检：跟随系统时对通知作出反应
        if ProcessInfo.processInfo.environment["DMS_APPEARANCE_SELFTEST"] == "1" {
            let c = AppearanceController.shared
            print("mode=\(c.mode.rawValue) systemDark=\(c.systemIsDark)")
            c.mode = .system
            DistributedNotificationCenter.default().post(name: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            print("after_notify mode=\(c.mode.rawValue) systemDark=\(c.systemIsDark) appAppearance=\(NSApp?.appearance?.name.rawValue ?? "nil")")
            c.mode = .dark
            print("dark appAppearance=\(NSApp?.appearance?.name.rawValue ?? "nil")")
            c.mode = .system
            print("system appAppearance=\(NSApp?.appearance?.name.rawValue ?? "nil")")
            exit(0)
        }

        // 预设自检：默认值 + 命名预设的持久化
        if ProcessInfo.processInfo.environment["DMS_PRESET_SELFTEST"] == "1" {
            let store = PresetStore.shared
            var p = PresetPayload.standard
            p.host = "E. coli TOP10"
            p.library.stepNt = 120
            p.qc.stop.enabled = true
            p.qc.stop.count = 7
            store.setDefaults(p)
            store.addPreset(name: "自检预设", payload: p)
            print("defaults_host=\(store.defaults.host) step=\(store.defaults.library.stepNt) qc_stop=\(store.defaults.qc.stop.count)")
            print("presets=\(store.presets.map(\.name).joined(separator: ","))")
            let fresh = PresetStore()
            print("reload_defaults_host=\(fresh.defaults.host) step=\(fresh.defaults.library.stepNt) presets=\(fresh.presets.count)")
            exit(0)
        }

        // 更新链路自检：DMS_UPDATE_SELFTEST=1 DMS_FEED=<manifest url>
        if ProcessInfo.processInfo.environment["DMS_UPDATE_SELFTEST"] == "1" {
            let feed = ProcessInfo.processInfo.environment["DMS_FEED"] ?? ""
            let sem = DispatchSemaphore(value: 0)
            Task.detached {
                do {
                    let r = try await UpdateChecker.check(feedURL: feed)
                    print("feed_ok version=\(r.manifest.latest.version) build=\(r.manifest.latest.build) current=\(r.currentBuild) newer=\(r.isNewer)")
                    if r.isNewer {
                        let url = try await UpdateChecker.download(r, publicKeyBase64: UpdateChecker.publicKeyBase64)
                        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                        print("download_ok path=\(url.path) bytes=\(size ?? 0)")
                    }
                    exit(0)
                } catch {
                    print("UPDATE_SELFTEST FAILED: \(error.localizedDescription)")
                    exit(1)
                }
            }
            sem.wait()
        }

        // 无界面自检：验证打包后的资源与引擎在 .app 内可正常工作
        if ProcessInfo.processInfo.environment["DMS_SELFTEST"] == "1" {
            var code: Int32 = 0
            do {
                let table = try CodonTable.load(.ecoli)
                print("codon_table_entries=\(table.file.codons.count)")

                guard let indexURL = EngineResources.url("indices_1024", "json") else {
                    print("indices: MISSING"); exit(3)
                }
                struct IndexFile: Codable { let count: Int; let indices: [Item]; struct Item: Codable { let seq: String } }
                let idx = try JSONDecoder().decode(IndexFile.self, from: Data(contentsOf: indexURL))
                print("indices=\(idx.count)")

                guard let url = EngineResources.url("tem1_cds", "gb") else {
                    print("sample: MISSING"); exit(2)
                }
                let plasmid = try GenBankParser.parse(contents: String(contentsOf: url, encoding: .utf8))
                print("sample_bp=\(plasmid.sequence.count) features=\(plasmid.features.count)")

                let ctx = CodingContext(plasmid: plasmid, feature: plasmid.features[0])
                let variants = try MutationEnumerator.enumerate(context: ctx, range: 1...ctx.codonCount,
                                                                params: LibraryParams(), table: table, seed: 1)
                print("codons=\(ctx.codonCount) variants=\(variants.count)")
                print("sublibraries=\(Partitioner.split(aaRange: 1...ctx.codonCount, codonStart: 1, stepNt: 150).count)")
                let enzymes = try EnzymeTable.load()
                let oh = try OverhangTable.load()
                let plans = GoldenGatePlanner.plan(coding: ctx.coding, codonStart: 1,
                                                   aaRange: 1...ctx.codonCount, stepNt: 150,
                                                   enzymeName: "BsaI", enzyme: enzymes.enzymes["BsaI"]!,
                                                   overhangs: oh)
                for p in plans {
                    print("plan \(p.id) aa\(p.aaStart)-\(p.aaEnd) oh5=\(p.overhang5.sequence)/\(p.overhang5.grade) oh3=\(p.overhang3.sequence)/\(p.overhang3.grade) viable=\(p.viable) intern=\(p.internalSites.count)")
                }
                print("SELFTEST OK")
            } catch {
                print("SELFTEST FAILED: \(error)"); code = 1
            }
            exit(code)
        }
    }

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(model)
                .tint(Theme.ink)
                .preferredColorScheme(AppearanceController.shared.mode.colorScheme)
        }

        WindowGroup(id: "main") {
            RootView().environmentObject(model)
                .frame(minWidth: 1100, minHeight: 720)
        }
        .defaultSize(width: 1320, height: 860)
            .windowStyle(.hiddenTitleBar)
        .defaultPosition(.center)
        .commands {
            CommandGroup(before: .appSettings) {
                Picker("Language", selection: Binding(
                    get: { L10n.shared.lang },
                    set: { v in DispatchQueue.main.async { L10n.shared.lang = v } })) {
                    Text("简体中文").tag("zh")
                    Text("English").tag("en")
                }
            }
            CommandMenu("视图") {
                Picker(L("外观"), selection: Binding(
                    get: { appearance.mode },
                    set: { appearance.mode = $0 })) {
                    ForEach(AppearanceMode.allCases) { m in
                        Text(L(m.title)).tag(m)
                    }
                }
                Divider()
                Button("文库设计") { model.section = .design }.keyboardShortcut("1", modifiers: [.option])
                Button("文库质控") { model.section = .qc }.keyboardShortcut("2", modifiers: [.option])
                Button("筛选分析") { model.section = .analysis }.keyboardShortcut("3", modifiers: [.option])
            }
            CommandGroup(after: .appInfo) {
                Button(L("检查更新…")) {
                    model.showUpdateSheet = true
                    Task { await model.checkUpdates() }
                }.keyboardShortcut("u")
            }
            CommandGroup(replacing: .newItem) {
                Button(L("显示主窗口")) { openWindow(id: "main") }
                    .keyboardShortcut("0")
                Button(L("新建项目")) { model.showNewProject = true }.keyboardShortcut("n")
                Button(L("载入示例（TEM-1）")) { model.loadSample() }
                    .keyboardShortcut("l")
                Button(L("载入示例（.dna）")) { model.loadSampleDNA() }
                    .keyboardShortcut("d")
                Divider()
                Button(L("步骤 1 · 项目信息")) { model.step = 1 }.keyboardShortcut("1")
                Button(L("步骤 2 · 导入与标注")) { model.step = 2 }.keyboardShortcut("2")
                Button(L("步骤 3 · 文库参数")) { model.step = 3 }.keyboardShortcut("3")
                Button(L("步骤 4 · 质检项")) { model.step = 4 }.keyboardShortcut("4")
                Button(L("步骤 5 · 组装方式")) { model.step = 5 }.keyboardShortcut("5")
                Button(L("步骤 6 · 子库 index")) { model.step = 6 }.keyboardShortcut("6")
                Button(L("步骤 7 · 生成与 QC")) { model.step = 7 }.keyboardShortcut("7")
                Button(L("步骤 8 · 导出")) { model.step = 8 }.keyboardShortcut("8")
                Divider()
                Button(L("生成文库")) { model.generateLibrary() }.keyboardShortcut("g")
                Button(L("导出四件套")) { model.exportLibrary() }.keyboardShortcut("e")
            }
        }
    }
}
