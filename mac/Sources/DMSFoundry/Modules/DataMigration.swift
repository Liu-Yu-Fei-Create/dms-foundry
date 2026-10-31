import Foundation
import DMSEngine

enum DataMigration {
    struct Item { let name: String; let url: URL }

    static func items(root: URL) -> [Item] {
        ["projects", "runs.sqlite", "presets.json"].compactMap { name in
            let u = root.appendingPathComponent(name)
            return FileManager.default.fileExists(atPath: u.path) ? Item(name: name, url: u) : nil
        }
    }

    static func totalBytes(_ items: [Item]) -> Int64 {
        items.reduce(0) { $0 + size(of: $1.url) }
    }

    static func size(of url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        }
        var total: Int64 = 0
        if let en = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) {
            for case let f as URL in en {
                let v = try? f.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                if v?.isRegularFile == true { total += Int64(v?.fileSize ?? 0) }
            }
        }
        return total
    }

    /// 复制到新根目录，成功后删除旧数据；进度按字节数回调。
    static func migrate(from source: URL, to destination: URL,
                        progress: @escaping (Double, String) -> Void) throws {
        let fm = FileManager.default
        let items = items(root: source)
        guard !items.isEmpty else { throw SequenceError.rangeOutOfBounds("没有找到需要迁移的数据") }

        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        for item in items {
            let target = destination.appendingPathComponent(item.name)
            if fm.fileExists(atPath: target.path) {
                throw SequenceError.rangeOutOfBounds("目标目录已有 \(item.name)，请换一个位置")
            }
        }

        let total = max(totalBytes(items), 1)
        var copied: Int64 = 0
        for item in items {
            let target = destination.appendingPathComponent(item.name)
            try copy(item.url, to: target, total: total, copied: &copied, progress: progress)
        }

        progress(1.0, "清理旧数据…")
        for item in items { try? fm.removeItem(at: item.url) }
        progress(1.0, "完成")
    }

    private static func copy(_ src: URL, to dst: URL, total: Int64,
                             copied: inout Int64, progress: (Double, String) -> Void) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        fm.fileExists(atPath: src.path, isDirectory: &isDir)
        if !isDir.boolValue {
            try fm.copyItem(at: src, to: dst)
            copied += size(of: src)
            progress(min(1, Double(copied) / Double(total)), src.lastPathComponent)
            return
        }
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        let base = src.path
        if let en = fm.enumerator(at: src, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) {
            for case let f as URL in en {
                let rel = String(f.path.dropFirst(base.count))
                let out = dst.appendingPathComponent(rel)
                let v = try? f.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                if v?.isRegularFile == true {
                    try fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.copyItem(at: f, to: out)
                    copied += Int64(v?.fileSize ?? 0)
                    progress(min(1, Double(copied) / Double(total)), f.lastPathComponent)
                } else if v?.isRegularFile == false {
                    try? fm.createDirectory(at: out, withIntermediateDirectories: true)
                }
            }
        }
    }
}
