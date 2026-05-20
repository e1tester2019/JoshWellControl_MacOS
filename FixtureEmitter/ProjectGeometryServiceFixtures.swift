//
//  ProjectGeometryServiceFixtures.swift
//
//  Fixture emitter for ProjectGeometryService — geometry queries
//  (diameters, areas, volumes, length-for-volume, MD↔TVD).
//
//  Each fixture pins one geometry configuration (annulus + drillString +
//  currentStringBottomMD + optional MD→TVD mapper) and a fixed set of
//  query points. Output is the per-query result. C# side parses the
//  geometry, runs the same queries, compares.
//

import Foundation
import XCTest

@testable import Josh_Well_Control_for_Mac

final class ProjectGeometryServiceFixtures: XCTestCase {

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

    fileprivate struct SurveySpec {
        var md: Double
        var tvd: Double
    }

    fileprivate struct CaseSpec {
        var name: String
        var annulus: [AnnulusSpec]
        var drillString: [DSSpec]
        var currentStringBottomMD: Double
        var surveys: [SurveySpec] = []   // empty → identity TVD
        var diameterMDs: [Double]
        var volumeRanges: [(top: Double, bottom: Double)]
        var lengthQueries: [(start: Double, vol: Double, side: String)]
        var tvdMDs: [Double]
    }

    // MARK: - Test methods

    func testEmit_vertical_singleAnnulus_singleDS() throws {
        try emit(CaseSpec(
            name: "vertical_singleAnnulus_singleDS",
            annulus: [
                AnnulusSpec(topDepth_m: 0, length_m: 3000,
                            innerDiameter_m: 0.311, outerDiameter_m: 0.127),
            ],
            drillString: [
                DSSpec(topDepth_m: 0, length_m: 3000,
                       outerDiameter_m: 0.127, innerDiameter_m: 0.108),
            ],
            currentStringBottomMD: 3000,
            diameterMDs: [0, 100, 1500, 2999, 3000, 3500],
            volumeRanges: [(0, 100), (0, 1500), (1500, 3000), (0, 3000)],
            lengthQueries: [
                (start: 0, vol: 1.0, side: "annulus"),
                (start: 0, vol: 10.0, side: "annulus"),
                (start: 0, vol: 1.0, side: "string"),
                (start: 1000, vol: 5.0, side: "string"),
            ],
            tvdMDs: [0, 1500, 3000]))
    }

    func testEmit_multi_section_string_pulled_back() throws {
        // Two-section string (DC + DP). Pulled to 2000 — bit not at TD.
        try emit(CaseSpec(
            name: "multi_section_string_pulled_back",
            annulus: [
                AnnulusSpec(topDepth_m: 0, length_m: 3000,
                            innerDiameter_m: 0.311, outerDiameter_m: 0.127),
            ],
            drillString: [
                // 5" DP from 0–2700
                DSSpec(topDepth_m: 0, length_m: 2700,
                       outerDiameter_m: 0.127, innerDiameter_m: 0.108),
                // 6¾" DC from 2700–3000
                DSSpec(topDepth_m: 2700, length_m: 300,
                       outerDiameter_m: 0.171, innerDiameter_m: 0.071),
            ],
            currentStringBottomMD: 2000,   // string pulled above DC zone
            diameterMDs: [0, 1000, 2000, 2500, 2999],
            volumeRanges: [(0, 1000), (0, 2000), (0, 3000), (1500, 2500)],
            lengthQueries: [
                (start: 0, vol: 5.0, side: "annulus"),
                (start: 0, vol: 50.0, side: "annulus"),
                (start: 0, vol: 5.0, side: "string"),
            ],
            tvdMDs: [0, 1000, 2000]))
    }

