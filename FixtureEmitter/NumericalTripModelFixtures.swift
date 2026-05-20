//
//  NumericalTripModelFixtures.swift
//
//  Fixture emitter for the trip-out simulator (NumericalTripModel.run).
//
//  Each XCTestCase method emits one fixture. Run via:
//    xcodebuild test -scheme FixtureEmitter \
//      -only-testing:FixtureEmitter/NumericalTripModelFixtures
//
//  Output JSON shape:
//    {
//      "service": "NumericalTripModel",
//      "case":    "<slug>",
//      "input":   { surveys, annulus, drillString, tripInput, fluidSchedule? },
//      "output":  { steps: [ { bitMD_m, bitTVD_m, SABP_kPa, ESDatTD_kgpm3, ... }, ... ] }
//    }
//
//  Output captures only TripStep scalar fields; LayerRow / Totals arrays are
//  large and can be added in a follow-up case if regression value warrants it.
//

import Foundation
import XCTest

@testable import Josh_Well_Control_for_Mac

final class NumericalTripModelFixtures: XCTestCase {

    // MARK: - Survey / geometry specs

    fileprivate struct SurveySpec {
        var md: Double
        var tvd: Double
    }

    fileprivate struct AnnulusSpec {
        var topDepth_m: Double
        var length_m: Double
        var innerDiameter_m: Double
        var outerDiameter_m: Double
        var density_kg_per_m3: Double = 1100
    }

    fileprivate struct DrillStringSpec {
        var topDepth_m: Double
        var length_m: Double
        var outerDiameter_m: Double
        var innerDiameter_m: Double
    }

    fileprivate struct FluidEntrySpec {
        var density_kgpm3: Double
        var volume_m3: Double
        var pv_cP: Double = 0
        var yp_Pa: Double = 0
    }

    /// Mirrors TripInput's scalar surface — closures and T&D inputs are omitted
    /// from fixtures (T&D has its own fixture target).
    fileprivate struct TripInputSpec {
        var shoeTVD_m: Double
        var shoeMD_m: Double = 0
        var startBitMD_m: Double
        var endMD_m: Double
        var crackFloat_kPa: Double = 1500
        var noFloat: Bool = false
        var step_m: Double = 100
        var baseMudDensity_kgpm3: Double
        var backfillDensity_kgpm3: Double
        var backfillPV_cP: Double = 0
        var backfillYP_Pa: Double = 0
        var baseMudPV_cP: Double = 0
        var baseMudYP_Pa: Double = 0
        var fixedBackfillVolume_m3: Double = 0
        var switchToBaseAfterFixed: Bool = true
        var targetESDAtTD_kgpm3: Double
        var initialSABP_kPa: Double = 0
        var holdSABPOpen: Bool = false
        var tripSpeed_m_per_s: Double = 0.5
        var eccentricityFactor: Double = 1.0
    }

    fileprivate struct CaseSpec {
        var name: String
        var surveys: [SurveySpec]
        var annulus: [AnnulusSpec]
        var drillString: [DrillStringSpec]
        var fluidSchedule: [FluidEntrySpec] = []
        var input: TripInputSpec
    }

    // MARK: - Reusable inputs

    /// Vertical 3000 m well: identity TVD mapping.
    fileprivate static let verticalSurveys: [SurveySpec] = [
        SurveySpec(md: 0,    tvd: 0),
        SurveySpec(md: 3000, tvd: 3000),
    ]

    /// Single 12¼" hole (ID = 0.311 m) around 5" DP (OD = 0.127 m).
    fileprivate static let stdAnnulus: [AnnulusSpec] = [
        AnnulusSpec(topDepth_m: 0, length_m: 3000,
                    innerDiameter_m: 0.311, outerDiameter_m: 0.127,
                    density_kg_per_m3: 1300),
    ]

    /// Single 5" DP all the way to TD (OD 0.127 m, ID 0.108 m).
    fileprivate static let stdDrillString: [DrillStringSpec] = [
        DrillStringSpec(topDepth_m: 0, length_m: 3000,
                        outerDiameter_m: 0.127, innerDiameter_m: 0.108),
    ]

    // MARK: - Test methods (one per case)

    func testEmit_vertical_singleFluid_noFloat_basic() throws {
        try emit(CaseSpec(
            name: "vertical_singleFluid_noFloat_basic",
            surveys: Self.verticalSurveys,
            annulus: Self.stdAnnulus,
            drillString: Self.stdDrillString,
            input: TripInputSpec(
                shoeTVD_m: 1500,
                shoeMD_m: 1500,
                startBitMD_m: 3000,
                endMD_m: 2000,
                noFloat: true,
                baseMudDensity_kgpm3: 1300,
                backfillDensity_kgpm3: 1300,
                targetESDAtTD_kgpm3: 1300)))
    }

