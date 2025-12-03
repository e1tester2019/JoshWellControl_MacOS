//
//  SwabRun.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-07.
//

import Foundation
import SwiftData

@Model
final class SwabRun {
    @Attribute var id: UUID = UUID()
    var createdAt: Date = Date.now
    var name: String = "Swab Run"

    // Inputs snapshot (store what matters to reproduce)
    var bitMD_m: Double = 0
    var topMD_m: Double = 0
    var lowerLimitMD_m: Double = 0
    var pipeOD_m: Double = 0
    var equivalentDia_m: Double = 0
    var swabSpeed_mps: Double = 0

    // Outputs summary
    var maxUnderbalance_kPa: Double = 0
    var nonLaminar: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \SwabSample.run) var samples: [SwabSample]?
    @Relationship var project: ProjectState?

    init(bitMD_m: Double, topMD_m: Double, lowerLimitMD_m: Double,
         pipeOD_m: Double, equivalentDia_m: Double, swabSpeed_mps: Double,
         maxUnderbalance_kPa: Double, nonLaminar: Bool, project: ProjectState?) {
        self.bitMD_m = bitMD_m
        self.topMD_m = topMD_m
        self.lowerLimitMD_m = lowerLimitMD_m
        self.pipeOD_m = pipeOD_m
        self.equivalentDia_m = equivalentDia_m
        self.swabSpeed_mps = swabSpeed_mps
        self.maxUnderbalance_kPa = maxUnderbalance_kPa
        self.nonLaminar = nonLaminar
        self.project = project
    }
}

@Model
final class SwabSample {
    @Attribute var id: UUID = UUID()
    var md_m: Double = 0
    var tvd_m: Double = 0
    var dP_kPa: Double = 0

    @Relationship var run: SwabRun?

    init(md_m: Double, tvd_m: Double, dP_kPa: Double) {
        self.md_m = md_m
        self.tvd_m = tvd_m
        self.dP_kPa = dP_kPa
    }
}
