import Foundation

/// 可播种、跨平台一致的 PRNG（Swift 的 SystemRandomNumberGenerator 不可播种）。
public struct SplitMix64: RandomNumberGenerator, Codable, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { self.state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// 命名空间派生：design / qc.stop / qc.syn / qc.pro / qc.rand / index / boundary
    public static func stream(seed: UInt64, purpose: String) -> SplitMix64 {
        var h: UInt64 = 1469598103934665603
        for b in purpose.utf8 {
            h ^= UInt64(b)
            h = h &* 1099511628211
        }
        return SplitMix64(seed: seed ^ h)
    }
}