    func testEmit_vertical_singleFluid_withFloat_basic() throws {
        try emit(CaseSpec(
            name: "vertical_singleFluid_withFloat_basic",
            surveys: Self.verticalSurveys,
            annulus: Self.stdAnnulus,
            drillString: Self.stdDrillString,
            input: TripInputSpec(
                shoeTVD_m: 1500,
                shoeMD_m: 1500,
                startBitMD_m: 3000,
                endMD_m: 2000,
                crackFloat_kPa: 1500,
                noFloat: false,
                baseMudDensity_kgpm3: 1300,
                backfillDensity_kgpm3: 1300,
                targetESDAtTD_kgpm3: 1300)))
    }

    // MARK: - Emit driver

    fileprivate func emit(_ spec: CaseSpec) throws {
        // Build @Model objects on the main actor (XCTest default with
        // SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor).
        let project = ProjectState()
        let annulus = spec.annulus.map {
            AnnulusSection(name: "Ann",
                           topDepth_m: $0.topDepth_m,
                           length_m: $0.length_m,
                           innerDiameter_m: $0.innerDiameter_m,
                           outerDiameter_m: $0.outerDiameter_m,
                           density_kg_per_m3: $0.density_kg_per_m3)
        }
        let drillString = spec.drillString.map {
            DrillStringSection(name: "DS",
                               topDepth_m: $0.topDepth_m,
                               length_m: $0.length_m,
                               outerDiameter_m: $0.outerDiameter_m,
                               innerDiameter_m: $0.innerDiameter_m)
        }
        project.annulus = annulus
        project.drillString = drillString

        // TVD mapper: linear interp from survey stations.
        let mds = spec.surveys.map(\.md)
        let tvds = spec.surveys.map(\.tvd)
        let tvdOfMd: @Sendable (Double) -> Double = { md in
            Self.linearInterp(md, mds: mds, tvds: tvds)
        }

        // Geometry from project sections; pipe-bottom = startBitMD.
        let geom = ProjectGeometryService(
            annulus: annulus,
            string: drillString,
            currentStringBottomMD: spec.input.startBitMD_m,
            mdToTvd: tvdOfMd)

        // Build TripInput
        var tripInput = NumericalTripModel.TripInput(
            tvdOfMd: tvdOfMd,
            shoeTVD_m: spec.input.shoeTVD_m,
            shoeMD_m: spec.input.shoeMD_m,
            startBitMD_m: spec.input.startBitMD_m,
            endMD_m: spec.input.endMD_m,
            crackFloat_kPa: spec.input.crackFloat_kPa,
            noFloat: spec.input.noFloat,
            step_m: spec.input.step_m,
            baseMudDensity_kgpm3: spec.input.baseMudDensity_kgpm3,
            backfillDensity_kgpm3: spec.input.backfillDensity_kgpm3,
            backfillPV_cP: spec.input.backfillPV_cP,
            backfillYP_Pa: spec.input.backfillYP_Pa,
            baseMudPV_cP: spec.input.baseMudPV_cP,
            baseMudYP_Pa: spec.input.baseMudYP_Pa,
            fixedBackfillVolume_m3: spec.input.fixedBackfillVolume_m3,
            switchToBaseAfterFixed: spec.input.switchToBaseAfterFixed,
            targetESDAtTD_kgpm3: spec.input.targetESDAtTD_kgpm3,
            initialSABP_kPa: spec.input.initialSABP_kPa,
            holdSABPOpen: spec.input.holdSABPOpen,
            tripSpeed_m_per_s: spec.input.tripSpeed_m_per_s,
            eccentricityFactor: spec.input.eccentricityFactor)
        tripInput.fluidSchedule = spec.fluidSchedule.map {
            NumericalTripModel.FluidScheduleEntry(
                density_kgpm3: $0.density_kgpm3,
                volume_m3: $0.volume_m3,
                pv_cP: $0.pv_cP,
                yp_Pa: $0.yp_Pa)
        }

        // ProjectSnapshot from finalized layers (empty if no FinalFluidLayers
        // are present — a vertical single-fluid well doesn't need them since
        // backfill alone defines the annulus seed when ProjectSnapshot is empty).
        let snapshot = NumericalTripModel.ProjectSnapshot(from: project)

        // Run
        let model = NumericalTripModel()
        let steps = model.run(tripInput, geom: geom, projectSnapshot: snapshot)

        // Encode input
        let inputJSON: [String: Any] = [
            "surveys": spec.surveys.map { ["md": $0.md, "tvd": $0.tvd] },
            "annulus": spec.annulus.map { [
                "topDepth_m": $0.topDepth_m,
                "length_m": $0.length_m,
                "innerDiameter_m": $0.innerDiameter_m,
                "outerDiameter_m": $0.outerDiameter_m,
                "density_kg_per_m3": $0.density_kg_per_m3,
            ] },
            "drillString": spec.drillString.map { [
                "topDepth_m": $0.topDepth_m,
                "length_m": $0.length_m,
                "outerDiameter_m": $0.outerDiameter_m,
                "innerDiameter_m": $0.innerDiameter_m,
            ] },
            "fluidSchedule": spec.fluidSchedule.map { [
                "density_kgpm3": $0.density_kgpm3,
                "volume_m3": ($0.volume_m3.isInfinite
                              ? "infinity" as Any
                              : $0.volume_m3 as Any),
                "pv_cP": $0.pv_cP,
                "yp_Pa": $0.yp_Pa,
            ] },
            "tripInput": [
                "shoeTVD_m": spec.input.shoeTVD_m,
                "shoeMD_m": spec.input.shoeMD_m,
                "startBitMD_m": spec.input.startBitMD_m,
                "endMD_m": spec.input.endMD_m,
                "crackFloat_kPa": spec.input.crackFloat_kPa,
                "noFloat": spec.input.noFloat,
                "step_m": spec.input.step_m,
                "baseMudDensity_kgpm3": spec.input.baseMudDensity_kgpm3,
                "backfillDensity_kgpm3": spec.input.backfillDensity_kgpm3,
                "backfillPV_cP": spec.input.backfillPV_cP,
                "backfillYP_Pa": spec.input.backfillYP_Pa,
                "baseMudPV_cP": spec.input.baseMudPV_cP,
                "baseMudYP_Pa": spec.input.baseMudYP_Pa,
                "fixedBackfillVolume_m3": spec.input.fixedBackfillVolume_m3,
                "switchToBaseAfterFixed": spec.input.switchToBaseAfterFixed,
                "targetESDAtTD_kgpm3": spec.input.targetESDAtTD_kgpm3,
                "initialSABP_kPa": spec.input.initialSABP_kPa,
                "holdSABPOpen": spec.input.holdSABPOpen,
                "tripSpeed_m_per_s": spec.input.tripSpeed_m_per_s,
                "eccentricityFactor": spec.input.eccentricityFactor,
            ],
        ]

        // Encode output (TripStep scalars only)
        let stepsJSON: [[String: Any]] = steps.map { Self.encodeStep($0) }

        try FixtureWriter.write(
            service: "NumericalTripModel",
            caseName: spec.name,
            input: inputJSON,
            output: ["steps": stepsJSON])
    }

