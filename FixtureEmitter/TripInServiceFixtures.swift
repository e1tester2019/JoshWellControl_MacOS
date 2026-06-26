//
//  TripInServiceFixtures.swift
//
//  Fixture emitter for TripInService.run — stateless trip-in physics
//  (per-step fill, displacement, ESD at control + bit, required choke).
//

import Foundation
import XCTest

@testable import Josh_Well_Control_for_Mac

final class TripInServiceFixtures: XCTestCase {

    // MARK: - Specs

    fileprivate struct AnnulusSpec {
        var topDepth_m: Double
        var length_m: Double
        var innerDiameter_m: Double
        var outerDiameter_m: Double
        var density_kg_per_m3: Double = 1100
    }

    fileprivate struct PocketLayerSpec {
        var side: String         // "annulus" | "pocket" — informational
        var topMD: Double
        var bottomMD: Double
        var topTVD: Double
        var bottomTVD: Double
        var rho_kgpm3: Double
    }

    fileprivate struct SurveySpec {
        var md: Double
        var tvd: Double
    }

    fileprivate struct CaseSpec {
        var name: String
        var startBitMD_m: Double
        var endBitMD_m: Double
        var controlMD_m: Double
        var step_m: Double
        var pipeOD_m: Double
        var pipeID_m: Double
        var activeMudDensity_kgpm3: Double
        var baseMudDensity_kgpm3: Double
        var targetESD_kgpm3: Double
        var isFloatedCasing: Bool
        var floatSubMD_m: Double
        var crackFloat_kPa: Double
        var pocketLayers: [PocketLayerSpec]
        var annulus: [AnnulusSpec]
        var surveys: [SurveySpec]
    }

    // MARK: - Test methods

    func testEmit_floatClosed_singleFluid_vertical() throws {
        try emit(CaseSpec(
            name: "floatClosed_singleFluid_vertical",
            startBitMD_m: 1500,
            endBitMD_m: 3000,
            controlMD_m: 1500,
            step_m: 100,
            pipeOD_m: 0.127,
            pipeID_m: 0.108,
            activeMudDensity_kgpm3: 1300,
            baseMudDensity_kgpm3: 1300,
            targetESD_kgpm3: 1300,
            isFloatedCasing: true,
            floatSubMD_m: 1500,
            crackFloat_kPa: 1500,
            pocketLayers: [PocketLayerSpec(side: "annulus",
                                           topMD: 1500, bottomMD: 3000,
                                           topTVD: 1500, bottomTVD: 3000,
                                           rho_kgpm3: 1300)],
            annulus: [AnnulusSpec(topDepth_m: 0, length_m: 3000,
                                  innerDiameter_m: 0.222,
                                  outerDiameter_m: 0.127,
                                  density_kg_per_m3: 1300)],
            surveys: [SurveySpec(md: 0, tvd: 0),
                      SurveySpec(md: 3000, tvd: 3000)]))
    }

    func testEmit_floatOpen_singleFluid_vertical() throws {
        try emit(CaseSpec(
            name: "floatOpen_singleFluid_vertical",
            startBitMD_m: 1500,
            endBitMD_m: 3000,
            controlMD_m: 1500,
            step_m: 100,
            pipeOD_m: 0.127,
            pipeID_m: 0.108,
            activeMudDensity_kgpm3: 1300,
            baseMudDensity_kgpm3: 1300,
            targetESD_kgpm3: 1300,
            isFloatedCasing: false,    // no float → continuous drain
            floatSubMD_m: 0,
            crackFloat_kPa: 0,
            pocketLayers: [PocketLayerSpec(side: "annulus",
                                           topMD: 1500, bottomMD: 3000,
                                           topTVD: 1500, bottomTVD: 3000,
                                           rho_kgpm3: 1300)],
            annulus: [AnnulusSpec(topDepth_m: 0, length_m: 3000,
                                  innerDiameter_m: 0.222,
                                  outerDiameter_m: 0.127,
                                  density_kg_per_m3: 1300)],
            surveys: [SurveySpec(md: 0, tvd: 0),
                      SurveySpec(md: 3000, tvd: 3000)]))
    }

    func testEmit_heavierKillMud_floatClosed() throws {
        // Active mud denser than base → pocket gets diluted by base on each step.
        try emit(CaseSpec(
            name: "heavierKillMud_floatClosed",
            startBitMD_m: 2000,
            endBitMD_m: 3000,
            controlMD_m: 2000,
            step_m: 100,
            pipeOD_m: 0.127,
            pipeID_m: 0.108,
            activeMudDensity_kgpm3: 1500,
            baseMudDensity_kgpm3: 1300,
            targetESD_kgpm3: 1500,
            isFloatedCasing: true,
            floatSubMD_m: 2000,
            crackFloat_kPa: 1500,
            pocketLayers: [PocketLayerSpec(side: "annulus",
                                           topMD: 2000, bottomMD: 3000,
                                           topTVD: 2000, bottomTVD: 3000,
                                           rho_kgpm3: 1500)],
            annulus: [AnnulusSpec(topDepth_m: 0, length_m: 3000,
                                  innerDiameter_m: 0.222,
                                  outerDiameter_m: 0.127,
                                  density_kg_per_m3: 1500)],
            surveys: [SurveySpec(md: 0, tvd: 0),
                      SurveySpec(md: 3000, tvd: 3000)]))
    }

