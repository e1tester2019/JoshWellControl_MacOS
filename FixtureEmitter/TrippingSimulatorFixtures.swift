//
//  TrippingSimulatorFixtures.swift
//
//  Fixture emitter for TrippingSimulator.simulate — marches a bit position
//  through a trip range and emits one TripSample per stop (swab pulling out
//  / surge running in).
//

import Foundation
import SwiftUI
import XCTest

@testable import Josh_Well_Control_for_Mac

final class TrippingSimulatorFixtures: XCTestCase {

    // MARK: - Specs

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

    /// One persisted final fluid layer in MD interval [topMD, bottomMD].
    fileprivate struct LayerSpec {
        var placement: String   // "annulus" | "string" | "both"
        var topMD_m: Double
        var bottomMD_m: Double
        var density_kgm3: Double
        var dial600: Double?
        var dial300: Double?
    }

    fileprivate struct SurveySpec {
        var md: Double
        var tvd: Double
    }

    fileprivate struct CaseSpec {
        var name: String
        var annulus: [AnnulusSpec]
        var drillString: [DSSpec]
        var layers: [LayerSpec]
        var surveys: [SurveySpec] = []
        var direction: String   // "pullOutOfHole" | "runInHole"
        var startBitMD: Double
        var endBitMD: Double
        var mdStep: Double
        var hoistSpeed_mpermin: Double
        var theta600: Double
        var theta300: Double
        var eccentricityFactor: Double = 1.0
        var surgeLowerLimitMD: Double
    }

    // MARK: - Test methods

    func testEmit_pullOutOfHole_singleLayer_vertical() throws {
        try emit(CaseSpec(
            name: "pullOutOfHole_singleLayer_vertical",
            annulus: [AnnulusSpec(topDepth_m: 0, length_m: 3000,
                                  innerDiameter_m: 0.222,
                                  outerDiameter_m: 0.127)],
            drillString: [DSSpec(topDepth_m: 0, length_m: 3000,
                                 outerDiameter_m: 0.127,
                                 innerDiameter_m: 0.108)],
            layers: [LayerSpec(placement: "both",
                               topMD_m: 0, bottomMD_m: 3000,
                               density_kgm3: 1300,
                               dial600: 84, dial300: 48)],
            direction: "pullOutOfHole",
            startBitMD: 3000,
            endBitMD: 2500,
            mdStep: 100,
            hoistSpeed_mpermin: 30,
            theta600: 84, theta300: 48,
            surgeLowerLimitMD: 3000))
    }

    func testEmit_runInHole_singleLayer_vertical() throws {
        try emit(CaseSpec(
            name: "runInHole_singleLayer_vertical",
            annulus: [AnnulusSpec(topDepth_m: 0, length_m: 3000,
                                  innerDiameter_m: 0.222,
                                  outerDiameter_m: 0.127)],
            drillString: [DSSpec(topDepth_m: 0, length_m: 3000,
                                 outerDiameter_m: 0.127,
                                 innerDiameter_m: 0.108)],
            layers: [LayerSpec(placement: "both",
                               topMD_m: 0, bottomMD_m: 3000,
                               density_kgm3: 1300,
                               dial600: 84, dial300: 48)],
            direction: "runInHole",
            startBitMD: 2400,
            endBitMD: 2900,
            mdStep: 100,
            hoistSpeed_mpermin: 30,
            theta600: 84, theta300: 48,
            // Lower limit must be > endBitMD so the surge slice stays non-empty.
            surgeLowerLimitMD: 3000))
    }

    func testEmit_pullOutOfHole_deviated_eccentric() throws {
        try emit(CaseSpec(
            name: "pullOutOfHole_deviated_eccentric",
            annulus: [AnnulusSpec(topDepth_m: 0, length_m: 3000,
                                  innerDiameter_m: 0.222,
                                  outerDiameter_m: 0.127)],
            drillString: [DSSpec(topDepth_m: 0, length_m: 3000,
                                 outerDiameter_m: 0.127,
                                 innerDiameter_m: 0.108)],
            layers: [LayerSpec(placement: "both",
                               topMD_m: 0, bottomMD_m: 3000,
                               density_kgm3: 1400,
                               dial600: 95, dial300: 55)],
            surveys: [SurveySpec(md: 0, tvd: 0),
                      SurveySpec(md: 500, tvd: 500),
                      SurveySpec(md: 1000, tvd: 950),
                      SurveySpec(md: 1500, tvd: 1300),
                      SurveySpec(md: 3000, tvd: 1300)],
            direction: "pullOutOfHole",
            startBitMD: 3000,
            endBitMD: 2500,
            mdStep: 50,
            hoistSpeed_mpermin: 45,
            theta600: 95, theta300: 55,
            eccentricityFactor: 1.3,
            surgeLowerLimitMD: 3000))
    }

