//
//  BackfillPlan.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-02.
//


import Foundation
import SwiftData

// MARK: - Backfill Plan

@Model
final class BackfillPlan {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = "Backfill Plan"

    /// The default fluid used for backfill (kg/m³)
    var fluidDensity_kg_per_m3: Double = 1200

    /// Safety overfill as a fraction of computed geometric volume (e.g., 0.05 = +5%)
    var overfillFrac: Double = 0.0

    /// Optional notes for program export
    var notes: String? = nil

    // Relationship back to project (must match internal _backfill property)
    @Relationship(deleteRule: .cascade, inverse: \ProjectState._backfill)
    var project: ProjectState?

    /// Rule set—ordered. First matching rule is used.
    @Relationship(deleteRule: .cascade)
    var rules: [BackfillRule] = []

    init() {}

    // MARK: - Core helpers

    /// Geometric backfill volume for a pulled length in a given annulus (m³)
    /// area = cross-sectional flow area of the relevant annulus segment (m²)
    func geometricVolume_m3(pulledLength_m: Double, annulusArea_m2: Double) -> Double {
        max(pulledLength_m, 0) * max(annulusArea_m2, 0)
    }

    /// Recommended backfill volume including overfill (m³)
    func recommendedVolume_m3(pulledLength_m: Double,
                              annulusArea_m2: Double) -> Double {
        let v = geometricVolume_m3(pulledLength_m: pulledLength_m, annulusArea_m2: annulusArea_m2)
        return v * (1.0 + overfillFrac)
    }

    /// Volume to pump for a stand (m³) using either a rule or pure geometry.
    /// - Parameters:
    ///   - standLength_m: typical stand length (m)
    ///   - mdTop_m: MD at top of the stand before pulling (for rule matching)
    ///   - annulusArea_m2: local annulus area around the stand (m²)
    func volumeForStand_m3(standLength_m: Double,
                           mdTop_m: Double,
                           annulusArea_m2: Double) -> Double {
        // If a matching rule applies, use it; else fall back to geometry + overfill
        if let rule = rule(forMD: mdTop_m) {
            return rule.volumeForStand_m3(standLength_m: standLength_m,
                                          annulusArea_m2: annulusArea_m2,
                                          plan: self)
        }
        return recommendedVolume_m3(pulledLength_m: standLength_m, annulusArea_m2: annulusArea_m2)
    }

    /// Returns the first rule whose MD range contains the given MD.
    func rule(forMD md_m: Double) -> BackfillRule? {
        rules.first { $0.mdRangeContains(md_m) }
    }
}

// MARK: - Backfill Rule

@Model
final class BackfillRule {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String

    /// MD range where this rule applies (inclusive of bounds)
    var fromMD_m: Double
    var toMD_m: Double

    /// Strategy for computing the volume
    enum Strategy: Int, Codable {
        /// Compute by geometry (annulus area × pulled length) with plan overfill.
        case geometric = 0
        /// Fixed volume per stand (m³/stand), ignores annulus area.
        case fixedPerStand
        /// Volume per meter pulled (m³/m): v = rate * pulledLength.
        case perMeter
    }
    var strategyRaw: Int = Strategy.geometric.rawValue

    /// Parameters for strategies (only one used depending on `strategy`)
    var fixedVolumePerStand_m3: Double = 0
    var volumePerMeter_m3_per_m: Double = 0

    /// Optional override for fluid density for this rule (kg/m³); if nil, use plan default
    var fluidDensityOverride_kg_per_m3: Double?

    init(name: String,
         fromMD_m: Double,
         toMD_m: Double,
         strategy: Strategy = .geometric,
         fixedVolumePerStand_m3: Double = 0,
         volumePerMeter_m3_per_m: Double = 0,
         fluidDensityOverride_kg_per_m3: Double? = nil) {
        self.name = name
        self.fromMD_m = min(fromMD_m, toMD_m)
        self.toMD_m = max(fromMD_m, toMD_m)
        self.strategyRaw = strategy.rawValue
        self.fixedVolumePerStand_m3 = fixedVolumePerStand_m3
        self.volumePerMeter_m3_per_m = volumePerMeter_m3_per_m
        self.fluidDensityOverride_kg_per_m3 = fluidDensityOverride_kg_per_m3
    }

    // Convenience
    @Transient var strategy: Strategy {
        get { Strategy(rawValue: strategyRaw) ?? .geometric }
        set { strategyRaw = newValue.rawValue }
    }

    func mdRangeContains(_ md: Double) -> Bool { md >= fromMD_m && md <= toMD_m }

    /// Compute the volume for a stand based on the rule
    func volumeForStand_m3(standLength_m: Double,
                           annulusArea_m2: Double,
                           plan: BackfillPlan) -> Double {
        switch strategy {
        case .geometric:
            return plan.recommendedVolume_m3(pulledLength_m: standLength_m, annulusArea_m2: annulusArea_m2)
        case .fixedPerStand:
            return fixedVolumePerStand_m3
        case .perMeter:
            return max(standLength_m, 0) * max(volumePerMeter_m3_per_m, 0)
        }
    }

    /// Density used when pumping for this rule (kg/m³)
    @Transient var effectiveDensity_kg_per_m3: Double {
        fluidDensityOverride_kg_per_m3 ?? 0
    }
}

