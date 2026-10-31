import SwiftUI
import AppKit

private extension NSColor {
    static func dyn(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { app in
            app.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
}

private func gray(_ w: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(white: w, alpha: a) }

/// 黑白身份的统一取值：颜色（随浅/深色自适应）、间距、行高。
enum Theme {
    // 纸张 / 墨色
    static let paper = Color(nsColor: .dyn(light: gray(1.0), dark: gray(0.09)))
    static let paperAlt = Color(nsColor: .dyn(light: gray(0.975), dark: gray(0.12)))
    static let ink = Color(nsColor: .dyn(light: gray(0.0), dark: gray(0.95)))
    static let ink2 = Color(nsColor: .dyn(light: gray(0.27), dark: gray(0.80)))
    static let muted = Color(nsColor: .dyn(light: gray(0.42), dark: gray(0.62)))
    static let faint = Color(nsColor: .dyn(light: gray(0.58), dark: gray(0.46)))

    // 线与面
    static let hairline = Color(nsColor: .dyn(light: gray(0.90), dark: gray(0.24)))
    static let hairlineStrong = Color(nsColor: .dyn(light: gray(0.74), dark: gray(0.38)))
    static let hover = Color(nsColor: .dyn(light: gray(0.965), dark: gray(0.20)))
    static let zebra = Color(nsColor: .dyn(light: gray(0.988), dark: gray(0.155)))
    static let wash = Color(nsColor: .dyn(light: gray(0.94), dark: gray(0.22)))
    static let wedge = Color(nsColor: .dyn(light: gray(0.0, 0.045), dark: gray(1.0, 0.07)))

    // 质粒图特征色（深色下提亮）
    static let featPromoter = Color(nsColor: .dyn(light: NSColor(red: 0.16, green: 0.42, blue: 0.40, alpha: 1),
                                                  dark: NSColor(red: 0.36, green: 0.68, blue: 0.64, alpha: 1)))
    static let featTerminator = Color(nsColor: .dyn(light: NSColor(red: 0.52, green: 0.34, blue: 0.16, alpha: 1),
                                                    dark: NSColor(red: 0.78, green: 0.60, blue: 0.36, alpha: 1)))
    static let featCDS = Color(nsColor: .dyn(light: NSColor(red: 0.16, green: 0.29, blue: 0.48, alpha: 1),
                                             dark: NSColor(red: 0.42, green: 0.58, blue: 0.82, alpha: 1)))
    static let featOrigin = Color(nsColor: .dyn(light: gray(0.42), dark: gray(0.62)))
    static let featResistance = Color(nsColor: .dyn(light: NSColor(red: 0.48, green: 0.16, blue: 0.22, alpha: 1),
                                                    dark: NSColor(red: 0.80, green: 0.42, blue: 0.48, alpha: 1)))
    static let featOther = Color(nsColor: .dyn(light: gray(0.58), dark: gray(0.55)))

    static let s1: CGFloat = 8
    static let s2: CGFloat = 12
    static let s3: CGFloat = 16
    static let s4: CGFloat = 24
    static let s5: CGFloat = 32
    static let s6: CGFloat = 40
    static let rowHeight: CGFloat = 30
    static let contentMax: CGFloat = 1120
}

/// 无框分区：小标题 + 内容 + 底部分隔线。
struct Block<Content: View>: View {
    let title: String
    var content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L(title))
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.08)
                .foregroundStyle(Theme.muted)
                .padding(.bottom, 6)
            content
        }
        .padding(.bottom, 18)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}

struct LabeledRow<Control: View>: View {
    let label: String
    var control: Control
    init(_ label: String, @ViewBuilder control: () -> Control) {
        self.label = label; self.control = control()
    }
    var body: some View {
        HStack(spacing: Theme.s3) {
            Text(L(label))
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.ink2)
                .frame(width: 150, alignment: .leading)
            control.frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: Theme.rowHeight)
        .padding(.vertical, 1)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}

struct MetricCell: View {
    let label: String
    let value: String
    var accent: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L(label)).font(.system(size: 11)).foregroundStyle(Theme.muted)
            Text(value)
                .font(.system(size: 20, weight: accent ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 黑白实心主按钮
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Theme.paper)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Theme.ink.opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.25))
            .contentShape(Rectangle())
    }
}

/// 黑白描边次按钮
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5))
            .foregroundStyle(enabled ? Theme.ink : Theme.faint)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(configuration.isPressed ? Theme.hover : Color.clear)
            .overlay(Rectangle().stroke(enabled ? Theme.hairlineStrong : Theme.hairline, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

/// 方框勾选，代替系统开关/复选框
struct InkToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(configuration.isOn ? Theme.ink : Color.clear)
                    .overlay(Rectangle().stroke(configuration.isOn ? Theme.ink : Theme.hairlineStrong, lineWidth: 1))
                    .overlay {
                        if configuration.isOn {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Theme.paper)
                        }
                    }
                    .frame(width: 14, height: 14)
                configuration.label
            }
        }
        .buttonStyle(.plain)
    }
}
