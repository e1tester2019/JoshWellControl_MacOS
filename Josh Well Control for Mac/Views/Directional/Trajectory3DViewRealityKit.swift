//
//  Trajectory3DViewRealityKit.swift
//  Josh Well Control for Mac
//
//  3D visualization of wellbore trajectory using RealityKit.
//  Alternative to SceneKit version for comparison.
//

import SwiftUI
import RealityKit

#if os(macOS)

struct Trajectory3DViewRealityKit: View {
    let variances: [SurveyVariance]
    let plan: DirectionalPlan?
    let limits: DirectionalLimits
    let bitProjection: BitProjection?
    @Binding var hoveredMD: Double?
    var onHover: (Double?) -> Void

    @State private var resetTrigger: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            hoverInfo
            TrajectoryRealityView(
                variances: variances,
                plan: plan,
                limits: limits,
                bitProjection: bitProjection,
                resetTrigger: resetTrigger
            )
            .frame(minHeight: 350)
            legend
        }
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

            Button {
                resetTrigger.toggle()
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .help("Reset camera")

            HStack(spacing: 8) {
                Image(systemName: "cube.transparent")
                    .foregroundStyle(.blue)
                Text("RealityKit")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.blue)
            }

            Text("Left-drag: rotate • Right-drag: pan • Scroll: zoom")
                .font(.caption2)
                .foregroundStyle(.secondary)
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

// MARK: - RealityKit View with Custom Camera Controls

struct TrajectoryRealityView: NSViewRepresentable {
    let variances: [SurveyVariance]
    let plan: DirectionalPlan?
    let limits: DirectionalLimits
    let bitProjection: BitProjection?
    let resetTrigger: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> RealityKitTrajectoryView {
        let arView = RealityKitTrajectoryView(frame: .zero)
        arView.coordinator = context.coordinator
        context.coordinator.arView = arView

        // Configure for non-AR rendering
        arView.environment.background = .color(.init(red: 0.15, green: 0.15, blue: 0.17, alpha: 1.0))

        // Setup content
        setupContent(in: arView, coordinator: context.coordinator)

        return arView
    }

    func updateNSView(_ arView: RealityKitTrajectoryView, context: Context) {
        // Clear and rebuild
        arView.scene.anchors.removeAll()
        setupContent(in: arView, coordinator: context.coordinator)

        // Handle reset
        if context.coordinator.lastResetTrigger != resetTrigger {
            context.coordinator.lastResetTrigger = resetTrigger
            context.coordinator.resetCamera()
        }
    }

    private func setupContent(in arView: ARView, coordinator: Coordinator) {
        let anchor = AnchorEntity(world: .zero)

        // Calculate scale and center
        let (center, scaleFactor) = calculateCenterAndScale()
        coordinator.center = center
        coordinator.scaleFactor = scaleFactor

        // Add content
        addPlanTrajectory(to: anchor, scale: scaleFactor, center: center)
        addActualTrajectory(to: anchor, scale: scaleFactor, center: center)
        addBitProjection(to: anchor, scale: scaleFactor, center: center)
        addAxes(to: anchor)

        arView.scene.addAnchor(anchor)

        // Setup initial camera if not already set
        if !coordinator.cameraInitialized {
            coordinator.setupInitialCamera(in: arView, center: center, scaleFactor: scaleFactor)
        }
    }

