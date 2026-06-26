//
//  CementJobFixtures.swift
//
//  Fixture emitter for CementJob / CementJobStage volume + tonnage + water math.
//
//  Lives in the XCTest FixtureEmitter (not SwiftFixtureCLI) because the real
//  calculation is @Model-coupled: CementJob.recalculateVolumes() reads
//  project.annulus / project.drillString and calls
//  AnnulusSection.effectiveAnnularVolume(with:). Stubbing that would re-derive
//  the engine and risk emitting non-golden values, so we run the real classes.
//
//  Each case pins: cased vs open-hole volume split, open-hole excess,
//  per-stage tonnage (volume ÷ yield) and mix water (tonnage × ratio) from
//  CementJobStage.updateCalculations, plus the job's aggregate @Transient totals
//  (displacement, total mix water, total water usage) and the legacy
//  tonnageFromVolume / mixWaterFromTonnage helpers.
//
//  Output JSON shape:
//    {
//      "service": "CementJob",
//      "case":    "<slug>",
//      "input":   { annulus, drillString, job, stages },
//      "output":  { job: {…totals…}, stages: [ {…tonnage, mixWater_L…} ] }
//    }
//

import Foundation
import XCTest

@testable import Josh_Well_Control_for_Mac

final class CementJobFixtures: XCTestCase {

    // MARK: - Specs

    fileprivate struct AnnulusSpec {
        var topDepth_m: Double
        var length_m: Double
        var innerDiameter_m: Double   // hole / previous-casing ID
        var outerDiameter_m: Double   // casing OD being cemented
        var isCased: Bool
        var density_kg_per_m3: Double = 1100
    }

    fileprivate struct DSSpec {
        var topDepth_m: Double
        var length_m: Double
        var outerDiameter_m: Double   // casing OD
        var innerDiameter_m: Double   // casing ID
    }

    /// One pump stage. `yieldFactor` / `waterRatio_m3_per_tonne` drive
    /// updateCalculations for cement stages; ignored (and emitted as 0) for others.
    fileprivate struct StageSpec {
        var stageType: String   // preFlush|spacer|leadCement|tailCement|displacement|mudDisplacement
        var name: String
        var volume_m3: Double
        var density_kgm3: Double
        var plasticViscosity_cP: Double
        var yieldPoint_Pa: Double
        var yieldFactor: Double = 0.62
        var waterRatio_m3_per_tonne: Double = 0.48
    }

    fileprivate struct CaseSpec {
        var name: String
        var casingType: String   // surface|intermediate|production|liner
        var annulus: [AnnulusSpec]
        var drillString: [DSSpec]
        var topMD_m: Double
        var bottomMD_m: Double
        var floatCollarDepth_m: Double
        var excessPercent: Double
        var leadYieldFactor: Double = 0.62
        var leadMixWaterRatio: Double = 0.48
        var tailYieldFactor: Double = 0.62
        var tailMixWaterRatio: Double = 0.48
        var legacyYieldFactor: Double = 0.62
        var legacyMixWaterRatio: Double = 0.48
        var washUpVolume_m3: Double = 0
        var pumpOutVolume_m3: Double = 0
        var stages: [StageSpec]
    }

    // MARK: - Test methods

    /// Intermediate casing through a cased + open-hole column, lead+tail cement,
    /// open-hole excess, plus mud and water displacement.
    func testEmit_intermediate_casedAndOpenHole_leadTail() throws {
        try emit(CaseSpec(
            name: "intermediate_casedAndOpenHole_leadTail",
            casingType: "intermediate",
            annulus: [
                // Cased section (9⅝" csg in 13⅜" csg ID), then open hole (12¼" bit).
                AnnulusSpec(topDepth_m: 0, length_m: 1200,
                            innerDiameter_m: 0.3151, outerDiameter_m: 0.2445,
                            isCased: true, density_kg_per_m3: 1300),
                AnnulusSpec(topDepth_m: 1200, length_m: 800,
                            innerDiameter_m: 0.3112, outerDiameter_m: 0.2445,
                            isCased: false, density_kg_per_m3: 1300),
            ],
            drillString: [
                DSSpec(topDepth_m: 0, length_m: 2000,
                       outerDiameter_m: 0.2445, innerDiameter_m: 0.2205),
            ],
            topMD_m: 800,
            bottomMD_m: 2000,
            floatCollarDepth_m: 1980,
            excessPercent: 50,
            leadYieldFactor: 0.62, leadMixWaterRatio: 0.48,
            tailYieldFactor: 0.99, tailMixWaterRatio: 0.44,
            legacyYieldFactor: 0.62, legacyMixWaterRatio: 0.48,
            washUpVolume_m3: 1.5,
            pumpOutVolume_m3: 0.8,
            stages: [
                StageSpec(stageType: "preFlush", name: "Water Spacer",
                          volume_m3: 3.0, density_kgm3: 1000,
                          plasticViscosity_cP: 15, yieldPoint_Pa: 5),
                StageSpec(stageType: "leadCement", name: "Lead 1450",
                          volume_m3: 8.0, density_kgm3: 1450,
                          plasticViscosity_cP: 60, yieldPoint_Pa: 10,
                          yieldFactor: 0.62, waterRatio_m3_per_tonne: 0.48),
                StageSpec(stageType: "tailCement", name: "Tail 1900",
                          volume_m3: 4.0, density_kgm3: 1900,
                          plasticViscosity_cP: 80, yieldPoint_Pa: 15,
                          yieldFactor: 0.99, waterRatio_m3_per_tonne: 0.44),
                StageSpec(stageType: "mudDisplacement", name: "Mud Ahead",
                          volume_m3: 2.0, density_kgm3: 1300,
                          plasticViscosity_cP: 20, yieldPoint_Pa: 8),
                StageSpec(stageType: "displacement", name: "Water Displacement",
                          volume_m3: 14.0, density_kgm3: 1000,
                          plasticViscosity_cP: 20, yieldPoint_Pa: 8),
            ]))
    }

