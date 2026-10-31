import SwiftUI
import AppKit
import UniformTypeIdentifiers
import DMSEngine

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var appearance = AppearanceController.shared

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 224)
                .background(Theme.paperAlt)
            Rectangle().fill(Theme.hairline).frame(width: 1)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.paper)
        }
        .tint(Theme.ink)
        .preferredColorScheme(appearance.mode.colorScheme)
        .onAppear {
            appearance.reapply()
            switch ProcessInfo.processInfo.environment["DMS_SECTION"] {
            case "qc": model.section = .qc
            case "screening": model.section = .screening
            case "analysis": model.section = .analysis
            default: break
            }
            DispatchQueue.main.async {
                if let w = NSApp.windows.first {
                    w.isMovableByWindowBackground = true
                    w.title = "DMS Foundry"
                    w.contentMinSize = NSSize(width: 960, height: 640)
                    if w.frame.width > 1500 || w.frame.height > 1000 {
                        w.setContentSize(NSSize(width: 1320, height: 860))
                        w.center()
                    }
                }
            }
        }
        .sheet(isPresented: $model.showNewProject) { NewProjectSheet() }
        .sheet(isPresented: $model.showUpdateSheet) { UpdateSheet() }
        .fileImporter(isPresented: $model.isImporting,
                      allowedContentTypes: allowedTypes,
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let u = urls.first { model.importPlasmid(url: u) }
            case .failure(let e): model.banner = "选择文件失败：\(e.localizedDescription)"
            }
        }
        .overlay {
            if let m = model.migration {
                MigrationOverlay(state: m)
                    .environmentObject(model)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let b = model.banner {
                HStack {
                    Text(b).font(.callout)
                    Spacer()
                    Button(L("关闭")) { model.banner = nil }.buttonStyle(.link)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(.thinMaterial)
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 红绿灯占位（窗口内容已从标题栏下缘开始）
            Color.clear.frame(height: 6)
            Text(L("模块"))
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.08)
                .foregroundStyle(Theme.faint)
                .padding(.horizontal, 16).padding(.bottom, 6)
            ForEach(AppSection.allCases) { sec in
                Button { model.section = sec } label: {
                    HStack(spacing: 10) {
                        Image(systemName: sec.icon).font(.system(size: 12)).frame(width: 16)
                        Text(L(sec.title)).font(.system(size: 12.5, weight: model.section == sec ? .semibold : .regular))
                        Spacer()
                    }
                    .foregroundStyle(model.section == sec ? Theme.ink : Theme.ink2)
                    .padding(.horizontal, 16).frame(height: 32)
                    .background(model.section == sec ? Theme.wash : Color.clear)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(model.section == sec ? Theme.ink : Color.clear).frame(width: 2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
            }

            Rectangle().fill(Theme.hairline).frame(height: 1).padding(.vertical, 12)

            Text(L("项目"))
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.08)
                .foregroundStyle(Theme.faint)
                .padding(.horizontal, 16).padding(.bottom, 6)
            ForEach(model.projects) { proj in
                Button { model.section = .design; model.open(proj) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(proj.name).font(.system(size: 12.5, weight: model.current?.id == proj.id ? .semibold : .regular))
                            .lineLimit(1)
                        Text(proj.host).font(.system(size: 10.5)).foregroundStyle(Theme.faint).lineLimit(1)
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 16).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(model.current?.id == proj.id ? Theme.wash : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
            }

            Spacer(minLength: 8)
            Button { model.showNewProject = true } label: {
                Label(L("新建项目"), systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(12)
        }
    }

    @ViewBuilder
    private var detail: some View {
        Group {
            switch model.section {
            case .design:
                if model.current == nil { EmptyProjectView() } else { DesignWorkspace() }
            case .qc:
                if model.current != nil { QCModuleView() } else { PlaceholderModule(section: .qc) }
            case .screening:
                if model.current != nil { ScreeningModuleView() } else { PlaceholderModule(section: .screening) }
            case .analysis:
                if model.current != nil { AnalysisModuleView() } else { PlaceholderModule(section: .analysis) }
            }
        }
        .id(model.section)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.16), value: model.section)
    }

    private var allowedTypes: [UTType] {
        var types: [UTType] = []
        for ext in ["gb", "gbk", "genbank", "fasta", "fa", "fna", "txt", "dna"] {
            if let t = UTType(filenameExtension: ext) { types.append(t) }
        }
        if types.isEmpty { types = [.plainText] }
        return types
    }
}

struct MigrationOverlay: View {
    @EnvironmentObject private var model: AppModel
    let state: AppModel.MigrationState

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            VStack(spacing: 16) {
                Text(L("正在迁移数据")).font(.system(size: 20, weight: .semibold))
                if let failure = state.failed {
                    Text(failure).font(.system(size: 12)).foregroundStyle(.red)
                        .frame(maxWidth: 420)
                    Button(L("返回")) { model.migration = nil }.buttonStyle(SecondaryButtonStyle())
                } else {
                    ProgressView(value: state.fraction)
                        .frame(width: 360)
                    Text(state.text).font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                    Text(L("迁移期间主界面不可用；完成后会自动重启。"))
                        .font(.system(size: 11)).foregroundStyle(Theme.faint)
                }
            }
        }
    }
}

struct EmptyProjectView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.and.pencil").font(.system(size: 42, weight: .light))
            Text(L("还没有打开的项目")).font(.title3)
            Text(L("新建一个项目，导入表达质粒，然后标注要突变的区段。"))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button(L("新建项目")) { model.showNewProject = true }
                    .buttonStyle(PrimaryButtonStyle())
                Button(L("载入示例（TEM-1）")) { model.loadSample() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
