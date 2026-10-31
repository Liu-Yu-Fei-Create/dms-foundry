import SwiftUI
import DMSEngine

struct ScreeningModuleView: View {
    @EnvironmentObject private var model: AppModel

    private var plan: ScreeningPlan { model.current?.screeningPlan ?? ScreeningPlan() }
    private var sublibraries: [SubLibrary] { model.design()?.sublibraries ?? [] }
    private var assigned: Set<String> { Set(plan.groups.flatMap(\.sublibraryIDs)) }
    private var missing: [String] { sublibraries.map(\.id).filter { !assigned.contains($0) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.s4) {
                header
                whyBlock
                if sublibraries.isEmpty {
                    Text(L("需要先在设计模块生成文库。"))
                        .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                } else {
                    groupsBlock
                    summaryBlock
                }
            }
            .padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 40)
            .frame(maxWidth: Theme.contentMax, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Theme.paper)
        .onAppear {
            model.ensureScreeningPlan()
            if ProcessInfo.processInfo.environment["DMS_SCREENING_DEMO"] == "1",
               (model.current?.screeningPlan?.groups.isEmpty ?? true),
               !sublibraries.isEmpty {
                var p = ScreeningPlan()
                let ids = sublibraries.map(\.id)
                p.groups = [ScreeningGroup(name: "分组 A", sublibraryIDs: Array(ids.prefix(3)), replicates: 3),
                            ScreeningGroup(name: "分组 B", sublibraryIDs: Array(ids.dropFirst(3)), replicates: 3)]
                model.current?.screeningPlan = p
                model.save()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("筛选方案")).font(.system(size: 20, weight: .semibold))
            Text(L("决定哪些子库一起筛、每个分组做几个重复；分析模块直接读取这份方案。"))
                .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
        }
    }

    private var whyBlock: some View {
        Block("为什么需要先定方案") {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("· 分组决定“能不能合并分析”：同一分组内的子库共享 selection 条件与重复，跨组只能在归一后合并。"))
                Text(L("· 重复数决定统计功效：2 个重复只能看趋势，3 个以上才谈得上置信区间。"))
                Text(L("· 方案一旦开始实验就不好改，所以先在这里定死，再让分析模块按方案出结论。"))
            }
            .font(.system(size: 11.5)).foregroundStyle(Theme.muted)
        }
    }

    private var groupsBlock: some View {
        Block("分组") {
            VStack(alignment: .leading, spacing: 0) {
                if plan.groups.isEmpty {
                    Text(L("还没有分组。至少建一个分组，把子库分配进去。"))
                        .font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.vertical, 10)
                }
                ForEach(Array(plan.groups.enumerated()), id: \.element.id) { idx, group in
                    groupRow(idx: idx, group: group)
                }
                HStack {
                    Button(L("新建分组")) { addGroup() }.buttonStyle(SecondaryButtonStyle())
                    if !missing.isEmpty {
                        Text(F("还有 %d 个子库未分配：%@", missing.count, missing.joined(separator: "、")))
                            .font(.system(size: 11)).foregroundStyle(.red)
                    }
                    Spacer()
                }
                .padding(.top, 10)
            }
        }
    }

    private func groupRow(idx: Int, group: ScreeningGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: Theme.s2) {
                TextField("", text: binding(idx, \.name))
                    .textFieldStyle(.plain).font(.system(size: 13, weight: .medium))
                    .frame(width: 160)
                Text(F("%d 个子库", group.sublibraryIDs.count))
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
                Spacer()
                Text(L("重复")).font(.system(size: 11)).foregroundStyle(Theme.muted)
                Stepper("", value: binding(idx, \.replicates), in: 1...8).labelsHidden()
                Text("\(group.replicates)").font(.system(size: 12, design: .monospaced))
                Button {
                    removeGroup(idx)
                } label: { Image(systemName: "trash") }.buttonStyle(.plain)
            }
            HStack(spacing: 6) {
                ForEach(sublibraries) { s in
                    let on = group.sublibraryIDs.contains(s.id)
                    Button {
                        toggle(idx, s.id)
                    } label: {
                        Text(s.id).font(.system(size: 10.5, design: .monospaced))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(on ? Theme.ink : Color.clear)
                            .foregroundStyle(on ? Theme.paper : Theme.ink2)
                            .overlay(Rectangle().stroke(on ? Theme.ink : Theme.hairlineStrong, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private var summaryBlock: some View {
        Block("方案摘要") {
            let samples = plan.groups.filter { !$0.sublibraryIDs.isEmpty }.reduce(0) { $0 + $1.replicates }
            HStack(spacing: 0) {
                MetricCell(label: "分组", value: "\(plan.groups.count)")
                divider
                MetricCell(label: "子库", value: "\(assigned.count)/\(sublibraries.count)")
                divider
                MetricCell(label: "样本数（分组×重复）", value: "\(samples)")
            }
            .padding(.vertical, 6)
            let empty = plan.groups.filter { $0.sublibraryIDs.isEmpty }
            if !empty.isEmpty {
                HStack(spacing: Theme.s2) {
                    Text(F("有 %d 个空分组，不会参与分析。", empty.count))
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                    Button(L("清理空分组")) { pruneEmpty() }.buttonStyle(SecondaryButtonStyle())
                }
            }
            if missing.isEmpty && !plan.groups.isEmpty {
                Text(L("所有子库已分配，可以按此方案做筛选与分析。"))
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
        }
    }

    private var divider: some View { Rectangle().fill(Theme.hairline).frame(width: 1, height: 34) }

    private func binding<T>(_ idx: Int, _ keyPath: WritableKeyPath<ScreeningGroup, T>) -> Binding<T> {
        Binding(
            get: { plan.groups.indices.contains(idx) ? plan.groups[idx][keyPath: keyPath] : plan.groups.first![keyPath: keyPath] },
            set: { newValue in
                guard var p = model.current?.screeningPlan, p.groups.indices.contains(idx) else { return }
                p.groups[idx][keyPath: keyPath] = newValue
                model.current?.screeningPlan = p
                model.save()
            })
    }

    private func addGroup() {
        var p = model.current?.screeningPlan ?? ScreeningPlan()
        let used = Set(p.groups.flatMap(\.sublibraryIDs))
        let free = sublibraries.map(\.id).filter { !used.contains($0) }
        let ids = Array(free.prefix(1))
        p.groups.append(ScreeningGroup(name: "分组 \(p.groups.count + 1)", sublibraryIDs: ids, replicates: 3))
        model.current?.screeningPlan = p
        model.save()
    }

    private func removeGroup(_ idx: Int) {
        guard var p = model.current?.screeningPlan, p.groups.indices.contains(idx) else { return }
        p.groups.remove(at: idx)
        model.current?.screeningPlan = p
        model.save()
    }

    private func pruneEmpty() {
        guard var p = model.current?.screeningPlan else { return }
        p.groups.removeAll { $0.sublibraryIDs.isEmpty }
        model.current?.screeningPlan = p
        model.save()
    }

    private func toggle(_ idx: Int, _ sub: String) {
        guard var p = model.current?.screeningPlan, p.groups.indices.contains(idx) else { return }
        var g = p.groups[idx]
        if let at = g.sublibraryIDs.firstIndex(of: sub) { g.sublibraryIDs.remove(at: at) }
        else { g.sublibraryIDs.append(sub); g.sublibraryIDs.sort() }
        p.groups[idx] = g
        model.current?.screeningPlan = p
        model.save()
    }
}
