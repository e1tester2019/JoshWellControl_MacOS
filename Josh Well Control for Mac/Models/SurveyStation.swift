//
//  SurveyStation.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-02.
//

import SwiftData

@Model
final class SurveyStation {
    var md: Double
    var inc: Double
    var azi: Double
    var tvd: Double?

    init(md: Double, inc: Double, azi: Double, tvd: Double?) {
        self.md = md
        self.inc = inc
        self.azi = azi
        self.tvd = tvd
    }
}
