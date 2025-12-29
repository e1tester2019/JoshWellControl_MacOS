//
//  DirectionalLimits.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-29.
//

import Foundation
import SwiftData

@Model
final class DirectionalLimits {
    // DLS Limits (degrees per 30m)
    var maxDLS_deg_per30m: Double = 6.0           // Max allowed dogleg severity (red threshold)
    var warningDLS_deg_per30m: Double = 4.5       // Warning threshold (yellow)

    // 3D Distance from Plan Limits (meters)
    var maxDistance3D_m: Double = 10.0            // Max allowed 3D offset from plan (red threshold)
    var warningDistance3D_m: Double = 5.0         // Warning threshold (yellow)

    // Optional: separate TVD/closure limits (nil = use 3D limit)
    var maxTVDVariance_m: Double?                 // Max allowed TVD variance
    var warningTVDVariance_m: Double?             // Warning TVD variance
    var maxClosureDistance_m: Double?             // Max allowed horizontal closure distance
    var warningClosureDistance_m: Double?         // Warning horizontal closure distance

    // Inverse relationship back to project
    @Relationship var project: ProjectState?

    init(maxDLS_deg_per30m: Double = 6.0,
         warningDLS_deg_per30m: Double = 4.5,
         maxDistance3D_m: Double = 10.0,
         warningDistance3D_m: Double = 5.0,
         maxTVDVariance_m: Double? = nil,
         warningTVDVariance_m: Double? = nil,
         maxClosureDistance_m: Double? = nil,
         warningClosureDistance_m: Double? = nil,
         project: ProjectState? = nil) {
        self.maxDLS_deg_per30m = maxDLS_deg_per30m
        self.warningDLS_deg_per30m = warningDLS_deg_per30m
        self.maxDistance3D_m = maxDistance3D_m
        self.warningDistance3D_m = warningDistance3D_m
        self.maxTVDVariance_m = maxTVDVariance_m
        self.warningTVDVariance_m = warningTVDVariance_m
        self.maxClosureDistance_m = maxClosureDistance_m
        self.warningClosureDistance_m = warningClosureDistance_m
        self.project = project
    }
}

// MARK: - Export

extension DirectionalLimits {
    var exportDictionary: [String: Any] {
        [
            "maxDLS_deg_per30m": maxDLS_deg_per30m,
            "warningDLS_deg_per30m": warningDLS_deg_per30m,
            "maxDistance3D_m": maxDistance3D_m,
            "warningDistance3D_m": warningDistance3D_m,
            "maxTVDVariance_m": maxTVDVariance_m ?? NSNull(),
            "warningTVDVariance_m": warningTVDVariance_m ?? NSNull(),
            "maxClosureDistance_m": maxClosureDistance_m ?? NSNull(),
            "warningClosureDistance_m": warningClosureDistance_m ?? NSNull()
        ]
    }
}
