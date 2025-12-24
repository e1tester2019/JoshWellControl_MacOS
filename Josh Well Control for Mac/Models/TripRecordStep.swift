//
//  TripRecordStep.swift
//  Josh Well Control for Mac
//
//  Created for storing individual trip recording steps with simulated and actual values.
//

import Foundation
import SwiftData

/// Represents a single step in a trip recording containing both simulated predictions
/// and actual field observations for comparison.
@Model
final class TripRecordStep {
    var id: UUID = UUID()

    /// Index of this step (0-based, matching source simulation order)
    var stepIndex: Int = 0

    // MARK: - Depth (from simulation, immutable)

    /// Bit depth at this step (MD in meters)
    var bitMD_m: Double = 0

    /// Bit depth at this step (TVD in meters)
    var bitTVD_m: Double = 0

    // MARK: - Simulated Values (copied from source simulation)

    /// Simulated surface annular back pressure (kPa)
    var simSABP_kPa: Double = 0

    /// Simulated dynamic SABP including swab compensation (kPa)
    var simSABP_Dynamic_kPa: Double = 0

    /// Simulated equivalent static density at TD (kg/m³)
    var simESDatTD_kgpm3: Double = 0

    /// Simulated equivalent static density at bit (kg/m³)
    var simESDatBit_kgpm3: Double = 0

    /// Simulated backfill pumped this step (m³)
    var simBackfill_m3: Double = 0

    /// Simulated cumulative backfill (m³)
    var simCumulativeBackfill_m3: Double = 0

    /// Simulated expected fill if float closed (m³)
    var simExpectedIfClosed_m3: Double = 0

    /// Simulated expected fill if float open (m³)
    var simExpectedIfOpen_m3: Double = 0

    /// Simulated float state description
    var simFloatState: String = "CLOSED 100%"

    /// Simulated pit gain this step (m³)
    var simPitGain_m3: Double = 0

    /// Simulated cumulative pit gain (m³)
    var simCumulativePitGain_m3: Double = 0

    /// Simulated surface tank delta this step (m³)
    var simTankDelta_m3: Double = 0

    /// Simulated cumulative surface tank delta (m³)
    var simCumulativeTankDelta_m3: Double = 0

    // MARK: - Layer Snapshots (JSON Data - for well visualization)

    /// Simulated annulus layers encoded as JSON
    var simLayersAnnulusData: Data?

    /// Simulated string layers encoded as JSON
    var simLayersStringData: Data?

    /// Simulated pocket layers encoded as JSON
    var simLayersPocketData: Data?

    // MARK: - Actual Values (user input, optional until recorded)

    /// Actual backfill pumped (m³) - user observed
    var actualBackfill_m3: Double?

    /// Actual SABP (kPa) - user observed
    var actualSABP_kPa: Double?

    /// Actual dynamic SABP (kPa) - user observed while moving pipe
    var actualSABP_Dynamic_kPa: Double?

    /// Actual pit change (m³) - user observed
    var actualPitChange_m3: Double?

    /// Float state override: nil=auto (use simulated), 0=forced closed, 1=forced open
    var actualFloatOverrideRaw: Int?

    /// Timestamp when actual values were recorded
    var observedAt: Date?

    /// Whether user explicitly skipped this depth
    var skipped: Bool = false

    /// User notes for this step
    var notes: String = ""

    // MARK: - Variance (calculated when actuals entered)

    /// SABP variance: actual - simulated (kPa)
    var sabpVariance_kPa: Double?

    /// Backfill variance: actual - expected (m³)
    var backfillVariance_m3: Double?

    /// Backfill variance as percentage
    var backfillVariancePercent: Double?

    // MARK: - Relationship

    /// Back-reference to the owning record
    @Relationship(deleteRule: .nullify)
    var record: TripRecord?

    // MARK: - Computed Properties

    /// Whether this step has any actual data recorded
    @Transient var hasActualData: Bool {
        actualBackfill_m3 != nil || actualSABP_kPa != nil || actualSABP_Dynamic_kPa != nil || actualPitChange_m3 != nil
    }

    /// Status of this step
    @Transient var status: StepStatus {
        if skipped { return .skipped }
        if hasActualData { return .recorded }
        return .pending
    }

    /// Float override enum accessor
    @Transient var actualFloatOverride: FloatOverride? {
        get {
            guard let raw = actualFloatOverrideRaw else { return nil }
            return FloatOverride(rawValue: raw)
        }
        set {
            actualFloatOverrideRaw = newValue?.rawValue
        }
    }

