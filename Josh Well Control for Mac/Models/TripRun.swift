//
//  TripRun.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-07.
//

import Foundation
import SwiftData

@Model
final class TripRun {
    @Attribute(.unique) var id: UUID = UUID()
    var createdAt: Date = Date.now
    var name: String = "Trip Run"

    // Inputs snapshot
    var startBitMD_m: Double
    var endMD_m: Double
    var step_m: Double
    var shoeTVD_m: Double
    var baseMudDensity_kgpm3: Double
    var backfillDensity_kgpm3: Double
    var targetESDAtTD_kgpm3: Double
    var crackFloat_kPa: Double
    var holdSABPOpen: Bool
    var initialSABP_kPa: Double

    // Summary outputs
    var minMarginToFrac_kPa: Double
    var maxSABP_kPa: Double

    @Relationship(deleteRule: .cascade, inverse: \TripSample.run) var samples: [TripSample]?
    @Relationship var project: ProjectState?

    init(startBitMD_m: Double, endMD_m: Double, step_m: Double,
         shoeTVD_m: Double, baseMudDensity_kgpm3: Double,
         backfillDensity_kgpm3: Double, targetESDAtTD_kgpm3: Double,
         crackFloat_kPa: Double, holdSABPOpen: Bool, initialSABP_kPa: Double,
         minMarginToFrac_kPa: Double, maxSABP_kPa: Double, project: ProjectState?) {
        self.startBitMD_m = startBitMD_m
        self.endMD_m = endMD_m
        self.step_m = step_m
        self.shoeTVD_m = shoeTVD_m
        self.baseMudDensity_kgpm3 = baseMudDensity_kgpm3
        self.backfillDensity_kgpm3 = backfillDensity_kgpm3
        self.targetESDAtTD_kgpm3 = targetESDAtTD_kgpm3
        self.crackFloat_kPa = crackFloat_kPa
        self.holdSABPOpen = holdSABPOpen
        self.initialSABP_kPa = initialSABP_kPa
        self.minMarginToFrac_kPa = minMarginToFrac_kPa
        self.maxSABP_kPa = maxSABP_kPa
        self.project = project
    }
}

@Model
final class TripSample {
    @Attribute(.unique) var id: UUID = UUID()
    var bitMD_m: Double
    var tvd_m: Double
    var total_kPa: Double
    var recommendedSABP_kPa: Double
    var nonLaminar: Bool

    @Relationship var run: TripRun?

    init(bitMD_m: Double, tvd_m: Double, total_kPa: Double,
         recommendedSABP_kPa: Double, nonLaminar: Bool) {
        self.bitMD_m = bitMD_m
        self.tvd_m = tvd_m
        self.total_kPa = total_kPa
        self.recommendedSABP_kPa = recommendedSABP_kPa
        self.nonLaminar = nonLaminar
    }
}