    private func calculateCenterAndScale() -> (SIMD3<Float>, Float) {
        var allPoints: [(ns: Double, ew: Double, tvd: Double)] = []

        for v in variances {
            allPoints.append((v.surveyNS, v.surveyEW, v.surveyTVD))
        }

        for station in plan?.sortedStations ?? [] {
            allPoints.append((station.ns_m, station.ew_m, station.tvd))
        }

        if let bit = bitProjection {
            allPoints.append((bit.bitNS, bit.bitEW, bit.bitTVD))
        }

        guard !allPoints.isEmpty else {
            return (SIMD3<Float>(0, 0, 0), 0.01)
        }

        let nsValues = allPoints.map { $0.ns }
        let ewValues = allPoints.map { $0.ew }
        let tvdValues = allPoints.map { $0.tvd }

        let avgNS = nsValues.reduce(0, +) / Double(allPoints.count)
        let avgEW = ewValues.reduce(0, +) / Double(allPoints.count)
        let avgTVD = tvdValues.reduce(0, +) / Double(allPoints.count)

        let nsRange = (nsValues.max() ?? 0) - (nsValues.min() ?? 0)
        let ewRange = (ewValues.max() ?? 0) - (ewValues.min() ?? 0)
        let tvdRange = (tvdValues.max() ?? 0) - (tvdValues.min() ?? 0)

        let maxRange = max(max(nsRange, ewRange), tvdRange)
        let scaleFactor: Float = maxRange > 0 ? Float(2.0 / maxRange) : 0.01

        let center = SIMD3<Float>(Float(avgEW), Float(-avgTVD), Float(avgNS))
        return (center, scaleFactor)
    }

    private func addPlanTrajectory(to anchor: AnchorEntity, scale: Float, center: SIMD3<Float>) {
        let stations = plan?.sortedStations ?? []
        guard stations.count > 1 else { return }

        for i in 0..<(stations.count - 1) {
            let start = stations[i]
            let end = stations[i + 1]

            let startPos = SIMD3<Float>(
                (Float(start.ew_m) - center.x / scale) * scale,
                (Float(-start.tvd) - center.y / scale) * scale,
                (Float(start.ns_m) - center.z / scale) * scale
            )
            let endPos = SIMD3<Float>(
                (Float(end.ew_m) - center.x / scale) * scale,
                (Float(-end.tvd) - center.y / scale) * scale,
                (Float(end.ns_m) - center.z / scale) * scale
            )

            addLine(from: startPos, to: endPos, color: .green, thickness: 0.008, to: anchor)
        }
    }

    private func addActualTrajectory(to anchor: AnchorEntity, scale: Float, center: SIMD3<Float>) {
        guard variances.count > 0 else { return }

        for i in 0..<variances.count {
            let v = variances[i]

            let pos = SIMD3<Float>(
                (Float(v.surveyEW) - center.x / scale) * scale,
                (Float(-v.surveyTVD) - center.y / scale) * scale,
                (Float(v.surveyNS) - center.z / scale) * scale
            )

            // Line to previous
            if i > 0 {
                let prev = variances[i - 1]
                let prevPos = SIMD3<Float>(
                    (Float(prev.surveyEW) - center.x / scale) * scale,
                    (Float(-prev.surveyTVD) - center.y / scale) * scale,
                    (Float(prev.surveyNS) - center.z / scale) * scale
                )
                addLine(from: prevPos, to: pos, color: .blue, thickness: 0.008, to: anchor)
            }

            // Survey point
            let status = v.status(for: limits)
            let color: NSColor
            switch status {
            case .ok: color = .green
            case .warning: color = .yellow
            case .alarm: color = .red
            }

            let sphere = MeshResource.generateSphere(radius: 0.03)
            var material = SimpleMaterial()
            material.color = .init(tint: color)
            let sphereEntity = ModelEntity(mesh: sphere, materials: [material])
            sphereEntity.position = pos
            anchor.addChild(sphereEntity)
        }
    }