    /// Decoded simulated annulus layers
    @Transient var simLayersAnnulus: [TripLayerSnapshot] {
        get {
            guard let data = simLayersAnnulusData else { return [] }
            return (try? JSONDecoder().decode([TripLayerSnapshot].self, from: data)) ?? []
        }
        set {
            simLayersAnnulusData = try? JSONEncoder().encode(newValue)
        }
    }

    /// Decoded simulated string layers
    @Transient var simLayersString: [TripLayerSnapshot] {
        get {
            guard let data = simLayersStringData else { return [] }
            return (try? JSONDecoder().decode([TripLayerSnapshot].self, from: data)) ?? []
        }
        set {
            simLayersStringData = try? JSONEncoder().encode(newValue)
        }
    }

    /// Decoded simulated pocket layers
    @Transient var simLayersPocket: [TripLayerSnapshot] {
        get {
            guard let data = simLayersPocketData else { return [] }
            return (try? JSONDecoder().decode([TripLayerSnapshot].self, from: data)) ?? []
        }
        set {
            simLayersPocketData = try? JSONEncoder().encode(newValue)
        }
    }

    // MARK: - Enums

    enum StepStatus: String {
        case pending = "pending"
        case recorded = "recorded"
        case skipped = "skipped"

        var icon: String {
            switch self {
            case .pending: return "circle"
            case .recorded: return "checkmark.circle.fill"
            case .skipped: return "arrow.right.circle"
            }
        }

        var label: String {
            switch self {
            case .pending: return "Pending"
            case .recorded: return "Recorded"
            case .skipped: return "Skipped"
            }
        }
    }

    enum FloatOverride: Int {
        case closed = 0
        case open = 1

        var label: String {
            switch self {
            case .closed: return "Forced Closed"
            case .open: return "Forced Open"
            }
        }
    }

    // MARK: - Initializer

    init(
        stepIndex: Int = 0,
        bitMD_m: Double = 0,
        bitTVD_m: Double = 0,
        simSABP_kPa: Double = 0,
        simESDatTD_kgpm3: Double = 0,
        simESDatBit_kgpm3: Double = 0,
        simBackfill_m3: Double = 0,
        simCumulativeBackfill_m3: Double = 0,
        simExpectedIfClosed_m3: Double = 0,
        simExpectedIfOpen_m3: Double = 0,
        simFloatState: String = "CLOSED 100%",
        simPitGain_m3: Double = 0,
        simCumulativePitGain_m3: Double = 0,
        simTankDelta_m3: Double = 0,
        simCumulativeTankDelta_m3: Double = 0,
        record: TripRecord? = nil
    ) {
        self.stepIndex = stepIndex
        self.bitMD_m = bitMD_m
        self.bitTVD_m = bitTVD_m
        self.simSABP_kPa = simSABP_kPa
        self.simESDatTD_kgpm3 = simESDatTD_kgpm3
        self.simESDatBit_kgpm3 = simESDatBit_kgpm3
        self.simBackfill_m3 = simBackfill_m3
        self.simCumulativeBackfill_m3 = simCumulativeBackfill_m3
        self.simExpectedIfClosed_m3 = simExpectedIfClosed_m3
        self.simExpectedIfOpen_m3 = simExpectedIfOpen_m3
        self.simFloatState = simFloatState
        self.simPitGain_m3 = simPitGain_m3
        self.simCumulativePitGain_m3 = simCumulativePitGain_m3
        self.simTankDelta_m3 = simTankDelta_m3
        self.simCumulativeTankDelta_m3 = simCumulativeTankDelta_m3
        self.record = record
    }

    // MARK: - Recording Methods

    /// Record actual values and calculate variance
    func recordActual(backfill: Double?, sabp: Double?, pitChange: Double?, floatOverride: FloatOverride? = nil, notes: String = "") {
        self.actualBackfill_m3 = backfill
        self.actualSABP_kPa = sabp
        self.actualPitChange_m3 = pitChange
        self.actualFloatOverride = floatOverride
        self.notes = notes
        self.observedAt = Date.now
        self.skipped = false

        calculateVariance()
    }

    /// Mark this step as skipped
    func markSkipped() {
        self.skipped = true
        self.actualBackfill_m3 = nil
        self.actualSABP_kPa = nil
        self.actualPitChange_m3 = nil
        self.sabpVariance_kPa = nil
        self.backfillVariance_m3 = nil
        self.backfillVariancePercent = nil
        self.observedAt = Date.now
    }

