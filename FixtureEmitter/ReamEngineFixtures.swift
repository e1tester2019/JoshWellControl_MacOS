//
//  ReamEngineFixtures.swift
//
//  Fixture emitter for ReamEngine — wraps NumericalTripModel (ream out)
//  and TripInService (ream in), augmenting each step with APL from pumping.
//
//  Ream Out: SABP_Dynamic = max(0, SABP_static + swab - APL)
//  Ream In:  dynamicChoke = max(0, requiredChoke - APL - surge)
//

import Foundation
import XCTest

@testable import Josh_Well_Control_for_Mac

final class ReamEngineFixtures: XCTestCase {

    // MARK: - Shared geometry specs

    fileprivate struct AnnulusSpec {
        var topDepth_m: Double
        var length_m: Double
        var innerDiameter_m: Double
        var outerDiameter_m: Double
        var density_kg_per_m3: Double = 1100
    }

    fileprivate struct DSSpec {
        var topDepth_m: Double
        var length_m: Double
        var outerDiameter_m: Double
        var innerDiameter_m: Double
    }

    fileprivate struct SurveySpec {
        var md: Double
        var tvd: Double
    }

    // MARK: - Ream Out spec

    fileprivate struct ReamOutSpec {
        var name: String
        var annulus: [AnnulusSpec]
        var drillString: [DSSpec]
        var surveys: [SurveySpec]
        var startBitMD_m: Double
        var endMD_m: Double
        var controlMD_m: Double
        var step_m: Double = 100
        var baseMudDensity_kgpm3: Double
        var backfillDensity_kgpm3: Double
        var targetESDAtTD_kgpm3: Double
        var crackFloat_kPa: Double = 1500
        var pumpRate_m3perMin: Double
    }

    // MARK: - Ream In spec

    fileprivate struct PocketLayerSpec {
        var side: String
        var topMD: Double
        var bottomMD: Double
        var topTVD: Double
        var bottomTVD: Double
        var rho_kgpm3: Double
        var pv_cP: Double?
        var yp_Pa: Double?
    }

    fileprivate struct ReamInSpec {
        var name: String
        var annulus: [AnnulusSpec]
        var drillString: [DSSpec]
        var surveys: [SurveySpec]
        var startBitMD_m: Double
        var endBitMD_m: Double
        var controlMD_m: Double
        var step_m: Double = 100
        var pipeOD_m: Double = 0.127
        var pipeID_m: Double = 0.108
        var activeMudDensity_kgpm3: Double
        var baseMudDensity_kgpm3: Double
        var targetESD_kgpm3: Double
        var crackFloat_kPa: Double = 1500
        var isFloatedCasing: Bool = true
        var floatSubMD_m: Double = 0
        var pocketLayers: [PocketLayerSpec]
        var pumpRate_m3perMin: Double
    }

    // MARK: - Test methods — Ream Out

    func testEmit_reamOut_vertical_lowPumpRate() throws {
        try emitReamOut(ReamOutSpec(
            name: "reamOut_vertical_lowPumpRate",
            annulus: [AnnulusSpec(topDepth_m: 0, length_m: 3000,
                                  innerDiameter_m: 0.222,
                                  outerDiameter_m: 0.127,
                                  density_kg_per_m3: 1300)],
            drillString: [DSSpec(topDepth_m: 0, length_m: 3000,
                                 outerDiameter_m: 0.127,
                                 innerDiameter_m: 0.108)],
            surveys: [SurveySpec(md: 0, tvd: 0),
                      SurveySpec(md: 3000, tvd: 3000)],
            startBitMD_m: 3000,
            endMD_m: 2500,
            controlMD_m: 1500,
            baseMudDensity_kgpm3: 1300,
            backfillDensity_kgpm3: 1300,
            targetESDAtTD_kgpm3: 1300,
            pumpRate_m3perMin: 0.3))
    }

    func testEmit_reamOut_vertical_highPumpRate() throws {
        try emitReamOut(ReamOutSpec(
            name: "reamOut_vertical_highPumpRate",
            annulus: [AnnulusSpec(topDepth_m: 0, length_m: 3000,
                                  innerDiameter_m: 0.222,
                                  outerDiameter_m: 0.127,
                                  density_kg_per_m3: 1300)],
            drillString: [DSSpec(topDepth_m: 0, length_m: 3000,
                                 outerDiameter_m: 0.127,
                                 innerDiameter_m: 0.108)],
            surveys: [SurveySpec(md: 0, tvd: 0),
                      SurveySpec(md: 3000, tvd: 3000)],
            startBitMD_m: 3000,
            endMD_m: 2500,
            controlMD_m: 1500,
            baseMudDensity_kgpm3: 1300,
            backfillDensity_kgpm3: 1300,
            targetESDAtTD_kgpm3: 1300,
            pumpRate_m3perMin: 0.8))
    }

