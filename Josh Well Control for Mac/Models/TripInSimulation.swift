//
//  TripInSimulation.swift
//  Josh Well Control for Mac
//
//  Simulates running pipe (casing/liner) INTO a well after stripping out.
//  Tracks fill volume, displacement returns, ESD at control depth, and required choke pressure.
//  Supports floated casing with air in lower section.
//

import Foundation
import SwiftData

/// Represents a trip-in simulation for running casing/pipe into the well.
/// Can import initial pocket state from a saved trip-out simulation.
@Model
final class TripInSimulation {
    var id: UUID = UUID()

    /// Descriptive name (e.g., "Run 7\" Liner - Floated")
    var name: String = ""

    /// Timestamp when created
    var createdAt: Date = Date.now

    /// Timestamp when last modified
    var updatedAt: Date = Date.now

    // MARK: - Source Trip Simulation

    /// UUID of the source trip-out simulation we're importing pocket state from
    var sourceSimulationID: UUID?

    /// Name of source simulation (snapshot at creation)
    var sourceSimulationName: String = ""

    /// Snapshot of initial pocket layers (JSON encoded)
    var initialPocketLayersData: Data?

    // MARK: - Depth Inputs

    /// Starting bit depth (MD in meters) - typically at surface (0)
    var startBitMD_m: Double = 0

    /// Ending bit depth (MD in meters) - typically TD or target depth
    var endBitMD_m: Double = 0

    /// Casing shoe depth (MD in meters) for control point
    var controlMD_m: Double = 0

    /// Depth step for calculations (meters)
    var step_m: Double = 100

    // MARK: - Drill String Configuration

    /// Name/description of the string being run (e.g., "7\" Liner", "9-5/8\" Casing")
    var stringName: String = ""

    /// Pipe outer diameter (meters)
    var pipeOD_m: Double = 0.1778  // 7" default

    /// Pipe inner diameter (meters)
    var pipeID_m: Double = 0.1572  // 6.184"

    /// Pipe weight (kg/m) for displacement calculation
    var pipeWeight_kgm: Double = 35.7

    // MARK: - Floated Casing Configuration

    /// Whether this is a floated casing run (air in lower section)
    var isFloatedCasing: Bool = false

    /// Depth where float sub is installed (MD in meters)
    /// Below this point, casing contains air (not mud)
    var floatSubMD_m: Double = 0

    /// Float valve crack pressure differential (kPa) - when float opens
    var crackFloat_kPa: Double = 2100

    // MARK: - Fluid Inputs

    /// UUID of the fill mud used (for retrieving color on load)
    var fillMudID: UUID?

    /// Active mud density used to fill pipe (kg/m³)
    var activeMudDensity_kgpm3: Double = 1200

    /// Target ESD at control depth (kg/m³) - alert if below this
    var targetESD_kgpm3: Double = 1200

    /// Base mud density in annulus at start (kg/m³)
    var baseMudDensity_kgpm3: Double = 1200

    // MARK: - Computed Results Summary

    /// Total fill volume pumped to fill pipe (m³)
    var totalFillVolume_m3: Double = 0

    /// Total displacement returns received (m³)
    var totalDisplacementReturns_m3: Double = 0

    /// Maximum choke pressure required (kPa)
    var maxChokePressure_kPa: Double = 0

    /// Minimum ESD at control depth (kg/m³)
    var minESDAtControl_kgpm3: Double = 0

    /// Maximum ESD at control depth (kg/m³)
    var maxESDAtControl_kgpm3: Double = 0

    /// Maximum differential pressure at casing bottom for floated casing (kPa)
    var maxDifferentialPressure_kPa: Double = 0

    /// Depth where ESD first drops below target (m), or nil if never
    var depthBelowTarget_m: Double?

    // MARK: - Relationships

    /// Steps for this simulation
    @Relationship(deleteRule: .cascade, inverse: \TripInSimulationStep.simulation)
    var steps: [TripInSimulationStep]?

    /// Back-reference to the owning project
    @Relationship(deleteRule: .nullify)
    var project: ProjectState?

    // MARK: - Computed Properties

    /// Sorted steps by depth (shallowest first for trip-in)
    @Transient var sortedSteps: [TripInSimulationStep] {
        (steps ?? []).sorted { $0.stepIndex < $1.stepIndex }
    }

    /// Number of steps
    @Transient var stepCount: Int {
        steps?.count ?? 0
    }

    /// Trip length (meters)
    @Transient var tripLength_m: Double {
        abs(endBitMD_m - startBitMD_m)
    }

    /// Pipe capacity per meter (m³/m)
    @Transient var pipeCapacity_m3pm: Double {
        .pi / 4.0 * pipeID_m * pipeID_m
    }

    /// Pipe displacement per meter (m³/m) - steel volume
    @Transient var pipeDisplacement_m3pm: Double {
        .pi / 4.0 * (pipeOD_m * pipeOD_m - pipeID_m * pipeID_m)
    }

    /// Decoded initial pocket layers
    @Transient var initialPocketLayers: [TripLayerSnapshot] {
        get {
            guard let data = initialPocketLayersData else { return [] }
            return (try? JSONDecoder().decode([TripLayerSnapshot].self, from: data)) ?? []
        }
        set {
            initialPocketLayersData = try? JSONEncoder().encode(newValue)
        }
    }

    // MARK: - Initializer

