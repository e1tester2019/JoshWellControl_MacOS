//
//  SurveyVariance.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-29.
//

import Foundation
import SwiftUI

/// Variance status for color-coded display
enum VarianceStatus: String, CaseIterable {
    case ok       // Green - within all limits
    case warning  // Yellow - exceeded warning threshold
    case alarm    // Red - exceeded hard limit

    var color: Color {
        switch self {
        case .ok: return .green
        case .warning: return .yellow
        case .alarm: return .red
        }
    }

    var icon: String {
        switch self {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .alarm: return "xmark.octagon.fill"
        }
    }

    var label: String {
        switch self {
        case .ok: return "OK"
        case .warning: return "Warning"
        case .alarm: return "Alarm"
        }
    }
}

/// Calculated variance data for a single survey station compared to plan
/// Not persisted - computed on demand
struct SurveyVariance: Identifiable {
    let id = UUID()

    // Survey values (actual measurements)
    let surveyMD: Double
    let surveyTVD: Double
    let surveyNS: Double
    let surveyEW: Double
    let surveyVS: Double
    let surveyInc: Double
    let surveyAzi: Double
    let surveyDLS: Double        // Actual DLS at this station (deg/30m)
    let surveyBR: Double         // Actual Build Rate (deg/30m) - positive = building
    let surveyTR: Double         // Actual Turn Rate (deg/30m) - positive = turning right

    // Interpolated plan values at survey MD
    let planTVD: Double
    let planNS: Double
    let planEW: Double
    let planVS: Double
    let planInc: Double
    let planAzi: Double
    let planDLS: Double          // Plan DLS at this point
    let planBR: Double           // Plan Build Rate at this point
    let planTR: Double           // Plan Turn Rate at this point

    // Required rates to return to plan (calculated for next 30m or to target)
    let requiredBR: Double       // Build Rate required to intercept plan
    let requiredTR: Double       // Turn Rate required to intercept plan
    let projectionDistance: Double  // Distance used for projection (typically 30m or to next plan station)

    // MARK: - Computed Variances

    /// TVD variance (positive = deeper than plan)
    var tvdVariance: Double {
        surveyTVD - planTVD
    }

    /// Vertical Section variance (positive = ahead of plan)
    var vsVariance: Double {
        surveyVS - planVS
    }

    /// Horizontal closure distance from plan (always positive)
    var closureDistance: Double {
        let dNS = surveyNS - planNS
        let dEW = surveyEW - planEW
        return sqrt(dNS * dNS + dEW * dEW)
    }

    /// 3D distance from plan (always positive)
    var distance3D: Double {
        let dTVD = surveyTVD - planTVD
        let dNS = surveyNS - planNS
        let dEW = surveyEW - planEW
        return sqrt(dTVD * dTVD + dNS * dNS + dEW * dEW)
    }

    /// Inclination variance (positive = higher inclination than plan)
    var incVariance: Double {
        surveyInc - planInc
    }

    /// Azimuth variance (normalized to -180 to +180)
    var aziVariance: Double {
        var delta = surveyAzi - planAzi
        while delta > 180 { delta -= 360 }
        while delta < -180 { delta += 360 }
        return delta
    }

    /// Build Rate variance (positive = building faster than plan)
    var brVariance: Double {
        surveyBR - planBR
    }

    /// Turn Rate variance (positive = turning more right than plan)
    var trVariance: Double {
        surveyTR - planTR
    }

    /// DLS variance (positive = more dogleg than plan)
    var dlsVariance: Double {
        surveyDLS - planDLS
    }

    // MARK: - Status Determination

    /// Determine overall status based on limits
    func status(for limits: DirectionalLimits) -> VarianceStatus {
        // Check DLS first
        if surveyDLS > limits.maxDLS_deg_per30m {
            return .alarm
        }
        if surveyDLS > limits.warningDLS_deg_per30m {
            return .warning
        }

        // Check 3D distance
        if distance3D > limits.maxDistance3D_m {
            return .alarm
        }
        if distance3D > limits.warningDistance3D_m {
            return .warning
        }

        // Check TVD variance if specific limits are set
        if let maxTVD = limits.maxTVDVariance_m, abs(tvdVariance) > maxTVD {
            return .alarm
        }
        if let warnTVD = limits.warningTVDVariance_m, abs(tvdVariance) > warnTVD {
            return .warning
        }

        // Check closure distance if specific limits are set
        if let maxClosure = limits.maxClosureDistance_m, closureDistance > maxClosure {
            return .alarm
        }
        if let warnClosure = limits.warningClosureDistance_m, closureDistance > warnClosure {
            return .warning
        }

        return .ok
    }

