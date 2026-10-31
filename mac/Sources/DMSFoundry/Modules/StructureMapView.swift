import SwiftUI
import SceneKit
import DMSEngine

enum StructureColorScheme: String, CaseIterable {
    case gray, diverging, heat
    var title: String {
        switch self {
        case .gray: return "灰阶"
        case .diverging: return "蓝红"
        case .heat: return "热度"
        }
    }
}

struct StructureMapView: NSViewRepresentable {
    let atoms: [PDBAtom]
    let effectByResidue: [Int: Double]
    let chains: Set<String>
    var scheme: StructureColorScheme = .gray

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.autoenablesDefaultLighting = true
        view.allowsCameraControl = true
        view.backgroundColor = NSColor(white: 1.0, alpha: 1.0)
        view.scene = StructureSceneBuilder.build(atoms: atoms, effectByResidue: effectByResidue,
                                                 chains: chains, scheme: scheme)
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        view.scene = StructureSceneBuilder.build(atoms: atoms, effectByResidue: effectByResidue,
                                                 chains: chains, scheme: scheme)
    }

    static func snapshot(atoms: [PDBAtom], effectByResidue: [Int: Double],
                         chains: Set<String>, scheme: StructureColorScheme,
                         size: CGSize = CGSize(width: 1600, height: 1200)) -> NSImage? {
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = StructureSceneBuilder.build(atoms: atoms, effectByResidue: effectByResidue,
                                                     chains: chains, scheme: scheme)
        return renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
    }
}

enum StructureSceneBuilder {
    static func build(atoms: [PDBAtom], effectByResidue: [Int: Double],
                      chains: Set<String>, scheme: StructureColorScheme) -> SCNScene {
        let scene = SCNScene()
        let root = scene.rootNode
        let filtered = atoms.filter { chains.contains($0.chain) }
        guard !filtered.isEmpty else { return scene }

        let xs = filtered.map { Double($0.x) }
        let ys = filtered.map { Double($0.y) }
        let zs = filtered.map { Double($0.z) }
        let cx = (xs.min()! + xs.max()!) / 2
        let cy = (ys.min()! + ys.max()!) / 2
        let cz = (zs.min()! + zs.max()!) / 2
        let span = max(xs.max()! - xs.min()!, max(ys.max()! - ys.min()!, zs.max()! - zs.min()!))
        let scale = span > 0 ? 30.0 / span : 1.0

        func pos(_ a: PDBAtom) -> SCNVector3 {
            SCNVector3(CGFloat((Double(a.x) - cx) * scale),
                       CGFloat((Double(a.y) - cy) * scale),
                       CGFloat((Double(a.z) - cz) * scale))
        }

        let byChain = Dictionary(grouping: filtered, by: \.chain)
        for (_, chainAtoms) in byChain {
            let pts = chainAtoms.sorted { $0.resSeq < $1.resSeq }
            guard pts.count > 1 else { continue }
            let positions: [SCNVector3] = pts.map(pos)
            for i in 0..<(positions.count - 1) {
                let p0 = positions[max(i - 1, 0)]
                let p1 = positions[i]
                let p2 = positions[i + 1]
                let p3 = positions[min(i + 2, positions.count - 1)]
                let effect = effectByResidue[pts[i].resSeq]
                var prev = p1
                for step in 1...5 {
                    let t = CGFloat(step) / 5
                    let cur = catmullRom(p0, p1, p2, p3, t)
                    let seg = cylinder(from: prev, to: cur, radius: 0.30)
                    seg.geometry?.firstMaterial?.diffuse.contents = color(for: effect, scheme: scheme)
                    root.addChildNode(seg)
                    prev = cur
                }
            }
            for (i, a) in pts.enumerated() {
                let sphere = SCNSphere(radius: 0.28)
                sphere.firstMaterial?.diffuse.contents = color(for: effectByResidue[a.resSeq], scheme: scheme)
                let node = SCNNode(geometry: sphere)
                node.position = positions[i]
                root.addChildNode(node)
            }
        }

        let camNode = SCNNode()
        camNode.camera = SCNCamera()
        camNode.position = SCNVector3(0, 0, 46)
        root.addChildNode(camNode)
        return scene
    }

    static func catmullRom(_ p0: SCNVector3, _ p1: SCNVector3, _ p2: SCNVector3, _ p3: SCNVector3, _ t: CGFloat) -> SCNVector3 {
        let t2 = t * t, t3 = t2 * t
        func axis(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
            0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
        }
        return SCNVector3(axis(p0.x, p1.x, p2.x, p3.x),
                          axis(p0.y, p1.y, p2.y, p3.y),
                          axis(p0.z, p1.z, p2.z, p3.z))
    }

    static func color(for effect: Double?, scheme: StructureColorScheme) -> NSColor {
        guard let e = effect else { return NSColor(white: 0.62, alpha: 1) }
        let t = min(abs(e) / 2.0, 1.0)
        switch scheme {
        case .gray:
            return e >= 0 ? NSColor(white: 1 - 0.85 * t, alpha: 1) : NSColor(white: 1 - 0.35 * t, alpha: 1)
        case .diverging:
            if e >= 0 { return NSColor(red: 0.85, green: 0.25 + 0.6 * (1 - t), blue: 0.25 + 0.6 * (1 - t), alpha: 1) }
            return NSColor(red: 0.20 + 0.7 * (1 - t), green: 0.35 + 0.5 * (1 - t), blue: 0.85, alpha: 1)
        case .heat:
            if e >= 0 { return NSColor(red: 0.95, green: 0.85 - 0.7 * t, blue: 0.25 * (1 - t), alpha: 1) }
            return NSColor(red: 0.25 + 0.5 * (1 - t), green: 0.55 + 0.3 * (1 - t), blue: 0.9, alpha: 1)
        }
    }

    static func cylinder(from a: SCNVector3, to b: SCNVector3, radius: CGFloat) -> SCNNode {
        let dx = b.x - a.x, dy = b.y - a.y, dz = b.z - a.z
        let dist = max(sqrt(dx * dx + dy * dy + dz * dz), 0.001)
        let geo = SCNCylinder(radius: radius, height: dist)
        let node = SCNNode(geometry: geo)
        node.position = SCNVector3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2)
        let dir = (dx / dist, dy / dist, dz / dist)
        let up = (CGFloat(0), CGFloat(1), CGFloat(0))
        let axis = (up.1 * dir.2 - up.2 * dir.1, up.2 * dir.0 - up.0 * dir.2, up.0 * dir.1 - up.1 * dir.0)
        let dot = up.0 * dir.0 + up.1 * dir.1 + up.2 * dir.2
        let angle = acos(max(-1, min(1, dot)))
        if abs(angle) > 1e-5 {
            node.rotation = SCNVector4(axis.0, axis.1, axis.2, angle)
        }
        return node
    }
}
