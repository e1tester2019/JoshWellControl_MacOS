//
//  SwabInput.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-02.
//


import Foundation
import SwiftData

@Model
final class SwabInput {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = "Swab Input"

    // MARK: - Pipe movement & geometry
    /// Pipe OD (m)
    var pipeOD_m: Double = 0.127      // e.g., 5 in DP
    /// Pipe ID (m)
    var pipeID_m: Double = 0.0953
    /// Casing/wellbore ID (m)
    var holeID_m: Double = 0.216      // e.g., 8½ in hole

    /// Stroke length per swab cycle (m)
    var strokeLength_m: Double = 3.0
    /// Pulling or running velocity (m/s)
    var pipeVelocity_m_per_s: Double = 0.3
    /// Strokes per minute (SPM)
    var strokesPerMinute: Double = 10.0

    // MARK: - Fluid properties
    var fluidDensity_kg_per_m3: Double = 1200
    var plasticViscosity_Pa_s: Double = 0.02
    var yieldPoint_Pa: Double = 6.0

    // MARK: - Depth conditions
    var topOfFluid_m: Double = 0.0
    var bottomOfFluid_m: Double = 2000.0
    var tvd_m: Double { bottomOfFluid_m } // for convenience in vertical wells

    // MARK: - Swab/surge model options
    enum ModelType: Int, Codable {
        case Bingham = 0
        case PowerLaw
        case HerschelBulkley
    }
    var modelRaw: Int = ModelType.Bingham.rawValue

    /// Effective annular eccentricity (0 concentric – 1 touching)
    var eccentricity: Double = 0.0

    // MARK: - Temperature & pressure effects
    var temperature_C: Double = 25.0
    var surfacePressure_kPa: Double = 0.0

    // MARK: - Relationship
    @Relationship(deleteRule: .nullify, inverse: \ProjectState.swab)
    var project: ProjectState?

    init() {}

    // MARK: - Computed / helpers
    @Transient var model: ModelType {
        get { ModelType(rawValue: modelRaw) ?? .Bingham }
        set { modelRaw = newValue.rawValue }
    }

    /// Effective annular area (m²)
    @Transient var annulusArea_m2: Double {
        let ID = holeID_m
        let OD = pipeOD_m
        return .pi * 0.25 * max(ID*ID - OD*OD, 0)
    }

    /// Hydraulic diameter (m)
    @Transient var equivalentDiameter_m: Double {
        max(holeID_m - pipeOD_m, 0)
    }

    /// Approximate Reynolds number (dimensionless) — quick sanity check
    func reynoldsNumber() -> Double {
        guard equivalentDiameter_m > 0 else { return 0 }
        let rho = fluidDensity_kg_per_m3
        let mu = plasticViscosity_Pa_s
        return (rho * pipeVelocity_m_per_s * equivalentDiameter_m) / mu
    }

    /// Simplified steady-state surge pressure estimate (kPa)
    /// ΔP = f * (L/D) * (ρ * v² / 2)
    func surgePressure_kPa() -> Double {
        guard equivalentDiameter_m > 0 else { return 0 }
        let rho = fluidDensity_kg_per_m3
        let v = pipeVelocity_m_per_s
        let L = bottomOfFluid_m - topOfFluid_m
        let D = equivalentDiameter_m
        let f = frictionFactor() // crude from Re
        let deltaP_Pa = f * (L / D) * (rho * v * v / 2)
        return deltaP_Pa / 1000.0
    }

    /// Simple friction factor correlation (laminar/turbulent mix)
    func frictionFactor() -> Double {
        let Re = reynoldsNumber()
        if Re < 2000 { return 64.0 / max(Re, 1) }           // laminar
        else { return 0.3164 / pow(Re, 0.25) }              // Blasius turbulent
    }
}
