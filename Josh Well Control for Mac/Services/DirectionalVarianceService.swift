//
//  DirectionalVarianceService.swift
//  Josh Well Control for Mac
//
//  Service for calculating variance between actual surveys and directional plan.
//

import Foundation

/// Service for calculating variance between actual surveys and a directional plan
enum DirectionalVarianceService {

    // MARK: - Main Calculation

    /// Calculate variance for each survey station compared to the plan
    /// - Parameters:
    ///   - surveys: Array of actual survey stations (sorted by MD)
    ///   - plan: The directional plan to compare against
    ///   - projectVsdDirection: Project's VSD direction in degrees (fallback if plan doesn't have one)
    /// - Returns: Array of SurveyVariance for each survey station
    /// Default projection distance for required rate calculations (meters)
    private static let defaultProjectionMD: Double = 30.0

    static func calculateVariances(
        surveys: [SurveyStation],
        plan: DirectionalPlan,
        projectVsdDirection: Double
    ) -> [SurveyVariance] {
        let planStations = plan.sortedStations
        let sortedSurveys = surveys.sorted { $0.md < $1.md }
        guard !planStations.isEmpty, !sortedSurveys.isEmpty else { return [] }

        // Use plan's VS azimuth if available, otherwise fall back to project's VSD direction
        let vsdDirection = plan.vsAzimuth_deg ?? projectVsdDirection
        let vsdRad = vsdDirection * .pi / 180.0
        var results: [SurveyVariance] = []

        for (index, survey) in sortedSurveys.enumerated() {
            // Skip surveys outside plan range
            guard survey.md >= planStations.first!.md,
                  survey.md <= planStations.last!.md else {
                continue
            }

            // Interpolate plan values at survey MD
            let interpolated = interpolatePlan(at: survey.md, planStations: planStations, vsdRad: vsdRad)

            // Calculate actual BR/TR from previous survey
            var surveyBR: Double = 0
            var surveyTR: Double = 0
            if index > 0 {
                let prevSurvey = sortedSurveys[index - 1]
                let intervalMD = survey.md - prevSurvey.md
                if intervalMD > 0 {
                    let rates = calculateRates(
                        inc1: prevSurvey.inc, azi1: prevSurvey.azi,
                        inc2: survey.inc, azi2: survey.azi,
                        intervalMD: intervalMD
                    )
                    surveyBR = rates.br
                    surveyTR = rates.tr
                }
            }

            // Calculate required rates to intercept plan
            // Project ahead to find where we should be targeting on the plan
            let projectionMD = min(defaultProjectionMD, planStations.last!.md - survey.md)
            let targetMD = survey.md + max(projectionMD, 10)  // At least 10m projection
            let targetPoint = interpolatePlan(at: min(targetMD, planStations.last!.md), planStations: planStations, vsdRad: vsdRad)

            let requiredRates = calculateRequiredRates(
                currentInc: survey.inc, currentAzi: survey.azi,
                targetInc: targetPoint.inc, targetAzi: targetPoint.azi,
                projectionMD: projectionMD > 0 ? projectionMD : defaultProjectionMD
            )

            let variance = SurveyVariance(
                surveyMD: survey.md,
                surveyTVD: survey.tvd ?? 0,
                surveyNS: survey.ns_m ?? 0,
                surveyEW: survey.ew_m ?? 0,
                surveyVS: survey.vs_m ?? 0,
                surveyInc: survey.inc,
                surveyAzi: survey.azi,
                surveyDLS: survey.dls_deg_per30m ?? 0,
                surveyBR: surveyBR,
                surveyTR: surveyTR,
                planTVD: interpolated.tvd,
                planNS: interpolated.ns,
                planEW: interpolated.ew,
                planVS: interpolated.vs,
                planInc: interpolated.inc,
                planAzi: interpolated.azi,
                planDLS: interpolated.dls,
                planBR: interpolated.br,
                planTR: interpolated.tr,
                requiredBR: requiredRates.br,
                requiredTR: requiredRates.tr,
                projectionDistance: projectionMD > 0 ? projectionMD : defaultProjectionMD
            )

            results.append(variance)
        }

        return results
    }

    // MARK: - Plan Interpolation

    private struct InterpolatedPoint {
        let tvd: Double
        let ns: Double
        let ew: Double
        let vs: Double
        let inc: Double
        let azi: Double
        let dls: Double    // Plan DLS at this point
        let br: Double     // Plan Build Rate at this point
        let tr: Double     // Plan Turn Rate at this point
    }

