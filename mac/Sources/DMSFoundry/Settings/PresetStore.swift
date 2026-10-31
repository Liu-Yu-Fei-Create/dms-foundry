import Foundation
import DMSEngine

/// 一套可复用的参数：宿主 + 文库参数 + 组装 + 质检项
struct PresetPayload: Codable {
    var host: String
    var library: LibraryParams
    var assembly: Assembly
    var qc: QCOptions

    static var standard: PresetPayload {
        PresetPayload(host: "E. coli BL21(DE3)",
                      library: LibraryParams(),
                      assembly: Assembly(),
                      qc: QCOptions())
    }
}

struct NamedPreset: Codable, Identifiable {
    var id: UUID
    var name: String
    var payload: PresetPayload
    var createdAt: Date
}

final class PresetStore: ObservableObject {
    static let shared = PresetStore()

    @Published private(set) var defaults: PresetPayload
    @Published private(set) var presets: [NamedPreset]

    private let defaultsKey = "defaultPreset"
    private let dir: URL
    private var presetsURL: URL { dir.appendingPathComponent("presets.json") }

    init() {
        let base = AppPaths.root
        dir = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let p = try? JSONDecoder().decode(PresetPayload.self, from: data) {
            defaults = p
        } else {
            defaults = .standard
        }
        if let data = try? Data(contentsOf: base.appendingPathComponent("presets.json")),
           let list = try? JSONDecoder().decode([NamedPreset].self, from: data) {
            presets = list
        } else {
            presets = []
        }
    }

    func setDefaults(_ p: PresetPayload) {
        defaults = p
        if let data = try? JSONEncoder().encode(p) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    func resetDefaults() {
        defaults = .standard
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    func addPreset(name: String, payload: PresetPayload) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        presets.append(NamedPreset(id: UUID(), name: name.isEmpty ? "未命名预设" : name,
                                   payload: payload, createdAt: Date()))
        save()
    }

    func updatePreset(id: UUID, payload: PresetPayload) {
        guard let i = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[i].payload = payload
        save()
    }

    func deletePreset(id: UUID) {
        presets.removeAll { $0.id == id }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(presets) {
            try? data.write(to: presetsURL, options: .atomic)
        }
    }
}