    func testEmit_deviated_with_surveys() throws {
        // Build-to-horizontal trajectory; TVD ≠ MD past 500 m.
        try emit(CaseSpec(
            name: "deviated_with_surveys",
            annulus: [
                AnnulusSpec(topDepth_m: 0, length_m: 3000,
                            innerDiameter_m: 0.222, outerDiameter_m: 0.127),
            ],
            drillString: [
                DSSpec(topDepth_m: 0, length_m: 3000,
                       outerDiameter_m: 0.127, innerDiameter_m: 0.108),
            ],
            currentStringBottomMD: 3000,
            surveys: [
                SurveySpec(md: 0, tvd: 0),
                SurveySpec(md: 500, tvd: 500),
                SurveySpec(md: 1000, tvd: 950),
                SurveySpec(md: 1500, tvd: 1300),
                SurveySpec(md: 3000, tvd: 1300),
            ],
            diameterMDs: [0, 1500, 3000],
            volumeRanges: [(0, 1500), (1500, 3000), (0, 3000)],
            lengthQueries: [
                (start: 1500, vol: 5.0, side: "annulus"),
            ],
            tvdMDs: [0, 250, 500, 750, 1000, 1500, 2250, 3000]))
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
        let string = spec.drillString.map {
            DrillStringSection(name: "DS",
                               topDepth_m: $0.topDepth_m,
                               length_m: $0.length_m,
                               outerDiameter_m: $0.outerDiameter_m,
                               innerDiameter_m: $0.innerDiameter_m)
        }

        let geom: ProjectGeometryService
        if spec.surveys.isEmpty {
            geom = ProjectGeometryService(annulus: annulus,
                                          string: string,
                                          currentStringBottomMD: spec.currentStringBottomMD)
        } else {
            let mds = spec.surveys.map(\.md)
            let tvds = spec.surveys.map(\.tvd)
            let mapper: @Sendable (Double) -> Double = { md in
                Self.linearInterp(md, mds: mds, tvds: tvds)
            }
            geom = ProjectGeometryService(annulus: annulus,
                                          string: string,
                                          currentStringBottomMD: spec.currentStringBottomMD,
                                          mdToTvd: mapper)
        }

        // Diameter / area queries
        let diameterResults: [[String: Any]] = spec.diameterMDs.map { md in
            [
                "md": md,
                "holeOD_m": geom.holeOD_m(md),
                "pipeOD_m": geom.pipeOD_m(md),
                "pipeID_m": geom.pipeID_m(md),
                "annulusGap_m": geom.annulusGap_m(md),
                "pipeArea_m2": geom.pipeArea_m2(md),
                "annulusArea_m2": geom.annulusArea_m2(md),
                "steelArea_m2": geom.steelArea_m2(md),
                "steelDisplacement_m2": geom.steelDisplacement_m2(md),
            ]
        }

        // Volume queries
        let volumeResults: [[String: Any]] = spec.volumeRanges.map { range in
            [
                "topMD": range.top,
                "bottomMD": range.bottom,
                "volumeInAnnulus_m3": geom.volumeInAnnulus_m3(range.top, range.bottom),
                "volumeInString_m3": geom.volumeInString_m3(range.top, range.bottom),
                "volumeOfStringOD_m3": geom.volumeOfStringOD_m3(range.top, range.bottom),
            ]
        }

        // Length-for-volume queries
        let lengthResults: [[String: Any]] = spec.lengthQueries.map { q in
            let len: Double
            switch q.side {
            case "annulus":
                len = geom.lengthForAnnulusVolume_m(q.start, q.vol)
            case "string":
                len = geom.lengthForStringVolume_m(q.start, q.vol)
            default:
                len = 0
            }
            return [
                "side": q.side,
                "startMD": q.start,
                "volume_m3": q.vol,
                "length_m": len,
            ]
        }

        // TVD queries
        let tvdResults: [[String: Any]] = spec.tvdMDs.map { md in
            [
                "md": md,
                "tvd": geom.tvd(of: md),
            ]
        }

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
            "currentStringBottomMD": spec.currentStringBottomMD,
            "surveys": spec.surveys.map { ["md": $0.md, "tvd": $0.tvd] },
            "queries": [
                "diameterMDs": spec.diameterMDs,
                "volumeRanges": spec.volumeRanges.map {
                    ["topMD": $0.top, "bottomMD": $0.bottom]
                },
                "lengthQueries": spec.lengthQueries.map {
                    ["side": $0.side, "startMD": $0.start, "volume_m3": $0.vol]
                },
                "tvdMDs": spec.tvdMDs,
            ],
        ]

        let outputJSON: [String: Any] = [
            "diameter": diameterResults,
            "volume": volumeResults,
            "length": lengthResults,
            "tvd": tvdResults,
        ]

        try FixtureWriter.write(
            service: "ProjectGeometryService",
            caseName: spec.name,
            input: inputJSON,
            output: outputJSON)
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