    /// Interpolate plan position at a specific MD using minimum curvature
    private static func interpolatePlan(
        at md: Double,
        planStations: [DirectionalPlanStation],
        vsdRad: Double
    ) -> InterpolatedPoint {
        // Find bracketing stations
        var lower: DirectionalPlanStation?
        var upper: DirectionalPlanStation?

        for station in planStations {
            if station.md <= md {
                lower = station
            }
            if station.md >= md && upper == nil {
                upper = station
            }
            if lower != nil && upper != nil { break }
        }

        // Handle edge cases
        if lower == nil {
            lower = planStations.first
        }
        if upper == nil {
            upper = planStations.last
        }

        guard let lo = lower, let hi = upper else {
            return InterpolatedPoint(tvd: 0, ns: 0, ew: 0, vs: 0, inc: 0, azi: 0, dls: 0, br: 0, tr: 0)
        }

        // Calculate plan rates between bracketing stations
        let intervalMD = hi.md - lo.md
        let (planDLS, planBR, planTR) = calculateRates(
            inc1: lo.inc, azi1: lo.azi,
            inc2: hi.inc, azi2: hi.azi,
            intervalMD: intervalMD
        )

        // If same station or very close, return that station's values
        if lo.md == hi.md || abs(md - lo.md) < 0.001 {
            return InterpolatedPoint(
                tvd: lo.tvd,
                ns: lo.ns_m,
                ew: lo.ew_m,
                vs: lo.vs_m ?? DirectionalSurveyService.calculateVS(ns: lo.ns_m, ew: lo.ew_m, vsdRad: vsdRad),
                inc: lo.inc,
                azi: lo.azi,
                dls: planDLS,
                br: planBR,
                tr: planTR
            )
        }

        if abs(md - hi.md) < 0.001 {
            return InterpolatedPoint(
                tvd: hi.tvd,
                ns: hi.ns_m,
                ew: hi.ew_m,
                vs: hi.vs_m ?? DirectionalSurveyService.calculateVS(ns: hi.ns_m, ew: hi.ew_m, vsdRad: vsdRad),
                inc: hi.inc,
                azi: hi.azi,
                dls: planDLS,
                br: planBR,
                tr: planTR
            )
        }

        // Calculate fraction along the interval
        let fraction = (md - lo.md) / (hi.md - lo.md)

        // Use minimum curvature to interpolate position
        let result = DirectionalSurveyService.minimumCurvature(
            md1: lo.md, inc1: lo.inc, azi1: lo.azi,
            md2: hi.md, inc2: hi.inc, azi2: hi.azi
        )

        // Interpolated position = lower + fraction * (delta from min curv)
        let tvd = lo.tvd + fraction * result.dTVD
        let ns = lo.ns_m + fraction * result.dNS
        let ew = lo.ew_m + fraction * result.dEW
        let vs = DirectionalSurveyService.calculateVS(ns: ns, ew: ew, vsdRad: vsdRad)

        // Linear interpolation for Inc/Azi
        let inc = lo.inc + fraction * (hi.inc - lo.inc)

        // Handle azimuth wrapping
        var aziDelta = hi.azi - lo.azi
        if aziDelta > 180 { aziDelta -= 360 }
        if aziDelta < -180 { aziDelta += 360 }
        var azi = lo.azi + fraction * aziDelta
        if azi < 0 { azi += 360 }
        if azi >= 360 { azi -= 360 }

        return InterpolatedPoint(
            tvd: tvd,
            ns: ns,
            ew: ew,
            vs: vs,
            inc: inc,
            azi: azi,
            dls: planDLS,
            br: planBR,
            tr: planTR
        )
    }

    // MARK: - Rate Calculations

