//
//  TripTrack.swift
//  Josh Well Control for Mac
//
//  Process-based trip tracking for live well operations.
//

import Foundation
import SwiftData

/// Represents a manual trip tracking session where operators input observed values step-by-step.
/// Unlike TripSimulation (which auto-runs), this tracks real-world operations as they happen.
@Model
final class TripTrack {
    var id: UUID = UUID()

    /// Descriptive name for this tracking session
    var name: String = ""

    /// Timestamp when this tracking session was started
    var createdAt: Date = Date.now

    /// Timestamp when this session was last modified
    var updatedAt: Date = Date.now

    // MARK: - Source Configuration

    /// Source type: 0 = fresh from project, 1 = loaded from simulation
    var sourceTypeRaw: Int = SourceType.fresh.rawValue

    /// ID of source TripSimulation (if loaded from simulation)
    var sourceTripSimulationID: UUID?

    // MARK: - Initial Configuration

    /// Starting bit depth when tracking began (MD in meters)
    var initialBitMD_m: Double = 0

    /// TD for ESD@TD calculations (MD in meters)
    var tdMD_m: Double = 0

    /// Casing shoe depth for control point (MD in meters)
    var shoeMD_m: Double = 0

    /// Target equivalent static density at TD (kg/m³)
    var targetESD_kgpm3: Double = 1080

    /// Float valve crack pressure differential (kPa)
    var crackFloat_kPa: Double = 2100

    /// Base mud density in annulus (kg/m³)
    var baseMudDensity_kgpm3: Double = 1080

    /// Default backfill mud density (kg/m³)
    var backfillDensity_kgpm3: Double = 1080

    // MARK: - Current State

    /// Current bit depth (MD in meters)
    var currentBitMD_m: Double = 0

    /// Current surface annular back pressure (kPa)
    var currentSABP_kPa: Double = 0

    // MARK: - Cumulative Totals

    /// Total backfill pumped (m³)
    var totalBackfill_m3: Double = 0

    /// Total pit gain (overflow at surface) (m³)
    var totalPitGain_m3: Double = 0

    /// Net surface tank delta (m³)
    var totalTankDelta_m3: Double = 0

    // MARK: - Current Layer State (JSON encoded)

    /// Current annulus layers encoded as JSON
    var layersAnnulusData: Data?

    /// Current string layers encoded as JSON
    var layersStringData: Data?

    /// Current pocket layers encoded as JSON
    var layersPocketData: Data?

    // MARK: - Relationships

    /// Locked steps for this tracking session
    @Relationship(deleteRule: .cascade, inverse: \TripTrackStep.tripTrack)
    var steps: [TripTrackStep]?

    /// Back-reference to the owning project
    @Relationship(deleteRule: .nullify)
    var project: ProjectState?

    /// Reference to the backfill mud used
    @Relationship(deleteRule: .nullify)
    var backfillMud: MudProperties?

    // MARK: - Source Type Enum

    enum SourceType: Int, Codable {
        case fresh = 0
        case simulation = 1
    }

    // MARK: - Computed Properties

    /// Source type as enum
    @Transient var sourceType: SourceType {
        get { SourceType(rawValue: sourceTypeRaw) ?? .fresh }
        set { sourceTypeRaw = newValue.rawValue }
    }

    /// Sorted steps by index
    @Transient var sortedSteps: [TripTrackStep] {
        (steps ?? []).sorted { $0.stepIndex < $1.stepIndex }
    }

    /// Number of locked steps
    @Transient var stepCount: Int {
        steps?.count ?? 0
    }

    /// Trip progress in meters (from initial to current)
    @Transient var tripProgress_m: Double {
        abs(initialBitMD_m - currentBitMD_m)
    }

    // MARK: - Layer Accessors

    /// Decoded current annulus layers
    @Transient var layersAnnulus: [TripLayerSnapshot] {
        get {
            guard let data = layersAnnulusData else { return [] }
            return (try? JSONDecoder().decode([TripLayerSnapshot].self, from: data)) ?? []
        }
        set {
            layersAnnulusData = try? JSONEncoder().encode(newValue)
        }
    }

    /// Decoded current string layers
    @Transient var layersString: [TripLayerSnapshot] {
        get {
            guard let data = layersStringData else { return [] }
            return (try? JSONDecoder().decode([TripLayerSnapshot].self, from: data)) ?? []
        }
        set {
            layersStringData = try? JSONEncoder().encode(newValue)
        }
    }

    /// Decoded current pocket layers
    @Transient var layersPocket: [TripLayerSnapshot] {
        get {
            guard let data = layersPocketData else { return [] }
            return (try? JSONDecoder().decode([TripLayerSnapshot].self, from: data)) ?? []
        }
        set {
            layersPocketData = try? JSONEncoder().encode(newValue)
        }
    }

