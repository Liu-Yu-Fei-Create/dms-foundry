import SwiftUI

struct NewProjectSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var host = PresetStore.shared.defaults.host

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("新建项目")).font(.title2).bold()
            Form {
                TextField(L("项目名称"), text: $name)
                Picker(L("宿主"), selection: $host) {
                    ForEach(HostCatalog.groups, id: \.self) { g in
                        Section(g) {
                            ForEach(HostCatalog.options.filter { $0.group == g }) { o in
                                Text(o.name).tag(o.name)
                            }
                        }
                    }
                }
            }.formStyle(.grouped).frame(height: 140)
            HStack {
                Spacer()
                Button(L("取消")) { dismiss() }.buttonStyle(SecondaryButtonStyle())
                Button(L("创建")) {
                    model.create(name: name, host: host); dismiss()
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 460)
    }
}