    // MARK: - Test methods — Ream In

    func testEmit_reamIn_vertical_lowPumpRate() throws {
        try emitReamIn(ReamInSpec(
            name: "reamIn_vertical_lowPumpRate",
            annulus: [AnnulusSpec(topDepth_m: 0, length_m: 3000,
                                  innerDiameter_m: 0.222,
                                  outerDiameter_m: 0.127,
                                  density_kg_per_m3: 1300)],
            drillString: [DSSpec(topDepth_m: 0, length_m: 3000,
                                 outerDiameter_m: 0.127,
                                 innerDiameter_m: 0.108)],
            surveys: [SurveySpec(md: 0, tvd: 0),
                      SurveySpec(md: 3000, tvd: 3000)],
            startBitMD_m: 1500,
            endBitMD_m: 3000,
            controlMD_m: 1500,
            activeMudDensity_kgpm3: 1300,
            baseMudDensity_kgpm3: 1300,
            targetESD_kgpm3: 1300,
            pocketLayers: [PocketLayerSpec(side: "annulus",
                                           topMD: 1500, bottomMD: 3000,
                                           topTVD: 1500, bottomTVD: 3000,
                                           rho_kgpm3: 1300,
                                           pv_cP: 25, yp_Pa: 8)],
            pumpRate_m3perMin: 0.3))
    }

    func testEmit_reamIn_vertical_highPumpRate() throws {
        try emitReamIn(ReamInSpec(
            name: "reamIn_vertical_highPumpRate",
            annulus: [AnnulusSpec(topDepth_m: 0, length_m: 3000,
                                  innerDiameter_m: 0.222,
                                  outerDiameter_m: 0.127,
                                  density_kg_per_m3: 1300)],
            drillString: [DSSpec(topDepth_m: 0, length_m: 3000,
                                 outerDiameter_m: 0.127,
                                 innerDiameter_m: 0.108)],
            surveys: [SurveySpec(md: 0, tvd: 0),
                      SurveySpec(md: 3000, tvd: 3000)],
            startBitMD_m: 1500,
            endBitMD_m: 3000,
            controlMD_m: 1500,
            activeMudDensity_kgpm3: 1300,
            baseMudDensity_kgpm3: 1300,
            targetESD_kgpm3: 1300,
            pocketLayers: [PocketLayerSpec(side: "annulus",
                                           topMD: 1500, bottomMD: 3000,
                                           topTVD: 1500, bottomTVD: 3000,
                                           rho_kgpm3: 1300,
                                           pv_cP: 25, yp_Pa: 8)],
            pumpRate_m3perMin: 0.8))
    }

    // MARK: - Emit drivers

    fileprivate func emitReamOut(_ spec: ReamOutSpec) throws {
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

        let surveys = spec.surveys.map {
            SurveyStation(md: $0.md, inc: 0, azi: 0, tvd: $0.tvd)
        }
        let tvdSampler = TvdSampler(stations: surveys)

        let geom = ProjectGeometryService(
            annulus: annulus,
            string: drillString,
            currentStringBottomMD: spec.startBitMD_m,
            mdToTvd: { tvdSampler.tvd(of: $0) })

        let snapshot = NumericalTripModel.ProjectSnapshot(from: project)

        let tripInput = NumericalTripModel.TripInput(
            tvdOfMd: { tvdSampler.tvd(of: $0) },
            shoeTVD_m: tvdSampler.tvd(of: spec.controlMD_m),
            shoeMD_m: spec.controlMD_m,
            startBitMD_m: spec.startBitMD_m,
            endMD_m: spec.endMD_m,
            crackFloat_kPa: spec.crackFloat_kPa,
            step_m: spec.step_m,
            baseMudDensity_kgpm3: spec.baseMudDensity_kgpm3,
            backfillDensity_kgpm3: spec.backfillDensity_kgpm3,
            targetESDAtTD_kgpm3: spec.targetESDAtTD_kgpm3)

        let steps = runReamOut(
            tripInput: tripInput,
            geom: geom,
            projectSnapshot: snapshot,
            pumpRate_m3perMin: spec.pumpRate_m3perMin,
            annulusSections: annulus,
            drillStringSections: drillString,
            controlMD_m: spec.controlMD_m,
            tvdSampler: tvdSampler)

        let inputJSON: [String: Any] = [
            "kind": "reamOut",
            "annulus": Self.encodeAnnulus(spec.annulus),
            "drillString": Self.encodeDrillString(spec.drillString),
            "surveys": spec.surveys.map { ["md": $0.md, "tvd": $0.tvd] },
            "startBitMD_m": spec.startBitMD_m,
            "endMD_m": spec.endMD_m,
            "controlMD_m": spec.controlMD_m,
            "step_m": spec.step_m,
            "baseMudDensity_kgpm3": spec.baseMudDensity_kgpm3,
            "backfillDensity_kgpm3": spec.backfillDensity_kgpm3,
            "targetESDAtTD_kgpm3": spec.targetESDAtTD_kgpm3,
            "crackFloat_kPa": spec.crackFloat_kPa,
            "pumpRate_m3perMin": spec.pumpRate_m3perMin,
        ]

        let outputJSON: [String: Any] = [
            "steps": steps.map { Self.encodeReamOutStep($0) },
        ]

        try FixtureWriter.write(
            service: "ReamEngine",
            caseName: spec.name,
            input: inputJSON,
            output: outputJSON)
    }

