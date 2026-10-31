import Foundation

/// 资源查找：兼顾 SPM 测试环境（Bundle.module）与手工组装的 .app（Contents/Resources 下的 *.bundle）
public enum EngineResources {
    public static func url(_ name: String, _ ext: String) -> URL? {
        let rel = "Resources/Data/\(name).\(ext)"
        let fm = FileManager.default
        var candidates: [URL] = []

        if let res = Bundle.main.resourceURL {
            candidates.append(res.appendingPathComponent(rel))          // 扁平放置
            if let items = try? fm.contentsOfDirectory(at: res, includingPropertiesForKeys: nil) {
                for item in items where item.pathExtension == "bundle" {
                    candidates.append(item.appendingPathComponent(rel))
                    candidates.append(item.appendingPathComponent("Contents/Resources/\(rel)"))
                }
            }
        }
        let exeDir = URL(fileURLWithPath: CommandLine.arguments.first ?? "").deletingLastPathComponent()
        candidates.append(exeDir.appendingPathComponent(rel))

        for c in candidates where fm.fileExists(atPath: c.path) { return c }

        // SPM 测试 / swift run
        if let u = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Resources/Data") { return u }
        return Bundle.module.url(forResource: name, withExtension: ext)
    }
}
