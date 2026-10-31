import Foundation

public final class ProjectStore {
    public static let shared = ProjectStore()
    public let root: URL
    private let fm = FileManager.default

    public init(root: URL? = nil) {
        if let root { self.root = root }
        else {
            self.root = AppPaths.projects
        }
        try? fm.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    public func projectDir(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }

    public func list() -> [Project] {
        let dirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        var out: [Project] = []
        for url in dirs {
            guard let id = UUID(uuidString: url.lastPathComponent),
                  let p = try? load(id: id) else { continue }
            out.append(p)
        }
        return out.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func load(id: UUID) throws -> Project {
        let url = projectDir(id).appendingPathComponent("project.json")
        let data = try Data(contentsOf: url)
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try dec.decode(Project.self, from: data)
    }

    public func save(_ project: Project) throws {
        var p = project; p.updatedAt = Date()
        let dir = projectDir(p.id)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(p)
        let tmp = dir.appendingPathComponent("project.json.tmp")
        try data.write(to: tmp, options: .atomic)
        let dst = dir.appendingPathComponent("project.json")
        _ = try? fm.replaceItemAt(dst, withItemAt: tmp)
    }
}
