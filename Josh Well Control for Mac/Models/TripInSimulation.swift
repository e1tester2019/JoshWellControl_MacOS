//
//  TripInSimulation.swift
//  Josh Well Control for Mac
//
//  Persists trip-in simulation input configurations.
//  Results are computed on-the-fly when the user clicks Run.
//

import Foundation
import SwiftData

/// Represents a trip-in simulation input configuration.
/// Results are computed at runtime — only inputs are persisted.
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

    /// Trip speed (m/min) for surge/swab calculations
    var tripSpeed_m_per_min: Double = 0

    // MARK: - Relationships

    /// Back-reference to the owning project
    @Relationship(deleteRule: .nullify)
    var project: ProjectState?

    /// Reference to the Well this simulation belongs to
    @Relationship(deleteRule: .nullify)
    var well: Well?

    // MARK: - Computed Properties

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
        tripSpeed_m_per_min: Double = 0,
        project: ProjectState? = nil,
        well: Well? = nil
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
        self.tripSpeed_m_per_min = tripSpeed_m_per_min
        self.project = project
        self.well = well
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
            "tripSpeed_m_per_min": tripSpeed_m_per_min,
            "fillMudID": fillMudID?.uuidString as Any
        ]
    }
}
