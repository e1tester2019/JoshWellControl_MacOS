//
//  KillMudSolverServiceFixtures.swift
//
//  Fixture emitter for KillMudSolverService.solve — kill mud density solver.
//  Solves pipe kill density analytically, sweeps annulus densities, validates
//  each candidate via a full NumericalTripModel.Run() against the project.
//
//  KillMudSolverService.solve is async; tests use `async throws`.
//

import Foundation
import XCTest

@testable import Josh_Well_Control_for_Mac

final class KillMudSolverServiceFixtures: XCTestCase {

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

    fileprivate struct SurveySpec {
        var md: Double
        var inc: Double
        var azi: Double = 0
        var tvd: Double
    }

    fileprivate struct CaseSpec {
        var name: String
        var annulus: [AnnulusSpec]
        var drillString: [DSSpec]
        var surveys: [SurveySpec]
        var startMD_m: Double
        var endMD_m: Double
        var controlMD_m: Double
        var targetESD_kgpm3: Double
        var crackFloat_kPa: Double = 1500
        var tripSpeed_m_per_s: Double = 0.5
        var eccentricityFactor: Double = 1.0
        var step_m: Double = 100
        var baseMudDensity_kgpm3: Double = 1300
        var baseMudPV_cP: Double = 25
        var baseMudYP_Pa: Double = 8
        var porePressureESD_kgpm3: Double = 1100
        var fracGradientESD_kgpm3: Double = 1900
        var sweepStartDensity_kgpm3: Double = 1500
        var sweepEndDensity_kgpm3: Double = 1700
        var sweepStep_kgpm3: Double = 50
    }

    // MARK: - Test methods

    func testEmit_vertical_singleZone() async throws {
        try await emit(CaseSpec(
            name: "vertical_singleZone",
            annulus: [AnnulusSpec(topDepth_m: 0, length_m: 3000,
                                  innerDiameter_m: 0.222,
                                  outerDiameter_m: 0.127,
                                  density_kg_per_m3: 1300,
                                  isCased: true)],
            drillString: [DSSpec(topDepth_m: 0, length_m: 3000,
                                 outerDiameter_m: 0.127,
                                 innerDiameter_m: 0.108)],
            surveys: [SurveySpec(md: 0, inc: 0, tvd: 0),
                      SurveySpec(md: 3000, inc: 0, tvd: 3000)],
            startMD_m: 3000,
            endMD_m: 1500,
            controlMD_m: 1500,
            targetESD_kgpm3: 1500,
            // narrow sweep so test runs fast (each candidate runs full NumericalTripModel)
            sweepStartDensity_kgpm3: 1500,
            sweepEndDensity_kgpm3: 1600,
            sweepStep_kgpm3: 50))
    }

    func testEmit_buildSection_horizontalHeel() async throws {
        try await emit(CaseSpec(
            name: "buildSection_horizontalHeel",
            annulus: [AnnulusSpec(topDepth_m: 0, length_m: 3000,
                                  innerDiameter_m: 0.222,
                                  outerDiameter_m: 0.127,
                                  density_kg_per_m3: 1300,
                                  isCased: true)],
            drillString: [DSSpec(topDepth_m: 0, length_m: 3000,
                                 outerDiameter_m: 0.127,
                                 innerDiameter_m: 0.108)],
            surveys: [SurveySpec(md: 0, inc: 0, tvd: 0),
                      SurveySpec(md: 500, inc: 0, tvd: 500),
                      SurveySpec(md: 1000, inc: 45, tvd: 950),
                      SurveySpec(md: 1500, inc: 90, tvd: 1300),
                      SurveySpec(md: 3000, inc: 90, tvd: 1300)],
            startMD_m: 3000,
            endMD_m: 1500,
            controlMD_m: 1500,
            targetESD_kgpm3: 1500,
            sweepStartDensity_kgpm3: 1500,
            sweepEndDensity_kgpm3: 1600,
            sweepStep_kgpm3: 50))
    }

    // MARK: - Emit driver

    fileprivate func emit(_ spec: CaseSpec) async throws {
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
            SurveyStation(md: $0.md, inc: $0.inc, azi: $0.azi, tvd: $0.tvd)
        }

        let snapshot = NumericalTripModel.ProjectSnapshot(from: project)

