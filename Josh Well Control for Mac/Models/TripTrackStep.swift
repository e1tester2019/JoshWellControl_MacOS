//
//  TripTrackStep.swift
//  Josh Well Control for Mac
//
//  Individual step in a process-based trip tracking session.
//

import Foundation
import SwiftData

/// Represents a single locked step in a trip tracking session.
/// Captures both user-observed values and system-calculated results for comparison.
@Model
final class TripTrackStep {
    var id: UUID = UUID()

    /// Index of this step (0-based, ordered by lock time)
    var stepIndex: Int = 0

    /// Timestamp when this step was locked
    var lockedAt: Date = Date.now

    // MARK: - User Inputs (Observed Values)

    /// Bit depth after this step (MD in meters)
    var bitMD_m: Double = 0

    /// Bit depth after this step (TVD in meters)
    var bitTVD_m: Double = 0

    /// Observed backfill volume pumped (m³)
    var observedBackfill_m3: Double = 0

    /// Observed surface annular back pressure (kPa)
    var observedSABP_kPa: Double = 0

    /// Observed pit/tank volume change (m³)
    var observedPitChange_m3: Double = 0

    /// Float state override: nil = auto, 0 = force closed, 1 = force open
    var floatStateOverrideRaw: Int?

    /// Backfill mud density used for this step (kg/m³)
    var backfillDensity_kgpm3: Double = 1080

    // MARK: - System Calculated Values

    /// Calculated SABP to maintain target ESD (kPa)
    var calculatedSABP_kPa: Double = 0

    /// Calculated ESD at TD (kg/m³)
    var calculatedESDatTD_kgpm3: Double = 0

    /// Calculated ESD at bit (kg/m³)
    var calculatedESDatBit_kgpm3: Double = 0

    /// Expected fill volume if float closed (DP Wet) (m³)
    var expectedFillIfClosed_m3: Double = 0

    /// Expected fill volume if float open (DP Dry) (m³)
    var expectedFillIfOpen_m3: Double = 0

    /// Calculated float state description
    var calculatedFloatState: String = "CLOSED 100%"

    // MARK: - Discrepancy Tracking

    /// Backfill discrepancy: observed - expected (m³)
    var backfillDiscrepancy_m3: Double = 0

    /// SABP discrepancy: observed - calculated (kPa)
    var SABPDiscrepancy_kPa: Double = 0

    /// Pit change discrepancy: observed - calculated (m³)
    var pitDiscrepancy_m3: Double = 0

    // MARK: - Cumulative Values

    /// Cumulative backfill pumped at this step (m³)
    var cumulativeBackfill_m3: Double = 0

    /// Cumulative pit change at this step (m³)
    var cumulativePitChange_m3: Double = 0

    /// Cumulative tank delta at this step (m³)
    var cumulativeTankDelta_m3: Double = 0

    // MARK: - Layer Snapshots (JSON encoded)

    /// Annulus layers after this step
    var layersAnnulusData: Data?

    /// String layers after this step
    var layersStringData: Data?

    /// Pocket layers after this step
    var layersPocketData: Data?

    // MARK: - Notes

    /// Optional notes for this step
    var notes: String = ""

    // MARK: - Relationship

    /// Back-reference to the owning trip track
    @Relationship(deleteRule: .nullify)
    var tripTrack: TripTrack?

    // MARK: - Float Override Enum

    enum FloatOverride: Int {
        case closed = 0
        case open = 1
    }

    // MARK: - Computed Properties

    /// Float state override as enum
    @Transient var floatOverride: FloatOverride? {
        get {
            guard let raw = floatStateOverrideRaw else { return nil }
            return FloatOverride(rawValue: raw)
        }
        set {
            floatStateOverrideRaw = newValue?.rawValue
        }
    }

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

    /// Whether there's a significant backfill discrepancy (> 5%)
    @Transient var hasBackfillDiscrepancy: Bool {
        let expected = expectedFillIfClosed_m3
        guard expected > 0.001 else { return false }
        return abs(backfillDiscrepancy_m3 / expected) > 0.05
    }

    /// Whether there's a significant SABP discrepancy (> 50 kPa)
    @Transient var hasSABPDiscrepancy: Bool {
        abs(SABPDiscrepancy_kPa) > 50
    }

    // MARK: - Initializer

