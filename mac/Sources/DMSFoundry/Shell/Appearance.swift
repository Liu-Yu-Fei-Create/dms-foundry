import SwiftUI
import AppKit

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// 统一管理外观：持久化、应用、以及「跟随系统」时的实时刷新。
final class AppearanceController: ObservableObject {
    static let shared = AppearanceController()

    @Published var mode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: "appearanceMode")
            apply()
        }
    }

    /// 系统当前是否深色（跟随系统时用于在设置里显示状态）
    @Published private(set) var systemIsDark: Bool = false

    private var observers: [NSObjectProtocol] = []
    private var kvo: NSKeyValueObservation?

    init() {
        let saved = UserDefaults.standard.string(forKey: "appearanceMode") ?? AppearanceMode.system.rawValue
        self.mode = AppearanceMode(rawValue: saved) ?? .system
        self.systemIsDark = Self.isSystemDark()
        apply()

        // 系统外观切换（通知是 distributed 的）
        let name = NSNotification.Name("AppleInterfaceThemeChangedNotification")
        observers.append(DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            self?.refreshIfFollowingSystem()
        })
        // AppKit 侧兜底：NSApp 的 effectiveAppearance 变化
        if let app = NSApp {
            kvo = app.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
                guard let self, self.mode == .system else { return }
                self.systemIsDark = Self.isSystemDark()
            }
        }
    }

    deinit {
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        kvo?.invalidate()
    }

    private static func isSystemDark() -> Bool {
        guard let app = NSApp else { return false }
        return app.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private func refreshIfFollowingSystem() {
        guard mode == .system else { return }
        systemIsDark = Self.isSystemDark()
        apply()
        objectWillChange.send()   // 让 SwiftUI 重新求值一遍
    }

    /// 窗口出现后重新应用一次（init 时 NSApp 可能还不存在）
    func reapply() { apply() }

    private func apply() {
        switch mode {
        case .system:
            NSApp?.appearance = nil
        case .light:
            NSApp?.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp?.appearance = NSAppearance(named: .darkAqua)
        }
        systemIsDark = Self.isSystemDark()
        if ProcessInfo.processInfo.environment["DMS_APPEARANCE_LOG"] == "1" {
            NSLog("appearance apply mode=%@ nsapp=%@ appearance=%@ systemDark=%@",
                  mode.rawValue, NSApp == nil ? "nil" : "yes",
                  NSApp?.appearance?.name.rawValue ?? "nil", systemIsDark ? "dark" : "light")
        }
    }
}
