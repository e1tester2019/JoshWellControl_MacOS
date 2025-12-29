//
//  Trajectory3DView.swift
//  Josh Well Control for Mac
//
//  3D visualization of wellbore trajectory using SceneKit.
//

import SwiftUI
import SceneKit

#if os(macOS)

struct Trajectory3DView: View {
    let variances: [SurveyVariance]
    let plan: DirectionalPlan?
    let limits: DirectionalLimits
    @Binding var hoveredMD: Double?
    var onHover: (Double?) -> Void

    @State private var scene: SCNScene = SCNScene()
    @State private var cameraNode: SCNNode = SCNNode()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            hoverInfo
            SceneView(
                scene: scene,
                pointOfView: cameraNode,
                options: [.allowsCameraControl, .autoenablesDefaultLighting]
            )
            .frame(minHeight: 350)
            .onAppear {
                setupScene()
            }
            .onChange(of: variances.count) { _, _ in
                setupScene()
            }
            .onChange(of: plan?.stations?.count) { _, _ in
                setupScene()
            }
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
            Text("Drag to rotate • Scroll to zoom")
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
            legendItem(color: .green, label: "OK", isPoint: true)
            legendItem(color: .yellow, label: "Warning", isPoint: true)
            legendItem(color: .red, label: "Alarm", isPoint: true)
            Spacer()
        }
        .font(.caption)
    }

    private func legendItem(color: Color, label: String, isPoint: Bool = false) -> some View {
        HStack(spacing: 4) {
            if isPoint {
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

    // MARK: - Scene Setup

    private func setupScene() {
        scene = SCNScene()
        scene.background.contents = NSColor.windowBackgroundColor

        setupCamera()
        setupLighting()
        setupAxes()
        setupPlanTrajectory()
        setupActualTrajectory()
    }

    private func setupCamera() {
        cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.automaticallyAdjustsZRange = true

        // Calculate center of trajectory for camera positioning
        let allPoints = variances.map { ($0.surveyNS, $0.surveyEW, $0.surveyTVD) }
        let planPoints = (plan?.sortedStations ?? []).map { ($0.ns_m, $0.ew_m, $0.tvd) }
        let combined = allPoints + planPoints

        if !combined.isEmpty {
            let nsValues: [Double] = combined.map { $0.0 }
            let ewValues: [Double] = combined.map { $0.1 }
            let tvdValues: [Double] = combined.map { $0.2 }

            let avgNS: Double = nsValues.reduce(0, +) / Double(combined.count)
            let avgEW: Double = ewValues.reduce(0, +) / Double(combined.count)
            let avgTVD: Double = tvdValues.reduce(0, +) / Double(combined.count)

            let maxNSRange: Double = nsValues.map { abs($0 - avgNS) }.max() ?? 100
            let maxEWRange: Double = ewValues.map { abs($0 - avgEW) }.max() ?? 100
            let maxTVDRange: Double = tvdValues.map { abs($0 - avgTVD) }.max() ?? 100

            let maxDim: Double = max(max(maxNSRange, maxEWRange), maxTVDRange)
            let distance: Double = maxDim * 3

            cameraNode.position = SCNVector3(
                Float(avgEW + distance * 0.7),
                Float(-avgTVD + distance * 0.5),
                Float(avgNS + distance * 0.7)
            )
            cameraNode.look(at: SCNVector3(Float(avgEW), Float(-avgTVD), Float(avgNS)))
        } else {
            cameraNode.position = SCNVector3(500, 500, 500)
            cameraNode.look(at: SCNVector3(0, 0, 0))
        }

        scene.rootNode.addChildNode(cameraNode)
    }

    private func setupLighting() {
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

    private func setupAxes() {
        // Create axis lines and labels
        let axisLength: Float = 200

        // X axis (East) - Red
        addAxisLine(from: SCNVector3(0, 0, 0), to: SCNVector3(axisLength, 0, 0), color: .red)
        addAxisLabel("E", at: SCNVector3(axisLength + 20, 0, 0), color: .red)

        // Y axis (Up/Down - negative TVD) - Green
        addAxisLine(from: SCNVector3(0, 0, 0), to: SCNVector3(0, axisLength, 0), color: .green)
        addAxisLabel("Up", at: SCNVector3(0, axisLength + 20, 0), color: .green)

        // Z axis (North) - Blue
        addAxisLine(from: SCNVector3(0, 0, 0), to: SCNVector3(0, 0, axisLength), color: .blue)
        addAxisLabel("N", at: SCNVector3(0, 0, axisLength + 20), color: .blue)
    }

    private func addAxisLine(from: SCNVector3, to: SCNVector3, color: NSColor) {
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

    private func addAxisLabel(_ text: String, at position: SCNVector3, color: NSColor) {
        let textGeometry = SCNText(string: text, extrusionDepth: 1)
        textGeometry.font = NSFont.systemFont(ofSize: 12)
        textGeometry.firstMaterial?.diffuse.contents = color

        let textNode = SCNNode(geometry: textGeometry)
        textNode.position = position
        textNode.scale = SCNVector3(2, 2, 2)

        // Billboard constraint to always face camera
        let constraint = SCNBillboardConstraint()
        constraint.freeAxes = [.X, .Y, .Z]
        textNode.constraints = [constraint]

        scene.rootNode.addChildNode(textNode)
    }

    // MARK: - Trajectory Drawing

    private func setupPlanTrajectory() {
        let stations = plan?.sortedStations ?? []
        guard stations.count > 1 else { return }

        var vertices: [SCNVector3] = []
        var indices: [Int32] = []

        for (index, station) in stations.enumerated() {
            // Convert to scene coordinates (Y is up, so negate TVD)
            let point = SCNVector3(
                Float(station.ew_m),
                Float(-station.tvd),  // Negate TVD so depth goes down
                Float(station.ns_m)
            )
            vertices.append(point)

            if index > 0 {
                indices.append(Int32(index - 1))
                indices.append(Int32(index))
            }
        }

        // Create line geometry
        let source = SCNGeometrySource(vertices: vertices)
        let data = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
        let element = SCNGeometryElement(data: data, primitiveType: .line, primitiveCount: indices.count / 2, bytesPerIndex: MemoryLayout<Int32>.size)

        let geometry = SCNGeometry(sources: [source], elements: [element])
        geometry.firstMaterial?.diffuse.contents = NSColor.green
        geometry.firstMaterial?.lightingModel = .constant

        let lineNode = SCNNode(geometry: geometry)
        scene.rootNode.addChildNode(lineNode)
    }

    private func setupActualTrajectory() {
        guard variances.count > 1 else { return }

        // Draw line connecting survey points
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

            // Add sphere at each survey point (color-coded by status)
            let status = variance.status(for: limits)
            addSurveyPoint(at: point, status: status, md: variance.surveyMD)
        }

        // Create line geometry
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

    private func addSurveyPoint(at position: SCNVector3, status: VarianceStatus, md: Double) {
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
}

#endif