    /// Calculate DLS, Build Rate, and Turn Rate between two survey points
    /// - Returns: (dls, buildRate, turnRate) all in deg/30m
    private static func calculateRates(
        inc1: Double, azi1: Double,
        inc2: Double, azi2: Double,
        intervalMD: Double
    ) -> (dls: Double, br: Double, tr: Double) {
        guard intervalMD > 0 else { return (0, 0, 0) }

        // Build Rate = inclination change per 30m (positive = building angle)
        let incChange = inc2 - inc1
        let br = incChange / intervalMD * 30.0

        // Turn Rate = azimuth change per 30m (positive = turning right/clockwise)
        var aziChange = azi2 - azi1
        if aziChange > 180 { aziChange -= 360 }
        if aziChange < -180 { aziChange += 360 }
        let tr = aziChange / intervalMD * 30.0

        // DLS using standard formula
        let inc1Rad = inc1 * .pi / 180.0
        let inc2Rad = inc2 * .pi / 180.0
        let aziChangeRad = aziChange * .pi / 180.0

        let cosDL = cos(inc2Rad - inc1Rad) - sin(inc1Rad) * sin(inc2Rad) * (1 - cos(aziChangeRad))
        let dlRad = acos(min(1, max(-1, cosDL)))  // Clamp to valid range
        let dls = (dlRad * 180.0 / .pi) / intervalMD * 30.0

        return (dls, br, tr)
    }

    /// Calculate required BR/TR to intercept plan at a given projection distance
    /// - Parameters:
    ///   - currentInc: Current inclination
    ///   - currentAzi: Current azimuth
    ///   - targetInc: Target inclination on plan
    ///   - targetAzi: Target azimuth on plan
    ///   - projectionMD: Distance over which to make the correction
    /// - Returns: (requiredBR, requiredTR) in deg/30m
    private static func calculateRequiredRates(
        currentInc: Double, currentAzi: Double,
        targetInc: Double, targetAzi: Double,
        projectionMD: Double
    ) -> (br: Double, tr: Double) {
        guard projectionMD > 0 else { return (0, 0) }

        // Required build rate to match target inclination
        let incDelta = targetInc - currentInc
        let requiredBR = incDelta / projectionMD * 30.0

        // Required turn rate to match target azimuth
        var aziDelta = targetAzi - currentAzi
        if aziDelta > 180 { aziDelta -= 360 }
        if aziDelta < -180 { aziDelta += 360 }
        let requiredTR = aziDelta / projectionMD * 30.0

        return (requiredBR, requiredTR)
    }

    /// Calculate required BR to reach a target
    /// - Parameters:
    ///   - currentTVD: Current TVD at bit
    ///   - currentInc: Current inclination at bit
    ///   - targetTVD: Target TVD to reach (nil if using plan)
    ///   - targetInc: Target landing inclination (nil = estimate from plan)
    ///   - userDistance: User-specified distance to land (nil = auto-calculate)
    ///   - planStations: Plan stations for reference
    /// - Returns: Calculation results or nil
    private static func calculateTargetRates(
        currentTVD: Double,
        currentInc: Double,
        targetTVD: Double?,
        targetInc: Double?,
        userDistance: Double?,
        planStations: [DirectionalPlanStation]
    ) -> (requiredBR: Double, calculatedDistance: Double, usedTargetInc: Double)? {
        // Need at least target TVD or user distance to calculate
        guard targetTVD != nil || userDistance != nil || targetInc != nil else { return nil }

        // Determine target inclination
        let landingInc: Double
        if let userTargetInc = targetInc {
            landingInc = userTargetInc
        } else if let tvd = targetTVD {
            // Find plan station at target TVD to get expected inclination
            var foundInc: Double = currentInc
            for station in planStations {
                if station.tvd >= tvd {
                    foundInc = station.inc
                    break
                }
            }
            // If we didn't find one, use the last station's inc
            if let lastStation = planStations.last, foundInc == currentInc {
                foundInc = lastStation.inc
            }
            landingInc = foundInc
        } else {
            landingInc = currentInc  // Hold angle if nothing specified
        }

        // Determine distance to land
        let distanceToLand: Double
        if let userDist = userDistance, userDist > 0 {
            distanceToLand = userDist
        } else if let tvd = targetTVD {
            // Calculate distance based on TVD remaining
            let tvdRemaining = tvd - currentTVD
            guard tvdRemaining > 0 else { return nil }

            // Use average inclination to estimate distance
            let avgInc = (currentInc + landingInc) / 2.0
            let avgIncRad = avgInc * .pi / 180.0
            let cosAvgInc = cos(avgIncRad)

            if abs(cosAvgInc) < 0.05 {
                // Very horizontal - use a simple estimate
                // At 85°+ inc, TVD gain is minimal, estimate based on inc change
                let estDist = abs(landingInc - currentInc) * 10  // Rough estimate
                if estDist < 10 { return nil }
                distanceToLand = estDist
            } else {
                distanceToLand = tvdRemaining / cosAvgInc
            }
        } else {
            return nil
        }

        guard distanceToLand > 0 else { return nil }

        // Calculate required BR: BR = (target_inc - current_inc) / distance * 30
        let incChange = landingInc - currentInc
        let requiredBR = incChange / distanceToLand * 30.0

        return (requiredBR, distanceToLand, landingInc)
    }

