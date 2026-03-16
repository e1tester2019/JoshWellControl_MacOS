//
//  SimVsRigComparisonService.swift
//  Josh Well Control for Mac
//
//  Compares T&D simulation results against processed rig sensor data.
//  Produces per-stand residuals and per-zone statistics.
//

import Foundation

// MARK: - Zone Classification

enum WellZone: String, CaseIterable {
    case vertical = "Vertical"
    case build = "Build"
    case lateral = "Lateral"

    /// Classify based on inclination (degrees)
    static func from(inclination_deg: Double) -> WellZone {
        if inclination_deg < 5 { return .vertical }
        if inclination_deg < 80 { return .build }
        return .lateral
    }
}

// MARK: - Output Structs

struct StandComparison: Identifiable {
    let id = UUID()
    let depth_m: Double
    let rigAvg_kDaN: Double
    let rigMin_kDaN: Double
    let rigMax_kDaN: Double
    let simValue_kDaN: Double      // pickup for trip out, slackOff for trip in
    let simFreeHanging_kDaN: Double
    let residual_kDaN: Double      // rig_avg - sim_value
    let zone: WellZone
}

struct ZoneStatistics: Identifiable {
    let id = UUID()
    let zone: String
    let count: Int
    let meanResidual: Double
    let p10: Double
    let p50: Double
    let p90: Double
    let stddev: Double
}

struct ComparisonResult {
    let stands: [StandComparison]
    let zoneStats: [ZoneStatistics]
    let overallStats: ZoneStatistics
}

// MARK: - Service

class SimVsRigComparisonService {
    static let shared = SimVsRigComparisonService()
    private init() {}

    /// Compare rig import data against sim results.
    /// - Parameters:
    ///   - rigImport: The processed rig data import
    ///   - simSteps: Array of (md, pickupHL_kN, slackOffHL_kN, freeHangingHL_kN) from sim results
    ///   - surveys: Array of (md, inclination_deg) from survey stations
    ///   - tripType: "in" or "out" - determines which sim value to compare against
    func compare(
        rigImport: RigDataImport,
        simSteps: [(md: Double, pickup_kN: Double, slackOff_kN: Double, freeHanging_kN: Double)],
        surveys: [(md: Double, inc_deg: Double)],
        tripType: String
    ) -> ComparisonResult {
        let rigStands = rigImport.correctedStandData
        guard !rigStands.isEmpty, !simSteps.isEmpty else {
            return ComparisonResult(stands: [], zoneStats: [], overallStats: emptyStats("Overall"))
        }

        // Sort sim steps by MD for interpolation
        let sortedSim = simSteps.sorted { $0.md < $1.md }
        let sortedSurveys = surveys.sorted { $0.md < $1.md }

        var comparisons: [StandComparison] = []

        for stand in rigStands {
            let depth = stand.standMidMD_m

            // Interpolate sim values at this depth (kN → kDaN: ÷10)
            let pickup_kDaN = interpolate(at: depth, from: sortedSim.map { ($0.md, $0.pickup_kN) }) / 10.0
            let slackOff_kDaN = interpolate(at: depth, from: sortedSim.map { ($0.md, $0.slackOff_kN) }) / 10.0
            let freeHanging_kDaN = interpolate(at: depth, from: sortedSim.map { ($0.md, $0.freeHanging_kN) }) / 10.0

            // Primary comparison: pickup for trip out, slackOff for trip in
            let simValue = tripType == "out" ? pickup_kDaN : slackOff_kDaN
            let residual = stand.avgHL_kDaN - simValue

            // Zone from survey inclination
            let inc = interpolate(at: depth, from: sortedSurveys.map { ($0.md, $0.inc_deg) })
            let zone = WellZone.from(inclination_deg: inc)

            comparisons.append(StandComparison(
                depth_m: depth,
                rigAvg_kDaN: stand.avgHL_kDaN,
                rigMin_kDaN: stand.minHL_kDaN,
                rigMax_kDaN: stand.maxHL_kDaN,
                simValue_kDaN: simValue,
                simFreeHanging_kDaN: freeHanging_kDaN,
                residual_kDaN: residual,
                zone: zone
            ))
        }

        // Compute zone statistics
        var zoneStats: [ZoneStatistics] = []
        for zone in WellZone.allCases {
            let zoneComps = comparisons.filter { $0.zone == zone }
            if !zoneComps.isEmpty {
                zoneStats.append(computeStats(name: zone.rawValue, residuals: zoneComps.map(\.residual_kDaN)))
            }
        }

        let overallStats = computeStats(name: "Overall", residuals: comparisons.map(\.residual_kDaN))

        return ComparisonResult(stands: comparisons, zoneStats: zoneStats, overallStats: overallStats)
    }

    // MARK: - Linear Interpolation

    private func interpolate(at x: Double, from points: [(Double, Double)]) -> Double {
        guard !points.isEmpty else { return 0 }
        if x <= points.first!.0 { return points.first!.1 }
        if x >= points.last!.0 { return points.last!.1 }

        // Binary search for bracket
        var lo = 0, hi = points.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if points[mid].0 <= x { lo = mid } else { hi = mid }
        }

        let x0 = points[lo].0, x1 = points[hi].0
        let y0 = points[lo].1, y1 = points[hi].1
        let t = (x - x0) / max(x1 - x0, 1e-12)
        return y0 + t * (y1 - y0)
    }

    // MARK: - Statistics

    private func computeStats(name: String, residuals: [Double]) -> ZoneStatistics {
        guard !residuals.isEmpty else { return emptyStats(name) }

        let n = Double(residuals.count)
        let mean = residuals.reduce(0, +) / n
        let variance = residuals.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / max(n - 1, 1)
        let stddev = sqrt(variance)

        let sorted = residuals.sorted()
        let p10 = percentile(sorted, p: 0.10)
        let p50 = percentile(sorted, p: 0.50)
        let p90 = percentile(sorted, p: 0.90)

        return ZoneStatistics(
            zone: name,
            count: residuals.count,
            meanResidual: mean,
            p10: p10,
            p50: p50,
            p90: p90,
            stddev: stddev
        )
    }

    private func percentile(_ sorted: [Double], p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let idx = p * Double(sorted.count - 1)
        let lo = Int(floor(idx))
        let hi = min(lo + 1, sorted.count - 1)
        let frac = idx - Double(lo)
        return sorted[lo] + frac * (sorted[hi] - sorted[lo])
    }

    private func emptyStats(_ name: String) -> ZoneStatistics {
        ZoneStatistics(zone: name, count: 0, meanResidual: 0, p10: 0, p50: 0, p90: 0, stddev: 0)
    }
}
