//
//  ProjectState.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-02.
//

import Foundation
import SwiftData

@Model
final class ProjectState {
    @Attribute(.unique) var id: UUID = UUID()

    // NEW — versioning & well linkage
    var name: String = "Baseline"
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var basedOnProjectID: UUID? = nil

    @Relationship(inverse: \Well.projects) var well: Well?

    // Collections (as you already have)
    @Relationship(deleteRule: .cascade) var surveys: [SurveyStation] = []
    @Relationship(deleteRule: .cascade) var drillString: [DrillStringSection] = []
    @Relationship(deleteRule: .cascade) var annulus: [AnnulusSection] = []
    @Relationship(deleteRule: .cascade) var mudSteps: [MudStep] = []
    @Relationship(deleteRule: .cascade) var finalLayers: [FinalFluidLayer] = []

    // Singletons
    var window: PressureWindow = PressureWindow()
    var slug: SlugPlan = SlugPlan()
    var backfill: BackfillPlan = BackfillPlan()
    var settings: TripSettings = TripSettings()
    var swab: SwabInput = SwabInput()

    var baseAnnulusDensity_kgm3: Double = 1260
    var baseStringDensity_kgm3: Double = 1260
    var pressureDepth_m: Double = 3200
    var activeMudDensity_kgm3: Double = 1260
    var activeMudVolume_m3: Double = 56.5
    var surfaceLineVolume_m3: Double = 1.4

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

extension ProjectState {
    /// Update the timestamp when you mutate state.
    func touchUpdated() {
        self.updatedAt = .now
    }

    /// Replace the persisted final layers with a new set and save.
    /// Call this from Mud Placement after committing a run.
    func replaceFinalLayers(with newLayers: [FinalFluidLayer], using context: ModelContext) {
        self.finalLayers.removeAll()
        self.finalLayers.append(contentsOf: newLayers)
        self.updatedAt = .now
        try? context.save()
    }

    /// Create a shallow snapshot of this project under the provided well.
    /// Collections (surveys, drillString, annulus, mudSteps, finalLayers) are NOT copied here.
    /// Use `deepClone(into:using:)` if you want a full snapshot.
    func shallowClone(into well: Well, using context: ModelContext) -> ProjectState {
        let p = ProjectState()
        p.name = self.name + " (Copy)"
        p.baseAnnulusDensity_kgm3 = self.baseAnnulusDensity_kgm3
        p.baseStringDensity_kgm3 = self.baseStringDensity_kgm3
        p.pressureDepth_m = self.pressureDepth_m
        p.well = well
        well.projects.append(p)
        try? context.save()
        return p
    }

    /// Full snapshot: duplicates major collections and reattaches to the new project under `well`.
    /// Assumes element initializers with settable properties exist for each model type.
    func deepClone(into well: Well, using context: ModelContext) -> ProjectState {
        let p = shallowClone(into: well, using: context)

        // Surveys
        for s0 in self.surveys {
            let s = SurveyStation(
                md: s0.md,
                inc: s0.inc,
                azi: s0.azi,
                tvd: s0.tvd)
            p.surveys.append(s)
        }

        // Drill string
        for d0 in self.drillString {
            let d = DrillStringSection(
                name: d0.name,
                topDepth_m: d0.topDepth_m,
                length_m: d0.length_m,
                outerDiameter_m: d0.outerDiameter_m,
                innerDiameter_m: d0.innerDiameter_m,
                toolJointOD_m: d0.toolJointOD_m,
                jointLength_m: d0.jointLength_m,
                grade: d0.grade,
                steelDensity_kg_per_m3: d0.steelDensity_kg_per_m3,
                unitWeight_kg_per_m: d0.unitWeight_kg_per_m,
                internalRoughness_m: d0.internalRoughness_m,
                project: p
            )
            p.drillString.append(d)
        }

        // Annulus
        for a0 in self.annulus {
            let a = AnnulusSection(
                name: a0.name,
                topDepth_m: a0.topDepth_m,
                length_m: a0.length_m,
                innerDiameter_m: a0.innerDiameter_m,
                outerDiameter_m: a0.outerDiameter_m,
                inclination_deg: a0.inclination_deg,
                wallRoughness_m: a0.wallRoughness_m,
                rheologyModel: a0.rheologyModel,
                density_kg_per_m3: a0.density_kg_per_m3,
                dynamicViscosity_Pa_s: a0.dynamicViscosity_Pa_s,
                pv_Pa_s: a0.pv_Pa_s,
                yp_Pa: a0.yp_Pa,
                n_powerLaw: a0.n_powerLaw,
                k_powerLaw_Pa_s_n: a0.k_powerLaw_Pa_s_n,
                hb_tau0_Pa: a0.hb_tau0_Pa,
                hb_n: a0.hb_n,
                hb_k_Pa_s_n: a0.hb_k_Pa_s_n,
                cuttingsVolFrac: a0.cuttingsVolFrac,
                project: p
            )
            p.annulus.append(a)
        }

        // Mud steps
        for m0 in self.mudSteps {
            let m = MudStep(
                name: m0.name,
                top_m: m0.top_m,
                bottom_m: m0.bottom_m,
                density_kgm3: m0.density_kgm3,
                colorHex: m0.colorHex,
                placementRaw: m0.placementRaw,
                project: p
            )
            p.mudSteps.append(m)
        }

        // Final layers
        for f0 in self.finalLayers {
            let f = FinalFluidLayer(
                project: p,
                name: f0.name,
                placement: f0.placement,
                topMD_m: f0.topMD_m,
                bottomMD_m: f0.bottomMD_m,
                density_kgm3: f0.density_kgm3,
                color: f0.color,
                createdAt: f0.createdAt
            )
            p.finalLayers.append(f)
        }

        // Singletons (best-effort copy of scalars). If these are structs/value types this is fine.
        // If they are reference types and you want true deep copies, mirror the field-by-field approach above.
        p.window = self.window
        p.slug = self.slug
        p.backfill = self.backfill
        p.settings = self.settings
        p.swab = self.swab

        p.updatedAt = .now
        try? context.save()
        return p
    }
}
