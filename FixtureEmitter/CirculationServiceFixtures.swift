//
//  CirculationServiceFixtures.swift
//
//  Fixture emitter for CirculationService.previewPumpQueue — parcel-based
//  dual-stack pump simulator. Pumps fluid down string, up annulus,
//  accumulates APL, returns per-step ESD/SABP and final layer arrays.
//

import Foundation
import XCTest

@testable import Josh_Well_Control_for_Mac

final class CirculationServiceFixtures: XCTestCase {

    // MARK: - Specs

    fileprivate struct AnnulusSpec {
        var topDepth_m: Double
        var length_m: Double
        var innerDiameter_m: Double
        var outerDiameter_m: Double
        var density_kg_per_m3: Double = 1100
        var isCased: Bool = false
    }

    fileprivate struct DSSpec {
        var topDepth_m: Double
        var length_m: Double
        var outerDiameter_m: Double
        var innerDiameter_m: Double
    }

    fileprivate struct LayerSpec {
        var side: String   // "annulus" | "string" | "pocket"
        var topMD: Double
        var bottomMD: Double
        var rho_kgpm3: Double
    }

    fileprivate struct SurveySpec {
        var md: Double
        var tvd: Double
    }

    /// One pump-and-circulate operation. mudID is fixed per fixture for stable diffs.
    fileprivate struct PumpOpSpec {
        var mudID: String          // UUID string
        var mudName: String
        var density_kgpm3: Double
        var volume_m3: Double
    }

    fileprivate struct CaseSpec {
        var name: String
        var annulus: [AnnulusSpec]
        var drillString: [DSSpec]
        var surveys: [SurveySpec]
        var pocketLayers: [LayerSpec]   // initial wellbore (annulus + open hole)
        var stringLayers: [LayerSpec]   // initial string contents
        var bitMD: Double
        var controlMD: Double
        var targetESD_kgpm3: Double
        var pumpQueue: [PumpOpSpec]
        var pumpOutput_m3perStroke: Double = 0.01
        var activeMudDensity_kgpm3: Double = 1300
        var maxPumpRate_m3perMin: Double = 1.0
        var minPumpRate_m3perMin: Double = 0.2
    }

    // MARK: - Test methods

    func testEmit_singlePump_displaceBaseMud() throws {
        try emit(CaseSpec(
            name: "singlePump_displaceBaseMud",
            annulus: [AnnulusSpec(topDepth_m: 0, length_m: 3000,
                                  innerDiameter_m: 0.222,
                                  outerDiameter_m: 0.127,
                                  density_kg_per_m3: 1300,
                                  isCased: true)],
            drillString: [DSSpec(topDepth_m: 0, length_m: 3000,
                                 outerDiameter_m: 0.127,
                                 innerDiameter_m: 0.108)],
            surveys: [SurveySpec(md: 0, tvd: 0),
                      SurveySpec(md: 3000, tvd: 3000)],
            pocketLayers: [LayerSpec(side: "annulus",
                                     topMD: 0, bottomMD: 3000,
                                     rho_kgpm3: 1300)],
            stringLayers: [LayerSpec(side: "string",
                                     topMD: 0, bottomMD: 3000,
                                     rho_kgpm3: 1300)],
            bitMD: 3000,
            controlMD: 1500,
            targetESD_kgpm3: 1300,
            pumpQueue: [PumpOpSpec(
                mudID: "00000000-0000-0000-0000-000000000001",
                mudName: "Kill Mud",
                density_kgpm3: 1500,
                volume_m3: 5.0)],
            activeMudDensity_kgpm3: 1300))
    }

    func testEmit_twoPumps_progressiveKill() throws {
        try emit(CaseSpec(
            name: "twoPumps_progressiveKill",
            annulus: [AnnulusSpec(topDepth_m: 0, length_m: 3000,
                                  innerDiameter_m: 0.222,
                                  outerDiameter_m: 0.127,
                                  density_kg_per_m3: 1300,
                                  isCased: true)],
            drillString: [DSSpec(topDepth_m: 0, length_m: 3000,
                                 outerDiameter_m: 0.127,
                                 innerDiameter_m: 0.108)],
            surveys: [SurveySpec(md: 0, tvd: 0),
                      SurveySpec(md: 3000, tvd: 3000)],
            pocketLayers: [LayerSpec(side: "annulus",
                                     topMD: 0, bottomMD: 3000,
                                     rho_kgpm3: 1300)],
            stringLayers: [LayerSpec(side: "string",
                                     topMD: 0, bottomMD: 3000,
                                     rho_kgpm3: 1300)],
            bitMD: 3000,
            controlMD: 1500,
            targetESD_kgpm3: 1300,
            pumpQueue: [
                PumpOpSpec(mudID: "00000000-0000-0000-0000-000000000001",
                           mudName: "Slug",
                           density_kgpm3: 2000,
                           volume_m3: 1.0),
                PumpOpSpec(mudID: "00000000-0000-0000-0000-000000000002",
                           mudName: "Kill Mud",
                           density_kgpm3: 1500,
                           volume_m3: 8.0),
            ],
            activeMudDensity_kgpm3: 1300))
    }

    // MARK: - Emit driver

