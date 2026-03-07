//
//  TripSimulation.swift
//  Josh Well Control for Mac
//
//  Persists trip simulation input configurations.
//  Results are computed on-the-fly when the user clicks Run.
//

import Foundation
import SwiftData

/// Represents a saved trip simulation input configuration.
/// Results are computed at runtime — only inputs are persisted.
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

    /// UUID of the backfill mud used (for retrieving on load)
    var backfillMudID: UUID?

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

    // MARK: - Torque & Drag Inputs

    /// Cased hole friction factor (dimensionless, 0-1)
    var tdCasedFF: Double = 0.20
    /// Open hole friction factor (dimensionless, 0-1)
    var tdOpenHoleFF: Double = 0.30
    /// Travelling block weight (kN)
    var tdBlockWeight_kN: Double = 0
    /// Whether to compute T&D during simulation
    var tdEnabled: Bool = false
    /// APL eccentricity factor for T&D
    var tdAplEccentricity: Double = 1.0
    /// Pressure-area buoyancy correction
    var tdPressureAreaBuoyancy: Bool = true
    /// T&D trip speed in cased hole (m/s)
    var tdTripSpeedCased_m_per_s: Double = 0
    /// T&D trip speed in open hole (m/s)
    var tdTripSpeedOpenHole_m_per_s: Double = 0
    /// T&D rotation efficiency for upward motion (0-1)
    var tdRotationEfficiencyUp: Double = 0.5
    /// T&D rotation efficiency for downward motion (0-1)
    var tdRotationEfficiencyDown: Double = 0.5
    var tdSheaveLineFriction: Double = 0

    // MARK: - Pit Gain Calibration

    /// Use observed pit gain instead of calculated
    var useObservedPitGain: Bool = false

    /// Observed initial pit gain from field (m³)
    var observedInitialPitGain_m3: Double = 0

    /// Calculated initial pit gain for comparison (m³)
    var calculatedInitialPitGain_m3: Double = 0

    // MARK: - Relationships

    /// Back-reference to the owning project
    @Relationship(deleteRule: .nullify)
    var project: ProjectState?

    /// Reference to the Well this simulation belongs to
    @Relationship(deleteRule: .nullify)
    var well: Well?

    // MARK: - Computed Properties

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
        tdCasedFF: Double = 0.20,
        tdOpenHoleFF: Double = 0.30,
        tdBlockWeight_kN: Double = 0,
        tdEnabled: Bool = false,
        tdAplEccentricity: Double = 1.0,
        tdPressureAreaBuoyancy: Bool = true,
        tdTripSpeedCased_m_per_s: Double = 0,
        tdTripSpeedOpenHole_m_per_s: Double = 0,
        tdRotationEfficiencyUp: Double = 0.5,
        tdRotationEfficiencyDown: Double = 0.5,
        tdSheaveLineFriction: Double = 0,
        useObservedPitGain: Bool = false,
        observedInitialPitGain_m3: Double = 0,
        project: ProjectState? = nil,
        well: Well? = nil,
        backfillMudID: UUID? = nil
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
        self.tdCasedFF = tdCasedFF
        self.tdOpenHoleFF = tdOpenHoleFF
        self.tdBlockWeight_kN = tdBlockWeight_kN
        self.tdEnabled = tdEnabled
        self.tdAplEccentricity = tdAplEccentricity
        self.tdPressureAreaBuoyancy = tdPressureAreaBuoyancy
        self.tdTripSpeedCased_m_per_s = tdTripSpeedCased_m_per_s
        self.tdTripSpeedOpenHole_m_per_s = tdTripSpeedOpenHole_m_per_s
        self.tdRotationEfficiencyUp = tdRotationEfficiencyUp
        self.tdRotationEfficiencyDown = tdRotationEfficiencyDown
        self.tdSheaveLineFriction = tdSheaveLineFriction
        self.useObservedPitGain = useObservedPitGain
        self.observedInitialPitGain_m3 = observedInitialPitGain_m3
        self.project = project
        self.well = well
        self.backfillMudID = backfillMudID
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
            "tdCasedFF": tdCasedFF,
            "tdOpenHoleFF": tdOpenHoleFF,
            "tdBlockWeight_kN": tdBlockWeight_kN,
            "tdEnabled": tdEnabled,
            "tdAplEccentricity": tdAplEccentricity,
            "tdPressureAreaBuoyancy": tdPressureAreaBuoyancy,
            "tdTripSpeedCased_m_per_s": tdTripSpeedCased_m_per_s,
            "tdTripSpeedOpenHole_m_per_s": tdTripSpeedOpenHole_m_per_s,
            "tdRotationEfficiencyUp": tdRotationEfficiencyUp,
            "tdRotationEfficiencyDown": tdRotationEfficiencyDown,
            "tdSheaveLineFriction": tdSheaveLineFriction,
            "useObservedPitGain": useObservedPitGain,
            "observedInitialPitGain_m3": observedInitialPitGain_m3,
            "calculatedInitialPitGain_m3": calculatedInitialPitGain_m3,
            "backfillMudID": backfillMudID?.uuidString as Any
        ]
    }
}