    fileprivate func emitReamIn(_ spec: ReamInSpec) throws {
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

        let surveys = spec.surveys.map {
            SurveyStation(md: $0.md, inc: 0, azi: 0, tvd: $0.tvd)
        }
        let tvdSampler = TvdSampler(stations: surveys)

        let pocketLayers = spec.pocketLayers.map {
            TripLayerSnapshot(side: $0.side,
                              topMD: $0.topMD,
                              bottomMD: $0.bottomMD,
                              topTVD: $0.topTVD,
                              bottomTVD: $0.bottomTVD,
                              rho_kgpm3: $0.rho_kgpm3,
                              deltaHydroStatic_kPa: 0,
                              volume_m3: 0,
                              pv_cP: $0.pv_cP,
                              yp_Pa: $0.yp_Pa)
        }

        let tripInInput = TripInService.TripInInput(
            startBitMD_m: spec.startBitMD_m,
            endBitMD_m: spec.endBitMD_m,
            controlMD_m: spec.controlMD_m,
            step_m: spec.step_m,
            pipeOD_m: spec.pipeOD_m,
            pipeID_m: spec.pipeID_m,
            activeMudDensity_kgpm3: spec.activeMudDensity_kgpm3,
            baseMudDensity_kgpm3: spec.baseMudDensity_kgpm3,
            targetESD_kgpm3: spec.targetESD_kgpm3,
            isFloatedCasing: spec.isFloatedCasing,
            floatSubMD_m: spec.floatSubMD_m,
            crackFloat_kPa: spec.crackFloat_kPa,
            pocketLayers: pocketLayers,
            annulusSections: annulus,
            tvdSampler: tvdSampler)

        let steps = runReamIn(
            tripInInput: tripInInput,
            pumpRate_m3perMin: spec.pumpRate_m3perMin,
            annulusSections: annulus,
            drillStringSections: drillString,
            tvdSampler: tvdSampler,
            controlMD_m: spec.controlMD_m)

        let inputJSON: [String: Any] = [
            "kind": "reamIn",
            "annulus": Self.encodeAnnulus(spec.annulus),
            "drillString": Self.encodeDrillString(spec.drillString),
            "surveys": spec.surveys.map { ["md": $0.md, "tvd": $0.tvd] },
            "startBitMD_m": spec.startBitMD_m,
            "endBitMD_m": spec.endBitMD_m,
            "controlMD_m": spec.controlMD_m,
            "step_m": spec.step_m,
            "pipeOD_m": spec.pipeOD_m,
            "pipeID_m": spec.pipeID_m,
            "activeMudDensity_kgpm3": spec.activeMudDensity_kgpm3,
            "baseMudDensity_kgpm3": spec.baseMudDensity_kgpm3,
            "targetESD_kgpm3": spec.targetESD_kgpm3,
            "crackFloat_kPa": spec.crackFloat_kPa,
            "isFloatedCasing": spec.isFloatedCasing,
            "floatSubMD_m": spec.floatSubMD_m,
            "pocketLayers": spec.pocketLayers.map {
                var d: [String: Any] = [
                    "side": $0.side,
                    "topMD": $0.topMD,
                    "bottomMD": $0.bottomMD,
                    "topTVD": $0.topTVD,
                    "bottomTVD": $0.bottomTVD,
                    "rho_kgpm3": $0.rho_kgpm3,
                ]
                if let v = $0.pv_cP { d["pv_cP"] = v }
                if let v = $0.yp_Pa { d["yp_Pa"] = v }
                return d
            },
            "pumpRate_m3perMin": spec.pumpRate_m3perMin,
        ]

        let outputJSON: [String: Any] = [
            "steps": steps.map { Self.encodeReamInStep($0) },
        ]

        try FixtureWriter.write(
            service: "ReamEngine",
            caseName: spec.name,
            input: inputJSON,
            output: outputJSON)
    }

    // MARK: - Helpers

    fileprivate static func encodeAnnulus(_ specs: [AnnulusSpec]) -> [[String: Any]] {
        specs.map { [
            "topDepth_m": $0.topDepth_m,
            "length_m": $0.length_m,
            "innerDiameter_m": $0.innerDiameter_m,
            "outerDiameter_m": $0.outerDiameter_m,
            "density_kg_per_m3": $0.density_kg_per_m3,
        ] }
    }

