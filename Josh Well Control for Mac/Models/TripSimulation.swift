//
//  TripSimulation.swift
//  Josh Well Control for Mac
//
//  Created for persisting trip simulation results.
//

import Foundation
import SwiftData

/// Represents a saved trip simulation with all inputs and computed results.
/// Used for storing and replaying trip-out simulations with slug displacement tracking.
@Model
final class TripSimulation {
    var id: UUID = UUID()

    /// Descriptive name for this simulation (e.g., "Trip Out - Heavy Slug")
    var name: String = ""

    /// Timestamp when this simulation was created
    var createdAt: Date = Date.now

    /// Timestamp when this simulation was last modified
    var updatedAt: Date = Date.now

    // MARK: - Depth Inputs

    /// Starting bit depth (MD in meters) - typically TD
    var startBitMD_m: Double = 0

    /// Ending bit depth (MD in meters) - typically surface
    var endMD_m: Double = 0

    /// Casing shoe depth (MD in meters) for control point
    var shoeMD_m: Double = 0

    /// Depth interval for recording results (meters)
    var step_m: Double = 100

    // MARK: - Fluid Inputs

    /// Base mud density in annulus (kg/m³)
    var baseMudDensity_kgpm3: Double = 1080

    /// Backfill mud density from surface (kg/m³)
    var backfillDensity_kgpm3: Double = 1080

    /// Target equivalent static density at TD (kg/m³)
    var targetESDAtTD_kgpm3: Double = 1080

    // MARK: - Pressure Inputs

    /// Float valve crack pressure differential (kPa)
    var crackFloat_kPa: Double = 2100

    /// Initial surface annular back pressure (kPa)
    var initialSABP_kPa: Double = 0

    /// Hold SABP open (no back pressure control)
    var holdSABPOpen: Bool = false

    // MARK: - Swab Inputs

    /// Trip speed (m/s)
    var tripSpeed_m_per_s: Double = 0.167

    /// Eccentricity factor (1.0 = concentric, >1.0 = eccentric)
    var eccentricityFactor: Double = 1.2

    /// Fallback rheology theta600 if muds don't have dial readings
    var fallbackTheta600: Double?

    /// Fallback rheology theta300 if muds don't have dial readings
    var fallbackTheta300: Double?

    // MARK: - Pit Gain Calibration

    /// Use observed pit gain instead of calculated
    var useObservedPitGain: Bool = false

    /// Observed initial pit gain from field (m³)
    var observedInitialPitGain_m3: Double = 0

    /// Calculated initial pit gain for comparison (m³)
    var calculatedInitialPitGain_m3: Double = 0

    // MARK: - Summary Results

    /// Maximum SABP during trip (kPa)
    var maxSABP_kPa: Double = 0

    /// Maximum ESD at TD during trip (kg/m³)
    var maxESD_kgpm3: Double = 0

    /// Minimum ESD at TD during trip (kg/m³)
    var minESD_kgpm3: Double = 0

    /// Total backfill pumped (m³)
    var totalBackfill_m3: Double = 0

    /// Total pit gain (overflow at surface) (m³)
    var totalPitGain_m3: Double = 0

    /// Final surface tank delta (m³)
    var finalTankDelta_m3: Double = 0

    // MARK: - Relationships

    /// Steps for this simulation
    @Relationship(deleteRule: .cascade, inverse: \TripSimulationStep.simulation)
    var steps: [TripSimulationStep]?

    /// Back-reference to the owning project
    @Relationship(deleteRule: .nullify)
    var project: ProjectState?

    /// Reference to the backfill mud used
    @Relationship(deleteRule: .nullify)
    var backfillMud: MudProperties?

    // MARK: - Computed Properties

    /// Sorted steps by depth (deepest first)
    @Transient var sortedSteps: [TripSimulationStep] {
        (steps ?? []).sorted { $0.stepIndex < $1.stepIndex }
    }

    /// Number of steps in this simulation
    @Transient var stepCount: Int {
        steps?.count ?? 0
    }

    /// Trip length in meters
    @Transient var tripLength_m: Double {
        abs(startBitMD_m - endMD_m)
    }

    // MARK: - Initializer