    // MARK: - Summary Statistics

    struct VarianceSummary {
        let maxDistance3D: Double
        let avgDistance3D: Double
        let maxDLS: Double
        let maxTVDVariance: Double
        let maxClosureDistance: Double
        let stationCount: Int
        let alarmCount: Int
        let warningCount: Int
    }

    /// Calculate summary statistics for a set of variances
    static func summarize(
        variances: [SurveyVariance],
        limits: DirectionalLimits
    ) -> VarianceSummary {
        guard !variances.isEmpty else {
            return VarianceSummary(
                maxDistance3D: 0,
                avgDistance3D: 0,
                maxDLS: 0,
                maxTVDVariance: 0,
                maxClosureDistance: 0,
                stationCount: 0,
                alarmCount: 0,
                warningCount: 0
            )
        }

        var maxDist3D: Double = 0
        var sumDist3D: Double = 0
        var maxDLS: Double = 0
        var maxTVD: Double = 0
        var maxClosure: Double = 0
        var alarms = 0
        var warnings = 0

        for v in variances {
            maxDist3D = max(maxDist3D, v.distance3D)
            sumDist3D += v.distance3D
            maxDLS = max(maxDLS, v.surveyDLS)
            maxTVD = max(maxTVD, abs(v.tvdVariance))
            maxClosure = max(maxClosure, v.closureDistance)

            switch v.status(for: limits) {
            case .alarm: alarms += 1
            case .warning: warnings += 1
            case .ok: break
            }
        }

        return VarianceSummary(
            maxDistance3D: maxDist3D,
            avgDistance3D: sumDist3D / Double(variances.count),
            maxDLS: maxDLS,
            maxTVDVariance: maxTVD,
            maxClosureDistance: maxClosure,
            stationCount: variances.count,
            alarmCount: alarms,
            warningCount: warnings
        )
    }

    // MARK: - Bit Projection

