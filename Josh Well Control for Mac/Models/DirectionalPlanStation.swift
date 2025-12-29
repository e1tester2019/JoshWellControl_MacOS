//
//  DirectionalPlanStation.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-29.
//

import Foundation
import SwiftData

@Model
final class DirectionalPlanStation {
    var md: Double = 0.0       // Measured Depth (m)
    var inc: Double = 0.0      // Inclination (degrees)
    var azi: Double = 0.0      // Azimuth (degrees)
    var tvd: Double = 0.0      // True Vertical Depth (m)
    var ns_m: Double = 0.0     // North-South coordinate (m)
    var ew_m: Double = 0.0     // East-West coordinate (m)
    var vs_m: Double?          // Vertical Section (m) - optional, calculated

    // Inverse relationship back to plan
    @Relationship var plan: DirectionalPlan?

    init(md: Double = 0.0,
         inc: Double = 0.0,
         azi: Double = 0.0,
         tvd: Double = 0.0,
         ns_m: Double = 0.0,
         ew_m: Double = 0.0,
         vs_m: Double? = nil,
         plan: DirectionalPlan? = nil) {
        self.md = md
        self.inc = inc
        self.azi = azi
        self.tvd = tvd
        self.ns_m = ns_m
        self.ew_m = ew_m
        self.vs_m = vs_m
        self.plan = plan
    }
}

// MARK: - Computed Properties

extension DirectionalPlanStation {
    /// Horizontal departure from origin
    var departure_m: Double {
        sqrt(ns_m * ns_m + ew_m * ew_m)
    }

    /// Direction from origin (azimuth in degrees)
    var direction_deg: Double {
        guard departure_m > 0.001 else { return 0 }
        let rad = atan2(ew_m, ns_m)
        let deg = rad * 180.0 / .pi
        return deg < 0 ? deg + 360 : deg
    }
}

// MARK: - Export

extension DirectionalPlanStation {
    var exportDictionary: [String: Any] {
        [
            "md": md,
            "inc": inc,
            "azi": azi,
            "tvd": tvd,
            "ns_m": ns_m,
            "ew_m": ew_m,
            "vs_m": vs_m ?? NSNull()
        ]
    }
}
