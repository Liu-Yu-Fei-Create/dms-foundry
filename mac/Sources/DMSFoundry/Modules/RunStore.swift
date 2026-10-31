import Foundation
import SQLite3
import DMSEngine

struct RunRecord: Identifiable {
    let id: UUID
    let type: String
    let title: String
    let createdAt: Date
    let payload: Data
}

/// 运行记录持久化（SQLite）。payload 为 JSON，便于各模块自描述。
final class RunStore {
    static let shared = RunStore()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "dms.runstore")

    init() {
        let base = AppPaths.root
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let url = AppPaths.runsDB
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { return }
        let sql = """
        CREATE TABLE IF NOT EXISTS runs (
          id TEXT PRIMARY KEY, type TEXT NOT NULL, project_id TEXT,
          title TEXT, created_at REAL, payload BLOB
        );
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    @discardableResult
    func save(type: String, projectID: UUID?, title: String, payload: Data) -> UUID? {
        let id = UUID()
        queue.sync {
            let sql = "INSERT INTO runs (id,type,project_id,title,created_at,payload) VALUES (?,?,?,?,?,?);"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, type, -1, SQLITE_TRANSIENT)
            if let p = projectID { sqlite3_bind_text(stmt, 3, p.uuidString, -1, SQLITE_TRANSIENT) }
            else { sqlite3_bind_null(stmt, 3) }
            sqlite3_bind_text(stmt, 4, title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 5, Date().timeIntervalSince1970)
            payload.withUnsafeBytes { buf in
                sqlite3_bind_blob(stmt, 6, buf.baseAddress, Int32(payload.count), SQLITE_TRANSIENT)
            }
            if sqlite3_step(stmt) != SQLITE_DONE { return }
        }
        return id
    }

    func list(type: String, projectID: UUID?) -> [RunRecord] {
        var out: [RunRecord] = []
        queue.sync {
            let sql = "SELECT id,title,created_at,payload FROM runs WHERE type = ? AND (project_id = ? OR project_id IS NULL) ORDER BY created_at DESC LIMIT 50;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, type, -1, SQLITE_TRANSIENT)
            if let p = projectID { sqlite3_bind_text(stmt, 2, p.uuidString, -1, SQLITE_TRANSIENT) }
            else { sqlite3_bind_null(stmt, 2) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let cid = sqlite3_column_text(stmt, 0),
                      let title = sqlite3_column_text(stmt, 1) else { continue }
                let created = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
                let n = Int(sqlite3_column_bytes(stmt, 3))
                var payload = Data()
                if let base = sqlite3_column_blob(stmt, 3), n > 0 {
                    payload = Data(bytes: base, count: n)
                }
                out.append(RunRecord(id: UUID(uuidString: String(cString: cid)) ?? UUID(),
                                     type: type, title: String(cString: title),
                                     createdAt: created, payload: payload))
            }
        }
        return out
    }

    func delete(_ id: UUID) {
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "DELETE FROM runs WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
