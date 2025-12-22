//
//  DirectionalSurveyService.swift
//  Josh Well Control for Mac
//
//  Minimum curvature method for directional survey calculations.
//  Reference: SPE Drilling Engineering Manual
//

import Foundation

/// Service for calculating directional survey values using minimum curvature method
enum DirectionalSurveyService {

    // MARK: - Main Calculation

    /// Recalculate all derived values for a sorted array of survey stations
    /// - Parameters:
    ///   - surveys: Array of SurveyStation sorted by MD (ascending)
    ///   - vsdDirection: Vertical Section Direction in degrees (reference azimuth for VS)
    ///   - kbElevation: Kelly Bushing elevation above sea level in meters (optional, for subsea calc)
    ///   - tieIn: Starting coordinates (NS, EW, TVD) for first station - defaults to (0, 0, 0)
    static func recalculate(
        surveys: [SurveyStation],
        vsdDirection: Double,
        kbElevation: Double? = nil,
        tieIn: (ns: Double, ew: Double, tvd: Double) = (0, 0, 0)
    ) {
        guard !surveys.isEmpty else { return }

        let vsdRad = vsdDirection * .pi / 180.0

        // First station - use tie-in values
        let first = surveys[0]
        first.tvd = tieIn.tvd
        first.ns_m = tieIn.ns
        first.ew_m = tieIn.ew
        first.vs_m = calculateVS(ns: tieIn.ns, ew: tieIn.ew, vsdRad: vsdRad)
        first.dls_deg_per30m = 0
        first.buildRate_deg_per30m = 0
        first.turnRate_deg_per30m = 0
        if let kb = kbElevation {
            first.subsea_m = kb - (first.tvd ?? 0)
        }

        // Process remaining stations using minimum curvature
        for i in 1..<surveys.count {
            let prev = surveys[i - 1]
            let curr = surveys[i]

            let result = minimumCurvature(
                md1: prev.md, inc1: prev.inc, azi1: prev.azi,
                md2: curr.md, inc2: curr.inc, azi2: curr.azi
            )

            // Accumulate coordinates
            let prevTVD = prev.tvd ?? 0
            let prevNS = prev.ns_m ?? 0
            let prevEW = prev.ew_m ?? 0

            curr.tvd = prevTVD + result.dTVD
            curr.ns_m = prevNS + result.dNS
            curr.ew_m = prevEW + result.dEW

            // Vertical section
            curr.vs_m = calculateVS(ns: curr.ns_m ?? 0, ew: curr.ew_m ?? 0, vsdRad: vsdRad)

            // Dogleg severity (°/30m)
            curr.dls_deg_per30m = result.dls_deg_per30m

            // Build and turn rates
            let courseLengthM = curr.md - prev.md
            if courseLengthM > 0 {
                let dInc = curr.inc - prev.inc
                let dAzi = normalizeAzimuthDelta(curr.azi - prev.azi)
                curr.buildRate_deg_per30m = (dInc / courseLengthM) * 30.0
                curr.turnRate_deg_per30m = (dAzi / courseLengthM) * 30.0
            } else {
                curr.buildRate_deg_per30m = 0
                curr.turnRate_deg_per30m = 0
            }

            // Subsea
            if let kb = kbElevation {
                curr.subsea_m = kb - (curr.tvd ?? 0)
            }
        }
    }

    // MARK: - Minimum Curvature Method

    struct MinCurvResult {
        let dTVD: Double
        let dNS: Double
        let dEW: Double
        let dls_deg_per30m: Double
    }

    /// Calculate position changes between two survey stations using minimum curvature
    static func minimumCurvature(
        md1: Double, inc1: Double, azi1: Double,
        md2: Double, inc2: Double, azi2: Double
    ) -> MinCurvResult {
        let courseLengthM = md2 - md1
        guard courseLengthM > 0 else {
            return MinCurvResult(dTVD: 0, dNS: 0, dEW: 0, dls_deg_per30m: 0)
        }

        // Convert to radians
        let I1 = inc1 * .pi / 180.0
        let I2 = inc2 * .pi / 180.0
        let A1 = azi1 * .pi / 180.0
        let A2 = azi2 * .pi / 180.0

        // Dogleg angle (radians)
        let cosDL = cos(I2 - I1) - sin(I1) * sin(I2) * (1 - cos(A2 - A1))
        let doglegRad = acos(min(max(cosDL, -1.0), 1.0))  // Clamp for numerical stability

        // Dogleg severity (°/30m)
        let doglegDeg = doglegRad * 180.0 / .pi
        let dls = (doglegDeg / courseLengthM) * 30.0

        // Ratio factor (RF) - handles small dogleg case
        let rf: Double
        if doglegRad < 1e-6 {
            rf = 1.0  // Tangential method for very small dogleg
        } else {
            rf = (2.0 / doglegRad) * tan(doglegRad / 2.0)
        }

        // Position changes using minimum curvature
        let dTVD = (courseLengthM / 2.0) * (cos(I1) + cos(I2)) * rf
        let dNS = (courseLengthM / 2.0) * (sin(I1) * cos(A1) + sin(I2) * cos(A2)) * rf
        let dEW = (courseLengthM / 2.0) * (sin(I1) * sin(A1) + sin(I2) * sin(A2)) * rf

        return MinCurvResult(dTVD: dTVD, dNS: dNS, dEW: dEW, dls_deg_per30m: dls)
    }

    // MARK: - Helpers

    /// Calculate Vertical Section from NS/EW coordinates
    /// VS = NS * cos(VSD) + EW * sin(VSD)
    static func calculateVS(ns: Double, ew: Double, vsdRad: Double) -> Double {
        return ns * cos(vsdRad) + ew * sin(vsdRad)
    }

    /// Normalize azimuth delta to -180 to +180 range
    static func normalizeAzimuthDelta(_ delta: Double) -> Double {
        var d = delta
        while d > 180 { d -= 360 }
        while d < -180 { d += 360 }
        return d
    }

    /// Calculate total horizontal departure from NS/EW
    static func departure(ns: Double, ew: Double) -> Double {
        return sqrt(ns * ns + ew * ew)
    }

    /// Calculate direction (azimuth) from NS/EW in degrees
    static func direction(ns: Double, ew: Double) -> Double {
        guard ns != 0 || ew != 0 else { return 0 }
        let rad = atan2(ew, ns)
        var deg = rad * 180.0 / .pi
        if deg < 0 { deg += 360 }
        return deg
    }
}