    init(
        name: String = "",
        startBitMD_m: Double = 0,
        endMD_m: Double = 0,
        shoeMD_m: Double = 0,
        step_m: Double = 100,
        baseMudDensity_kgpm3: Double = 1080,
        backfillDensity_kgpm3: Double = 1080,
        targetESDAtTD_kgpm3: Double = 1080,
        crackFloat_kPa: Double = 2100,
        initialSABP_kPa: Double = 0,
        holdSABPOpen: Bool = false,
        tripSpeed_m_per_s: Double = 0.167,
        eccentricityFactor: Double = 1.2,
        fallbackTheta600: Double? = nil,
        fallbackTheta300: Double? = nil,
        useObservedPitGain: Bool = false,
        observedInitialPitGain_m3: Double = 0,
        project: ProjectState? = nil,
        backfillMud: MudProperties? = nil
    ) {
        self.name = name
        self.startBitMD_m = startBitMD_m
        self.endMD_m = endMD_m
        self.shoeMD_m = shoeMD_m
        self.step_m = step_m
        self.baseMudDensity_kgpm3 = baseMudDensity_kgpm3
        self.backfillDensity_kgpm3 = backfillDensity_kgpm3
        self.targetESDAtTD_kgpm3 = targetESDAtTD_kgpm3
        self.crackFloat_kPa = crackFloat_kPa
        self.initialSABP_kPa = initialSABP_kPa
        self.holdSABPOpen = holdSABPOpen
        self.tripSpeed_m_per_s = tripSpeed_m_per_s
        self.eccentricityFactor = eccentricityFactor
        self.fallbackTheta600 = fallbackTheta600
        self.fallbackTheta300 = fallbackTheta300
        self.useObservedPitGain = useObservedPitGain
        self.observedInitialPitGain_m3 = observedInitialPitGain_m3
        self.project = project
        self.backfillMud = backfillMud
    }

    // MARK: - Step Management

    /// Add a step to this simulation
    func addStep(_ step: TripSimulationStep) {
        if steps == nil { steps = [] }
        step.simulation = self
        steps?.append(step)
    }

    /// Update summary results from steps
    func updateSummaryResults() {
        guard let allSteps = steps, !allSteps.isEmpty else { return }

        maxSABP_kPa = allSteps.map { $0.SABP_kPa }.max() ?? 0
        maxESD_kgpm3 = allSteps.map { $0.ESDatTD_kgpm3 }.max() ?? 0
        minESD_kgpm3 = allSteps.map { $0.ESDatTD_kgpm3 }.min() ?? 0

        if let lastStep = allSteps.max(by: { $0.stepIndex < $1.stepIndex }) {
            totalBackfill_m3 = lastStep.cumulativeBackfill_m3
            totalPitGain_m3 = lastStep.cumulativePitGain_m3
            finalTankDelta_m3 = lastStep.cumulativeSurfaceTankDelta_m3
        }

        updatedAt = .now
    }
}

// MARK: - Export Dictionary

extension TripSimulation {
    var exportDictionary: [String: Any] {
        [
            "id": id.uuidString,
            "name": name,
            "createdAt": ISO8601DateFormatter().string(from: createdAt),
            "updatedAt": ISO8601DateFormatter().string(from: updatedAt),
            // Inputs
            "startBitMD_m": startBitMD_m,
            "endMD_m": endMD_m,
            "shoeMD_m": shoeMD_m,
            "step_m": step_m,
            "baseMudDensity_kgpm3": baseMudDensity_kgpm3,
            "backfillDensity_kgpm3": backfillDensity_kgpm3,
            "targetESDAtTD_kgpm3": targetESDAtTD_kgpm3,
            "crackFloat_kPa": crackFloat_kPa,
            "initialSABP_kPa": initialSABP_kPa,
            "holdSABPOpen": holdSABPOpen,
            "tripSpeed_m_per_s": tripSpeed_m_per_s,
            "eccentricityFactor": eccentricityFactor,
            "fallbackTheta600": fallbackTheta600 as Any,
            "fallbackTheta300": fallbackTheta300 as Any,
            "useObservedPitGain": useObservedPitGain,
            "observedInitialPitGain_m3": observedInitialPitGain_m3,
            "calculatedInitialPitGain_m3": calculatedInitialPitGain_m3,
            // Summary results
            "maxSABP_kPa": maxSABP_kPa,
            "maxESD_kgpm3": maxESD_kgpm3,
            "minESD_kgpm3": minESD_kgpm3,
            "totalBackfill_m3": totalBackfill_m3,
            "totalPitGain_m3": totalPitGain_m3,
            "finalTankDelta_m3": finalTankDelta_m3,
            // Steps
            "steps": sortedSteps.map { $0.exportDictionary }
        ]
    }
}
