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

extension ProjectState {
    /// TVD at an arbitrary MD using linear interpolation over `surveys`.
    func tvd(of mdQuery: Double) -> Double {
        guard !surveys.isEmpty else { return mdQuery } // fallback
        // Sort once per call (fast enough, or cache if you like)
        let s = surveys.sorted { $0.md < $1.md }

        if mdQuery <= s.first!.md { return s.first!.tvd ?? 0 }
        if mdQuery >= s.last!.md  { return s.last!.tvd ?? 0 }

        // Binary search for bracketing indices
        var lo = 0, hi = s.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if s[mid].md <= mdQuery { lo = mid } else { hi = mid }
        }

        let md0 = s[lo].md,  md1 = s[hi].md
        let tv0 = s[lo].tvd, tv1 = s[hi].tvd
        let t = (mdQuery - md0) / max(md1 - md0, 1e-12)
        return (tv0 ?? 0.0) + t * ((tv1 ?? 0.0) - (tv0 ?? 0.0))
    }
}

extension ProjectState {
    var finalAnnulusLayersSorted: [FinalFluidLayer] {
        finalLayers.filter { $0.placement == .annulus }.sorted { $0.topMD_m < $1.topMD_m }
    }
    var finalStringLayersSorted: [FinalFluidLayer] {
        finalLayers.filter { $0.placement == .string }.sorted { $0.topMD_m < $1.topMD_m }
    }
}


