//
//  CementJobStage.swift
//  Josh Well Control for Mac
//
//  Represents a single stage in a cement job (pump stage or operation).
//

import Foundation
import SwiftData
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Represents a single stage in a cement job.
/// Can be either a pump stage (preFlush, spacer, cement, displacement) or an operation (pressure test, plug drop, etc.)
@Model
final class CementJobStage {
    var id: UUID = UUID()

    /// Order of this stage in the cement job sequence
    var orderIndex: Int = 0

    /// Type of stage (pump vs operation)
    var stageTypeRaw: Int = StageType.spacer.rawValue

    /// Descriptive name for this stage (e.g., "MAG EV 1300-BC", "Pressure Test Lines")
    var name: String = ""

    // MARK: - Pump Stage Properties

    /// Volume to pump (m³) - for pump stages
    var volume_m3: Double = 0.0

    /// Density of fluid being pumped (kg/m³)
    var density_kgm3: Double = 1200.0

    /// Pump rate (m³/min) - optional
    var pumpRate_m3permin: Double?

    // MARK: - Rheology Properties (for friction/APL calculations)

    /// Plastic Viscosity (cP = mPa·s) - Bingham Plastic model
    /// Typical values: Mud 15-25, Spacer 10-20, Lead cement 40-80, Tail cement 60-100
    var plasticViscosity_cP: Double = 30.0

    /// Yield Point (Pa) - Bingham Plastic model
    /// Typical values: Mud 5-15, Spacer 3-10, Lead cement 5-15, Tail cement 10-20
    var yieldPoint_Pa: Double = 10.0

    /// Calculated tonnage for cement stages (tonnes)
    /// Computed from volume / yield factor
    var tonnage_t: Double?

    /// Calculated mix water requirement (liters)
    /// Computed from tonnage × water ratio
    var mixWater_L: Double?

    // MARK: - Operation Properties

    /// Type of operation for non-pump stages
    var operationTypeRaw: Int?

    /// Pressure for pressure tests or bump plug (MPa)
    var pressure_MPa: Double?

    /// Secondary pressure (e.g., "over FCP" for bump plug)
    var overPressure_MPa: Double?

    /// Duration of operation (minutes)
    var duration_min: Double?

    /// Volume for bleed-back or similar operations (liters)
    var operationVolume_L: Double?

    /// Time stamp for operations like "plug down at 04:45 hrs"
    var operationTime: String?

    /// For float check operation: true if floats closed, false if open
    var floatsClosed: Bool = true

    /// For plug drop operation: true if dropped on the fly, false if lines pumped out first
    var plugDropOnTheFly: Bool = true

    /// Additional notes about the stage
    var notes: String = ""

    // MARK: - Visual Properties

    /// Color for visualization (RGBA 0..1)
    var colorR: Double = 0.5
    var colorG: Double = 0.5
    var colorB: Double = 0.5
    var colorA: Double = 1.0

    // MARK: - Relationships

    /// Optional link to a MudProperties (for spacers, displacement fluids that use existing muds)
    /// Inverse is declared on MudProperties.cementStages
    @Relationship(deleteRule: .nullify)
    var mud: MudProperties?

    /// Back-reference to the cement job
    /// Inverse is declared on CementJob.stages
    @Relationship(deleteRule: .nullify)
    var cementJob: CementJob?

    // MARK: - Stage Type Enum

    enum StageType: Int, Codable, CaseIterable {
        case preFlush = 0
        case spacer = 1
        case leadCement = 2
        case tailCement = 3
        case displacement = 4       // Water displacement
        case operation = 5
        case mudDisplacement = 6    // Mud displacement (separate from water)

        var displayName: String {
            switch self {
            case .preFlush: return "Pre-Flush"
            case .spacer: return "Spacer/Sweep"
            case .leadCement: return "Lead Cement"
            case .tailCement: return "Tail Cement"
            case .displacement: return "Water Displacement"
            case .mudDisplacement: return "Mud Displacement"
            case .operation: return "Operation"
            }
        }

        var isPumpStage: Bool {
            switch self {
            case .preFlush, .spacer, .leadCement, .tailCement, .displacement, .mudDisplacement:
                return true
            case .operation:
                return false
            }
        }

        var isCementStage: Bool {
            self == .leadCement || self == .tailCement
        }

        var isDisplacementStage: Bool {
            self == .displacement || self == .mudDisplacement
        }

        /// Default plastic viscosity (cP) for this stage type
        var defaultPlasticViscosity_cP: Double {
            switch self {
            case .preFlush: return 15.0
            case .spacer: return 20.0
            case .leadCement: return 60.0
            case .tailCement: return 80.0
            case .displacement, .mudDisplacement: return 20.0
            case .operation: return 20.0
            }
        }

        /// Default yield point (Pa) for this stage type
        var defaultYieldPoint_Pa: Double {
            switch self {
            case .preFlush: return 5.0
            case .spacer: return 8.0
            case .leadCement: return 10.0
            case .tailCement: return 15.0
            case .displacement, .mudDisplacement: return 8.0
            case .operation: return 8.0
            }
        }
    }