    /// Project wellbore position from last survey to the bit
    /// - Parameters:
    ///   - lastSurvey: The most recent survey station
    ///   - previousSurvey: The survey before the last (for rate calculation)
    ///   - surveyToBitDistance: Distance from survey tool to bit (meters)
    ///   - plan: Directional plan to compare against
    ///   - vsdDirection: VS direction in degrees
    ///   - useRates: If true, applies current BR/TR to projection; if false, holds inc/azi constant
    /// - Returns: BitProjection with projected position and plan comparison
    static func projectToBit(
        lastSurvey: SurveyStation,
        previousSurvey: SurveyStation?,
        surveyToBitDistance: Double,
        plan: DirectionalPlan,
        vsdDirection: Double,
        useRates: Bool = true,
        targetTVD: Double? = nil
    ) -> BitProjection? {
        let planStations = plan.sortedStations
        guard !planStations.isEmpty else { return nil }

        let vsdRad = vsdDirection * .pi / 180.0
        let bitMD = lastSurvey.md + surveyToBitDistance

        // Check if bit MD is within plan range
        guard bitMD <= planStations.last!.md else { return nil }

        // Calculate current rates from last two surveys
        var currentBR: Double = 0
        var currentTR: Double = 0

        if useRates, let prevSurvey = previousSurvey {
            let intervalMD = lastSurvey.md - prevSurvey.md
            if intervalMD > 0 {
                let rates = calculateRates(
                    inc1: prevSurvey.inc, azi1: prevSurvey.azi,
                    inc2: lastSurvey.inc, azi2: lastSurvey.azi,
                    intervalMD: intervalMD
                )
                currentBR = rates.br
                currentTR = rates.tr
            }
        }

        // Project inclination and azimuth at bit
        // BR and TR are in deg/30m, convert to deg/m
        let brPerM = currentBR / 30.0
        let trPerM = currentTR / 30.0

        let bitInc = lastSurvey.inc + brPerM * surveyToBitDistance
        var bitAzi = lastSurvey.azi + trPerM * surveyToBitDistance
        if bitAzi < 0 { bitAzi += 360 }
        if bitAzi >= 360 { bitAzi -= 360 }

        // Project position using minimum curvature
        let projection = DirectionalSurveyService.minimumCurvature(
            md1: lastSurvey.md,
            inc1: lastSurvey.inc,
            azi1: lastSurvey.azi,
            md2: bitMD,
            inc2: bitInc,
            azi2: bitAzi
        )

        let bitTVD = (lastSurvey.tvd ?? 0) + projection.dTVD
        let bitNS = (lastSurvey.ns_m ?? 0) + projection.dNS
        let bitEW = (lastSurvey.ew_m ?? 0) + projection.dEW
        let bitVS = DirectionalSurveyService.calculateVS(ns: bitNS, ew: bitEW, vsdRad: vsdRad)

        // Get plan values at bit MD
        let planAtBit = interpolatePlan(at: bitMD, planStations: planStations, vsdRad: vsdRad)

        // Calculate required rates to land on plan from bit position
        // Project ahead to find target point on plan
        let projectionMD: Double = 30.0  // Standard 30m projection for rate calculation
        let targetMD = min(bitMD + projectionMD, planStations.last!.md)
        let targetPoint = interpolatePlan(at: targetMD, planStations: planStations, vsdRad: vsdRad)
        let actualProjectionMD = targetMD - bitMD

        let requiredRates = calculateRequiredRates(
            currentInc: bitInc, currentAzi: bitAzi,
            targetInc: targetPoint.inc, targetAzi: targetPoint.azi,
            projectionMD: actualProjectionMD > 0 ? actualProjectionMD : projectionMD
        )

        // Calculate BR required to reach target TVD (if set)
        let targetCalcs = calculateTargetTVDRates(
            currentTVD: bitTVD,
            currentInc: bitInc,
            targetTVD: targetTVD,
            planStations: planStations
        )

        return BitProjection(
            surveyMD: lastSurvey.md,
            surveyToBitDistance: surveyToBitDistance,
            bitMD: bitMD,
            bitTVD: bitTVD,
            bitNS: bitNS,
            bitEW: bitEW,
            bitVS: bitVS,
            bitInc: bitInc,
            bitAzi: bitAzi,
            planTVD: planAtBit.tvd,
            planNS: planAtBit.ns,
            planEW: planAtBit.ew,
            planVS: planAtBit.vs,
            planInc: planAtBit.inc,
            planAzi: planAtBit.azi,
            requiredBR: requiredRates.br,
            requiredTR: requiredRates.tr,
            projectionToTargetMD: actualProjectionMD > 0 ? actualProjectionMD : projectionMD,
            targetTVD: targetTVD,
            requiredBRToTarget: targetCalcs?.requiredBR,
            distanceToTarget: targetCalcs?.distance
        )
    }

