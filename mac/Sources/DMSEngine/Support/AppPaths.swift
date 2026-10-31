import Foundation

/// 数据根目录：默认为 Application Support/DMSFoundry，可在设置里迁移到自定义位置。
public enum AppPaths {
    public static let defaultsKey = "dataRoot"

    public static var defaultRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("DMSFoundry", isDirectory: true)
    }

    public static var root: URL {
        if let custom = UserDefaults.standard.string(forKey: defaultsKey), !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return defaultRoot
    }

    public static func setRoot(_ url: URL?) {
        if let url { UserDefaults.standard.set(url.path, forKey: defaultsKey) }
        else { UserDefaults.standard.removeObject(forKey: defaultsKey) }
    }

    public static var projects: URL { root.appendingPathComponent("projects", isDirectory: true) }
    public static var runsDB: URL { root.appendingPathComponent("runs.sqlite") }
    public static var presetsFile: URL { root.appendingPathComponent("presets.json") }
    public static var updates: URL { root.appendingPathComponent("updates", isDirectory: true) }
}
