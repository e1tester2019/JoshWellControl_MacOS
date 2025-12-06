//
//  CementJob.swift
//  Josh Well Control for Mac
//
//  Created for CloudKit compatibility
//

import Foundation
import SwiftData
import SwiftUI

@Model
final class CementJob {
    var id: UUID = UUID()

    var name: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    // Cement job properties
    var targetDepth_m: Double = 0.0
    var casingOD_m: Double = 0.0
    var casingID_m: Double = 0.0
    var holeSize_m: Double = 0.0

    // Relationship to stages (with inverse)
    @Relationship(deleteRule: .cascade, inverse: \CementJobStage.cementJob)
    var stages: [CementJobStage]?

    // Back-reference to owning project
    @Relationship var project: ProjectState?

    init(name: String = "Cement Job",
         targetDepth_m: Double = 0.0,
         casingOD_m: Double = 0.0,
         casingID_m: Double = 0.0,
         holeSize_m: Double = 0.0,
         project: ProjectState? = nil) {
        self.name = name
        self.targetDepth_m = targetDepth_m
        self.casingOD_m = casingOD_m
        self.casingID_m = casingID_m
        self.holeSize_m = holeSize_m
        self.project = project
    }
}
