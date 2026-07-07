import RealityKit
import UIKit

extension MeshResource {
    /// `generateCylinder` 需 iOS 18+;此處提供向下相容包裝:
    /// iOS 18 以上使用系統 API,iOS 17 以程序化網格產生等效圓柱。
    static func compatibleCylinder(height: Float, radius: Float, segments: Int = 24) -> MeshResource {
        if #available(iOS 18.0, *) {
            return .generateCylinder(height: height, radius: radius)
        }
        return proceduralCylinder(height: height, radius: radius, segments: segments)
    }

    private static func proceduralCylinder(height: Float, radius: Float, segments: Int) -> MeshResource {
        let halfH = height / 2
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var triangles: [UInt32] = []

        // 側面:每段兩個頂點(下、上),法線朝外
        for i in 0..<segments {
            let angle = 2 * Float.pi * Float(i) / Float(segments)
            let x = cos(angle), z = sin(angle)
            positions.append([radius * x, -halfH, radius * z])
            positions.append([radius * x,  halfH, radius * z])
            normals.append([x, 0, z])
            normals.append([x, 0, z])
        }
        for i in 0..<segments {
            let next = (i + 1) % segments
            let a = UInt32(i * 2)          // 下 (本段)
            let b = UInt32(i * 2 + 1)      // 上 (本段)
            let c = UInt32(next * 2)       // 下 (下一段)
            let d = UInt32(next * 2 + 1)   // 上 (下一段)
            triangles += [a, b, c, b, d, c]
        }

        // 頂/底蓋圓心
        let bottomCenter = UInt32(positions.count)
        positions.append([0, -halfH, 0]); normals.append([0, -1, 0])
        let topCenter = UInt32(positions.count)
        positions.append([0, halfH, 0]); normals.append([0, 1, 0])

        // 蓋面環頂點(法線朝上/下,與側面分開避免共用平滑)
        let ringStart = UInt32(positions.count)
        for i in 0..<segments {
            let angle = 2 * Float.pi * Float(i) / Float(segments)
            let x = cos(angle), z = sin(angle)
            positions.append([radius * x, -halfH, radius * z]); normals.append([0, -1, 0])
            positions.append([radius * x,  halfH, radius * z]); normals.append([0, 1, 0])
        }
        for i in 0..<segments {
            let next = (i + 1) % segments
            let bi = ringStart + UInt32(i * 2)
            let bn = ringStart + UInt32(next * 2)
            triangles += [bottomCenter, bn, bi]           // 底(朝 -Y)
            let ti = ringStart + UInt32(i * 2 + 1)
            let tn = ringStart + UInt32(next * 2 + 1)
            triangles += [topCenter, ti, tn]              // 頂(朝 +Y)
        }

        var descriptor = MeshDescriptor(name: "compatibleCylinder")
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.primitives = .triangles(triangles)
        return (try? MeshResource.generate(from: [descriptor]))
            ?? .generateBox(size: [radius * 2, height, radius * 2])
    }
}

/// 參照物定義。尺寸一律為真實公制(公尺)。
/// v1 先以程序化幾何體(box/cylinder)佔位,之後替換為無商標 USDZ 模型:
/// 將 .usdz 放入 Resources/USDZ/ 並填入 usdzName 即自動改用模型載入。
struct ReferenceObject: Identifiable {
    let id: String
    let name: String
    let icon: String            // SF Symbol
    let usdzName: String?       // 之後替換用
    let makeEntity: () -> ModelEntity

