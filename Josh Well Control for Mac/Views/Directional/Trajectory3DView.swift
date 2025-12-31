//
//  Trajectory3DView.swift
//  Josh Well Control for Mac
//
//  3D visualization of wellbore trajectory using SceneKit.
//

import SwiftUI
import SceneKit

#if os(macOS)

enum CameraMode: String, CaseIterable {
    case orbit = "Orbit"
    case followPath = "Follow Path"

    var icon: String {
        switch self {
        case .orbit: return "rotate.3d"
        case .followPath: return "point.topleft.down.to.point.bottomright.curvepath"
        }
    }
}

enum FollowPathType: String, CaseIterable {
    case survey = "Survey"
    case plan = "Plan"
}

struct Trajectory3DView: View {
    let variances: [SurveyVariance]
    let plan: DirectionalPlan?
    let limits: DirectionalLimits
    let bitProjection: BitProjection?
    @Binding var hoveredMD: Double?
    var onHover: (Double?) -> Void

    @State private var resetTrigger: Bool = false
    @State private var cameraMode: CameraMode = .orbit
    @State private var pathPosition: Double = 0.0  // 0 to 1 along the path
    @State private var followPathType: FollowPathType = .survey

    private var planStations: [DirectionalPlanStation] {
        plan?.sortedStations ?? []
    }

    private var mdRange: ClosedRange<Double> {
        switch followPathType {
        case .survey:
            guard !variances.isEmpty else { return 0...100 }
            let minMD = variances.first?.surveyMD ?? 0
            let maxMD = variances.last?.surveyMD ?? 100
            return minMD...max(minMD + 1, maxMD)
        case .plan:
            guard !planStations.isEmpty else { return 0...100 }
            let minMD = planStations.first?.md ?? 0
            let maxMD = planStations.last?.md ?? 100
            return minMD...max(minMD + 1, maxMD)
        }
    }