    /// Project from raw survey data (for scenario surveys)
    /// - Parameters:
    ///   - surveyMD: MD of the survey point
    ///   - surveyInc: Inclination in degrees
    ///   - surveyAzi: Azimuth in degrees
    ///   - surveyTVD: TVD in meters
    ///   - surveyNS: Northing in meters
    ///   - surveyEW: Easting in meters
    ///   - previousMD: MD of previous survey (for rate calculation)
    ///   - previousInc: Inclination of previous survey
    ///   - previousAzi: Azimuth of previous survey
    ///   - surveyToBitDistance: Distance from survey to bit
    ///   - plan: Directional plan
    ///   - vsdDirection: VS direction in degrees
    ///   - useRates: Whether to apply rates to projection
    static func projectToBitFromData(
        surveyMD: Double,
        surveyInc: Double,
        surveyAzi: Double,
        surveyTVD: Double,
        surveyNS: Double,
        surveyEW: Double,
        previousMD: Double?,
        previousInc: Double?,
        previousAzi: Double?,
        surveyToBitDistance: Double,
        plan: DirectionalPlan,
        vsdDirection: Double,
        useRates: Bool = true,
        targetTVD: Double? = nil
    ) -> BitProjection? {
        let planStations = plan.sortedStations
        guard !planStations.isEmpty else { return nil }

        let vsdRad = vsdDirection * .pi / 180.0
        let bitMD = surveyMD + surveyToBitDistance

        // Check if bit MD is within plan range
        guard bitMD <= planStations.last!.md else { return nil }

        // Calculate current rates
        var currentBR: Double = 0
        var currentTR: Double = 0

        if useRates, let prevMD = previousMD, let prevInc = previousInc, let prevAzi = previousAzi {
            let intervalMD = surveyMD - prevMD
            if intervalMD > 0 {
                let rates = calculateRates(
                    inc1: prevInc, azi1: prevAzi,
                    inc2: surveyInc, azi2: surveyAzi,
                    intervalMD: intervalMD
                )
                currentBR = rates.br
                currentTR = rates.tr
            }
        }

        // Project inclination and azimuth at bit
        let brPerM = currentBR / 30.0
        let trPerM = currentTR / 30.0

        let bitInc = surveyInc + brPerM * surveyToBitDistance
        var bitAzi = surveyAzi + trPerM * surveyToBitDistance
        if bitAzi < 0 { bitAzi += 360 }
        if bitAzi >= 360 { bitAzi -= 360 }

        // Project position using minimum curvature
        let projection = DirectionalSurveyService.minimumCurvature(
            md1: surveyMD,
            inc1: surveyInc,
            azi1: surveyAzi,
            md2: bitMD,
            inc2: bitInc,
            azi2: bitAzi
        )

        let bitTVD = surveyTVD + projection.dTVD
        let bitNS = surveyNS + projection.dNS
        let bitEW = surveyEW + projection.dEW
        let bitVS = DirectionalSurveyService.calculateVS(ns: bitNS, ew: bitEW, vsdRad: vsdRad)

        // Get plan values at bit MD
        let planAtBit = interpolatePlan(at: bitMD, planStations: planStations, vsdRad: vsdRad)

        // Calculate required rates to land on plan from bit position
        let projectionMD: Double = 30.0
        let targetMD = min(bitMD + projectionMD, planStations.last!.md)
        let targetPoint = interpolatePlan(at: targetMD, planStations: planStations, vsdRad: vsdRad)
        let actualProjectionMD = targetMD - bitMD

        let requiredRates = calculateRequiredRates(
            currentInc: bitInc, currentAzi: bitAzi,
            targetInc: targetPoint.inc, targetAzi: targetPoint.azi,
            projectionMD: actualProjectionMD > 0 ? actualProjectionMD : projectionMD
        )

        // Calculate BR required to reach target TVD (if set)
        let targetCalcs = calculateTargetTVDRates(
            currentTVD: bitTVD,
            currentInc: bitInc,
            targetTVD: targetTVD,
            planStations: planStations
        )

        return BitProjection(
            surveyMD: surveyMD,
            surveyToBitDistance: surveyToBitDistance,
            bitMD: bitMD,
            bitTVD: bitTVD,
            bitNS: bitNS,
            bitEW: bitEW,
            bitVS: bitVS,
            bitInc: bitInc,
            bitAzi: bitAzi,
            planTVD: planAtBit.tvd,
            planNS: planAtBit.ns,
            planEW: planAtBit.ew,
            planVS: planAtBit.vs,
            planInc: planAtBit.inc,
            planAzi: planAtBit.azi,
            requiredBR: requiredRates.br,
            requiredTR: requiredRates.tr,
            projectionToTargetMD: actualProjectionMD > 0 ? actualProjectionMD : projectionMD,
            targetTVD: targetTVD,
            requiredBRToTarget: targetCalcs?.requiredBR,
            distanceToTarget: targetCalcs?.distance
        )
    }

    // MARK: - Boundary Corridor Calculation

    /// Calculate boundary corridor points around the plan for visualization
    /// - Parameters:
    ///   - planStations: Sorted plan stations
    ///   - radius: Tolerance radius in meters
    ///   - vsdRad: VSD in radians (for side view corridor)
    /// - Returns: Tuple of (warningBoundary, alarmBoundary) corridors
    static func calculateBoundaryCorridors(
        planStations: [DirectionalPlanStation],
        warningRadius: Double,
        alarmRadius: Double
    ) -> (warning: [(upper: Double, lower: Double)], alarm: [(upper: Double, lower: Double)]) {
        var warningBounds: [(upper: Double, lower: Double)] = []
        var alarmBounds: [(upper: Double, lower: Double)] = []

        for station in planStations {
            // For TVD corridors (used in side view)
            warningBounds.append((upper: station.tvd + warningRadius, lower: station.tvd - warningRadius))
            alarmBounds.append((upper: station.tvd + alarmRadius, lower: station.tvd - alarmRadius))
        }

        return (warning: warningBounds, alarm: alarmBounds)
    }
}
