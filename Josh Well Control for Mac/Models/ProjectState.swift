//
//  ProjectState.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-02.
//

import Foundation
import SwiftData

import Foundation
import SwiftData

@Model
final class ProjectState {
    @Attribute(.unique) var id: UUID = UUID()

    // MARK: - Collections
    @Relationship(deleteRule: .cascade) var surveys: [SurveyStation] = []
    @Relationship(deleteRule: .cascade) var drillString: [DrillStringSection] = []
    @Relationship(deleteRule: .cascade) var annulus: [AnnulusSection] = []
    @Relationship(deleteRule: .cascade) var mudSteps: [MudStep] = []
    @Relationship(deleteRule: .cascade) var finalLayers: [FinalFluidLayer] = []

    // MARK: - Single Objects
    var window: PressureWindow = PressureWindow()
    var slug: SlugPlan = SlugPlan()
    var backfill: BackfillPlan = BackfillPlan()
    var settings: TripSettings = TripSettings()
    var swab: SwabInput = SwabInput()

    // Optional ECD Mud Cap (commented out in your C#)
    // var ecdMudCap: EcdMudCapState? = nil
    
    var baseAnnulusDensity_kgm3: Double = 1260
    var baseStringDensity_kgm3: Double = 1260
    var pressureDepth_m: Double = 3200
    
    // Placed (final) layers for display

    init() {}
}