    // MARK: - Emit driver

    fileprivate func emit(_ spec: CaseSpec) throws {
        let annulus = spec.annulus.map {
            AnnulusSection(name: "Ann",
                           topDepth_m: $0.topDepth_m,
                           length_m: $0.length_m,
                           innerDiameter_m: $0.innerDiameter_m,
                           outerDiameter_m: $0.outerDiameter_m,
                           density_kg_per_m3: $0.density_kg_per_m3)
        }

        let surveyStations = spec.surveys.map {
            SurveyStation(md: $0.md, inc: 0, azi: 0, tvd: $0.tvd)
        }
        let tvdSampler = TvdSampler(stations: surveyStations)

        let pocketLayers = spec.pocketLayers.map {
            TripLayerSnapshot(side: $0.side,
                              topMD: $0.topMD,
                              bottomMD: $0.bottomMD,
                              topTVD: $0.topTVD,
                              bottomTVD: $0.bottomTVD,
                              rho_kgpm3: $0.rho_kgpm3,
                              deltaHydroStatic_kPa: 0,
                              volume_m3: 0)
        }

        let input = TripInService.TripInInput(
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

        let result = TripInService.run(input)

        // JSON encode
        let inputJSON: [String: Any] = [
            "startBitMD_m": spec.startBitMD_m,
            "endBitMD_m": spec.endBitMD_m,
            "controlMD_m": spec.controlMD_m,
            "step_m": spec.step_m,
            "pipeOD_m": spec.pipeOD_m,
            "pipeID_m": spec.pipeID_m,
            "activeMudDensity_kgpm3": spec.activeMudDensity_kgpm3,
            "baseMudDensity_kgpm3": spec.baseMudDensity_kgpm3,
            "targetESD_kgpm3": spec.targetESD_kgpm3,
            "isFloatedCasing": spec.isFloatedCasing,
            "floatSubMD_m": spec.floatSubMD_m,
            "crackFloat_kPa": spec.crackFloat_kPa,
            "pocketLayers": spec.pocketLayers.map { [
                "side": $0.side,
                "topMD": $0.topMD,
                "bottomMD": $0.bottomMD,
                "topTVD": $0.topTVD,
                "bottomTVD": $0.bottomTVD,
                "rho_kgpm3": $0.rho_kgpm3,
            ] },
            "annulus": spec.annulus.map { [
                "topDepth_m": $0.topDepth_m,
                "length_m": $0.length_m,
                "innerDiameter_m": $0.innerDiameter_m,
                "outerDiameter_m": $0.outerDiameter_m,
                "density_kg_per_m3": $0.density_kg_per_m3,
            ] },
            "surveys": spec.surveys.map { ["md": $0.md, "tvd": $0.tvd] },
        ]

        let stepsJSON: [[String: Any]] = result.steps.map { Self.encodeStep($0) }

        try FixtureWriter.write(
            service: "TripInService",
            caseName: spec.name,
            input: inputJSON,
            output: ["steps": stepsJSON])
    }

    fileprivate static func encodeStep(_ s: TripInService.TripInStepResult) -> [String: Any] {
        return [
            "stepIndex": s.stepIndex,
            "bitMD_m": s.bitMD_m,
            "bitTVD_m": s.bitTVD_m,
            "stepFillVolume_m3": s.stepFillVolume_m3,
            "cumulativeFillVolume_m3": s.cumulativeFillVolume_m3,
            "expectedFillClosed_m3": s.expectedFillClosed_m3,
            "expectedFillOpen_m3": s.expectedFillOpen_m3,
            "stepDisplacementReturns_m3": s.stepDisplacementReturns_m3,
            "cumulativeDisplacementReturns_m3": s.cumulativeDisplacementReturns_m3,
            "ESDAtControl_kgpm3": s.ESDAtControl_kgpm3,
            "ESDAtBit_kgpm3": s.ESDAtBit_kgpm3,
            "requiredChokePressure_kPa": s.requiredChokePressure_kPa,
            "isBelowTarget": s.isBelowTarget,
            "differentialPressureAtBottom_kPa": s.differentialPressureAtBottom_kPa,
            "annulusPressureAtBit_kPa": s.annulusPressureAtBit_kPa,
            "stringPressureAtBit_kPa": s.stringPressureAtBit_kPa,
            "floatState": s.floatState,
            "surgePressure_kPa": s.surgePressure_kPa,
            "surgeECD_kgm3": s.surgeECD_kgm3,
            "dynamicESDAtControl_kgpm3": s.dynamicESDAtControl_kgpm3,
            // Per-step fluid column (pocket layers carried/displaced this step).
            "layers": [
                "pocket": s.layersPocket.map { encodeSnapshot($0) },
            ],
        ]
    }

    /// Serialize a TripLayerSnapshot — same field set as NumericalTripModel's
    /// LayerRow (colour + rheology emitted only when present).
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
