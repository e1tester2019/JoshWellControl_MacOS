//
//  TripInSimulationStep.swift
//  Josh Well Control for Mac
//
//  Represents a single step in a trip-in simulation with all computed values.
//

import Foundation
import SwiftData

/// Represents a single step in a trip-in simulation.
/// Tracks fill volume, displacement, ESD, choke pressure, and differential pressure.
@Model
final class TripInSimulationStep {
    var id: UUID = UUID()

    /// Index of this step (0-based, ordered by execution)
    var stepIndex: Int = 0

    // MARK: - Depth

    /// Bit depth at this step (MD in meters)
    var bitMD_m: Double = 0

    /// Bit depth at this step (TVD in meters)
    var bitTVD_m: Double = 0

    // MARK: - Fill Volumes

    /// Fill volume pumped this step (m³) - mud pumped to fill pipe from top
    var stepFillVolume_m3: Double = 0

    /// Cumulative fill volume (m³)
    var cumulativeFillVolume_m3: Double = 0

    /// Expected fill volume for closed pipe (m³) - pipe capacity
    var expectedFillClosed_m3: Double = 0

    /// Expected fill volume for open pipe (m³) - just steel displacement
    var expectedFillOpen_m3: Double = 0

    // MARK: - Displacement Returns

    /// Displacement returns this step (m³) - volume returned as pipe enters hole
    var stepDisplacementReturns_m3: Double = 0

    /// Cumulative displacement returns (m³)
    var cumulativeDisplacementReturns_m3: Double = 0

    // MARK: - Pressures & ESD

    /// ESD at control depth (kg/m³) - shoe or specified control point
    var ESDAtControl_kgpm3: Double = 0

    /// ESD at current bit depth (kg/m³)
    var ESDAtBit_kgpm3: Double = 0

    /// Required choke pressure to maintain target ESD (kPa)
    /// Zero if ESD is at or above target
    var requiredChokePressure_kPa: Double = 0

    /// Whether ESD is below target (needs choke)
    var isBelowTarget: Bool = false

    /// Differential pressure at bottom of casing (kPa)
    /// For floated casing: annulus pressure - air column pressure
    var differentialPressureAtBottom_kPa: Double = 0

    /// Hydrostatic pressure on annulus side at bit depth (kPa)
    var annulusPressureAtBit_kPa: Double = 0

    /// Hydrostatic pressure on string side at bit depth (kPa)
    var stringPressureAtBit_kPa: Double = 0

    /// Float valve state description
    var floatState: String = "N/A"

    // MARK: - Annulus State

    /// Current mud density at control depth (kg/m³) - considering pocket displacement
    var mudDensityAtControl_kgpm3: Double = 0

    // MARK: - Layer Snapshots (stored as JSON Data)

    /// Annulus layers encoded as JSON
    var layersAnnulusData: Data?

    /// String (inside pipe) layers encoded as JSON
    var layersStringData: Data?

    /// Pocket layers (below bit) encoded as JSON
    var layersPocketData: Data?

    // MARK: - Relationship

    /// Back-reference to the owning simulation
    @Relationship(deleteRule: .nullify)
    var simulation: TripInSimulation?

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
        stepFillVolume_m3: Double = 0,
        cumulativeFillVolume_m3: Double = 0,
        expectedFillClosed_m3: Double = 0,
        expectedFillOpen_m3: Double = 0,
        stepDisplacementReturns_m3: Double = 0,
        cumulativeDisplacementReturns_m3: Double = 0,
        ESDAtControl_kgpm3: Double = 0,
        ESDAtBit_kgpm3: Double = 0,
        requiredChokePressure_kPa: Double = 0,
        isBelowTarget: Bool = false,
        differentialPressureAtBottom_kPa: Double = 0,
        annulusPressureAtBit_kPa: Double = 0,
        stringPressureAtBit_kPa: Double = 0,
        floatState: String = "N/A",
        mudDensityAtControl_kgpm3: Double = 0,
        simulation: TripInSimulation? = nil
    ) {
        self.stepIndex = stepIndex
        self.bitMD_m = bitMD_m
        self.bitTVD_m = bitTVD_m
        self.stepFillVolume_m3 = stepFillVolume_m3
        self.cumulativeFillVolume_m3 = cumulativeFillVolume_m3
        self.expectedFillClosed_m3 = expectedFillClosed_m3
        self.expectedFillOpen_m3 = expectedFillOpen_m3
        self.stepDisplacementReturns_m3 = stepDisplacementReturns_m3
        self.cumulativeDisplacementReturns_m3 = cumulativeDisplacementReturns_m3
        self.ESDAtControl_kgpm3 = ESDAtControl_kgpm3
        self.ESDAtBit_kgpm3 = ESDAtBit_kgpm3
        self.requiredChokePressure_kPa = requiredChokePressure_kPa
        self.isBelowTarget = isBelowTarget
        self.differentialPressureAtBottom_kPa = differentialPressureAtBottom_kPa
        self.annulusPressureAtBit_kPa = annulusPressureAtBit_kPa
        self.stringPressureAtBit_kPa = stringPressureAtBit_kPa
        self.floatState = floatState
        self.mudDensityAtControl_kgpm3 = mudDensityAtControl_kgpm3
        self.simulation = simulation
    }
}

// MARK: - Export Dictionary

extension TripInSimulationStep {
    var exportDictionary: [String: Any] {
        [
            "stepIndex": stepIndex,
            "bitMD_m": bitMD_m,
            "bitTVD_m": bitTVD_m,
            "stepFillVolume_m3": stepFillVolume_m3,
            "cumulativeFillVolume_m3": cumulativeFillVolume_m3,
            "expectedFillClosed_m3": expectedFillClosed_m3,
            "expectedFillOpen_m3": expectedFillOpen_m3,
            "stepDisplacementReturns_m3": stepDisplacementReturns_m3,
            "cumulativeDisplacementReturns_m3": cumulativeDisplacementReturns_m3,
            "ESDAtControl_kgpm3": ESDAtControl_kgpm3,
            "ESDAtBit_kgpm3": ESDAtBit_kgpm3,
            "requiredChokePressure_kPa": requiredChokePressure_kPa,
            "isBelowTarget": isBelowTarget,
            "differentialPressureAtBottom_kPa": differentialPressureAtBottom_kPa,
            "annulusPressureAtBit_kPa": annulusPressureAtBit_kPa,
            "stringPressureAtBit_kPa": stringPressureAtBit_kPa,
            "floatState": floatState,
            "mudDensityAtControl_kgpm3": mudDensityAtControl_kgpm3,
            "layersAnnulus": layersAnnulus.map { $0.dictionary },
            "layersString": layersString.map { $0.dictionary },
            "layersPocket": layersPocket.map { $0.dictionary }
        ]
    }
}
