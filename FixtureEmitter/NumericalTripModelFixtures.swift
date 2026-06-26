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
//      "output":  { steps: [ { bitMD_m, ..., layers:{pocket,annulus,string},
//                              totals:{pocket,annulus,string} }, ... ] }
//    }
//
//  Each step emits the 28 scalar TripStep fields plus the full per-step fluid
//  column (`layers` — every LayerRow field incl. colour) and `totals`.
//  TripInput closures + T&D inputs remain omitted (T&D has its own fixtures).
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
        // Optional fluid color (0..1). When set, the pumped fluid carries this
        // color into the layer column (also gates merge-by-color behaviour).
        var colorR: Double? = nil
        var colorG: Double? = nil
        var colorB: Double? = nil
        var colorA: Double? = nil
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
        // Annulus mixing / density-inversion controls (0 = legacy/off)
        var annulusMixingLength_m: Double = 0
        var annulusInversionThreshold_kgpm3: Double = 0
        var annulusInversionMixZone_m: Double = 0
        var annulusSymmetricMixZone_m: Double = 0
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

    /// Multi-fluid schedule (≥2 distinct, coloured fluids pumped from surface):
    /// exercises layer ordering, colour propagation, and merge-by-colour in the
    /// annulus column as the bit trips out.
    func testEmit_vertical_multiFluid_schedule() throws {
        try emit(CaseSpec(
            name: "vertical_multiFluid_schedule",
            surveys: Self.verticalSurveys,
            annulus: Self.stdAnnulus,
            drillString: Self.stdDrillString,
            fluidSchedule: [
                // Heavy coloured pill first, then lighter base mud indefinitely.
                FluidEntrySpec(density_kgpm3: 1600, volume_m3: 6.0,
                               pv_cP: 35, yp_Pa: 12,
                               colorR: 0.85, colorG: 0.20, colorB: 0.10, colorA: 1.0),
                FluidEntrySpec(density_kgpm3: 1450, volume_m3: 8.0,
                               pv_cP: 28, yp_Pa: 9,
                               colorR: 0.20, colorG: 0.45, colorB: 0.85, colorA: 1.0),
                FluidEntrySpec(density_kgpm3: 1300, volume_m3: .infinity,
                               pv_cP: 22, yp_Pa: 7,
                               colorR: 0.30, colorG: 0.65, colorB: 0.30, colorA: 1.0),
            ],
            input: TripInputSpec(
                shoeTVD_m: 1500,
                shoeMD_m: 1500,
                startBitMD_m: 3000,
                endMD_m: 1800,
                crackFloat_kPa: 1500,
                noFloat: false,
                baseMudDensity_kgpm3: 1300,
                backfillDensity_kgpm3: 1300,
                targetESDAtTD_kgpm3: 1300)))
    }

    /// Build-to-horizontal trajectory (TVD ≠ MD past the kickoff): exercises the
    /// MD↔TVD mapping inside the layer/hydrostatic snapshots.
    func testEmit_deviated_singleFluid_withFloat() throws {
        try emit(CaseSpec(
            name: "deviated_singleFluid_withFloat",
            surveys: [
                SurveySpec(md: 0,    tvd: 0),
                SurveySpec(md: 500,  tvd: 500),
                SurveySpec(md: 1000, tvd: 950),
                SurveySpec(md: 1500, tvd: 1300),
                SurveySpec(md: 3000, tvd: 1300),
            ],
            annulus: [
                AnnulusSpec(topDepth_m: 0, length_m: 3000,
                            innerDiameter_m: 0.222, outerDiameter_m: 0.127,
                            density_kg_per_m3: 1300),
            ],
            drillString: Self.stdDrillString,
            input: TripInputSpec(
                shoeTVD_m: 1300,
                shoeMD_m: 1500,
                startBitMD_m: 3000,
                endMD_m: 1800,
                crackFloat_kPa: 1500,
                noFloat: false,
                baseMudDensity_kgpm3: 1300,
                backfillDensity_kgpm3: 1300,
                targetESDAtTD_kgpm3: 1300)))
    }

    /// Heavy kill pill backfilled on top of lighter mud with the density-inversion
    /// rectifier enabled: triggers the buoyancy-merge path that blends unstable
    /// adjacent layers in the annulus column.
    func testEmit_vertical_killPill_densityInversion() throws {
        try emit(CaseSpec(
            name: "vertical_killPill_densityInversion",
            surveys: Self.verticalSurveys,
            annulus: Self.stdAnnulus,
            drillString: Self.stdDrillString,
            input: TripInputSpec(
                shoeTVD_m: 1500,
                shoeMD_m: 1500,
                startBitMD_m: 3000,
                endMD_m: 1800,
                crackFloat_kPa: 1500,
                noFloat: false,
                // Backfill heavier than the base mud already in the hole → the
                // column inverts (heavy over light) and the rectifier must merge.
                baseMudDensity_kgpm3: 1300,
                backfillDensity_kgpm3: 1700,
                baseMudPV_cP: 22, baseMudYP_Pa: 7,
                targetESDAtTD_kgpm3: 1300,
                // Enable inversion rectification + symmetric boundary smoothing.
                annulusInversionThreshold_kgpm3: 50,
                annulusInversionMixZone_m: 30,
                annulusSymmetricMixZone_m: 10)))
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
            annulusMixingLength_m: spec.input.annulusMixingLength_m,
            annulusInversionThreshold_kgpm3: spec.input.annulusInversionThreshold_kgpm3,
            annulusInversionMixZone_m: spec.input.annulusInversionMixZone_m,
            annulusSymmetricMixZone_m: spec.input.annulusSymmetricMixZone_m,
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
                color: Self.colorRGBA($0.colorR, $0.colorG, $0.colorB, $0.colorA),
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
            "fluidSchedule": spec.fluidSchedule.map { e -> [String: Any] in
                var d: [String: Any] = [
                    "density_kgpm3": e.density_kgpm3,
                    "volume_m3": (e.volume_m3.isInfinite
                                  ? "infinity" as Any
                                  : e.volume_m3 as Any),
                    "pv_cP": e.pv_cP,
                    "yp_Pa": e.yp_Pa,
                ]
                if let c = Self.encodeColor(Self.colorRGBA(e.colorR, e.colorG, e.colorB, e.colorA)) {
                    d["color"] = c
                }
                return d
            },
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
                "annulusMixingLength_m": spec.input.annulusMixingLength_m,
                "annulusInversionThreshold_kgpm3": spec.input.annulusInversionThreshold_kgpm3,
                "annulusInversionMixZone_m": spec.input.annulusInversionMixZone_m,
                "annulusSymmetricMixZone_m": spec.input.annulusSymmetricMixZone_m,
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
            // Per-step fluid column (full LayerRow fields incl. colour) + totals.
            "layers": [
                "pocket": s.layersPocket.map { Self.encodeLayerRow($0) },
                "annulus": s.layersAnnulus.map { Self.encodeLayerRow($0) },
                "string": s.layersString.map { Self.encodeLayerRow($0) },
            ],
            "totals": [
                "pocket": Self.encodeTotals(s.totalsPocket),
                "annulus": Self.encodeTotals(s.totalsAnnulus),
                "string": Self.encodeTotals(s.totalsString),
            ],
        ]
    }

    // MARK: - Layer / totals / colour encoders

    fileprivate static func colorRGBA(_ r: Double?, _ g: Double?, _ b: Double?,
                                      _ a: Double?) -> NumericalTripModel.ColorRGBA? {
        guard let r, let g, let b else { return nil }
        return NumericalTripModel.ColorRGBA(r: r, g: g, b: b, a: a ?? 1)
    }

    fileprivate static func encodeColor(_ c: NumericalTripModel.ColorRGBA?) -> [String: Any]? {
        guard let c else { return nil }
        return ["r": c.r, "g": c.g, "b": c.b, "a": c.a]
    }

    fileprivate static func encodeLayerRow(_ r: NumericalTripModel.LayerRow) -> [String: Any] {
        var d: [String: Any] = [
            "side": r.side,
            "topMD": r.topMD,
            "bottomMD": r.bottomMD,
            "topTVD": r.topTVD,
            "bottomTVD": r.bottomTVD,
            "rho_kgpm3": r.rho_kgpm3,
            "deltaHydroStatic_kPa": r.deltaHydroStatic_kPa,
            "volume_m3": r.volume_m3,
            "pv_cP": r.pv_cP,
            "yp_Pa": r.yp_Pa,
        ]
        if let c = encodeColor(r.color) { d["color"] = c }
        return d
    }

    fileprivate static func encodeTotals(_ t: NumericalTripModel.Totals) -> [String: Any] {
        ["count": t.count, "tvd_m": t.tvd_m, "deltaP_kPa": t.deltaP_kPa]
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