    // MARK: - Emit driver

    fileprivate final class _LinearTrajSampler: TrajectorySampler {
        let mds: [Double]
        let tvds: [Double]
        init(mds: [Double], tvds: [Double]) {
            self.mds = mds; self.tvds = tvds
        }
        func TVDofMD(_ md: Double) -> Double {
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

    fileprivate func emit(_ spec: CaseSpec) throws {
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

        let finalLayers = spec.layers.map { ls -> FinalFluidLayer in
            let placement: Placement
            switch ls.placement {
            case "annulus": placement = .annulus
            case "string":  placement = .string
            default:        placement = .both
            }
            let mud: MudProperties? = (ls.dial600 != nil || ls.dial300 != nil)
                ? MudProperties(density_kgm3: ls.density_kgm3)
                : nil
            if let m = mud {
                m.dial600 = ls.dial600 ?? 0
                m.dial300 = ls.dial300 ?? 0
            }
            return FinalFluidLayer(project: project,
                                   name: "L",
                                   placement: placement,
                                   topMD_m: ls.topMD_m,
                                   bottomMD_m: ls.bottomMD_m,
                                   density_kgm3: ls.density_kgm3,
                                   color: .gray,
                                   mud: mud)
        }

        let traj: TrajectorySampler? = spec.surveys.isEmpty
            ? nil
            : _LinearTrajSampler(mds: spec.surveys.map(\.md),
                                 tvds: spec.surveys.map(\.tvd))

        let dir: TripDirection.Kind = (spec.direction == "runInHole")
            ? .runInHole : .pullOutOfHole

        let sim = TrippingSimulator()
        let samples = try sim.simulateDetailed(
            project: project,
            finalLayers: finalLayers,
            annulus: annulus,
            string: drillString,
            direction: dir,
            startBitMD: spec.startBitMD,
            endBitMD: spec.endBitMD,
            mdStep: spec.mdStep,
            hoistSpeed_mpermin: spec.hoistSpeed_mpermin,
            theta600: spec.theta600,
            theta300: spec.theta300,
            eccentricityFactor: spec.eccentricityFactor,
            traj: traj,
            surgeLowerLimitMD: spec.surgeLowerLimitMD)

        // JSON encode
        let inputJSON: [String: Any] = [
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
            "layers": spec.layers.map {
                var d: [String: Any] = [
                    "placement": $0.placement,
                    "topMD_m": $0.topMD_m,
                    "bottomMD_m": $0.bottomMD_m,
                    "density_kgm3": $0.density_kgm3,
                ]
                if let v = $0.dial600 { d["dial600"] = v }
                if let v = $0.dial300 { d["dial300"] = v }
                return d
            },
            "surveys": spec.surveys.map { ["md": $0.md, "tvd": $0.tvd] },
            "direction": spec.direction,
            "startBitMD": spec.startBitMD,
            "endBitMD": spec.endBitMD,
            "mdStep": spec.mdStep,
            "hoistSpeed_mpermin": spec.hoistSpeed_mpermin,
            "theta600": spec.theta600,
            "theta300": spec.theta300,
            "eccentricityFactor": spec.eccentricityFactor,
            "surgeLowerLimitMD": spec.surgeLowerLimitMD,
        ]

        let samplesJSON: [[String: Any]] = samples.map { sample in
            [
                "bitMD_m": sample.bitMD_m,
                "tvd_m": sample.tvd_m,
                "total_kPa": sample.total_kPa,
                "recommendedSABP_kPa": sample.recommendedSABP_kPa,
                "nonLaminar": sample.nonLaminar,
                // Per-sample swab/surge column (matches SwabCalculator fixture shape).
                "profile": sample.profile.map { seg in
                    [
                        "MD_m": seg.MD_m,
                        "TVD_m": seg.TVD_m,
                        "Dh_m": seg.Dh_m,
                        "Va_mps": seg.Va_mps,
                        "dPperM_PaPerM": seg.dPperM_PaPerM,
                        "CumSwab_kPa": seg.CumSwab_kPa,
                        "Laminar": seg.Laminar,
                        "Re_g": seg.Re_g,
                    ]
                },
            ]
        }

        try FixtureWriter.write(
            service: "TrippingSimulator",
            caseName: spec.name,
            input: inputJSON,
            output: ["samples": samplesJSON])
    }
}
