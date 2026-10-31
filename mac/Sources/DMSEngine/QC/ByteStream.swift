import Foundation

/// 分块字节流：普通文件或 gzip 解压流，绝不整文件载入。
public protocol ByteStream: AnyObject {
    func read(maxBytes: Int) throws -> Data?
    func close()
}

public final class FileByteStream: ByteStream {
    private var handle: FileHandle?
    public init(url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
    }
    public func read(maxBytes: Int) throws -> Data? {
        guard let h = handle else { return nil }
        let d = try h.read(upToCount: maxBytes) ?? Data()
        return d.isEmpty ? nil : d
    }
    public func close() {
        try? handle?.close()
        handle = nil
    }
}

/// 用系统 gzip 解压为管道流；读多少解多少，内存恒定。
public final class GzipByteStream: ByteStream {
    private let process = Process()
    private var handle: FileHandle?

    public init(url: URL) throws {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-dc", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        handle = pipe.fileHandleForReading
    }

    public func read(maxBytes: Int) throws -> Data? {
        guard let h = handle else { return nil }
        let d = try h.read(upToCount: maxBytes) ?? Data()
        return d.isEmpty ? nil : d
    }

    public func close() {
        try? handle?.close()
        handle = nil
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
    }
}

public func openByteStream(url: URL) throws -> ByteStream {
    let gz = url.pathExtension.lowercased() == "gz"
    return gz ? try GzipByteStream(url: url) : try FileByteStream(url: url)
}

/// 按行切分的缓冲读取器（UTF-8，容忍 CRLF）。
public final class LineReader {
    private let stream: ByteStream
    private var buffer = Data()
    private var eof = false

    public init(stream: ByteStream) { self.stream = stream }

    public func nextLine() throws -> String? {
        while true {
            if let idx = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer[buffer.startIndex..<idx]
                buffer.removeSubrange(buffer.startIndex...idx)
                var s = String(decoding: lineData, as: UTF8.self)
                if s.hasSuffix("\r") { s.removeLast() }
                return s
            }
            if eof { break }
            if let chunk = try stream.read(maxBytes: 1 << 22) {
                buffer.append(chunk)
            } else {
                eof = true
            }
        }
        guard !buffer.isEmpty else { return nil }
        let s = String(decoding: buffer, as: UTF8.self)
        buffer.removeAll(keepingCapacity: false)
        return s
    }
}

public struct FastqRecord: Sendable {
    public var name: String
    public var sequence: String
    public var quality: String
    public init(name: String, sequence: String, quality: String) {
        self.name = name; self.sequence = sequence; self.quality = quality
    }
}

public final class FastqReader {
    private var reader: LineReader
    public private(set) var lineCount = 0

    public init(url: URL) throws {
        reader = LineReader(stream: try openByteStream(url: url))
    }

    public init(stream: ByteStream) {
        reader = LineReader(stream: stream)
    }

    public func next() throws -> FastqRecord? {
        guard let head = try reader.nextLine() else { return nil }
        if head.isEmpty { return try next() }
        guard head.hasPrefix("@") else { throw SequenceError.rangeOutOfBounds("FASTQ 头不是 @: \(head.prefix(40))") }
        guard let seq = try reader.nextLine(),
              let plus = try reader.nextLine(),
              let qual = try reader.nextLine() else {
            throw SequenceError.rangeOutOfBounds("FASTQ 记录被截断")
        }
        guard plus.hasPrefix("+") else { throw SequenceError.rangeOutOfBounds("FASTQ 第三行不是 +") }
        lineCount += 4
        return FastqRecord(name: String(head.dropFirst()), sequence: seq.uppercased(), quality: qual)
    }

    public func close() {}
}