    fileprivate static func encodeDrillString(_ specs: [DSSpec]) -> [[String: Any]] {
        specs.map { [
            "topDepth_m": $0.topDepth_m,
            "length_m": $0.length_m,
            "outerDiameter_m": $0.outerDiameter_m,
            "innerDiameter_m": $0.innerDiameter_m,
        ] }
    }

    fileprivate static func encodeReamOutStep(_ s: ReamOutStep) -> [String: Any] {
        return [
            "bitMD_m": s.bitMD_m,
            "bitTVD_m": s.bitTVD_m,
            "SABP_kPa": s.SABP_kPa,
            "SABP_kPa_Raw": s.SABP_kPa_Raw,
            "ESDatTD_kgpm3": s.ESDatTD_kgpm3,
            "ESDatBit_kgpm3": s.ESDatBit_kgpm3,
            "swab_kPa": s.swab_kPa,
            "apl_kPa": s.apl_kPa,
            "pumpRate_m3perMin": s.pumpRate_m3perMin,
            "SABP_Dynamic_kPa": s.SABP_Dynamic_kPa,
            "ECD_kgpm3": s.ECD_kgpm3,
            "floatState": s.floatState,
            "stepBackfill_m3": s.stepBackfill_m3,
            "cumulativeBackfill_m3": s.cumulativeBackfill_m3,
            "expectedFillIfClosed_m3": s.expectedFillIfClosed_m3,
            "expectedFillIfOpen_m3": s.expectedFillIfOpen_m3,
            // Per-step fluid column (full LayerRow fields incl. colour) + totals.
            "layers": [
                "pocket": s.layersPocket.map { encodeLayerRow($0) },
                "annulus": s.layersAnnulus.map { encodeLayerRow($0) },
                "string": s.layersString.map { encodeLayerRow($0) },
            ],
            "totals": [
                "pocket": encodeTotals(s.totalsPocket),
                "annulus": encodeTotals(s.totalsAnnulus),
                "string": encodeTotals(s.totalsString),
            ],
        ]
    }

    fileprivate static func encodeReamInStep(_ s: ReamInStep) -> [String: Any] {
        return [
            "stepIndex": s.stepIndex,
            "bitMD_m": s.bitMD_m,
            "bitTVD_m": s.bitTVD_m,
            "ESDAtControl_kgpm3": s.ESDAtControl_kgpm3,
            "ESDAtBit_kgpm3": s.ESDAtBit_kgpm3,
            "requiredChokePressure_kPa": s.requiredChokePressure_kPa,
            "surge_kPa": s.surge_kPa,
            "apl_kPa": s.apl_kPa,
            "pumpRate_m3perMin": s.pumpRate_m3perMin,
            "dynamicChoke_kPa": s.dynamicChoke_kPa,
            "ECD_kgpm3": s.ECD_kgpm3,
            "stepFillVolume_m3": s.stepFillVolume_m3,
            "cumulativeFillVolume_m3": s.cumulativeFillVolume_m3,
            "expectedFillClosed_m3": s.expectedFillClosed_m3,
            "expectedFillOpen_m3": s.expectedFillOpen_m3,
            "stepDisplacementReturns_m3": s.stepDisplacementReturns_m3,
            "cumulativeDisplacementReturns_m3": s.cumulativeDisplacementReturns_m3,
            "isBelowTarget": s.isBelowTarget,
            "floatState": s.floatState,
            // Per-step fluid column (pocket layers, trip-in snapshot format).
            "layers": [
                "pocket": s.layersPocket.map { encodeSnapshot($0) },
            ],
        ]
    }

    // MARK: - Layer / totals / snapshot encoders

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

    fileprivate static func encodeSnapshot(_ s: TripLayerSnapshot) -> [String: Any] {
        var d: [String: Any] = [
            "side": s.side,
            "topMD": s.topMD,
            "bottomMD": s.bottomMD,
            "topTVD": s.topTVD,
            "bottomTVD": s.bottomTVD,
            "rho_kgpm3": s.rho_kgpm3,
            "deltaHydroStatic_kPa": s.deltaHydroStatic_kPa,
            "volume_m3": s.volume_m3,
        ]
        if let v = s.pv_cP { d["pv_cP"] = v }
        if let v = s.yp_Pa { d["yp_Pa"] = v }
        if let v = s.dial600 { d["dial600"] = v }
        if let v = s.dial300 { d["dial300"] = v }
        if let r = s.colorR, let g = s.colorG, let b = s.colorB {
            d["color"] = ["r": r, "g": g, "b": b, "a": s.colorA ?? 1]
        }
        if let v = s.isInAnnulus { d["isInAnnulus"] = v }
        return d
    }
}