    /// Production casing, fully cased annulus: open-hole excess has NO effect
    /// (totalVolumeWithExcess == casedVolume). Lead+tail + water displacement.
    func testEmit_production_casedOnly_displacement() throws {
        try emit(CaseSpec(
            name: "production_casedOnly_displacement",
            casingType: "production",
            annulus: [
                AnnulusSpec(topDepth_m: 0, length_m: 2500,
                            innerDiameter_m: 0.2205, outerDiameter_m: 0.1778,
                            isCased: true, density_kg_per_m3: 1250),
            ],
            drillString: [
                DSSpec(topDepth_m: 0, length_m: 2500,
                       outerDiameter_m: 0.1778, innerDiameter_m: 0.1594),
            ],
            topMD_m: 1500,
            bottomMD_m: 2500,
            floatCollarDepth_m: 2480,
            excessPercent: 20,
            leadYieldFactor: 0.62, leadMixWaterRatio: 0.50,
            tailYieldFactor: 0.95, tailMixWaterRatio: 0.45,
            legacyYieldFactor: 0.62, legacyMixWaterRatio: 0.50,
            washUpVolume_m3: 1.0,
            pumpOutVolume_m3: 0.5,
            stages: [
                StageSpec(stageType: "spacer", name: "Chemical Wash",
                          volume_m3: 2.0, density_kgm3: 1050,
                          plasticViscosity_cP: 20, yieldPoint_Pa: 8),
                StageSpec(stageType: "leadCement", name: "Lead 1560",
                          volume_m3: 5.0, density_kgm3: 1560,
                          plasticViscosity_cP: 60, yieldPoint_Pa: 10,
                          yieldFactor: 0.62, waterRatio_m3_per_tonne: 0.50),
                StageSpec(stageType: "tailCement", name: "Tail 1920",
                          volume_m3: 6.0, density_kgm3: 1920,
                          plasticViscosity_cP: 80, yieldPoint_Pa: 15,
                          yieldFactor: 0.95, waterRatio_m3_per_tonne: 0.45),
                StageSpec(stageType: "displacement", name: "Water Displacement",
                          volume_m3: 18.0, density_kgm3: 1000,
                          plasticViscosity_cP: 20, yieldPoint_Pa: 8),
            ]))
    }

    /// Liner across open hole with heavy (100%) excess: exercises the open-hole
    /// excess multiplier on totalVolumeWithExcess and a single-cement stage.
    func testEmit_liner_openHole_heavyExcess() throws {
        try emit(CaseSpec(
            name: "liner_openHole_heavyExcess",
            casingType: "liner",
            annulus: [
                AnnulusSpec(topDepth_m: 1800, length_m: 800,
                            innerDiameter_m: 0.2159, outerDiameter_m: 0.1778,
                            isCased: false, density_kg_per_m3: 1350),
            ],
            drillString: [
                DSSpec(topDepth_m: 1800, length_m: 800,
                       outerDiameter_m: 0.1778, innerDiameter_m: 0.1594),
            ],
            topMD_m: 1800,
            bottomMD_m: 2600,
            floatCollarDepth_m: 2580,
            excessPercent: 100,
            leadYieldFactor: 0.66, leadMixWaterRatio: 0.52,
            tailYieldFactor: 0.66, tailMixWaterRatio: 0.52,
            legacyYieldFactor: 0.66, legacyMixWaterRatio: 0.52,
            washUpVolume_m3: 0.8,
            pumpOutVolume_m3: 0.4,
            stages: [
                StageSpec(stageType: "preFlush", name: "Spacer",
                          volume_m3: 2.5, density_kgm3: 1100,
                          plasticViscosity_cP: 15, yieldPoint_Pa: 5),
                StageSpec(stageType: "leadCement", name: "Liner Cement",
                          volume_m3: 7.0, density_kgm3: 1880,
                          plasticViscosity_cP: 70, yieldPoint_Pa: 12,
                          yieldFactor: 0.66, waterRatio_m3_per_tonne: 0.52),
                StageSpec(stageType: "displacement", name: "Water Displacement",
                          volume_m3: 9.0, density_kgm3: 1000,
                          plasticViscosity_cP: 20, yieldPoint_Pa: 8),
            ]))
    }