    // MARK: - Operation Type Enum

    enum OperationType: Int, Codable, CaseIterable {
        case pressureTestLines = 0
        case tripSet = 1
        case plugDrop = 2
        case bumpPlug = 3
        case pressureTestCasing = 4
        case floatCheck = 5
        case bleedBack = 6
        case rigOut = 7
        case other = 8

        var displayName: String {
            switch self {
            case .pressureTestLines: return "Pressure Test Lines"
            case .tripSet: return "Trips Set"
            case .plugDrop: return "Plug Drop"
            case .bumpPlug: return "Bump Plug"
            case .pressureTestCasing: return "Pressure Test Casing"
            case .floatCheck: return "Float Check"
            case .bleedBack: return "Bleed Back"
            case .rigOut: return "Rig Out Cementers"
            case .other: return "Other"
            }
        }
    }

    // MARK: - Computed Properties

    @Transient var stageType: StageType {
        get { StageType(rawValue: stageTypeRaw) ?? .spacer }
        set { stageTypeRaw = newValue.rawValue }
    }

    @Transient var operationType: OperationType? {
        get { operationTypeRaw.flatMap { OperationType(rawValue: $0) } }
        set { operationTypeRaw = newValue?.rawValue }
    }

    @Transient var color: Color {
        get { Color(red: colorR, green: colorG, blue: colorB, opacity: colorA) }
        set {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            #if canImport(UIKit)
            UIColor(newValue).getRed(&r, green: &g, blue: &b, alpha: &a)
            #elseif canImport(AppKit)
            let ns = NSColor(newValue)
            let inSRGB = ns.usingColorSpace(.sRGB) ?? ns.usingColorSpace(.deviceRGB)
            inSRGB?.getRed(&r, green: &g, blue: &b, alpha: &a)
            #endif
            colorR = Double(r)
            colorG = Double(g)
            colorB = Double(b)
            colorA = Double(a)
        }
    }

    /// Display string for volume (handles both m³ and liters appropriately)
    @Transient var volumeDisplayString: String {
        if volume_m3 >= 1.0 {
            return String(format: "%.1f m³", volume_m3)
        } else {
            return String(format: "%.0f L", volume_m3 * 1000)
        }
    }

    /// Display string for tonnage
    @Transient var tonnageDisplayString: String? {
        guard let t = tonnage_t else { return nil }
        return String(format: "%.2f t", t)
    }

    // MARK: - Initializer

    init(
        stageType: StageType = .spacer,
        name: String = "",
        volume_m3: Double = 0.0,
        density_kgm3: Double = 1200.0,
        pumpRate_m3permin: Double? = nil,
        color: Color = .gray,
        mud: MudProperties? = nil,
        cementJob: CementJob? = nil
    ) {
        self.stageTypeRaw = stageType.rawValue
        self.name = name
        self.volume_m3 = volume_m3
        self.density_kgm3 = density_kgm3
        self.pumpRate_m3permin = pumpRate_m3permin
        self.mud = mud
        self.cementJob = cementJob

        // Set color
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if canImport(UIKit)
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        #elseif canImport(AppKit)
        let ns = NSColor(color)
        let inSRGB = ns.usingColorSpace(.sRGB) ?? ns.usingColorSpace(.deviceRGB)
        inSRGB?.getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        self.colorR = Double(r)
        self.colorG = Double(g)
        self.colorB = Double(b)
        self.colorA = Double(a)
    }

    /// Convenience initializer for operation stages
    static func operation(
        type: OperationType,
        name: String? = nil,
        pressure_MPa: Double? = nil,
        overPressure_MPa: Double? = nil,
        duration_min: Double? = nil,
        volume_L: Double? = nil,
        time: String? = nil,
        floatsClosed: Bool = true,
        plugDropOnTheFly: Bool = true,
        notes: String = "",
        cementJob: CementJob? = nil
    ) -> CementJobStage {
        let stage = CementJobStage()
        stage.stageType = .operation
        stage.operationType = type
        stage.name = name ?? type.displayName
        stage.pressure_MPa = pressure_MPa
        stage.overPressure_MPa = overPressure_MPa
        stage.duration_min = duration_min
        stage.operationVolume_L = volume_L
        stage.operationTime = time
        stage.floatsClosed = floatsClosed
        stage.plugDropOnTheFly = plugDropOnTheFly
        stage.notes = notes
        stage.cementJob = cementJob
        return stage
    }

    // MARK: - Calculation Methods

    /// Update tonnage and mix water based on cement job parameters
    /// waterRatio_m3_per_tonne is in m³ per tonne of dry cement
    func updateCalculations(yieldFactor: Double, waterRatio_m3_per_tonne: Double) {
        guard stageType.isCementStage else {
            tonnage_t = nil
            mixWater_L = nil
            return
        }

        guard yieldFactor > 0 else {
            tonnage_t = nil
            mixWater_L = nil
            return
        }

        let t = volume_m3 / yieldFactor
        tonnage_t = t
        // Convert m³ to L for storage (waterRatio is now in m³/tonne)
        mixWater_L = t * waterRatio_m3_per_tonne * 1000.0
    }