    static let catalog: [ReferenceObject] = [
        ReferenceObject(id: "slipper", name: "藍白拖", icon: "shoe", usdzName: nil) {
            // 26 x 10 cm、厚 2cm,藍白雙色
            let sole = ModelEntity(mesh: .generateBox(size: [0.26, 0.015, 0.10], cornerRadius: 0.02),
                                   materials: [SimpleMaterial(color: .white, isMetallic: false)])
            let strap = ModelEntity(mesh: .generateBox(size: [0.10, 0.008, 0.09], cornerRadius: 0.01),
                                    materials: [SimpleMaterial(color: .systemBlue, isMetallic: false)])
            strap.position = [0.03, 0.014, 0]
            sole.addChild(strap)
            return sole
        },
        ReferenceObject(id: "lighter", name: "打火機", icon: "flame", usdzName: nil) {
            // BIC 大:8.1 x 2.5 x 1.2 cm,平放
            ModelEntity(mesh: .generateBox(size: [0.081, 0.012, 0.025], cornerRadius: 0.005),
                        materials: [SimpleMaterial(color: .systemRed, isMetallic: false)])
        },
        ReferenceObject(id: "can330", name: "330ml 鋁罐", icon: "cylinder", usdzName: nil) {
            // 高 11.5cm、直徑 6.6cm,直立
            let e = ModelEntity(mesh: .compatibleCylinder(height: 0.115, radius: 0.033),
                                materials: [SimpleMaterial(color: .systemGray, isMetallic: true)])
            e.position.y = 0.0575
            return e
        },
        ReferenceObject(id: "easycard", name: "悠遊卡", icon: "creditcard", usdzName: nil) {
            // ISO ID-1:8.56 x 5.4 cm
            ModelEntity(mesh: .generateBox(size: [0.0856, 0.001, 0.054], cornerRadius: 0.003),
                        materials: [SimpleMaterial(color: .systemTeal, isMetallic: false)])
        },
        ReferenceObject(id: "bottle600", name: "600ml 寶特瓶", icon: "waterbottle", usdzName: nil) {
            let e = ModelEntity(mesh: .compatibleCylinder(height: 0.205, radius: 0.032),
                                materials: [SimpleMaterial(color: UIColor.systemCyan.withAlphaComponent(0.5),
                                                           isMetallic: false)])
            e.position.y = 0.1025
            return e
        },
        ReferenceObject(id: "coin1", name: "1元硬幣", icon: "circle", usdzName: nil) {
            ModelEntity(mesh: .compatibleCylinder(height: 0.0015, radius: 0.010),
                        materials: [SimpleMaterial(color: .systemYellow, isMetallic: true)])
        },
        ReferenceObject(id: "ruler30", name: "30cm 直尺", icon: "ruler", usdzName: nil) {
            ModelEntity(mesh: .generateBox(size: [0.30, 0.002, 0.035]),
                        materials: [SimpleMaterial(color: UIColor.systemYellow.withAlphaComponent(0.85),
                                                   isMetallic: false)])
        },
    ]
}

/// 參照物放置:放在魚體旁(主軸平行、間距 5cm),可拖曳/旋轉,禁止縮放。
@MainActor
final class ReferenceObjectPlacer {
    private(set) var placedIDs: [String] = []
    private var anchors: [AnchorEntity] = []
    let maxObjects = 3

    func place(_ object: ReferenceObject,
               near fishEndpoints: (SIMD3<Float>, SIMD3<Float>)?,
               in arView: ARView) {
        guard placedIDs.count < maxObjects else { return }

        let entity = object.makeEntity()
        entity.generateCollisionShapes(recursive: true)

        // 放置位置:魚主軸中點,往主軸法線方向偏移 (魚寬估 + 5cm)
        var position = SIMD3<Float>(0, 0, -0.4)
        if let (w1, w2) = fishEndpoints {
            let mid = (w1 + w2) / 2
            let axis = simd_normalize(w2 - w1)
            let up = SIMD3<Float>(0, 1, 0)
            let side = simd_normalize(simd_cross(axis, up))
            position = mid + side * 0.12
            // 參照物長軸對齊魚主軸
            let angle = atan2(axis.x, axis.z) - .pi / 2
            entity.orientation = simd_quatf(angle: angle, axis: up)
        } else if let hit = arView.raycast(from: CGPoint(x: arView.bounds.midX,
                                                         y: arView.bounds.midY),
                                           allowing: .estimatedPlane,
                                           alignment: .horizontal).first {
            let t = hit.worldTransform.columns.3
            position = SIMD3(t.x, t.y, t.z)
        }

        let anchor = AnchorEntity(world: position)
        anchor.addChild(entity)
        arView.scene.addAnchor(anchor)

        // 拖曳 + 旋轉手勢(刻意不含 .scale,維持比例可信度)
        arView.installGestures([.translation, .rotation], for: entity)

        anchors.append(anchor)
        placedIDs.append(object.id)
    }

    func removeAll(in arView: ARView) {
        anchors.forEach { arView.scene.removeAnchor($0) }
        anchors.removeAll()
        placedIDs.removeAll()
    }
}