    fileprivate func emit(_ spec: CaseSpec) throws {
        let project = ProjectState()
        let annulus = spec.annulus.map {
            let s = AnnulusSection(name: "Ann",
                                   topDepth_m: $0.topDepth_m,
                                   length_m: $0.length_m,
                                   innerDiameter_m: $0.innerDiameter_m,
                                   outerDiameter_m: $0.outerDiameter_m,
                                   density_kg_per_m3: $0.density_kg_per_m3)
            s.isCased = $0.isCased
            return s
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
            currentStringBottomMD: spec.bitMD,
            mdToTvd: { tvdSampler.tvd(of: $0) })

        func toLayers(_ specs: [LayerSpec]) -> [TripLayerSnapshot] {
            specs.map { ls in
                TripLayerSnapshot(side: ls.side,
                                  topMD: ls.topMD,
                                  bottomMD: ls.bottomMD,
                                  topTVD: tvdSampler.tvd(of: ls.topMD),
                                  bottomTVD: tvdSampler.tvd(of: ls.bottomMD),
                                  rho_kgpm3: ls.rho_kgpm3,
                                  deltaHydroStatic_kPa: 0,
                                  volume_m3: 0)
            }
        }

        let pocketLayers = toLayers(spec.pocketLayers)
        let stringLayers = toLayers(spec.stringLayers)

        let pumpQueue = spec.pumpQueue.map { p in
            CirculationService.PumpOperation(
                mudID: UUID(uuidString: p.mudID) ?? UUID(),
                mudName: p.mudName,
                mudDensity_kgpm3: p.density_kgpm3,
                mudColorR: 0.5,
                mudColorG: 0.5,
                mudColorB: 0.5,
                volume_m3: p.volume_m3)
        }

        let result = CirculationService.previewPumpQueue(
            pocketLayers: pocketLayers,
            stringLayers: stringLayers,
            bitMD: spec.bitMD,
            controlMD: spec.controlMD,
            targetESD_kgpm3: spec.targetESD_kgpm3,
            geom: geom,
            tvdSampler: tvdSampler,
            pumpQueue: pumpQueue,
            pumpOutput_m3perStroke: spec.pumpOutput_m3perStroke,
            activeMudDensity_kgpm3: spec.activeMudDensity_kgpm3,
            maxPumpRate_m3perMin: spec.maxPumpRate_m3perMin,
            minPumpRate_m3perMin: spec.minPumpRate_m3perMin,
            annulusSections: annulus,
            drillStringSections: drillString)

        // JSON encode
        let inputJSON: [String: Any] = [
            "annulus": spec.annulus.map { [
                "topDepth_m": $0.topDepth_m,
                "length_m": $0.length_m,
                "innerDiameter_m": $0.innerDiameter_m,
                "outerDiameter_m": $0.outerDiameter_m,
                "density_kg_per_m3": $0.density_kg_per_m3,
                "isCased": $0.isCased,
            ] },
            "drillString": spec.drillString.map { [
                "topDepth_m": $0.topDepth_m,
                "length_m": $0.length_m,
                "outerDiameter_m": $0.outerDiameter_m,
                "innerDiameter_m": $0.innerDiameter_m,
            ] },
            "surveys": spec.surveys.map { ["md": $0.md, "tvd": $0.tvd] },
            "pocketLayers": Self.encodeLayerSpecs(spec.pocketLayers),
            "stringLayers": Self.encodeLayerSpecs(spec.stringLayers),
            "bitMD": spec.bitMD,
            "controlMD": spec.controlMD,
            "targetESD_kgpm3": spec.targetESD_kgpm3,
            "pumpQueue": spec.pumpQueue.map { [
                "mudID": $0.mudID,
                "mudName": $0.mudName,
                "density_kgpm3": $0.density_kgpm3,
                "volume_m3": $0.volume_m3,
            ] },
            "pumpOutput_m3perStroke": spec.pumpOutput_m3perStroke,
            "activeMudDensity_kgpm3": spec.activeMudDensity_kgpm3,
            "maxPumpRate_m3perMin": spec.maxPumpRate_m3perMin,
            "minPumpRate_m3perMin": spec.minPumpRate_m3perMin,
        ]

        let outputJSON: [String: Any] = [
            "ESDAtControl": result.ESDAtControl,
            "requiredSABP": result.requiredSABP,
            "schedule": result.schedule.map { Self.encodeStep($0) },
            "resultLayersPocket": Self.encodeLayers(result.resultLayersPocket),
            "resultLayersString": Self.encodeLayers(result.resultLayersString),
        ]

        try FixtureWriter.write(
            service: "CirculationService",
            caseName: spec.name,
            input: inputJSON,
            output: outputJSON)
    }

    fileprivate static func encodeLayerSpecs(_ specs: [LayerSpec]) -> [[String: Any]] {
        specs.map { [
            "side": $0.side,
            "topMD": $0.topMD,
            "bottomMD": $0.bottomMD,
            "rho_kgpm3": $0.rho_kgpm3,
        ] }
    }

    fileprivate static func encodeLayers(_ layers: [TripLayerSnapshot]) -> [[String: Any]] {
        layers.map { [
            "side": $0.side,
            "topMD": $0.topMD,
            "bottomMD": $0.bottomMD,
            "topTVD": $0.topTVD,
            "bottomTVD": $0.bottomTVD,
            "rho_kgpm3": $0.rho_kgpm3,
        ] }
    }

    fileprivate static func encodeStep(_ s: CirculationService.CirculateOutStep) -> [String: Any] {
        return [
            "stepIndex": s.stepIndex,
            "volumePumped_m3": s.volumePumped_m3,
            "volumePumped_bbl": s.volumePumped_bbl,
            "strokesAtPumpOutput": s.strokesAtPumpOutput,
            "ESDAtControl_kgpm3": s.ESDAtControl_kgpm3,
            "requiredSABP_kPa": s.requiredSABP_kPa,
            "deltaSABP_kPa": s.deltaSABP_kPa,
            "cumulativeDeltaSABP_kPa": s.cumulativeDeltaSABP_kPa,
            "description": s.description,
            "pumpRate_m3perMin": s.pumpRate_m3perMin,
            "apl_kPa": s.apl_kPa,
        ]
    }
}