    /// Link to a mud and update density/color from it
    func linkToMud(_ mud: MudProperties) {
        self.mud = mud
        self.density_kgm3 = mud.density_kgm3
        self.color = mud.color
        if name.isEmpty {
            self.name = mud.name
        }
    }
}

// MARK: - Summary Text Generation

extension CementJobStage {
    /// Generate summary text for clipboard export
    func summaryText() -> String {
        switch stageType {
        case .preFlush:
            return "pump \(volumeDisplayString) \(name) at \(Int(density_kgm3))kg/m³"

        case .spacer:
            return "pump \(volumeDisplayString) \(name) at \(Int(density_kgm3))kg/m³"

        case .leadCement:
            var text = "pump lead cement \(volumeDisplayString)"
            if let t = tonnage_t {
                text += " (\(String(format: "%.2f", t))t)"
            }
            text += " \(name) at \(Int(density_kgm3))kg/m³"
            return text

        case .tailCement:
            var text = "pump tail cement \(volumeDisplayString)"
            if let t = tonnage_t {
                text += " (\(String(format: "%.2f", t))t)"
            }
            text += " \(name) at \(Int(density_kgm3))kg/m³"
            return text

        case .mudDisplacement:
            return "displaced with \(volumeDisplayString) of \(Int(density_kgm3))kg/m³ \(name)"

        case .displacement:
            return "displaced with \(volumeDisplayString) of \(Int(density_kgm3))kg/m³ \(name)"

        case .operation:
            return operationSummaryText()
        }
    }

    private func operationSummaryText() -> String {
        guard let opType = operationType else {
            return notes.isEmpty ? name : notes
        }

        switch opType {
        case .pressureTestLines:
            if let p = pressure_MPa {
                return "pressure test lines to \(String(format: "%.1f", p))MPa"
            }
            return "pressure test lines"

        case .tripSet:
            if let p = pressure_MPa {
                return "trips set at \(String(format: "%.1f", p))MPa"
            }
            return "trips set"

        case .plugDrop:
            if plugDropOnTheFly {
                return "drop plug on the fly"
            } else {
                // Use pump out volume from cement job if available
                if let job = cementJob, job.pumpOutVolume_m3 > 0 {
                    return "lines pumped out with \(String(format: "%.1f", job.pumpOutVolume_m3))m³, drop plug"
                }
                return "lines pumped out, drop plug"
            }

        case .bumpPlug:
            var text = "bumped plug"
            if let over = overPressure_MPa, let p = pressure_MPa {
                text += " \(String(format: "%.1f", over))MPa over FCP to \(String(format: "%.1f", p))MPa"
            } else if let p = pressure_MPa {
                text += " to \(String(format: "%.1f", p))MPa"
            }
            return text

        case .pressureTestCasing:
            var text = "pressure tested casing"
            if let p = pressure_MPa {
                text += " to \(String(format: "%.1f", p))MPa"
            }
            if let d = duration_min {
                text += " (\(Int(d))min)"
            }
            text += " ok"
            return text

        case .floatCheck:
            return floatsClosed ? "floats held" : "floats open"

        case .bleedBack:
            if let vol = operationVolume_L {
                return "bled back \(Int(vol))L"
            }
            return "bled back"

        case .rigOut:
            return "Rig out cementers"

        case .other:
            return notes.isEmpty ? name : notes
        }
    }
}

// MARK: - Export Dictionary

extension CementJobStage {
    var exportDictionary: [String: Any] {
        var dict: [String: Any] = [
            "id": id.uuidString,
            "orderIndex": orderIndex,
            "stageType": stageType.rawValue,
            "name": name,
            "volume_m3": volume_m3,
            "density_kgm3": density_kgm3,
            "color": ["r": colorR, "g": colorG, "b": colorB, "a": colorA],
            "notes": notes
        ]

        if let rate = pumpRate_m3permin { dict["pumpRate_m3permin"] = rate }
        if let t = tonnage_t { dict["tonnage_t"] = t }
        if let water = mixWater_L { dict["mixWater_L"] = water }
        if let opType = operationType { dict["operationType"] = opType.rawValue }
        if let p = pressure_MPa { dict["pressure_MPa"] = p }
        if let op = overPressure_MPa { dict["overPressure_MPa"] = op }
        if let d = duration_min { dict["duration_min"] = d }
        if let vol = operationVolume_L { dict["operationVolume_L"] = vol }
        if let time = operationTime { dict["operationTime"] = time }
        if operationType == .floatCheck { dict["floatsClosed"] = floatsClosed }
        if operationType == .plugDrop { dict["plugDropOnTheFly"] = plugDropOnTheFly }
        if let mudID = mud?.id { dict["mudID"] = mudID.uuidString }

        return dict
    }
}