    // MARK: - Initializer

    init(
        name: String = "",
        sourceType: SourceType = .fresh,
        sourceTripSimulationID: UUID? = nil,
        initialBitMD_m: Double = 0,
        tdMD_m: Double = 0,
        shoeMD_m: Double = 0,
        targetESD_kgpm3: Double = 1080,
        crackFloat_kPa: Double = 2100,
        baseMudDensity_kgpm3: Double = 1080,
        backfillDensity_kgpm3: Double = 1080,
        project: ProjectState? = nil,
        backfillMud: MudProperties? = nil
    ) {
        self.name = name
        self.sourceTypeRaw = sourceType.rawValue
        self.sourceTripSimulationID = sourceTripSimulationID
        self.initialBitMD_m = initialBitMD_m
        self.tdMD_m = tdMD_m
        self.shoeMD_m = shoeMD_m
        self.targetESD_kgpm3 = targetESD_kgpm3
        self.crackFloat_kPa = crackFloat_kPa
        self.baseMudDensity_kgpm3 = baseMudDensity_kgpm3
        self.backfillDensity_kgpm3 = backfillDensity_kgpm3
        self.currentBitMD_m = initialBitMD_m
        self.project = project
        self.backfillMud = backfillMud
    }

    // MARK: - Step Management

    /// Add a locked step to this tracking session
    func addStep(_ step: TripTrackStep) {
        if steps == nil { steps = [] }
        step.tripTrack = self
        steps?.append(step)

        // Update current state from step
        currentBitMD_m = step.bitMD_m
        currentSABP_kPa = step.observedSABP_kPa
        totalBackfill_m3 = step.cumulativeBackfill_m3
        totalTankDelta_m3 = step.cumulativeTankDelta_m3

        // Update layer state from step
        layersAnnulusData = step.layersAnnulusData
        layersStringData = step.layersStringData
        layersPocketData = step.layersPocketData

        updatedAt = .now
    }

    /// Remove the last step (undo)
    func removeLastStep() -> TripTrackStep? {
        guard let allSteps = steps, !allSteps.isEmpty else { return nil }

        let sorted = allSteps.sorted { $0.stepIndex < $1.stepIndex }
        guard let lastStep = sorted.last else { return nil }

        // Remove the step
        steps?.removeAll { $0.id == lastStep.id }

        // Restore state from previous step or initial
        if let previousStep = sorted.dropLast().last {
            currentBitMD_m = previousStep.bitMD_m
            currentSABP_kPa = previousStep.observedSABP_kPa
            totalBackfill_m3 = previousStep.cumulativeBackfill_m3
            totalTankDelta_m3 = previousStep.cumulativeTankDelta_m3
            layersAnnulusData = previousStep.layersAnnulusData
            layersStringData = previousStep.layersStringData
            layersPocketData = previousStep.layersPocketData
        } else {
            // No previous step - reset to initial state
            currentBitMD_m = initialBitMD_m
            currentSABP_kPa = 0
            totalBackfill_m3 = 0
            totalTankDelta_m3 = 0
            // Note: Initial layer state would need to be restored separately
        }

        updatedAt = .now
        return lastStep
    }
}

// MARK: - Export Dictionary

extension TripTrack {
    var exportDictionary: [String: Any] {
        [
            "id": id.uuidString,
            "name": name,
            "createdAt": ISO8601DateFormatter().string(from: createdAt),
            "updatedAt": ISO8601DateFormatter().string(from: updatedAt),
            "sourceType": sourceType == .fresh ? "fresh" : "simulation",
            "sourceTripSimulationID": sourceTripSimulationID?.uuidString as Any,
            // Configuration
            "initialBitMD_m": initialBitMD_m,
            "tdMD_m": tdMD_m,
            "shoeMD_m": shoeMD_m,
            "targetESD_kgpm3": targetESD_kgpm3,
            "crackFloat_kPa": crackFloat_kPa,
            "baseMudDensity_kgpm3": baseMudDensity_kgpm3,
            "backfillDensity_kgpm3": backfillDensity_kgpm3,
            // Current state
            "currentBitMD_m": currentBitMD_m,
            "currentSABP_kPa": currentSABP_kPa,
            // Cumulative
            "totalBackfill_m3": totalBackfill_m3,
            "totalPitGain_m3": totalPitGain_m3,
            "totalTankDelta_m3": totalTankDelta_m3,
            // Steps
            "steps": sortedSteps.map { $0.exportDictionary }
        ]
    }
}
