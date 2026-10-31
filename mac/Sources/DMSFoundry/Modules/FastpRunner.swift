import Foundation
import DMSEngine

/// 可选：分析前用 fastp 过滤 FASTQ（默认开启，路径与参数在设置里改）。
enum FastpRunner {
    static var enabled: Bool {
        UserDefaults.standard.object(forKey: "fastpEnabled") as? Bool ?? true
    }
    static var binaryPath: String {
        UserDefaults.standard.string(forKey: "fastpPath") ?? "/opt/homebrew/bin/fastp"
    }
    static var extraArgs: String {
        UserDefaults.standard.string(forKey: "fastpArgs") ?? "--qualified_quality_phred 15 --length_required 30"
    }

    static func available() -> Bool { FileManager.default.isExecutableFile(atPath: binaryPath) }

    static func trim(_ url: URL, into dir: URL) throws -> URL {
        let out = dir.appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".trim.fastq")
        let report = dir.appendingPathComponent(out.lastPathComponent + ".fastp.json")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: binaryPath)
        var args = ["-i", url.path, "-o", out.path, "--json", report.path, "--disable_trim_poly_g"]
        args += extraArgs.split(separator: " ").map(String.init)
        p.arguments = args
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0, FileManager.default.fileExists(atPath: out.path) else {
            throw SequenceError.rangeOutOfBounds("fastp 运行失败（退出码 \(p.terminationStatus)）")
        }
        return out
    }
}