    init(
        name: String = "",
        sourceSimulationID: UUID? = nil,
        sourceSimulationName: String = "",
        startBitMD_m: Double = 0,
        endBitMD_m: Double = 0,
        controlMD_m: Double = 0,
        step_m: Double = 100,
        stringName: String = "",
        pipeOD_m: Double = 0.1778,
        pipeID_m: Double = 0.1572,
        pipeWeight_kgm: Double = 35.7,
        isFloatedCasing: Bool = false,
        floatSubMD_m: Double = 0,
        crackFloat_kPa: Double = 2100,
        fillMudID: UUID? = nil,
        activeMudDensity_kgpm3: Double = 1200,
        targetESD_kgpm3: Double = 1200,
        baseMudDensity_kgpm3: Double = 1200,
        project: ProjectState? = nil
    ) {
        self.name = name
        self.sourceSimulationID = sourceSimulationID
        self.sourceSimulationName = sourceSimulationName
        self.startBitMD_m = startBitMD_m
        self.endBitMD_m = endBitMD_m
        self.controlMD_m = controlMD_m
        self.step_m = step_m
        self.stringName = stringName
        self.pipeOD_m = pipeOD_m
        self.pipeID_m = pipeID_m
        self.pipeWeight_kgm = pipeWeight_kgm
        self.isFloatedCasing = isFloatedCasing
        self.floatSubMD_m = floatSubMD_m
        self.crackFloat_kPa = crackFloat_kPa
        self.fillMudID = fillMudID
        self.activeMudDensity_kgpm3 = activeMudDensity_kgpm3
        self.targetESD_kgpm3 = targetESD_kgpm3
        self.baseMudDensity_kgpm3 = baseMudDensity_kgpm3
        self.project = project
    }

    // MARK: - Step Management

    /// Add a step to this simulation
    func addStep(_ step: TripInSimulationStep) {
        if steps == nil { steps = [] }
        step.simulation = self
        steps?.append(step)
    }

    /// Update summary results from steps
    func updateSummaryResults() {
        guard let allSteps = steps, !allSteps.isEmpty else { return }

        if let lastStep = allSteps.max(by: { $0.stepIndex < $1.stepIndex }) {
            totalFillVolume_m3 = lastStep.cumulativeFillVolume_m3
            totalDisplacementReturns_m3 = lastStep.cumulativeDisplacementReturns_m3
        }

        maxChokePressure_kPa = allSteps.map { $0.requiredChokePressure_kPa }.max() ?? 0
        minESDAtControl_kgpm3 = allSteps.map { $0.ESDAtControl_kgpm3 }.min() ?? 0
        maxESDAtControl_kgpm3 = allSteps.map { $0.ESDAtControl_kgpm3 }.max() ?? 0
        maxDifferentialPressure_kPa = allSteps.map { $0.differentialPressureAtBottom_kPa }.max() ?? 0

        // Find first depth where ESD drops below target
        if let firstBelow = allSteps.sorted(by: { $0.stepIndex < $1.stepIndex })
            .first(where: { $0.ESDAtControl_kgpm3 < targetESD_kgpm3 }) {
            depthBelowTarget_m = firstBelow.bitMD_m
        } else {
            depthBelowTarget_m = nil
        }

        updatedAt = .now
    }

    /// Import pocket state from a trip-out simulation
    func importPocketsFrom(simulation: TripSimulation) {
        sourceSimulationID = simulation.id
        sourceSimulationName = simulation.name

        // Get the final step (deepest pulled out = shallowest bit = last step)
        if let finalStep = simulation.sortedSteps.last {
            initialPocketLayers = finalStep.layersPocket
        }

        // Copy relevant parameters
        controlMD_m = simulation.shoeMD_m
        baseMudDensity_kgpm3 = simulation.baseMudDensity_kgpm3
        targetESD_kgpm3 = simulation.targetESDAtTD_kgpm3
    }
}

// MARK: - Export Dictionary

extension TripInSimulation {
    var exportDictionary: [String: Any] {
        [
            "id": id.uuidString,
            "name": name,
            "createdAt": ISO8601DateFormatter().string(from: createdAt),
            "updatedAt": ISO8601DateFormatter().string(from: updatedAt),
            // Source
            "sourceSimulationID": sourceSimulationID?.uuidString ?? "",
            "sourceSimulationName": sourceSimulationName,
            // Inputs
            "startBitMD_m": startBitMD_m,
            "endBitMD_m": endBitMD_m,
            "controlMD_m": controlMD_m,
            "step_m": step_m,
            "stringName": stringName,
            "pipeOD_m": pipeOD_m,
            "pipeID_m": pipeID_m,
            "pipeWeight_kgm": pipeWeight_kgm,
            "isFloatedCasing": isFloatedCasing,
            "floatSubMD_m": floatSubMD_m,
            "crackFloat_kPa": crackFloat_kPa,
            "activeMudDensity_kgpm3": activeMudDensity_kgpm3,
            "targetESD_kgpm3": targetESD_kgpm3,
            "baseMudDensity_kgpm3": baseMudDensity_kgpm3,
            // Summary results
            "totalFillVolume_m3": totalFillVolume_m3,
            "totalDisplacementReturns_m3": totalDisplacementReturns_m3,
            "maxChokePressure_kPa": maxChokePressure_kPa,
            "minESDAtControl_kgpm3": minESDAtControl_kgpm3,
            "maxESDAtControl_kgpm3": maxESDAtControl_kgpm3,
            "maxDifferentialPressure_kPa": maxDifferentialPressure_kPa,
            "depthBelowTarget_m": depthBelowTarget_m as Any,
            // Steps
            "steps": sortedSteps.map { $0.exportDictionary }
        ]
    }
}
