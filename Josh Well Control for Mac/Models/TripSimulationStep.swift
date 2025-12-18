//
//  TripSimulationStep.swift
//  Josh Well Control for Mac
//
//  Created for persisting individual trip simulation steps.
//

import Foundation
import SwiftData

/// Represents a single step in a trip simulation with all computed values and layer snapshots.
@Model
final class TripSimulationStep {
    var id: UUID = UUID()

    /// Index of this step in the simulation (0-based, ordered by execution)
    var stepIndex: Int = 0

    // MARK: - Depth

    /// Bit depth at this step (MD in meters)
    var bitMD_m: Double = 0

    /// Bit depth at this step (TVD in meters)
    var bitTVD_m: Double = 0

    // MARK: - Pressures

    /// Surface annular back pressure (kPa)
    var SABP_kPa: Double = 0

    /// Raw SABP before hold-open override (kPa)
    var SABP_kPa_Raw: Double = 0

    /// Dynamic SABP including swab compensation (kPa)
    var SABP_Dynamic_kPa: Double = 0

    /// Equivalent static density at TD (kg/m³)
    var ESDatTD_kgpm3: Double = 0

    /// Equivalent static density at bit (kg/m³)
    var ESDatBit_kgpm3: Double = 0

    /// Swab pressure drop to bit (kPa)
    var swabDropToBit_kPa: Double = 0

    // MARK: - Float State

    /// Float valve state description (e.g., "OPEN 72%", "CLOSED 100%")
    var floatState: String = "CLOSED 100%"

    // MARK: - Volumes

    /// Backfill pumped this step (m³)
    var stepBackfill_m3: Double = 0

    /// Cumulative backfill pumped (m³)
    var cumulativeBackfill_m3: Double = 0

    /// Expected fill volume if float closed (pipe OD) (m³)
    var expectedFillIfClosed_m3: Double = 0

    /// Expected fill volume if float open (steel only) (m³)
    var expectedFillIfOpen_m3: Double = 0

    /// Slug contribution from string draining (m³)
    var slugContribution_m3: Double = 0

    /// Cumulative slug contribution (m³)
    var cumulativeSlugContribution_m3: Double = 0

    /// Pit gain (overflow at surface) this step (m³)
    var pitGain_m3: Double = 0

    /// Cumulative pit gain (m³)
    var cumulativePitGain_m3: Double = 0

    /// Surface tank delta this step (m³)
    var surfaceTankDelta_m3: Double = 0

    /// Cumulative surface tank delta (m³)
    var cumulativeSurfaceTankDelta_m3: Double = 0

    /// Remaining backfill available (m³)
    var backfillRemaining_m3: Double = 0

    // MARK: - Layer Snapshots (stored as JSON Data)

    /// Annulus layers encoded as JSON
    var layersAnnulusData: Data?

    /// String layers encoded as JSON
    var layersStringData: Data?

    /// Pocket layers encoded as JSON
    var layersPocketData: Data?

    // MARK: - Relationship

    /// Back-reference to the owning simulation
    @Relationship(deleteRule: .nullify)
    var simulation: TripSimulation?

    // MARK: - Computed Properties for Layer Access

    /// Decoded annulus layers
    @Transient var layersAnnulus: [TripLayerSnapshot] {
        get {
            guard let data = layersAnnulusData else { return [] }
            return (try? JSONDecoder().decode([TripLayerSnapshot].self, from: data)) ?? []
        }
        set {
            layersAnnulusData = try? JSONEncoder().encode(newValue)
        }
    }

    /// Decoded string layers
    @Transient var layersString: [TripLayerSnapshot] {
        get {
            guard let data = layersStringData else { return [] }
            return (try? JSONDecoder().decode([TripLayerSnapshot].self, from: data)) ?? []
        }
        set {
            layersStringData = try? JSONEncoder().encode(newValue)
        }
    }