    private var currentMD: Double {
        let range = mdRange
        return range.lowerBound + pathPosition * (range.upperBound - range.lowerBound)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            hoverInfo
            TrajectorySceneView(
                variances: variances,
                plan: plan,
                limits: limits,
                bitProjection: bitProjection,
                resetTrigger: resetTrigger,
                cameraMode: cameraMode,
                pathPosition: pathPosition,
                followPathType: followPathType
            )
            .frame(minHeight: 350)

            if cameraMode == .followPath {
                pathControls
            }

            legend
        }
    }

    private var pathControls: some View {
        VStack(spacing: 8) {
            // Path type picker
            HStack {
                Text("Follow:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $followPathType) {
                    ForEach(FollowPathType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                Spacer()
            }
            .padding(.horizontal, 8)

            pathSlider
        }
    }

    private var pathSlider: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.up")
                .foregroundStyle(.secondary)

            Slider(value: $pathPosition, in: 0...1) {
                Text("Position")
            }

            Image(systemName: "arrow.down")
                .foregroundStyle(.secondary)

            Text("MD: \(Int(currentMD))m")
                .font(.caption)
                .monospacedDigit()
                .frame(width: 80)
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Hover Info

    private var hoverInfo: some View {
        HStack {
            if let md = hoveredMD,
               let variance = variances.min(by: { abs($0.surveyMD - md) < abs($1.surveyMD - md) }) {
                HStack(spacing: 12) {
                    Text("MD: \(Int(variance.surveyMD))m")
                        .monospacedDigit()
                    Text("3D Dist: \(String(format: "%.1f", variance.distance3D))m")
                        .foregroundStyle(variance.distance3DStatus(for: limits).color)
                        .monospacedDigit()
                }
                .font(.caption)
            }
            Spacer()

            // Camera mode picker
            Picker("Camera", selection: $cameraMode) {
                ForEach(CameraMode.allCases, id: \.self) { mode in
                    Label(mode.rawValue, systemImage: mode.icon)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            Button {
                resetTrigger.toggle()
                if cameraMode == .followPath {
                    pathPosition = 0
                }
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .help("Reset camera")

            if cameraMode == .orbit {
                Text("Left-drag: rotate • Right-drag: pan • Scroll: zoom")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Use slider to move along path")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 20)
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(color: .green, label: "Plan")
            legendItem(color: .blue, label: "Actual")
            legendItem(color: .orange, label: "Bit Proj", isDiamond: true)
            legendItem(color: .green, label: "OK", isPoint: true)
            legendItem(color: .yellow, label: "Warning", isPoint: true)
            legendItem(color: .red, label: "Alarm", isPoint: true)
            Spacer()
        }
        .font(.caption)
    }

    private func legendItem(color: Color, label: String, isPoint: Bool = false, isDiamond: Bool = false) -> some View {
        HStack(spacing: 4) {
            if isDiamond {
                Rectangle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .rotationEffect(.degrees(45))
            } else if isPoint {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            } else {
                Rectangle()
                    .fill(color)
                    .frame(width: 16, height: 3)
            }
            Text(label)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Custom SceneKit View with Better Camera Controls

struct TrajectorySceneView: NSViewRepresentable {
    let variances: [SurveyVariance]
    let plan: DirectionalPlan?
    let limits: DirectionalLimits
    let bitProjection: BitProjection?
    let resetTrigger: Bool
    let cameraMode: CameraMode
    let pathPosition: Double  // 0 to 1 along the path
    let followPathType: FollowPathType

    private var planStations: [DirectionalPlanStation] {
        plan?.sortedStations ?? []
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> SCNView {
        let scnView = TrajectoryScrollView()
        scnView.scene = SCNScene()
        scnView.scene?.background.contents = NSColor.windowBackgroundColor
        scnView.autoenablesDefaultLighting = true
        scnView.allowsCameraControl = false  // We handle this ourselves

        // Link coordinator to scroll view
        scnView.coordinator = context.coordinator

        // Setup scene content
        setupScene(scnView: scnView, coordinator: context.coordinator)

        // Add gesture recognizers for camera control
        let panGesture = NSPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        scnView.addGestureRecognizer(panGesture)

        let magnifyGesture = NSMagnificationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMagnify(_:)))
        scnView.addGestureRecognizer(magnifyGesture)

        // Store reference for coordinator
        context.coordinator.scnView = scnView

        return scnView
    }

    func updateNSView(_ scnView: SCNView, context: Context) {
        setupScene(scnView: scnView, coordinator: context.coordinator)
    }

    private func setupScene(scnView: SCNView, coordinator: Coordinator) {
        guard let scene = scnView.scene else { return }

        // Clear existing content except camera
        scene.rootNode.childNodes.filter { $0.name != "camera" && $0.name != "cameraOrbit" }.forEach { $0.removeFromParentNode() }

        // Calculate trajectory center and bounds
        let (center, maxDim) = calculateCenterAndBounds()

        // Setup or update camera
        if coordinator.cameraOrbitNode == nil {
            setupCamera(scene: scene, coordinator: coordinator, center: center, maxDim: maxDim)
        } else {
            // Update orbit center for new data
            coordinator.orbitCenter = center
            coordinator.initialDistance = Float(maxDim * 2.5)
        }

        setupLighting(scene: scene)
        setupAxes(scene: scene)
        setupPlanTrajectory(scene: scene)
        setupActualTrajectory(scene: scene)
        setupBitProjection(scene: scene)

        // Set point of view
        if let cameraNode = coordinator.cameraNode {
            scnView.pointOfView = cameraNode
        }

        // Handle camera mode
        coordinator.cameraMode = cameraMode
        if cameraMode == .followPath {
            updateFollowPathCamera(coordinator: coordinator)
        }

        // Reset camera if triggered
        if coordinator.lastResetTrigger != resetTrigger {
            coordinator.lastResetTrigger = resetTrigger
            coordinator.orbitCenter = center
            coordinator.initialDistance = Float(maxDim * 2.5)
            coordinator.resetCamera()
        }
    }

    private func updateFollowPathCamera(coordinator: Coordinator) {
        let currentPos: SCNVector3

        switch followPathType {
        case .survey:
            guard variances.count >= 2 else { return }

            let totalSegments = variances.count - 1
            let exactIndex = pathPosition * Double(totalSegments)
            let lowerIndex = min(Int(exactIndex), totalSegments - 1)
            let upperIndex = min(lowerIndex + 1, totalSegments)
            let t = CGFloat(exactIndex - Double(lowerIndex))

            let v1 = variances[lowerIndex]
            let v2 = variances[upperIndex]

            let pos1 = SCNVector3(CGFloat(v1.surveyEW), CGFloat(-v1.surveyTVD), CGFloat(v1.surveyNS))
            let pos2 = SCNVector3(CGFloat(v2.surveyEW), CGFloat(-v2.surveyTVD), CGFloat(v2.surveyNS))

            currentPos = SCNVector3(
                pos1.x + (pos2.x - pos1.x) * t,
                pos1.y + (pos2.y - pos1.y) * t,
                pos1.z + (pos2.z - pos1.z) * t
            )

        case .plan:
            guard planStations.count >= 2 else { return }

            let totalSegments = planStations.count - 1
            let exactIndex = pathPosition * Double(totalSegments)
            let lowerIndex = min(Int(exactIndex), totalSegments - 1)
            let upperIndex = min(lowerIndex + 1, totalSegments)
            let t = CGFloat(exactIndex - Double(lowerIndex))

            let s1 = planStations[lowerIndex]
            let s2 = planStations[upperIndex]

            let pos1 = SCNVector3(CGFloat(s1.ew_m), CGFloat(-s1.tvd), CGFloat(s1.ns_m))
            let pos2 = SCNVector3(CGFloat(s2.ew_m), CGFloat(-s2.tvd), CGFloat(s2.ns_m))

            currentPos = SCNVector3(
                pos1.x + (pos2.x - pos1.x) * t,
                pos1.y + (pos2.y - pos1.y) * t,
                pos1.z + (pos2.z - pos1.z) * t
            )
        }

        // Update the orbit center to the current path position
        coordinator.followPathCenter = currentPos

        // Animate orbit node to the new center position
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.15

        // Move orbit center to current path position
        coordinator.cameraOrbitNode?.position = currentPos

        // Apply horizontal rotation only - camera stays level to show inclination
        coordinator.cameraOrbitNode?.eulerAngles = SCNVector3(
            0,  // No pitch - camera stays level
            coordinator.followPathRotationY,
            0   // No roll
        )

        // Camera at fixed distance from orbit center
        coordinator.cameraNode?.position = SCNVector3(0, 0, coordinator.followPathDistance)

        SCNTransaction.commit()
    }

    private func calculateCenterAndBounds() -> (SCNVector3, Double) {
        var allPoints = variances.map { ($0.surveyNS, $0.surveyEW, $0.surveyTVD) }
        let planPoints = (plan?.sortedStations ?? []).map { ($0.ns_m, $0.ew_m, $0.tvd) }

        if let bit = bitProjection {
            allPoints.append((bit.bitNS, bit.bitEW, bit.bitTVD))
        }

        let combined = allPoints + planPoints

        guard !combined.isEmpty else {
            return (SCNVector3(0, 0, 0), 500)
        }

        let nsValues = combined.map { $0.0 }
        let ewValues = combined.map { $0.1 }
        let tvdValues = combined.map { $0.2 }

        let avgNS = nsValues.reduce(0, +) / Double(combined.count)
        let avgEW = ewValues.reduce(0, +) / Double(combined.count)
        let avgTVD = tvdValues.reduce(0, +) / Double(combined.count)

        let maxNSRange = nsValues.map { abs($0 - avgNS) }.max() ?? 100
        let maxEWRange = ewValues.map { abs($0 - avgEW) }.max() ?? 100
        let maxTVDRange = tvdValues.map { abs($0 - avgTVD) }.max() ?? 100

        let maxDim = max(max(maxNSRange, maxEWRange), maxTVDRange)

        let center = SCNVector3(Float(avgEW), Float(-avgTVD), Float(avgNS))
        return (center, max(maxDim, 50))
    }

    private func setupCamera(scene: SCNScene, coordinator: Coordinator, center: SCNVector3, maxDim: Double) {
        // Create orbit node at center
        let orbitNode = SCNNode()
        orbitNode.name = "cameraOrbit"
        orbitNode.position = center
        scene.rootNode.addChildNode(orbitNode)

        // Create camera node
        let cameraNode = SCNNode()
        cameraNode.name = "camera"
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.automaticallyAdjustsZRange = true
        cameraNode.camera?.zNear = 1
        cameraNode.camera?.zFar = 100000

        // Position camera at distance from center
        let distance = Float(maxDim * 2.5)
        cameraNode.position = SCNVector3(0, 0, distance)
        orbitNode.addChildNode(cameraNode)

        // Initial rotation to get a good viewing angle
        orbitNode.eulerAngles = SCNVector3(-Float.pi / 6, Float.pi / 4, 0)

        coordinator.cameraOrbitNode = orbitNode
        coordinator.cameraNode = cameraNode
        coordinator.orbitCenter = center
        coordinator.initialDistance = distance
        coordinator.currentDistance = distance
    }

    private func setupLighting(scene: SCNScene) {
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 500
        scene.rootNode.addChildNode(ambientLight)

        let directionalLight = SCNNode()
        directionalLight.light = SCNLight()
        directionalLight.light?.type = .directional
        directionalLight.light?.intensity = 800
        directionalLight.position = SCNVector3(100, 200, 100)
        directionalLight.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(directionalLight)
    }

    private func setupAxes(scene: SCNScene) {
        let axisLength: Float = 200

        // X axis (East) - Red
        addAxisLine(scene: scene, from: SCNVector3(0, 0, 0), to: SCNVector3(axisLength, 0, 0), color: .red)
        addAxisLabel(scene: scene, "E", at: SCNVector3(axisLength + 20, 0, 0), color: .red)

        // Y axis (Up/Down - negative TVD) - Green
        addAxisLine(scene: scene, from: SCNVector3(0, 0, 0), to: SCNVector3(0, axisLength, 0), color: .green)
        addAxisLabel(scene: scene, "Up", at: SCNVector3(0, axisLength + 20, 0), color: .green)

        // Z axis (North) - Blue
        addAxisLine(scene: scene, from: SCNVector3(0, 0, 0), to: SCNVector3(0, 0, axisLength), color: .blue)
        addAxisLabel(scene: scene, "N", at: SCNVector3(0, 0, axisLength + 20), color: .blue)
    }

    private func addAxisLine(scene: SCNScene, from: SCNVector3, to: SCNVector3, color: NSColor) {
        let vertices: [SCNVector3] = [from, to]
        let source = SCNGeometrySource(vertices: vertices)
        let indices: [Int32] = [0, 1]
        let data = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
        let element = SCNGeometryElement(data: data, primitiveType: .line, primitiveCount: 1, bytesPerIndex: MemoryLayout<Int32>.size)

        let geometry = SCNGeometry(sources: [source], elements: [element])
        geometry.firstMaterial?.diffuse.contents = color

        let node = SCNNode(geometry: geometry)
        scene.rootNode.addChildNode(node)
    }

    private func addAxisLabel(scene: SCNScene, _ text: String, at position: SCNVector3, color: NSColor) {
        let textGeometry = SCNText(string: text, extrusionDepth: 1)
        textGeometry.font = NSFont.systemFont(ofSize: 12)
        textGeometry.firstMaterial?.diffuse.contents = color

        let textNode = SCNNode(geometry: textGeometry)
        textNode.position = position
        textNode.scale = SCNVector3(2, 2, 2)

        let constraint = SCNBillboardConstraint()
        constraint.freeAxes = [.X, .Y, .Z]
        textNode.constraints = [constraint]

        scene.rootNode.addChildNode(textNode)
    }

    private func setupPlanTrajectory(scene: SCNScene) {
        let stations = plan?.sortedStations ?? []
        guard stations.count > 1 else { return }

        var vertices: [SCNVector3] = []
        var indices: [Int32] = []

        for (index, station) in stations.enumerated() {
            let point = SCNVector3(
                Float(station.ew_m),
                Float(-station.tvd),
                Float(station.ns_m)
            )
            vertices.append(point)

            if index > 0 {
                indices.append(Int32(index - 1))
                indices.append(Int32(index))
            }
        }

        let source = SCNGeometrySource(vertices: vertices)
        let data = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
        let element = SCNGeometryElement(data: data, primitiveType: .line, primitiveCount: indices.count / 2, bytesPerIndex: MemoryLayout<Int32>.size)

        let geometry = SCNGeometry(sources: [source], elements: [element])
        geometry.firstMaterial?.diffuse.contents = NSColor.green
        geometry.firstMaterial?.lightingModel = .constant

        let lineNode = SCNNode(geometry: geometry)
        scene.rootNode.addChildNode(lineNode)
    }

    private func setupActualTrajectory(scene: SCNScene) {
        guard variances.count > 1 else { return }

        var lineVertices: [SCNVector3] = []
        var lineIndices: [Int32] = []

        for (index, variance) in variances.enumerated() {
            let point = SCNVector3(
                Float(variance.surveyEW),
                Float(-variance.surveyTVD),
                Float(variance.surveyNS)
            )
            lineVertices.append(point)

            if index > 0 {
                lineIndices.append(Int32(index - 1))
                lineIndices.append(Int32(index))
            }

            let status = variance.status(for: limits)
            addSurveyPoint(scene: scene, at: point, status: status, md: variance.surveyMD)
        }

        if lineIndices.count > 0 {
            let source = SCNGeometrySource(vertices: lineVertices)
            let data = Data(bytes: lineIndices, count: lineIndices.count * MemoryLayout<Int32>.size)
            let element = SCNGeometryElement(data: data, primitiveType: .line, primitiveCount: lineIndices.count / 2, bytesPerIndex: MemoryLayout<Int32>.size)

            let geometry = SCNGeometry(sources: [source], elements: [element])
            geometry.firstMaterial?.diffuse.contents = NSColor.blue
            geometry.firstMaterial?.lightingModel = .constant

            let lineNode = SCNNode(geometry: geometry)
            scene.rootNode.addChildNode(lineNode)
        }
    }

    private func addSurveyPoint(scene: SCNScene, at position: SCNVector3, status: VarianceStatus, md: Double) {
        let sphere = SCNSphere(radius: 5)

        let color: NSColor
        switch status {
        case .ok: color = .green
        case .warning: color = .yellow
        case .alarm: color = .red
        }

        sphere.firstMaterial?.diffuse.contents = color
        sphere.firstMaterial?.lightingModel = .phong

        let node = SCNNode(geometry: sphere)
        node.position = position
        node.name = "survey_\(md)"

        scene.rootNode.addChildNode(node)
    }

    private func setupBitProjection(scene: SCNScene) {
        guard let bit = bitProjection, let lastVariance = variances.last else { return }

        let lastSurveyPos = SCNVector3(
            Float(lastVariance.surveyEW),
            Float(-lastVariance.surveyTVD),
            Float(lastVariance.surveyNS)
        )

        let bitPos = SCNVector3(
            Float(bit.bitEW),
            Float(-bit.bitTVD),
            Float(bit.bitNS)
        )

        let planAtBitPos = SCNVector3(
            Float(bit.planEW),
            Float(-bit.planTVD),
            Float(bit.planNS)
        )

        addDashedLine(scene: scene, from: lastSurveyPos, to: bitPos, color: .orange, dashLength: 10, gapLength: 10)
        addBitMarker(scene: scene, at: bitPos, status: bit.status(for: limits))

        let planSphere = SCNSphere(radius: 4)
        planSphere.firstMaterial?.diffuse.contents = NSColor.green.withAlphaComponent(0.7)
        planSphere.firstMaterial?.lightingModel = .phong
        let planNode = SCNNode(geometry: planSphere)
        planNode.position = planAtBitPos
        scene.rootNode.addChildNode(planNode)

        addBitLabel(scene: scene, at: bitPos)
    }

    private func addDashedLine(scene: SCNScene, from: SCNVector3, to: SCNVector3, color: NSColor, dashLength: Float, gapLength: Float) {
        let dx = Float(to.x - from.x)
        let dy = Float(to.y - from.y)
        let dz = Float(to.z - from.z)
        let length = sqrt(dx * dx + dy * dy + dz * dz)

        guard length > 0 else { return }

        let unitX = dx / length
        let unitY = dy / length
        let unitZ = dz / length

        var currentLength: Float = 0
        var vertices: [SCNVector3] = []
        var indices: [Int32] = []
        var vertexIndex: Int32 = 0
        var isDash = true

        let fromX = Float(from.x)
        let fromY = Float(from.y)
        let fromZ = Float(from.z)

        while currentLength < length {
            let segmentLength = min(isDash ? dashLength : gapLength, length - currentLength)

            if isDash {
                let startPoint = SCNVector3(
                    fromX + unitX * currentLength,
                    fromY + unitY * currentLength,
                    fromZ + unitZ * currentLength
                )
                let endPoint = SCNVector3(
                    fromX + unitX * (currentLength + segmentLength),
                    fromY + unitY * (currentLength + segmentLength),
                    fromZ + unitZ * (currentLength + segmentLength)
                )
                vertices.append(startPoint)
                vertices.append(endPoint)
                indices.append(vertexIndex)
                indices.append(vertexIndex + 1)
                vertexIndex += 2
            }

            currentLength += segmentLength
            isDash.toggle()
        }

        guard !vertices.isEmpty else { return }

        let source = SCNGeometrySource(vertices: vertices)
        let data = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
        let element = SCNGeometryElement(data: data, primitiveType: .line, primitiveCount: indices.count / 2, bytesPerIndex: MemoryLayout<Int32>.size)

        let geometry = SCNGeometry(sources: [source], elements: [element])
        geometry.firstMaterial?.diffuse.contents = color
        geometry.firstMaterial?.lightingModel = .constant

        let node = SCNNode(geometry: geometry)
        scene.rootNode.addChildNode(node)
    }

    private func addBitMarker(scene: SCNScene, at position: SCNVector3, status: VarianceStatus) {
        let box = SCNBox(width: 10, height: 10, length: 10, chamferRadius: 1)

        let color: NSColor
        switch status {
        case .ok: color = .orange
        case .warning: color = .yellow
        case .alarm: color = .red
        }

        box.firstMaterial?.diffuse.contents = color
        box.firstMaterial?.lightingModel = .phong

        let node = SCNNode(geometry: box)
        node.position = position
        node.eulerAngles = SCNVector3(Float.pi / 4, Float.pi / 4, 0)
        node.name = "bit_projection"

        scene.rootNode.addChildNode(node)
    }

    private func addBitLabel(scene: SCNScene, at position: SCNVector3) {
        let textGeometry = SCNText(string: "BIT", extrusionDepth: 1)
        textGeometry.font = NSFont.boldSystemFont(ofSize: 10)
        textGeometry.firstMaterial?.diffuse.contents = NSColor.orange

        let textNode = SCNNode(geometry: textGeometry)
        textNode.position = SCNVector3(position.x, position.y + 15, position.z)
        textNode.scale = SCNVector3(1.5, 1.5, 1.5)

        let constraint = SCNBillboardConstraint()
        constraint.freeAxes = [.X, .Y, .Z]
        textNode.constraints = [constraint]

        scene.rootNode.addChildNode(textNode)
    }

    // MARK: - Coordinator for Gesture Handling

    class Coordinator: NSObject {
        weak var scnView: SCNView?
        var cameraOrbitNode: SCNNode?
        var cameraNode: SCNNode?
        var orbitCenter: SCNVector3 = .init(0, 0, 0)
        var initialDistance: Float = 500
        var currentDistance: Float = 500
        var lastResetTrigger: Bool = false
        var cameraMode: CameraMode = .orbit

        var currentRotationX: Float = -Float.pi / 6
        var currentRotationY: Float = Float.pi / 4

        // Follow path mode - separate rotation tracking
        var followPathRotationY: Float = 0  // Horizontal rotation only
        var followPathDistance: Float = 100
        var followPathCenter: SCNVector3 = .init(0, 0, 0)

        override init() {
            super.init()
        }

        func resetCamera() {
            currentRotationX = -Float.pi / 6
            currentRotationY = Float.pi / 4
            currentDistance = initialDistance

            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.3
            cameraOrbitNode?.eulerAngles = SCNVector3(currentRotationX, currentRotationY, 0)
            cameraOrbitNode?.position = orbitCenter
            cameraNode?.position = SCNVector3(0, 0, currentDistance)
            SCNTransaction.commit()
        }

        @objc func handlePan(_ gesture: NSPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            let isRightClick = NSEvent.pressedMouseButtons & 0x2 != 0

            if cameraMode == .followPath {
                // In follow path mode: only allow horizontal rotation (left-drag), no panning
                if !isRightClick {
                    let sensitivity: Float = 0.005
                    followPathRotationY += Float(translation.x) * sensitivity
                    // Camera stays level - no vertical rotation
                    cameraOrbitNode?.eulerAngles = SCNVector3(0, followPathRotationY, 0)
                }
                // Right-click (pan) is ignored in follow path mode
            } else {
                // Orbit mode: full controls
                if isRightClick {
                    // Right-drag: pan the view
                    let panSpeed = CGFloat(currentDistance) * 0.001
                    let dx = translation.x * panSpeed
                    let dy = translation.y * panSpeed

                    if let orbitNode = cameraOrbitNode {
                        let right = orbitNode.worldRight
                        let up = orbitNode.worldUp

                        orbitNode.position.x -= CGFloat(right.x) * dx - CGFloat(up.x) * dy
                        orbitNode.position.y -= CGFloat(right.y) * dx - CGFloat(up.y) * dy
                        orbitNode.position.z -= CGFloat(right.z) * dx - CGFloat(up.z) * dy
                    }
                } else {
                    // Left-drag: orbit rotation
                    let sensitivity: Float = 0.005
                    currentRotationY += Float(translation.x) * sensitivity
                    currentRotationX += Float(translation.y) * sensitivity

                    currentRotationX = max(-Float.pi / 2 + 0.1, min(Float.pi / 2 - 0.1, currentRotationX))

                    cameraOrbitNode?.eulerAngles = SCNVector3(currentRotationX, currentRotationY, 0)
                }
            }

            gesture.setTranslation(.zero, in: gesture.view)
        }

        @objc func handleMagnify(_ gesture: NSMagnificationGestureRecognizer) {
            let scale = 1.0 - Float(gesture.magnification)

            if cameraMode == .followPath {
                followPathDistance *= scale
                followPathDistance = max(20, min(followPathDistance, 500))
                cameraNode?.position.z = CGFloat(followPathDistance)
            } else {
                currentDistance *= scale
                currentDistance = max(50, min(currentDistance, initialDistance * 5))
                cameraNode?.position.z = CGFloat(currentDistance)
            }
            gesture.magnification = 0
        }
    }
}

// MARK: - Custom SCNView Subclass to Handle Scroll Wheel

class TrajectoryScrollView: SCNView {
    var coordinator: TrajectorySceneView.Coordinator?

    override func scrollWheel(with event: NSEvent) {
        guard let coordinator = coordinator else { return }

        let zoomSpeed: Float = 0.05
        let delta = Float(event.scrollingDeltaY) * zoomSpeed

        if coordinator.cameraMode == .followPath {
            coordinator.followPathDistance *= (1 - delta)
            coordinator.followPathDistance = max(20, min(coordinator.followPathDistance, 500))
            coordinator.cameraNode?.position.z = CGFloat(coordinator.followPathDistance)
        } else {
            coordinator.currentDistance *= (1 - delta)
            coordinator.currentDistance = max(50, min(coordinator.currentDistance, coordinator.initialDistance * 5))
            coordinator.cameraNode?.position.z = CGFloat(coordinator.currentDistance)
        }
    }
}

#endif
