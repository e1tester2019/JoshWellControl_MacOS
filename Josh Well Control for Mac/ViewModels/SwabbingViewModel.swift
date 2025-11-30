//
//  SwabbingViewModel.swift
//  Josh Well Control
//
//  ViewModel for swab/surge calculations
//

import Foundation
import SwiftUI
import Observation

@Observable
class SwabbingViewModel {
    // Inputs
    var bitMD_m: Double = 4000
    var theta600: Double = 60
    var theta300: Double = 40
    var hoistSpeed_mpermin: Double = 10
    var eccentricityFactor: Double = 1.2
    var step_m: Double = 5

    enum AxisDirection: String, CaseIterable, Identifiable {
        case shallowToDeep = "TD→0"
        case deepToShallow = "0→TD"
        var id: String { rawValue }
    }
    var axisDirection: AxisDirection = .shallowToDeep

    // Outputs
    var estimate: SwabEstimate? = nil

    // Rheology source indicators
    var mudLinkedCount: Int = 0
    var totalLayerCount: Int = 0
    var usedGlobalFallback: Bool = false

    /// Sets bitMD_m to the current drill string bottom MD for this project
    func syncBitDepth(to project: ProjectState) {
        let maxBottom = (project.drillString ?? []).map { $0.bottomDepth_m }.max() ?? 0
        if maxBottom > 0, abs(maxBottom - bitMD_m) > 1e-6 {
            bitMD_m = maxBottom
        }
    }

    var rheologyBadgeText: String {
        if totalLayerCount == 0 { return "No layers" }
        if mudLinkedCount == totalLayerCount { return "Rheology: mud checks (all)" }
        if mudLinkedCount == 0 {
            return usedGlobalFallback ? "Rheology: fallback θ600/θ300" : "Rheology: missing"
        }
        return usedGlobalFallback ? "Rheology: mud checks + fallback" : "Rheology: mud checks (partial)"
    }

    var rheologyBadgeTint: Color {
        if totalLayerCount == 0 { return .secondary }
        if mudLinkedCount == totalLayerCount { return .green }
        if mudLinkedCount == 0 { return usedGlobalFallback ? .orange : .red }
        return .orange
    }

    func preloadDefaults() {
        if bitMD_m <= 0 { bitMD_m = 1000 }
    }

    func compute(project: ProjectState, layers: [FinalFluidLayer]) {
        // Scope layers to this project
        let projectLayers = layers.filter { $0.project === project }
        let geom = ProjectGeometryService(project: project, currentStringBottomMD: bitMD_m)
        let dto = LayerResolver.slice(projectLayers,
                                      for: project,
                                      domain: .swabAboveBit,
                                      bitMD: bitMD_m,
                                      lowerLimitMD: 0)

        // Enrich each sliced layer with rheology from its source mud, if linked
        var linkedCount = 0
        let enriched: [SwabCalculator.LayerDTO] = dto.map { d in
            let mid = 0.5 * (d.topMD_m + d.bottomMD_m)
            if let src = projectLayers.first(where: {
                mid >= min($0.topMD_m, $0.bottomMD_m) - 1e-6 &&
                mid <= max($0.topMD_m, $0.bottomMD_m) + 1e-6
            }) {
                if let m = src.mud {
                    linkedCount += 1
                    return SwabCalculator.LayerDTO(
                        rho_kgpm3: d.rho_kgpm3,
                        topMD_m: d.topMD_m,
                        bottomMD_m: d.bottomMD_m,
                        K_Pa_s_n: m.k_powerLaw_Pa_s_n,
                        n_powerLaw: m.n_powerLaw,
                        theta600: m.dial600,
                        theta300: m.dial300
                    )
                }
            }
            // Fallback: leave as-is and allow global 600/300 to apply if provided
            return d
        }

        // Update indicators for UI
        self.totalLayerCount = enriched.count
        self.mudLinkedCount = linkedCount
        self.usedGlobalFallback = (linkedCount < enriched.count) && (theta600 > 0 && theta300 > 0)

        do {
            let calc = SwabCalculator()
            let est = try calc.estimateFromLayersPowerLaw(
                layers: enriched,
                theta600: theta600,
                theta300: theta300,
                hoistSpeed_mpermin: hoistSpeed_mpermin,
                eccentricityFactor: eccentricityFactor,
                step_m: step_m,
                geom: geom,
                traj: nil,
                sabpSafety: 1.0,
                floatIsOpen: true
            )
            self.estimate = est
        } catch {
            self.estimate = nil
        }
    }
}