        let input = KillMudSolverService.SolverInput(
            annulusSections: annulus,
            drillStringSections: drillString,
            surveys: surveys,
            projectSnapshot: snapshot,
            startMD_m: spec.startMD_m,
            endMD_m: spec.endMD_m,
            controlMD_m: spec.controlMD_m,
            targetESD_kgpm3: spec.targetESD_kgpm3,
            crackFloat_kPa: spec.crackFloat_kPa,
            tripSpeed_m_per_s: spec.tripSpeed_m_per_s,
            eccentricityFactor: spec.eccentricityFactor,
            step_m: spec.step_m,
            baseMudDensity_kgpm3: spec.baseMudDensity_kgpm3,
            baseMudPV_cP: spec.baseMudPV_cP,
            baseMudYP_Pa: spec.baseMudYP_Pa,
            porePressureESD_kgpm3: spec.porePressureESD_kgpm3,
            fracGradientESD_kgpm3: spec.fracGradientESD_kgpm3,
            sweepStartDensity_kgpm3: spec.sweepStartDensity_kgpm3,
            sweepEndDensity_kgpm3: spec.sweepEndDensity_kgpm3,
            sweepStep_kgpm3: spec.sweepStep_kgpm3)

        let (geometry, results) = await KillMudSolverService.solve(input: input)

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
            "surveys": spec.surveys.map { [
                "md": $0.md, "inc": $0.inc, "azi": $0.azi, "tvd": $0.tvd,
            ] },
            "startMD_m": spec.startMD_m,
            "endMD_m": spec.endMD_m,
            "controlMD_m": spec.controlMD_m,
            "targetESD_kgpm3": spec.targetESD_kgpm3,
            "crackFloat_kPa": spec.crackFloat_kPa,
            "tripSpeed_m_per_s": spec.tripSpeed_m_per_s,
            "eccentricityFactor": spec.eccentricityFactor,
            "step_m": spec.step_m,
            "baseMudDensity_kgpm3": spec.baseMudDensity_kgpm3,
            "baseMudPV_cP": spec.baseMudPV_cP,
            "baseMudYP_Pa": spec.baseMudYP_Pa,
            "porePressureESD_kgpm3": spec.porePressureESD_kgpm3,
            "fracGradientESD_kgpm3": spec.fracGradientESD_kgpm3,
            "sweepStartDensity_kgpm3": spec.sweepStartDensity_kgpm3,
            "sweepEndDensity_kgpm3": spec.sweepEndDensity_kgpm3,
            "sweepStep_kgpm3": spec.sweepStep_kgpm3,
        ]

        let outputJSON: [String: Any] = [
            "geometry": Self.encodeGeometry(geometry),
            "results": results.map { Self.encodeResult($0) },
        ]

        try FixtureWriter.write(
            service: "KillMudSolverService",
            caseName: spec.name,
            input: inputJSON,
            output: outputJSON)
    }

    fileprivate static func encodeGeometry(_ g: KillMudSolverService.SolverGeometry) -> [String: Any] {
        return [
            "pipeDensity_kgpm3": g.pipeDensity_kgpm3,
            "pipeVolume_m3": g.pipeVolume_m3,
            "heelMD_m": g.heelMD_m,
            "bitTVD_m": g.bitTVD_m,
            "controlTVD_m": g.controlTVD_m,
            "steelDisplacement_m3": g.steelDisplacement_m3,
            "slugDrop_m3": g.slugDrop_m3,
            "maxBackfillHeight_m": g.maxBackfillHeight_m,
            "boreVolToControl_m3": g.boreVolToControl_m3,
            "avgDensityAtControl_kgpm3": g.avgDensityAtControl_kgpm3,
            "totalKillPressure_kPa": g.totalKillPressure_kPa,
            "remainingPressure_kPa": g.remainingPressure_kPa,
            "slugTopMD_m": g.slugTopMD_m,
            "kopMD_m": g.kopMD_m,
            "casingCapacity_m3_per_m": g.casingCapacity_m3_per_m,
            "pipeCapacity_m3_per_m": g.pipeCapacity_m3_per_m,
            "drainHeight_m": g.drainHeight_m,
            "killDepth_m": g.killDepth_m,
            "killStringVolume_m3": g.killStringVolume_m3,
            "killStringHeight_m": g.killStringHeight_m,
            "pipeKillPressure_kPa": g.pipeKillPressure_kPa,
            "dispHeight_m": g.dispHeight_m,
        ]
    }

    fileprivate static func encodeResult(_ r: KillMudSolverService.SolverResult) -> [String: Any] {
        return [
            "label": r.label,
            "fillFraction": r.fillFraction,
            "pipeKillDensity_kgpm3": r.pipeKillDensity_kgpm3,
            "pipeKillVolume_m3": r.pipeKillVolume_m3,
            "annulusKillDensity_kgpm3": r.annulusKillDensity_kgpm3,
            "annulusKillVolume_m3": (r.annulusKillVolume_m3.isInfinite
                                     ? "infinity" as Any
                                     : r.annulusKillVolume_m3 as Any),
            "killTVD_m": r.killTVD_m,
            "sustainedKillDepth_m": r.sustainedKillDepth_m,
            "maxESDAtControl_kgpm3": r.maxESDAtControl_kgpm3,
            "maxSABP_kPa": r.maxSABP_kPa,
            "feasible": r.feasible,
            "relived": r.relived,
        ]
    }
}