    /// Decoded pocket layers
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
        stepIndex: Int = 0,
        bitMD_m: Double = 0,
        bitTVD_m: Double = 0,
        SABP_kPa: Double = 0,
        SABP_kPa_Raw: Double = 0,
        SABP_Dynamic_kPa: Double = 0,
        ESDatTD_kgpm3: Double = 0,
        ESDatBit_kgpm3: Double = 0,
        swabDropToBit_kPa: Double = 0,
        floatState: String = "CLOSED 100%",
        stepBackfill_m3: Double = 0,
        cumulativeBackfill_m3: Double = 0,
        expectedFillIfClosed_m3: Double = 0,
        expectedFillIfOpen_m3: Double = 0,
        slugContribution_m3: Double = 0,
        cumulativeSlugContribution_m3: Double = 0,
        pitGain_m3: Double = 0,
        cumulativePitGain_m3: Double = 0,
        surfaceTankDelta_m3: Double = 0,
        cumulativeSurfaceTankDelta_m3: Double = 0,
        backfillRemaining_m3: Double = 0,
        simulation: TripSimulation? = nil
    ) {
        self.stepIndex = stepIndex
        self.bitMD_m = bitMD_m
        self.bitTVD_m = bitTVD_m
        self.SABP_kPa = SABP_kPa
        self.SABP_kPa_Raw = SABP_kPa_Raw
        self.SABP_Dynamic_kPa = SABP_Dynamic_kPa
        self.ESDatTD_kgpm3 = ESDatTD_kgpm3
        self.ESDatBit_kgpm3 = ESDatBit_kgpm3
        self.swabDropToBit_kPa = swabDropToBit_kPa
        self.floatState = floatState
        self.stepBackfill_m3 = stepBackfill_m3
        self.cumulativeBackfill_m3 = cumulativeBackfill_m3
        self.expectedFillIfClosed_m3 = expectedFillIfClosed_m3
        self.expectedFillIfOpen_m3 = expectedFillIfOpen_m3
        self.slugContribution_m3 = slugContribution_m3
        self.cumulativeSlugContribution_m3 = cumulativeSlugContribution_m3
        self.pitGain_m3 = pitGain_m3
        self.cumulativePitGain_m3 = cumulativePitGain_m3
        self.surfaceTankDelta_m3 = surfaceTankDelta_m3
        self.cumulativeSurfaceTankDelta_m3 = cumulativeSurfaceTankDelta_m3
        self.backfillRemaining_m3 = backfillRemaining_m3
        self.simulation = simulation
    }

    // MARK: - Convenience Initializer from TripStep

    /// Create from a NumericalTripModel.TripStep
    convenience init(from tripStep: TripStep, index: Int) {
        self.init(
            stepIndex: index,
            bitMD_m: tripStep.bitMD_m,
            bitTVD_m: tripStep.bitTVD_m,
            SABP_kPa: tripStep.SABP_kPa,
            SABP_kPa_Raw: tripStep.SABP_kPa_Raw,
            SABP_Dynamic_kPa: tripStep.SABP_Dynamic_kPa,
            ESDatTD_kgpm3: tripStep.ESDatTD_kgpm3,
            ESDatBit_kgpm3: tripStep.ESDatBit_kgpm3,
            swabDropToBit_kPa: tripStep.swabDropToBit_kPa,
            floatState: tripStep.floatState,
            stepBackfill_m3: tripStep.stepBackfill_m3,
            cumulativeBackfill_m3: tripStep.cumulativeBackfill_m3,
            expectedFillIfClosed_m3: tripStep.expectedFillIfClosed_m3,
            expectedFillIfOpen_m3: tripStep.expectedFillIfOpen_m3,
            slugContribution_m3: tripStep.slugContribution_m3,
            cumulativeSlugContribution_m3: tripStep.cumulativeSlugContribution_m3,
            pitGain_m3: tripStep.pitGain_m3,
            cumulativePitGain_m3: tripStep.cumulativePitGain_m3,
            surfaceTankDelta_m3: tripStep.surfaceTankDelta_m3,
            cumulativeSurfaceTankDelta_m3: tripStep.cumulativeSurfaceTankDelta_m3,
            backfillRemaining_m3: tripStep.backfillRemaining_m3
        )

        // Convert layer rows to snapshots
        self.layersAnnulus = tripStep.layersAnnulus.map { TripLayerSnapshot(from: $0) }
        self.layersString = tripStep.layersString.map { TripLayerSnapshot(from: $0) }
        self.layersPocket = tripStep.layersPocket.map { TripLayerSnapshot(from: $0) }
    }
}

// MARK: - Export Dictionary

extension TripSimulationStep {
    var exportDictionary: [String: Any] {
        [
            "stepIndex": stepIndex,
            "bitMD_m": bitMD_m,
            "bitTVD_m": bitTVD_m,
            "SABP_kPa": SABP_kPa,
            "SABP_kPa_Raw": SABP_kPa_Raw,
            "SABP_Dynamic_kPa": SABP_Dynamic_kPa,
            "ESDatTD_kgpm3": ESDatTD_kgpm3,
            "ESDatBit_kgpm3": ESDatBit_kgpm3,
            "swabDropToBit_kPa": swabDropToBit_kPa,
            "floatState": floatState,
            "stepBackfill_m3": stepBackfill_m3,
            "cumulativeBackfill_m3": cumulativeBackfill_m3,
            "expectedFillIfClosed_m3": expectedFillIfClosed_m3,
            "expectedFillIfOpen_m3": expectedFillIfOpen_m3,
            "slugContribution_m3": slugContribution_m3,
            "cumulativeSlugContribution_m3": cumulativeSlugContribution_m3,
            "pitGain_m3": pitGain_m3,
            "cumulativePitGain_m3": cumulativePitGain_m3,
            "surfaceTankDelta_m3": surfaceTankDelta_m3,
            "cumulativeSurfaceTankDelta_m3": cumulativeSurfaceTankDelta_m3,
            "backfillRemaining_m3": backfillRemaining_m3,
            "layersAnnulus": layersAnnulus.map { $0.dictionary },
            "layersString": layersString.map { $0.dictionary },
            "layersPocket": layersPocket.map { $0.dictionary }
        ]
    }
}