    private func addBitProjection(to anchor: AnchorEntity, scale: Float, center: SIMD3<Float>) {
        guard let bit = bitProjection, let lastVariance = variances.last else { return }

        let lastPos = SIMD3<Float>(
            (Float(lastVariance.surveyEW) - center.x / scale) * scale,
            (Float(-lastVariance.surveyTVD) - center.y / scale) * scale,
            (Float(lastVariance.surveyNS) - center.z / scale) * scale
        )

        let bitPos = SIMD3<Float>(
            (Float(bit.bitEW) - center.x / scale) * scale,
            (Float(-bit.bitTVD) - center.y / scale) * scale,
            (Float(bit.bitNS) - center.z / scale) * scale
        )

        // Dashed line
        addDashedLine(from: lastPos, to: bitPos, color: .orange, thickness: 0.006, to: anchor)

        // Bit marker (diamond)
        let bitStatus = bit.status(for: limits)
        let bitColor: NSColor
        switch bitStatus {
        case .ok: bitColor = .orange
        case .warning: bitColor = .yellow
        case .alarm: bitColor = .red
        }

        let box = MeshResource.generateBox(size: 0.06)
        var bitMaterial = SimpleMaterial()
        bitMaterial.color = .init(tint: bitColor)
        let bitEntity = ModelEntity(mesh: box, materials: [bitMaterial])
        bitEntity.position = bitPos
        bitEntity.orientation = simd_quatf(angle: .pi / 4, axis: [1, 0, 0]) * simd_quatf(angle: .pi / 4, axis: [0, 1, 0])
        anchor.addChild(bitEntity)

        // Plan position
        let planPos = SIMD3<Float>(
            (Float(bit.planEW) - center.x / scale) * scale,
            (Float(-bit.planTVD) - center.y / scale) * scale,
            (Float(bit.planNS) - center.z / scale) * scale
        )
        let planSphere = MeshResource.generateSphere(radius: 0.025)
        var planMaterial = SimpleMaterial()
        planMaterial.color = .init(tint: NSColor.green.withAlphaComponent(0.7))
        let planEntity = ModelEntity(mesh: planSphere, materials: [planMaterial])
        planEntity.position = planPos
        anchor.addChild(planEntity)
    }

    private func addLine(from start: SIMD3<Float>, to end: SIMD3<Float>, color: NSColor, thickness: Float, to anchor: AnchorEntity) {
        let direction = end - start
        let length = simd_length(direction)
        guard length > 0 else { return }

        let mesh = MeshResource.generateBox(width: thickness, height: thickness, depth: length)
        var material = SimpleMaterial()
        material.color = .init(tint: color)

        let lineEntity = ModelEntity(mesh: mesh, materials: [material])

        let midpoint = (start + end) / 2
        lineEntity.position = midpoint

        let up = SIMD3<Float>(0, 0, 1)
        let normalizedDir = simd_normalize(direction)
        let rotationAxis = simd_cross(up, normalizedDir)
        let rotationAngle = acos(simd_clamp(simd_dot(up, normalizedDir), -1, 1))

        if simd_length(rotationAxis) > 0.001 {
            lineEntity.orientation = simd_quatf(angle: rotationAngle, axis: simd_normalize(rotationAxis))
        }

        anchor.addChild(lineEntity)
    }

    private func addDashedLine(from start: SIMD3<Float>, to end: SIMD3<Float>, color: NSColor, thickness: Float, to anchor: AnchorEntity) {
        let direction = end - start
        let length = simd_length(direction)
        guard length > 0 else { return }

        let normalizedDir = simd_normalize(direction)
        let dashLength: Float = 0.05
        let gapLength: Float = 0.05

        var currentLength: Float = 0
        var isDash = true

        while currentLength < length {
            let segmentLength = min(isDash ? dashLength : gapLength, length - currentLength)

            if isDash {
                let segmentStart = start + normalizedDir * currentLength
                let segmentEnd = start + normalizedDir * (currentLength + segmentLength)
                addLine(from: segmentStart, to: segmentEnd, color: color, thickness: thickness, to: anchor)
            }

            currentLength += segmentLength
            isDash.toggle()
        }
    }

