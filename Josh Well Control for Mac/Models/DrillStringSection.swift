//
//  DrillStringSection.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-02.
//


import Foundation
import SwiftData

@Model
final class DrillStringSection {
    // Identity
    var id: UUID = UUID()
    var name: String = ""

    // Placement (m)
    var topDepth_m: Double = 0.0     // MD at top
    var length_m: Double = 0.0       // section length
    var inclination_deg: Double = 0  // optional: for later torque/drag nuance

    // Geometry (m)
    var outerDiameter_m: Double = 0.0      // pipe OD
    var innerDiameter_m: Double = 0.0      // pipe ID
    var toolJointOD_m: Double?       // optional: TJ OD for contact/friction models
    var jointLength_m: Double = 0.0  // optional: average TJ length

    // Mechanics / properties
    var grade: String?               // e.g., G105, S135, etc.
    var steelDensity_kg_per_m3: Double = 7850 // default carbon steel
    var unitWeight_kg_per_m: Double? // if known from tables; else computed from OD/ID

    // Hydraulics (fluids are set per annulus in your model; these are string-side only if needed)
    var internalRoughness_m: Double = 4.6e-5 // ~0.0018 in, typical DP roughness

    // Relationships
    @Relationship(deleteRule: .nullify)
    var project: ProjectState?

    // Derived convenience -----------------------------------------------

    /// Bottom MD (m)
    @Transient var bottomDepth_m: Double {
        topDepth_m + length_m
    }

    /// Metal area (m²)
    @Transient var metalArea_m2: Double {
        let ro = outerDiameter_m * 0.5
        let ri = innerDiameter_m * 0.5
        return .pi * (ro*ro - ri*ri)
    }

    /// Cross-sectional steel volume per meter (m³/m)
    @Transient var volumePerMeter_m3_per_m: Double {
        metalArea_m2 * 1.0
    }

    /// Self-weight in air (kDaN/m). 1 kDaN = 10 kN.
    /// W_air = mass_per_m * g / 10_000  (N→kDaN)
    @Transient var weightAir_kDaN_per_m: Double {
        let massPerM = unitWeight_kg_per_m ?? (steelDensity_kg_per_m3 * volumePerMeter_m3_per_m)
        return (massPerM * 9.80665) / 10_000.0
    }

    /// Displacement (m²) – pipe metal area; useful for buoyancy calc with fluid density
    @Transient var displacedArea_m2: Double {
        metalArea_m2
    }

    // Init ---------------------------------------------------------------
    init(
        name: String,
        topDepth_m: Double,
        length_m: Double,
        outerDiameter_m: Double,
        innerDiameter_m: Double,
        toolJointOD_m: Double? = nil,
        jointLength_m: Double = 0.0,
        grade: String? = nil,
        steelDensity_kg_per_m3: Double = 7850,
        unitWeight_kg_per_m: Double? = nil,
        internalRoughness_m: Double = 4.6e-5,
        project: ProjectState? = nil
    ) {
        self.name = name
        self.topDepth_m = topDepth_m
        self.length_m = length_m
        self.outerDiameter_m = outerDiameter_m
        self.innerDiameter_m = innerDiameter_m
        self.toolJointOD_m = toolJointOD_m
        self.jointLength_m = jointLength_m
        self.grade = grade
        self.steelDensity_kg_per_m3 = steelDensity_kg_per_m3
        self.unitWeight_kg_per_m = unitWeight_kg_per_m
        self.internalRoughness_m = internalRoughness_m
        self.project = project
    }
}
