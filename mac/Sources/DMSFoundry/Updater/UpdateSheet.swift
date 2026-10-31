import SwiftUI
import DMSEngine

struct UpdateSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L("检查更新")).font(.title2).bold()
                Spacer()
                Text(model.appVersionText).font(.callout).foregroundStyle(.secondary)
            }

            HStack {
                Text(L("更新服务器")).font(.callout)
                TextField("https://example.com/dmsfoundry/stable/manifest.json",
                          text: $model.updateFeedURL)
                    .textFieldStyle(.roundedBorder)
                Button(L("保存并检查")) {
                    Task { await model.checkUpdates() }
                }
            }

            Group {
                switch model.updatePhase {
                case .idle:
                    Text(L("填好服务器地址后点「保存并检查」。")).foregroundStyle(.secondary)
                case .checking:
                    HStack { ProgressView().controlSize(.small); Text(L("正在检查…")) }
                case .upToDate(let v):
                    Text(F("已是最新版本（服务器：%@）", v)).foregroundStyle(.secondary)
                case .available(let v, let notes):
                    VStack(alignment: .leading, spacing: 6) {
                        Text(F("发现新版本 %@", v)).font(.headline)
                        Text(notes).font(.callout).foregroundStyle(.secondary)
                    }
                case .downloading:
                    HStack { ProgressView().controlSize(.small); Text(L("正在下载…")) }
                case .ready(let path):
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("已下载并通过校验")).font(.headline)
                        Text(path).font(.caption).monospaced().foregroundStyle(.secondary)
                        Text(L("ad-hoc 阶段不做就地替换：请在 Finder 里把新版本拖入「应用程序」，或等拿到 Developer ID 后启用 Sparkle 自动安装。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                case .failed(let msg):
                    Text(msg).foregroundStyle(.red).font(.callout)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
            HStack {
                if case .available = model.updatePhase {
                    Button(L("下载并校验")) { Task { await model.downloadUpdate() } }
                        .buttonStyle(PrimaryButtonStyle())
                }
                Spacer()
                Button(L("关闭")) { dismiss() }
            }
        }
        .padding(20)
        .frame(width: 620, height: 320)
    }
}