    // MARK: - Emit driver

    fileprivate func emit(_ spec: CaseSpec) throws {
        let project = ProjectState()
        let annulus = spec.annulus.map {
            AnnulusSection(name: "Ann",
                           topDepth_m: $0.topDepth_m,
                           length_m: $0.length_m,
                           innerDiameter_m: $0.innerDiameter_m,
                           outerDiameter_m: $0.outerDiameter_m,
                           isCased: $0.isCased,
                           density_kg_per_m3: $0.density_kg_per_m3)
        }
        let drillString = spec.drillString.map {
            DrillStringSection(name: "Casing",
                               topDepth_m: $0.topDepth_m,
                               length_m: $0.length_m,
                               outerDiameter_m: $0.outerDiameter_m,
                               innerDiameter_m: $0.innerDiameter_m)
        }
        project.annulus = annulus
        project.drillString = drillString

        let job = CementJob(
            name: spec.name,
            casingType: Self.casingType(spec.casingType),
            topMD_m: spec.topMD_m,
            bottomMD_m: spec.bottomMD_m,
            floatCollarDepth_m: spec.floatCollarDepth_m,
            leadExcessPercent: spec.excessPercent,
            leadTopMD_m: spec.topMD_m,
            leadBottomMD_m: spec.bottomMD_m,
            leadYieldFactor_m3_per_tonne: spec.leadYieldFactor,
            leadMixWaterRatio_m3_per_tonne: spec.leadMixWaterRatio,
            tailExcessPercent: spec.excessPercent,
            tailTopMD_m: spec.topMD_m,
            tailBottomMD_m: spec.bottomMD_m,
            tailYieldFactor_m3_per_tonne: spec.tailYieldFactor,
            tailMixWaterRatio_m3_per_tonne: spec.tailMixWaterRatio,
            washUpVolume_m3: spec.washUpVolume_m3,
            pumpOutVolume_m3: spec.pumpOutVolume_m3,
            excessPercent: spec.excessPercent,
            yieldFactor_m3_per_tonne: spec.legacyYieldFactor,
            mixWaterRatio_m3_per_tonne: spec.legacyMixWaterRatio,
            project: project)

        // Geometry-based cased / open-hole volume split + excess.
        job.recalculateVolumes()

        // Build stages, then run per-stage tonnage / mix-water calc.
        for s in spec.stages {
            let stage = CementJobStage(
                stageType: Self.stageType(s.stageType),
                name: s.name,
                volume_m3: s.volume_m3,
                density_kgm3: s.density_kgm3)
            stage.plasticViscosity_cP = s.plasticViscosity_cP
            stage.yieldPoint_Pa = s.yieldPoint_Pa
            job.addStage(stage)
            stage.updateCalculations(yieldFactor: s.yieldFactor,
                                     waterRatio_m3_per_tonne: s.waterRatio_m3_per_tonne)
        }

        // Legacy helper methods (tonnage ← yield, mix water ← ratio) on total volume.
        let legacyTonnage = job.tonnageFromVolume(job.totalVolumeWithExcess_m3)
        let legacyMixWater_L = job.mixWaterFromTonnage(legacyTonnage)

        // JSON encode
        let inputJSON: [String: Any] = [
            "annulus": spec.annulus.map { [
                "topDepth_m": $0.topDepth_m,
                "length_m": $0.length_m,
                "innerDiameter_m": $0.innerDiameter_m,
                "outerDiameter_m": $0.outerDiameter_m,
                "isCased": $0.isCased,
                "density_kg_per_m3": $0.density_kg_per_m3,
            ] },
            "drillString": spec.drillString.map { [
                "topDepth_m": $0.topDepth_m,
                "length_m": $0.length_m,
                "outerDiameter_m": $0.outerDiameter_m,
                "innerDiameter_m": $0.innerDiameter_m,
            ] },
            "job": [
                "name": spec.name,
                "casingType": spec.casingType,
                "topMD_m": spec.topMD_m,
                "bottomMD_m": spec.bottomMD_m,
                "floatCollarDepth_m": spec.floatCollarDepth_m,
                "excessPercent": spec.excessPercent,
                "leadYieldFactor_m3_per_tonne": spec.leadYieldFactor,
                "leadMixWaterRatio_m3_per_tonne": spec.leadMixWaterRatio,
                "tailYieldFactor_m3_per_tonne": spec.tailYieldFactor,
                "tailMixWaterRatio_m3_per_tonne": spec.tailMixWaterRatio,
                "yieldFactor_m3_per_tonne": spec.legacyYieldFactor,
                "mixWaterRatio_m3_per_tonne": spec.legacyMixWaterRatio,
                "washUpVolume_m3": spec.washUpVolume_m3,
                "pumpOutVolume_m3": spec.pumpOutVolume_m3,
            ],
            "stages": spec.stages.map { [
                "stageType": $0.stageType,
                "name": $0.name,
                "volume_m3": $0.volume_m3,
                "density_kgm3": $0.density_kgm3,
                "plasticViscosity_cP": $0.plasticViscosity_cP,
                "yieldPoint_Pa": $0.yieldPoint_Pa,
                "yieldFactor": $0.yieldFactor,
                "waterRatio_m3_per_tonne": $0.waterRatio_m3_per_tonne,
            ] },
        ]

        let outputJSON: [String: Any] = [
            "job": [
                "cementLength_m": job.cementLength_m,
                "casedVolume_m3": job.casedVolume_m3,
                "openHoleVolume_m3": job.openHoleVolume_m3,
                "excessVolume_m3": job.excessVolume_m3,
                "totalVolumeWithExcess_m3": job.totalVolumeWithExcess_m3,
                "leadCementVolume_m3": job.leadCementVolume_m3,
                "tailCementVolume_m3": job.tailCementVolume_m3,
                "totalCementVolume_m3": job.totalCementVolume_m3,
                "leadCementTonnage_t": job.leadCementTonnage_t,
                "tailCementTonnage_t": job.tailCementTonnage_t,
                "totalCementTonnage_t": job.totalCementTonnage_t,
                "leadMixWater_L": job.leadMixWater_L,
                "tailMixWater_L": job.tailMixWater_L,
                "totalMixWater_L": job.totalMixWater_L,
                "totalMixWater_m3": job.totalMixWater_m3,
                "mudDisplacementVolume_m3": job.mudDisplacementVolume_m3,
                "waterDisplacementVolume_m3": job.waterDisplacementVolume_m3,
                "displacementVolume_m3": job.displacementVolume_m3,
                "displacementVolume_L": job.displacementVolume_L,
                "totalWaterUsage_m3": job.totalWaterUsage_m3,
                "totalWaterUsage_L": job.totalWaterUsage_L,
                "legacyTonnageFromTotalVolume_t": legacyTonnage,
                "legacyMixWaterFromTonnage_L": legacyMixWater_L,
            ],
            "stages": job.sortedStages.map { Self.encodeStage($0) },
        ]

        try FixtureWriter.write(
            service: "CementJob",
            caseName: spec.name,
            input: inputJSON,
            output: outputJSON)
    }

