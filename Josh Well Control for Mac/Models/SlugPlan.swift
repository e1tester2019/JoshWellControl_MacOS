//
//  SlugPlan.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-02.
//


import Foundation
import SwiftData

// MARK: - Slug Plan

@Model
final class SlugPlan {
    var id: UUID = UUID()
    var name: String = "Slug Plan"

    /// Base mud density the slug is compared against (kg/m³)
    var baseMudDensity_kg_per_m3: Double = 1200

    /// Optional notes (for ops program export)
    var notes: String? = nil

    // Relationship back to project (must match internal _slug property)
    @Relationship(deleteRule: .cascade, inverse: \ProjectState._slug)
    var project: ProjectState?

    /// One or more slug steps (e.g., a viscous spacer + heavy slug)
    @Relationship(deleteRule: .cascade, inverse: \SlugStep.plan)
    var steps: [SlugStep]?

    init() {}

    // MARK: - Evaluation helpers

    /// Net hydrostatic change at a given TVD compared to uniform base mud (kPa).
    /// Positive means pressure increase; negative means reduction.
    func deltaHydrostatic_kPa(atTVD tvd_m: Double) -> Double {
        let g = 9.80665
        // Sum the contribution from each step where the step covers that TVD
        let sumPa = (steps ?? []).reduce(0.0) { acc, step in
            acc + step.deltaPressure_Pa(atTVD: tvd_m, baseMudDensity_kg_per_m3: baseMudDensity_kg_per_m3, g: g)
        }
        return sumPa / 1000.0
    }

    /// Convenience: the pressure window shift at a casing shoe depth (kPa)
    func deltaAtShoe_kPa(shoeTVD_m: Double) -> Double {
        deltaHydrostatic_kPa(atTVD: shoeTVD_m)
    }
}

// MARK: - Slug Step

@Model
final class SlugStep {
    var id: UUID = UUID()
    var name: String = ""

    enum Placement: Int, Codable { case inString = 0, inAnnulus }
    var placementRaw: Int = Placement.inString.rawValue

    /// Slug density (kg/m³) and optional rheology hints
    var density_kg_per_m3: Double = 0.0
    var pv_Pa_s: Double? = nil        // optional Plastic Viscosity
    var yp_Pa: Double? = nil          // optional Yield Point

    /// Geometry along well path (measured)
    var topMD_m: Double = 0.0         // where slug starts (top)
    var length_m: Double = 0.0        // slug length along MD

    /// If you have TVD mapping available, you can set these directly.
    /// If left as nil, helpers can approximate TVD ≈ MD for vertical sections.
    var topTVD_m: Double?
    var bottomTVD_m: Double?

    /// Optional pump rate for ops reference (m³/min)
    var pumpRate_m3_per_min: Double? = nil

    // Relationship back to plan (inverse declared on parent side only)
    var plan: SlugPlan?

    init(
        name: String,
        placement: Placement = .inString,
        density_kg_per_m3: Double,
        topMD_m: Double,
        length_m: Double,
        topTVD_m: Double? = nil,
        bottomTVD_m: Double? = nil,
        pv_Pa_s: Double? = nil,
        yp_Pa: Double? = nil,
        pumpRate_m3_per_min: Double? = nil
    ) {
        self.name = name
        self.placementRaw = placement.rawValue
        self.density_kg_per_m3 = density_kg_per_m3
        self.topMD_m = topMD_m
        self.length_m = length_m
        self.topTVD_m = topTVD_m
        self.bottomTVD_m = bottomTVD_m
        self.pv_Pa_s = pv_Pa_s
        self.yp_Pa = yp_Pa
        self.pumpRate_m3_per_min = pumpRate_m3_per_min
    }

    // MARK: - Convenience & derived

    @Transient var placement: Placement {
        get { Placement(rawValue: placementRaw) ?? .inString }
        set { placementRaw = newValue.rawValue }
    }

    @Transient var bottomMD_m: Double { topMD_m + length_m }

    /// Preferred TVD span if explicitly set; otherwise falls back to MD span.
    @Transient var tvdSpan: (top: Double, bottom: Double) {
        if let t = topTVD_m, let b = bottomTVD_m { return (min(t,b), max(t,b)) }
        // Approximation when TVD not provided
        return (topMD_m, topMD_m + length_m)
    }

    // MARK: - Pressure effect

    /// Delta pressure at a given TVD vs base mud (Pa).
    /// For a TVD inside this slug, ΔP = (ρ_slug − ρ_base)*g*ΔTVD_covered.
    func deltaPressure_Pa(atTVD tvd_m: Double, baseMudDensity_kg_per_m3: Double, g: Double) -> Double {
        let (t, b) = tvdSpan
        guard tvd_m >= t else { return 0 }                 // above slug: no contribution
        let covered = min(tvd_m, b) - t                    // TVD of slug column above the point
        guard covered > 0 else { return 0 }
        let dRho = density_kg_per_m3 - baseMudDensity_kg_per_m3
        return dRho * g * covered
    }
}

