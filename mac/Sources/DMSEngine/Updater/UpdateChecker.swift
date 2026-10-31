import Foundation
import CryptoKit

public struct UpdateNotes: Codable, Sendable {
    public var zh: String?
    public var en: String?
}

public struct UpdateArtifact: Codable, Sendable {
    public var arch: String
    public var url: String
    public var sha256: String
    public var signature: String?
    public var size: Int?
}

public struct UpdateLatest: Codable, Sendable {
    public var version: String
    public var build: Int
    public var minOS: String?
    public var publishedAt: String?
    public var notes: UpdateNotes?
    public var artifacts: [UpdateArtifact]
}

public struct UpdateManifest: Codable, Sendable {
    public var schemaVersion: Int
    public var channel: String?
    public var latest: UpdateLatest
}

public enum UpdateError: Error, LocalizedError {
    case badURL, insecureTransport, checksumMismatch, signatureInvalid, signatureMissing
    case httpStatus(Int)
    case decode(String)
    case noArtifactForArch(String)
    case downloadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .badURL: return "更新地址不合法"
        case .insecureTransport: return "更新地址必须使用 HTTPS（本机调试除外）"
        case .httpStatus(let c): return "服务器返回 HTTP \(c)"
        case .decode(let m): return "无法解析更新清单：\(m)"
        case .noArtifactForArch(let a): return "清单里没有适用于 \(a) 的产物"
        case .checksumMismatch: return "SHA-256 校验不通过，下载可能被篡改"
        case .signatureInvalid: return "Ed25519 签名校验不通过"
        case .signatureMissing: return "产物没有签名，拒绝安装"
        case .downloadFailed(let m): return "下载失败：\(m)"
        }
    }
}

public struct UpdateCheckResult: Sendable {
    public var manifest: UpdateManifest
    public var artifact: UpdateArtifact
    public var currentBuild: Int
    public var isNewer: Bool
}

public enum UpdateChecker {

    public static var currentBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0
    }
    public static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
    public static var defaultFeedURL: String {
        Bundle.main.infoDictionary?["DSFUpdateFeedURL"] as? String ?? ""
    }
    public static var publicKeyBase64: String {
        Bundle.main.infoDictionary?["DSFUpdatePublicKey"] as? String ?? ""
    }

    static func isLocalHost(_ url: URL) -> Bool {
        ["127.0.0.1", "localhost", "::1"].contains(url.host ?? "")
    }

    public static func check(feedURL: String) async throws -> UpdateCheckResult {
        guard let url = URL(string: feedURL), !feedURL.isEmpty else { throw UpdateError.badURL }
        guard url.scheme == "https" || (url.scheme == "http" && isLocalHost(url)) else {
            throw UpdateError.insecureTransport
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw UpdateError.downloadFailed("无响应") }
        guard http.statusCode == 200 else { throw UpdateError.httpStatus(http.statusCode) }
        let manifest: UpdateManifest
        do { manifest = try JSONDecoder().decode(UpdateManifest.self, from: data) }
        catch { throw UpdateError.decode(error.localizedDescription) }

        let arch = currentArch()
        guard let artifact = manifest.latest.artifacts.first(where: { $0.arch == arch || $0.arch == "universal" }) else {
            throw UpdateError.noArtifactForArch(arch)
        }
        return UpdateCheckResult(manifest: manifest, artifact: artifact,
                                 currentBuild: currentBuild,
                                 isNewer: manifest.latest.build > currentBuild)
    }

    public static func currentArch() -> String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    public static func download(_ result: UpdateCheckResult, publicKeyBase64: String) async throws -> URL {
        guard let url = URL(string: result.artifact.url) else { throw UpdateError.badURL }
        guard url.scheme == "https" || (url.scheme == "http" && isLocalHost(url)) else {
            throw UpdateError.insecureTransport
        }
        let (tmp, resp) = try await URLSession.shared.download(from: url)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.httpStatus((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let data = try Data(contentsOf: tmp)
        let digest = Data(SHA256.hash(data: data))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        guard hex.lowercased() == result.artifact.sha256.lowercased() else {
            throw UpdateError.checksumMismatch
        }
        guard let sigB64 = result.artifact.signature, !sigB64.isEmpty else {
            throw UpdateError.signatureMissing
        }
        guard !publicKeyBase64.isEmpty,
              let pubData = Data(base64Encoded: publicKeyBase64),
              let sigData = Data(base64Encoded: sigB64) else {
            throw UpdateError.signatureInvalid
        }
        let pub = try Curve25519.Signing.PublicKey(rawRepresentation: pubData)
        guard pub.isValidSignature(sigData, for: digest) else {
            throw UpdateError.signatureInvalid
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DMSFoundry/updates", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let dest = base.appendingPathComponent("DMSFoundry-\(result.manifest.latest.version).zip")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }
}