    // MARK: - Helpers

    fileprivate static func encodeStage(_ s: CementJobStage) -> [String: Any] {
        var d: [String: Any] = [
            "orderIndex": s.orderIndex,
            "stageTypeRaw": s.stageTypeRaw,
            "stageType": Self.stageName(s.stageType),
            "name": s.name,
            "volume_m3": s.volume_m3,
            "density_kgm3": s.density_kgm3,
            "plasticViscosity_cP": s.plasticViscosity_cP,
            "yieldPoint_Pa": s.yieldPoint_Pa,
        ]
        if let t = s.tonnage_t { d["tonnage_t"] = t }
        if let w = s.mixWater_L { d["mixWater_L"] = w }
        return d
    }

    fileprivate static func casingType(_ s: String) -> CementJob.CasingType {
        switch s {
        case "surface":      return .surface
        case "production":   return .production
        case "liner":        return .liner
        default:             return .intermediate
        }
    }

    fileprivate static func stageType(_ s: String) -> CementJobStage.StageType {
        switch s {
        case "preFlush":         return .preFlush
        case "leadCement":       return .leadCement
        case "tailCement":       return .tailCement
        case "displacement":     return .displacement
        case "mudDisplacement":  return .mudDisplacement
        case "operation":        return .operation
        default:                 return .spacer
        }
    }

    fileprivate static func stageName(_ t: CementJobStage.StageType) -> String {
        switch t {
        case .preFlush:         return "preFlush"
        case .spacer:           return "spacer"
        case .leadCement:       return "leadCement"
        case .tailCement:       return "tailCement"
        case .displacement:     return "displacement"
        case .mudDisplacement:  return "mudDisplacement"
        case .operation:        return "operation"
        }
    }
}
