import SwiftUI

struct PlaceholderModule: View {
    let section: AppSection

    private var planned: [String] {
        switch section {
        case .qc:
            return ["读段质控与覆盖度", "sub-library skew 检查", "合成错误的识别与剔除", "批次间一致性"]
        case .analysis:
            return ["variant effect 计算", "单点突变热图", "重复间合并与尺度校正", "功能景观分析"]
        default:
            return []
        }
    }

    var body: some View {
        VStack(spacing: Theme.s3) {
            Image(systemName: section.icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.ink)
            Text(L(section.title)).font(.system(size: 19, weight: .semibold))
            Text(L("开发中 · 敬请期待")).font(.system(size: 12.5)).foregroundStyle(Theme.muted)

            VStack(alignment: .leading, spacing: 0) {
                Text(L("规划能力"))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.06)
                    .foregroundStyle(Theme.muted)
                    .padding(.bottom, 6)
                ForEach(Array(planned.enumerated()), id: \.element) { idx, item in
                    HStack(spacing: Theme.s2) {
                        Rectangle().fill(Theme.ink).frame(width: 4, height: 4)
                        Text(L(item)).font(.system(size: 12.5))
                        Spacer()
                    }
                    .frame(height: 34)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                    }
                }
            }
            .frame(width: 560)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }

            Text(L("接口已预留：设计模块的导出数据将作为这两个模块的输入。"))
                .font(.system(size: 11)).foregroundStyle(Theme.faint)

            Button(L("导出设计数据供下游")) {}
                .buttonStyle(SecondaryButtonStyle())
                .disabled(true)
                .help(L("设计模块完成后可用"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.s6)
    }
}
