//
//  MudPlacementViewModel.swift
//  Josh Well Control
//
//  ViewModel for mud placement and final layer management
//

import Foundation
import SwiftUI
import SwiftData
import Observation

@Observable
class MudPlacementViewModel {
    var project: ProjectState
    private var context: ModelContext?

    var mudsSortedByName: [MudProperties] {
        (project.muds ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    init(project: ProjectState) {
        self.project = project
    }

    func attach(context: ModelContext) {
        self.context = context
    }

    // MARK: - Steps Management

    var steps: [MudStep] {
        (project.mudSteps ?? []).sorted { a, b in
            let ra = placementRank(a.placement)
            let rb = placementRank(b.placement)
            if ra != rb { return ra < rb }
            if a.top_m != b.top_m { return a.top_m < b.top_m }
            return a.bottom_m < b.bottom_m
        }
    }

    private func placementRank(_ p: Placement) -> Int {
        switch p {
        case .annulus: return 0
        case .string: return 1
        case .both: return 2
        }
    }

    func seedInitialSteps() {
        let samples: [MudStep] = [
            MudStep(name: "Annulus Kill", top_m: 687,  bottom_m: 1010, density_kgm3: 1800, color: .blue,   placement: .annulus, project: project),
            MudStep(name: "Active Mud",   top_m: 1010, bottom_m: 2701, density_kgm3: 1260, color: .yellow, placement: .annulus, project: project),
            MudStep(name: "Lube Blend",   top_m: 2701, bottom_m: 6000, density_kgm3: 1260, color: .orange, placement: .both,    project: project),
            MudStep(name: "Active Mud",   top_m: 2040, bottom_m: 2701, density_kgm3: 1260, color: .yellow, placement: .string,  project: project),
            MudStep(name: "Balance Slug", top_m: 1705, bottom_m: 2040, density_kgm3: 1800, color: .blue,   placement: .string,  project: project),
            MudStep(name: "Active Mud",   top_m: 596,  bottom_m: 1705, density_kgm3: 1260, color: .yellow, placement: .string,  project: project),
            MudStep(name: "Dry Pipe Slug",top_m: 220,  bottom_m: 596,  density_kgm3: 2100, color: .brown,  placement: .string,  project: project),
            MudStep(name: "Air",          top_m: 0,    bottom_m: 221,  density_kgm3: 1.2,  color: .cyan,   placement: .string,  project: project)
        ]
        let existing = Set((project.mudSteps ?? []).map { "\($0.name)|\($0.top_m)|\($0.bottom_m)" })
        for s in samples where !existing.contains("\(s.name)|\(s.top_m)|\(s.bottom_m)") {
            context?.insert(s)
        }
        try? context?.save()
    }

    func deleteStep(_ s: MudStep) {
        if let idx = (project.mudSteps ?? []).firstIndex(where: { $0 === s }) {
            project.mudSteps?.remove(at: idx)
        }
        context?.delete(s)
        try? context?.save()
    }

    func clearAllSteps() {
        for s in (project.mudSteps ?? []) {
            context?.delete(s)
        }
        project.mudSteps?.removeAll()
        try? context?.save()
    }

    // MARK: - Geometry & Volume Calculations

    func uniqueBoundaries(_ values: [Double], tol: Double = 1e-6) -> [Double] {
        let sorted = values.sorted()
        var out: [Double] = []
        for v in sorted {
            if let last = out.last, abs(last - v) <= tol { continue }
            out.append(v)
        }
        return out
    }

    func computeVolumesBetween(top: Double, bottom: Double) -> (
        length_m: Double,
        annular_m3: Double, annularPerM_m3perm: Double,
        stringCapacity_m3: Double, stringCapacityPerM_m3perm: Double,
        stringDisp_m3: Double, stringDispPerM_m3perm: Double,
        openHole_m3: Double, openHolePerM_m3perm: Double,
        stringMetal_m3: Double, stringMetalPerM_m3perm: Double
    ) {
        guard bottom > top else { return (0,0,0,0,0,0,0,0,0,0,0) }
        var bounds: [Double] = [top, bottom]
        for a in (project.annulus ?? []) where a.bottomDepth_m > top && a.topDepth_m < bottom {
            bounds.append(max(a.topDepth_m, top))
            bounds.append(min(a.bottomDepth_m, bottom))
        }
        for d in (project.drillString ?? []) where d.bottomDepth_m > top && d.topDepth_m < bottom {
            bounds.append(max(d.topDepth_m, top))
            bounds.append(min(d.bottomDepth_m, bottom))
        }
        let uniq = uniqueBoundaries(bounds)
        if uniq.count < 2 { return (0,0,0,0,0,0,0,0,0,0,0) }

        var annular = 0.0, openHole = 0.0, strCap = 0.0, strDisp = 0.0, strMetal = 0.0, L = 0.0
        for i in 0..<(uniq.count - 1) {
            let t = uniq[i], b = uniq[i+1]
            guard b > t else { continue }
            L += (b - t)
            let ann = (project.annulus ?? []).first { $0.topDepth_m <= t && $0.bottomDepth_m >= b }
            let str = (project.drillString ?? []).first { $0.topDepth_m <= t && $0.bottomDepth_m >= b }
            if let a = ann {
                let id = max(a.innerDiameter_m, 0)
                openHole += (.pi * id * id / 4.0) * (b - t)
                let od = max(str?.outerDiameter_m ?? 0, 0)
                let areaAnn = max(0, .pi * (id*id - od*od) / 4.0)
                annular += areaAnn * (b - t)
            }
            if let s = str {
                let idStr = max(s.innerDiameter_m, 0)
                let odStr = max(s.outerDiameter_m, 0)
                strCap += (.pi * idStr * idStr / 4.0) * (b - t)
                strDisp += (.pi * odStr * odStr / 4.0) * (b - t)
                strMetal += max(0, .pi * (odStr*odStr - idStr*idStr) / 4.0) * (b - t)
            }
        }
        return (
            L,
            annular, L>0 ? annular/L : 0,
            strCap,  L>0 ? strCap/L  : 0,
            strDisp, L>0 ? strDisp/L : 0,
            openHole, L>0 ? openHole/L : 0,
            strMetal, L>0 ? strMetal/L : 0
        )
    }

    func totalMudWithPipeBetween(top: Double, bottom: Double) -> (total_m3: Double, annular_m3: Double, string_m3: Double) {
        guard bottom > top else { return (0,0,0) }
        let r = computeVolumesBetween(top: top, bottom: bottom)
        return (r.annular_m3 + r.stringCapacity_m3, r.annular_m3, r.stringCapacity_m3)
    }

    func solvePipeInIntervalForEqualVolume(targetTop: Double, targetBottom: Double, tol: Double = 1e-6, maxIter: Int = 60) -> (length_m: Double, total_m3: Double, annular_m3: Double, string_m3: Double, mudTop_m: Double) {
        let t = min(targetTop, targetBottom)
        let b = max(targetTop, targetBottom)
        guard b > t else { return (0,0,0,0,b) }
        let target = computeVolumesBetween(top: t, bottom: b).openHole_m3
        var lo = 0.0
        var hi = max(0.0, b)
        let vHi = totalMudWithPipeBetween(top: max(0.0, b - hi), bottom: b).total_m3
        if vHi < target {
            let fallback = totalMudWithPipeBetween(top: t, bottom: b)
            return (b - t, fallback.total_m3, fallback.annular_m3, fallback.string_m3, t)
        }
        for _ in 0..<maxIter {
            let mid = 0.5 * (lo + hi)
            let vMid = totalMudWithPipeBetween(top: max(0.0, b - mid), bottom: b).total_m3
            if abs(vMid - target) <= max(1e-9, tol * max(target, 1.0)) {
                let topWithPipe = max(0.0, b - mid)
                let parts = totalMudWithPipeBetween(top: topWithPipe, bottom: b)
                return (mid, vMid, parts.annular_m3, parts.string_m3, topWithPipe)
            }
            if vMid < target { lo = mid } else { hi = mid }
        }
        let L = hi
        let topWithPipe = max(0.0, b - L)
        let parts = totalMudWithPipeBetween(top: topWithPipe, bottom: b)
        return (L, parts.total_m3, parts.annular_m3, parts.string_m3, topWithPipe)
    }

    func mdToTVD(_ md: Double) -> Double {
        let stations = (project.surveys ?? []).sorted { $0.md < $1.md }
        guard let first = stations.first else { return md }
        guard let last  = stations.last  else { return md }
        let tvd0 = first.tvd ?? 0
        let tvdN = last.tvd  ?? tvd0
        if md <= first.md { return tvd0 }
        if md >= last.md  { return tvdN }
        for i in 0..<(stations.count - 1) {
            let a = stations[i]
            let b = stations[i+1]
            if md >= a.md && md <= b.md {
                let tvdA = a.tvd ?? 0
                let tvdB = b.tvd ?? tvdA
                let span = max(b.md - a.md, 1e-9)
                let f = (md - a.md) / span
                return tvdA + f * (tvdB - tvdA)
            }
        }
        return tvdN
    }

    // MARK: - Final Layer Persistence

    func persistFinalLayers(from ann: [FinalLayer], _ str: [FinalLayer]) {
        // Delete existing layers from context
        for layer in (project.finalLayers ?? []) {
            context?.delete(layer)
        }

        // Clear the relationship array explicitly
        project.finalLayers = []

        // Create and save new layers
        var newLayers: [FinalFluidLayer] = []

        func save(_ lay: FinalLayer, where placement: Placement) {
            let f = FinalFluidLayer(
                project: project,
                name: lay.name,
                placement: placement,
                topMD_m: min(lay.top, lay.bottom),
                bottomMD_m: max(lay.top, lay.bottom),
                density_kgm3: lay.density,
                color: lay.color,
                mud: lay.mud
            )
            context?.insert(f)
            newLayers.append(f)
        }

        for a in ann { save(a, where: .annulus) }
        for s in str { save(s, where: .string) }

        // Explicitly set the relationship array
        project.finalLayers = newLayers

        // Save to persist all changes
        try? context?.save()

        #if DEBUG
        print("[MudPlacement] Persisted \(newLayers.count) final layers (ann: \(ann.count), str: \(str.count))")
        #endif
    }
}

// MARK: - Supporting Types
struct FinalLayer: Identifiable, Equatable {
    let id = UUID()
    enum Domain { case annulus, string }
    let domain: Domain
    var top: Double
    var bottom: Double
    var name: String
    var color: Color
    var density: Double
    var mud: MudProperties?
}