    init(
        stepIndex: Int = 0,
        bitMD_m: Double = 0,
        bitTVD_m: Double = 0,
        observedBackfill_m3: Double = 0,
        observedSABP_kPa: Double = 0,
        observedPitChange_m3: Double = 0,
        floatOverride: FloatOverride? = nil,
        backfillDensity_kgpm3: Double = 1080,
        calculatedSABP_kPa: Double = 0,
        calculatedESDatTD_kgpm3: Double = 0,
        calculatedESDatBit_kgpm3: Double = 0,
        expectedFillIfClosed_m3: Double = 0,
        expectedFillIfOpen_m3: Double = 0,
        calculatedFloatState: String = "CLOSED 100%",
        cumulativeBackfill_m3: Double = 0,
        cumulativePitChange_m3: Double = 0,
        cumulativeTankDelta_m3: Double = 0,
        notes: String = "",
        tripTrack: TripTrack? = nil
    ) {
        self.stepIndex = stepIndex
        self.bitMD_m = bitMD_m
        self.bitTVD_m = bitTVD_m
        self.observedBackfill_m3 = observedBackfill_m3
        self.observedSABP_kPa = observedSABP_kPa
        self.observedPitChange_m3 = observedPitChange_m3
        self.floatStateOverrideRaw = floatOverride?.rawValue
        self.backfillDensity_kgpm3 = backfillDensity_kgpm3
        self.calculatedSABP_kPa = calculatedSABP_kPa
        self.calculatedESDatTD_kgpm3 = calculatedESDatTD_kgpm3
        self.calculatedESDatBit_kgpm3 = calculatedESDatBit_kgpm3
        self.expectedFillIfClosed_m3 = expectedFillIfClosed_m3
        self.expectedFillIfOpen_m3 = expectedFillIfOpen_m3
        self.calculatedFloatState = calculatedFloatState
        self.cumulativeBackfill_m3 = cumulativeBackfill_m3
        self.cumulativePitChange_m3 = cumulativePitChange_m3
        self.cumulativeTankDelta_m3 = cumulativeTankDelta_m3
        self.notes = notes
        self.tripTrack = tripTrack

        // Calculate discrepancies
        self.backfillDiscrepancy_m3 = observedBackfill_m3 - expectedFillIfClosed_m3
        self.SABPDiscrepancy_kPa = observedSABP_kPa - calculatedSABP_kPa
    }
}

// MARK: - Export Dictionary

extension TripTrackStep {
    var exportDictionary: [String: Any] {
        [
            "stepIndex": stepIndex,
            "lockedAt": ISO8601DateFormatter().string(from: lockedAt),
            // Observed values
            "bitMD_m": bitMD_m,
            "bitTVD_m": bitTVD_m,
            "observedBackfill_m3": observedBackfill_m3,
            "observedSABP_kPa": observedSABP_kPa,
            "observedPitChange_m3": observedPitChange_m3,
            "floatOverride": floatOverride.map { $0 == .closed ? "closed" : "open" } as Any,
            "backfillDensity_kgpm3": backfillDensity_kgpm3,
            // Calculated values
            "calculatedSABP_kPa": calculatedSABP_kPa,
            "calculatedESDatTD_kgpm3": calculatedESDatTD_kgpm3,
            "calculatedESDatBit_kgpm3": calculatedESDatBit_kgpm3,
            "expectedFillIfClosed_m3": expectedFillIfClosed_m3,
            "expectedFillIfOpen_m3": expectedFillIfOpen_m3,
            "calculatedFloatState": calculatedFloatState,
            // Discrepancies
            "backfillDiscrepancy_m3": backfillDiscrepancy_m3,
            "SABPDiscrepancy_kPa": SABPDiscrepancy_kPa,
            "pitDiscrepancy_m3": pitDiscrepancy_m3,
            // Cumulative
            "cumulativeBackfill_m3": cumulativeBackfill_m3,
            "cumulativePitChange_m3": cumulativePitChange_m3,
            "cumulativeTankDelta_m3": cumulativeTankDelta_m3,
            // Notes
            "notes": notes,
            // Layers
            "layersAnnulus": layersAnnulus.map { $0.dictionary },
            "layersString": layersString.map { $0.dictionary },
            "layersPocket": layersPocket.map { $0.dictionary }
        ]
    }
}