    private func addAxes(to anchor: AnchorEntity) {
        let axisLength: Float = 0.8
        let thickness: Float = 0.004

        addLine(from: .zero, to: SIMD3<Float>(axisLength, 0, 0), color: .red, thickness: thickness, to: anchor)
        addLine(from: .zero, to: SIMD3<Float>(0, axisLength, 0), color: .green, thickness: thickness, to: anchor)
        addLine(from: .zero, to: SIMD3<Float>(0, 0, axisLength), color: .blue, thickness: thickness, to: anchor)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject {
        weak var arView: ARView?
        var cameraAnchor: AnchorEntity?
        var cameraEntity: PerspectiveCamera?
        var center: SIMD3<Float> = .zero
        var scaleFactor: Float = 0.01
        var cameraInitialized = false
        var lastResetTrigger = false

        // Camera state
        var cameraDistance: Float = 5.0
        var cameraRotationX: Float = -Float.pi / 6
        var cameraRotationY: Float = Float.pi / 4
        var cameraPanX: Float = 0
        var cameraPanY: Float = 0

        func setupInitialCamera(in arView: ARView, center: SIMD3<Float>, scaleFactor: Float) {
            // Remove old camera if exists
            cameraAnchor?.removeFromParent()

            cameraDistance = 5.0
            cameraRotationX = -Float.pi / 6
            cameraRotationY = Float.pi / 4
            cameraPanX = 0
            cameraPanY = 0

            // Create camera
            let camera = PerspectiveCamera()
            let anchor = AnchorEntity(world: .zero)
            anchor.addChild(camera)
            arView.scene.addAnchor(anchor)

            cameraEntity = camera
            cameraAnchor = anchor
            cameraInitialized = true

            updateCamera()
        }

        func resetCamera() {
            cameraDistance = 5.0
            cameraRotationX = -Float.pi / 6
            cameraRotationY = Float.pi / 4
            cameraPanX = 0
            cameraPanY = 0
            updateCamera()
        }

        func updateCamera() {
            guard let camera = cameraEntity else { return }

            // Calculate camera position based on orbit
            let x = cameraDistance * cos(cameraRotationX) * sin(cameraRotationY) + cameraPanX
            let y = cameraDistance * sin(cameraRotationX) + cameraPanY
            let z = cameraDistance * cos(cameraRotationX) * cos(cameraRotationY)

            let cameraPosition = SIMD3<Float>(x, y, z)
            let lookAtPoint = SIMD3<Float>(cameraPanX, cameraPanY, 0)

            // Look at target
            camera.look(at: lookAtPoint, from: cameraPosition, relativeTo: nil)
        }

        func handlePan(translation: CGPoint, isRightClick: Bool) {
            if isRightClick {
                // Pan
                let panSpeed: Float = cameraDistance * 0.002
                cameraPanX -= Float(translation.x) * panSpeed
                cameraPanY += Float(translation.y) * panSpeed
            } else {
                // Rotate
                let sensitivity: Float = 0.005
                cameraRotationY += Float(translation.x) * sensitivity
                cameraRotationX += Float(translation.y) * sensitivity
                cameraRotationX = max(-Float.pi / 2 + 0.1, min(Float.pi / 2 - 0.1, cameraRotationX))
            }
            updateCamera()
        }

        func handleZoom(delta: Float) {
            cameraDistance *= (1 - delta * 0.1)
            cameraDistance = max(1, min(cameraDistance, 20))
            updateCamera()
        }
    }
}

// MARK: - Custom ARView with Mouse Handling

class RealityKitTrajectoryView: ARView {
    var coordinator: TrajectoryRealityView.Coordinator?

    override func scrollWheel(with event: NSEvent) {
        coordinator?.handleZoom(delta: Float(event.scrollingDeltaY) * 0.05)
    }

    override func mouseDragged(with event: NSEvent) {
        let translation = CGPoint(x: event.deltaX, y: event.deltaY)
        let isRightClick = event.buttonNumber == 1
        coordinator?.handlePan(translation: translation, isRightClick: isRightClick)
    }

    override func rightMouseDragged(with event: NSEvent) {
        let translation = CGPoint(x: event.deltaX, y: event.deltaY)
        coordinator?.handlePan(translation: translation, isRightClick: true)
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

#endif