    /// Calculate variance from actuals vs simulated
    func calculateVariance() {
        // SABP variance
        if let actual = actualSABP_kPa {
            sabpVariance_kPa = actual - simSABP_kPa
        } else {
            sabpVariance_kPa = nil
        }

        // Backfill variance (compare to expected fill based on float state)
        if let actual = actualBackfill_m3 {
            // Use expected fill based on override or simulated float state
            let expected: Double
            if let override = actualFloatOverride {
                expected = override == .closed ? simExpectedIfClosed_m3 : simExpectedIfOpen_m3
            } else {
                // Use simulated expected (already accounts for float state)
                expected = simBackfill_m3
            }

            backfillVariance_m3 = actual - expected
            if expected > 0 {
                backfillVariancePercent = (backfillVariance_m3! / expected) * 100
            } else {
                backfillVariancePercent = 0
            }
        } else {
            backfillVariance_m3 = nil
            backfillVariancePercent = nil
        }
    }

    /// Clear actual values
    func clearActual() {
        actualBackfill_m3 = nil
        actualSABP_kPa = nil
        actualSABP_Dynamic_kPa = nil
        actualPitChange_m3 = nil
        actualFloatOverrideRaw = nil
        observedAt = nil
        skipped = false
        notes = ""
        sabpVariance_kPa = nil
        backfillVariance_m3 = nil
        backfillVariancePercent = nil
    }
}

// MARK: - Creation from Simulation Step

extension TripRecordStep {
    /// Create a TripRecordStep from a TripSimulationStep
    static func createFrom(simulationStep: TripSimulationStep) -> TripRecordStep {
        let step = TripRecordStep(
            stepIndex: simulationStep.stepIndex,
            bitMD_m: simulationStep.bitMD_m,
            bitTVD_m: simulationStep.bitTVD_m,
            simSABP_kPa: simulationStep.SABP_kPa,
            simESDatTD_kgpm3: simulationStep.ESDatTD_kgpm3,
            simESDatBit_kgpm3: simulationStep.ESDatBit_kgpm3,
            simBackfill_m3: simulationStep.stepBackfill_m3,
            simCumulativeBackfill_m3: simulationStep.cumulativeBackfill_m3,
            simExpectedIfClosed_m3: simulationStep.expectedFillIfClosed_m3,
            simExpectedIfOpen_m3: simulationStep.expectedFillIfOpen_m3,
            simFloatState: simulationStep.floatState,
            simPitGain_m3: simulationStep.pitGain_m3,
            simCumulativePitGain_m3: simulationStep.cumulativePitGain_m3,
            simTankDelta_m3: simulationStep.surfaceTankDelta_m3,
            simCumulativeTankDelta_m3: simulationStep.cumulativeSurfaceTankDelta_m3
        )

        // Copy dynamic SABP
        step.simSABP_Dynamic_kPa = simulationStep.SABP_Dynamic_kPa

        // Copy layer snapshots
        step.simLayersAnnulusData = simulationStep.layersAnnulusData
        step.simLayersStringData = simulationStep.layersStringData
        step.simLayersPocketData = simulationStep.layersPocketData

        return step
    }
}

// MARK: - Export Dictionary

extension TripRecordStep {
    var exportDictionary: [String: Any] {
        var dict: [String: Any] = [
            "stepIndex": stepIndex,
            "bitMD_m": bitMD_m,
            "bitTVD_m": bitTVD_m,
            "status": status.rawValue,
            "skipped": skipped,
            // Simulated values
            "simSABP_kPa": simSABP_kPa,
            "simSABP_Dynamic_kPa": simSABP_Dynamic_kPa,
            "simESDatTD_kgpm3": simESDatTD_kgpm3,
            "simESDatBit_kgpm3": simESDatBit_kgpm3,
            "simBackfill_m3": simBackfill_m3,
            "simCumulativeBackfill_m3": simCumulativeBackfill_m3,
            "simExpectedIfClosed_m3": simExpectedIfClosed_m3,
            "simExpectedIfOpen_m3": simExpectedIfOpen_m3,
            "simFloatState": simFloatState,
            "simPitGain_m3": simPitGain_m3,
            "simCumulativeTankDelta_m3": simCumulativeTankDelta_m3
        ]

        // Actual values (only if recorded)
        if let v = actualBackfill_m3 { dict["actualBackfill_m3"] = v }
        if let v = actualSABP_kPa { dict["actualSABP_kPa"] = v }
        if let v = actualSABP_Dynamic_kPa { dict["actualSABP_Dynamic_kPa"] = v }
        if let v = actualPitChange_m3 { dict["actualPitChange_m3"] = v }
        if let v = observedAt { dict["observedAt"] = ISO8601DateFormatter().string(from: v) }

        // Variance (only if calculated)
        if let v = sabpVariance_kPa { dict["sabpVariance_kPa"] = v }
        if let v = backfillVariance_m3 { dict["backfillVariance_m3"] = v }
        if let v = backfillVariancePercent { dict["backfillVariancePercent"] = v }

        if !notes.isEmpty { dict["notes"] = notes }

        return dict
    }
}
