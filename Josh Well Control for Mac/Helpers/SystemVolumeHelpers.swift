//
//  SystemVolumeHelpers.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-08.
//

import Foundation
import SwiftUI
import SwiftData

struct SystemVolumes {
    let total_m3: Double
    let annulus_m3: Double
    let string_m3: Double
}

extension ProjectState {
    /// Compute current in-hole volume for layers filtered by `mud` (nil = all muds).
    /// Uses finalLayers + current annulus/string geometry (like MudPlacementView).
    func inHoleVolume(for mud: MudProperties?, compute: (_ top: Double, _ bottom: Double) -> (
        annular_m3: Double, stringCapacity_m3: Double, disp_m3: Double, openHole_m3: Double
    )) -> SystemVolumes {

        // Build FinalLayer-like tuples filtered by mud
        struct Slice { let domainIsAnnulus: Bool; let top: Double; let bottom: Double; let density: Double }
        var ann: [Slice] = []
        var str: [Slice] = []

        for L in (finalLayers ?? []) {
            if let mud, L.mud?.id != mud.id { continue }
            let t = min(L.topMD_m, L.bottomMD_m)
            let b = max(L.topMD_m, L.bottomMD_m)
            if L.placement == Placement.annulus || L.placement == Placement.both {
                ann.append(.init(domainIsAnnulus: true, top: t, bottom: b, density: L.density_kgm3))
            }
            if L.placement == Placement.string || L.placement == Placement.both {
                str.append(.init(domainIsAnnulus: false, top: t, bottom: b, density: L.density_kgm3))
            }
        }

        func sumVolumes(_ parts: [Slice], pick: (_ annular: Bool) -> ( (Double, Double) -> Double ) ) -> Double {
            parts.reduce(0) { acc, s in
                let r = compute(s.top, s.bottom)
                let v = s.domainIsAnnulus ? r.annular_m3 : r.stringCapacity_m3
                return acc + v
            }
        }

        // We only need totals; compute() already accounts for OD changes per slice.
        let annulus = ann.reduce(0) { $0 + compute($1.top, $1.bottom).annular_m3 }
        let string  = str.reduce(0) { $0 + compute($1.top, $1.bottom).stringCapacity_m3 }
        return .init(total_m3: annulus + string, annulus_m3: annulus, string_m3: string)
    }
}

enum Mixing {
    /// Blend two fluids: result density
    static func blendDensity(rho1: Double, V1: Double, rho2: Double, V2: Double) -> Double {
        guard (V1 + V2) > 0 else { return rho1 }
        return (rho1*V1 + rho2*V2) / (V1 + V2)
    }

    /// Solve for V2 needed to hit a target with a given second-fluid density.
    /// Returns nil if target is unreachable with rho2.
    static func solveV2ForTarget(rho1: Double, V1: Double, rho2: Double, rhoTarget: Double) -> Double? {
        let denom = (rhoTarget - rho2)
        let numer = (rho1 - rhoTarget) * V1
        if abs(denom) < 1e-12 { return nil }                // degenerate
        let V2 = numer / denom
        if V2 < 0 { return nil }                            // needs removal, not addition
        return V2
    }

    /// Barite mass required to raise density from rhoM to rhoTarget in volume Vm.
    /// rhoB default ~4200 kg/m³. Returns kg of barite. Nil if invalid target.
    static func bariteMassForTarget(rhoM: Double, Vm: Double, rhoTarget: Double, rhoB: Double = 4200) -> Double? {
        guard rhoTarget > rhoM, rhoTarget < rhoB, Vm > 0 else { return nil }
        let denom = (1 - rhoTarget / rhoB)
        guard abs(denom) > 1e-12 else { return nil }
        return (rhoTarget - rhoM) * Vm / denom
    }
}