    /// Get individual metric statuses for detailed display
    func dlsStatus(for limits: DirectionalLimits) -> VarianceStatus {
        if surveyDLS > limits.maxDLS_deg_per30m { return .alarm }
        if surveyDLS > limits.warningDLS_deg_per30m { return .warning }
        return .ok
    }

    func distance3DStatus(for limits: DirectionalLimits) -> VarianceStatus {
        if distance3D > limits.maxDistance3D_m { return .alarm }
        if distance3D > limits.warningDistance3D_m { return .warning }
        return .ok
    }

    func tvdStatus(for limits: DirectionalLimits) -> VarianceStatus {
        if let max = limits.maxTVDVariance_m, abs(tvdVariance) > max { return .alarm }
        if let warn = limits.warningTVDVariance_m, abs(tvdVariance) > warn { return .warning }
        // Fall back to 3D distance status if no specific TVD limits
        if limits.maxTVDVariance_m == nil {
            return distance3DStatus(for: limits)
        }
        return .ok
    }

    func closureStatus(for limits: DirectionalLimits) -> VarianceStatus {
        if let max = limits.maxClosureDistance_m, closureDistance > max { return .alarm }
        if let warn = limits.warningClosureDistance_m, closureDistance > warn { return .warning }
        // Fall back to 3D distance status if no specific closure limits
        if limits.maxClosureDistance_m == nil {
            return distance3DStatus(for: limits)
        }
        return .ok
    }
}

// MARK: - Bit Projection

/// Projected position at the bit based on last survey
struct BitProjection {
    // Projection inputs
    let surveyMD: Double           // MD of last survey
    let surveyToBitDistance: Double // Distance from survey tool to bit
    let bitMD: Double              // Projected bit MD

    // Projected bit position (using current inc/azi and rates)
    let bitTVD: Double
    let bitNS: Double
    let bitEW: Double
    let bitVS: Double
    let bitInc: Double             // Projected inclination at bit
    let bitAzi: Double             // Projected azimuth at bit

    // Plan values at bit MD
    let planTVD: Double
    let planNS: Double
    let planEW: Double
    let planVS: Double
    let planInc: Double
    let planAzi: Double

    // Required rates to land on target (from bit position)
    let requiredBR: Double         // Build rate required to intercept plan (deg/30m)
    let requiredTR: Double         // Turn rate required to intercept plan (deg/30m)
    let projectionToTargetMD: Double  // Distance to target point used for calculation

    // Target-based calculations (when user sets a specific target)
    let targetTVD: Double?           // User's target TVD (nil = use plan)
    let targetLandingInc: Double?    // User's target landing inclination
    let userDistanceToLand: Double?  // User-specified distance to land
    let calculatedDistanceToLand: Double?  // Auto-calculated distance to land
    let requiredBRToTarget: Double?  // BR required to reach target

    // Variances at bit
    var tvdVariance: Double { bitTVD - planTVD }
    var vsVariance: Double { bitVS - planVS }
    var closureDistance: Double {
        let dNS = bitNS - planNS
        let dEW = bitEW - planEW
        return sqrt(dNS * dNS + dEW * dEW)
    }
    var distance3D: Double {
        let dTVD = bitTVD - planTVD
        let dNS = bitNS - planNS
        let dEW = bitEW - planEW
        return sqrt(dTVD * dTVD + dNS * dNS + dEW * dEW)
    }
    var incVariance: Double { bitInc - planInc }
    var aziVariance: Double {
        var delta = bitAzi - planAzi
        while delta > 180 { delta -= 360 }
        while delta < -180 { delta += 360 }
        return delta
    }

    /// Status at projected bit position
    func status(for limits: DirectionalLimits) -> VarianceStatus {
        if distance3D > limits.maxDistance3D_m { return .alarm }
        if distance3D > limits.warningDistance3D_m { return .warning }
        if let maxTVD = limits.maxTVDVariance_m, abs(tvdVariance) > maxTVD { return .alarm }
        if let warnTVD = limits.warningTVDVariance_m, abs(tvdVariance) > warnTVD { return .warning }
        return .ok
    }
}

// MARK: - Formatting Helpers

extension SurveyVariance {
    /// Format a variance value with sign and unit
    static func formatVariance(_ value: Double, unit: String = "m", decimals: Int = 2) -> String {
        let sign = value >= 0 ? "+" : ""
        return String(format: "\(sign)%.\(decimals)f \(unit)", value)
    }

    /// Format a distance value (always positive)
    static func formatDistance(_ value: Double, unit: String = "m", decimals: Int = 2) -> String {
        return String(format: "%.\(decimals)f \(unit)", value)
    }
}