    fileprivate static func encodeStep(_ s: NumericalTripModel.TripStep) -> [String: Any] {
        return [
            "bitMD_m": s.bitMD_m,
            "bitTVD_m": s.bitTVD_m,
            "SABP_kPa": s.SABP_kPa,
            "SABP_kPa_Raw": s.SABP_kPa_Raw,
            "ESDatTD_kgpm3": s.ESDatTD_kgpm3,
            "ESDatControl_kgpm3": s.ESDatControl_kgpm3,
            "ESDatBit_kgpm3": s.ESDatBit_kgpm3,
            "backfillRemaining_m3": s.backfillRemaining_m3,
            "swabDropToBit_kPa": s.swabDropToBit_kPa,
            "SABP_Dynamic_kPa": s.SABP_Dynamic_kPa,
            "floatState": s.floatState,
            "stepBackfill_m3": s.stepBackfill_m3,
            "cumulativeBackfill_m3": s.cumulativeBackfill_m3,
            "expectedFillIfClosed_m3": s.expectedFillIfClosed_m3,
            "expectedFillIfOpen_m3": s.expectedFillIfOpen_m3,
            "slugContribution_m3": s.slugContribution_m3,
            "cumulativeSlugContribution_m3": s.cumulativeSlugContribution_m3,
            "pitGain_m3": s.pitGain_m3,
            "cumulativePitGain_m3": s.cumulativePitGain_m3,
            "surfaceTankDelta_m3": s.surfaceTankDelta_m3,
            "cumulativeSurfaceTankDelta_m3": s.cumulativeSurfaceTankDelta_m3,
            "pocketInflow_m3": s.pocketInflow_m3,
            "pocketInflowDensity_kgpm3": s.pocketInflowDensity_kgpm3,
            "pocketFromAnnulus_m3": s.pocketFromAnnulus_m3,
            "pocketFromAnnulusDensity_kgpm3": s.pocketFromAnnulusDensity_kgpm3,
            "pocketFromString_m3": s.pocketFromString_m3,
            "pocketFromStringDensity_kgpm3": s.pocketFromStringDensity_kgpm3,
            "cumulativePocketInflow_m3": s.cumulativePocketInflow_m3,
        ]
    }

    fileprivate static func linearInterp(_ md: Double,
                                         mds: [Double],
                                         tvds: [Double]) -> Double {
        guard let first = mds.first, let last = mds.last else { return md }
        if md <= first { return tvds.first! }
        if md >= last  { return tvds.last!  }
        for i in 0..<(mds.count - 1) {
            if md >= mds[i] && md <= mds[i+1] {
                let t = (md - mds[i]) / max(mds[i+1] - mds[i], 1e-12)
                return tvds[i] + t * (tvds[i+1] - tvds[i])
            }
        }
        return tvds.last!
    }
}
