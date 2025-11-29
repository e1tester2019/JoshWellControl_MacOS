//
//  SurveyStation.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-02.
//

import SwiftData

@Model
final class SurveyStation {
    var md: Double = 0.0
    var inc: Double = 0.0
    var azi: Double = 0.0
    var tvd: Double?

    // Inverse relationship back to project
    @Relationship(inverse: \ProjectState.surveys) var project: ProjectState?

    // Optional extras (from Pason exports)
    var vs_m: Double?            // Vertical Section (m)
    var ns_m: Double?            // North-South (m)
    var ew_m: Double?            // East-West (m)
    var dls_deg_per30m: Double?  // Dogleg Severity (deg/30 m)
    var subsea_m: Double?        // Subsea TVD (m)
    var buildRate_deg_per30m: Double?
    var turnRate_deg_per30m: Double?

    // Optional metadata
    var vsd_direction_deg: Double?
    var sourceFileName: String?

    init(md: Double,
         inc: Double,
         azi: Double,
         tvd: Double? = nil,
         vs_m: Double? = nil,
         ns_m: Double? = nil,
         ew_m: Double? = nil,
         dls_deg_per30m: Double? = nil,
         subsea_m: Double? = nil,
         buildRate_deg_per30m: Double? = nil,
         turnRate_deg_per30m: Double? = nil,
         vsd_direction_deg: Double? = nil,
         sourceFileName: String? = nil) {
        self.md = md
        self.inc = inc
        self.azi = azi
        self.tvd = tvd
        self.vs_m = vs_m
        self.ns_m = ns_m
        self.ew_m = ew_m
        self.dls_deg_per30m = dls_deg_per30m
        self.subsea_m = subsea_m
        self.buildRate_deg_per30m = buildRate_deg_per30m
        self.turnRate_deg_per30m = turnRate_deg_per30m
        self.vsd_direction_deg = vsd_direction_deg
        self.sourceFileName = sourceFileName
    }
}
