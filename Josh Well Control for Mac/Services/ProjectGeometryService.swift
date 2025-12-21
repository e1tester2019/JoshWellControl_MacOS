//
//  ProjectGeometryService.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-06.
//

import Foundation

/// Simple geometry protocol used by swab/surge engines.
/// Implementations must return hole ID and pipe OD (meters) at a given MD.
protocol GeometryService {
    func holeOD_m(_ md: Double) -> Double
    func pipeOD_m(_ md: Double) -> Double
    func pipeID_m(_ md: Double) -> Double

    // Volumes and lengths (piecewise-constant geometry along MD)
    func volumeInAnnulus_m3(_ topMD: Double, _ bottomMD: Double) -> Double
    func volumeInString_m3(_ topMD: Double, _ bottomMD: Double) -> Double
    func lengthForAnnulusVolume_m(_ startMD: Double, _ volume_m3: Double) -> Double
    func lengthForStringVolume_m(_ startMD: Double, _ volume_m3: Double) -> Double
    /// Steel (pipe OD) cross‑sectional area at MD (m²). Typically equals pipeArea_m2(md) when the string is present.
    func steelArea_m2(_ md: Double) -> Double
    /// Swept solid OD volume of the string within [topMD, bottomMD] (m³).
    func volumeOfStringOD_m3(_ topMD: Double, _ bottomMD: Double) -> Double
    /// MD → TVD mapping (m). Implementations may forward to a survey sampler; default may be identity.
    func tvd(of md: Double) -> Double
}

extension GeometryService {
    /// Annular gap (m); never negative.
    func annulusGap_m(_ md: Double) -> Double {
        max(holeOD_m(md) - pipeOD_m(md), 0.0)
    }
    /// Pipe metal OD area (m²).
    func pipeArea_m2(_ md: Double) -> Double {
        let d = max(pipeOD_m(md), 0.0)
        return .pi * d * d / 4.0
    }
    /// Annular flow area (m²); clamped to ≥ 0.
    func annulusArea_m2(_ md: Double) -> Double {
        let dh = max(holeOD_m(md), 0.0)
        let do_ = max(pipeOD_m(md), 0.0)
        return max(0.0, .pi * (dh * dh - do_ * do_) / 4.0)
    }

    /// Default steel area equals pipe OD area when the string is present.
    func steelArea_m2(_ md: Double) -> Double { pipeArea_m2(md) }
    /// Steel displacement area (metal ring): π × (OD² - ID²) / 4
    /// This is the "DP Dry" or displacement volume per meter.
    func steelDisplacement_m2(_ md: Double) -> Double {
        let od = max(pipeOD_m(md), 0.0)
        let id = max(pipeID_m(md), 0.0)
        return max(0.0, .pi * (od * od - id * id) / 4.0)
    }
    /// Identity TVD fallback unless overridden by an implementation with surveys.
    func tvd(of md: Double) -> Double { md }
}

/// Geometry provider backed by the project's AnnulusSection and DrillStringSection arrays.
/// - Note: `currentStringBottomMD` controls how far down the pipe is considered present.
/// - Note: Marked @unchecked Sendable because the section data is effectively immutable during simulation.
final class ProjectGeometryService: GeometryService, @unchecked Sendable {
    private let annulus: [AnnulusSection]
    private let string: [DrillStringSection]
    private let mdToTvd: (Double) -> Double
    
    /// Update per simulation step to reflect how far the string extends.
    var currentStringBottomMD: Double
    
    /// Designated initializer with explicit section arrays.
    init(annulus: [AnnulusSection], string: [DrillStringSection], currentStringBottomMD: Double, mdToTvd: @escaping (Double)->Double = { $0 }) {
        // Sort once for predictable lookups
        self.annulus = annulus.sorted { $0.topDepth_m < $1.topDepth_m }
        self.string  = string.sorted { $0.topDepth_m < $1.topDepth_m }
        self.currentStringBottomMD = currentStringBottomMD
        self.mdToTvd = mdToTvd
    }
    
    /// Convenience initializer from a ProjectState (no trajectory dependency)
    convenience init(project: ProjectState, currentStringBottomMD: Double) {
        self.init(annulus: project.annulus ?? [],
                  string: project.drillString ?? [],
                  currentStringBottomMD: currentStringBottomMD)
    }

    /// Convenience initializer when you have an MD→TVD mapper (e.g., from surveys)
    convenience init(project: ProjectState,
                     currentStringBottomMD: Double,
                     tvdMapper: @escaping (Double)->Double) {
        self.init(annulus: project.annulus ?? [],
                  string: project.drillString ?? [],
                  currentStringBottomMD: currentStringBottomMD,
                  mdToTvd: tvdMapper)
    }

    /// Lightweight TVD sampler using (md,tvd) stations; linear interp between stations.
    private final class _TvdSampler {
        private let md: [Double]
        private let tvd: [Double]
        init(stations: [SurveyStation]) {
            let s = stations.sorted { $0.md < $1.md }
            var mdArr: [Double] = []
            var tvdArr: [Double] = []
            var lastMD = -Double.greatestFiniteMagnitude
            for st in s where st.md > lastMD {
                mdArr.append(st.md)
                tvdArr.append(st.tvd ?? st.md)
                lastMD = st.md
            }
            self.md = mdArr
            self.tvd = tvdArr
        }
        func tvd(of mdQuery: Double) -> Double {
            guard let first = md.first, let last = md.last else { return mdQuery }
            if mdQuery <= first { return tvd.first! }
            if mdQuery >= last  { return tvd.last!  }
            var lo = 0, hi = md.count - 1
            while hi - lo > 1 {
                let mid = (lo + hi) / 2
                if md[mid] <= mdQuery { lo = mid } else { hi = mid }
            }
            let t = (mdQuery - md[lo]) / max(md[hi] - md[lo], 1e-12)
            return tvd[lo] + t * (tvd[hi] - tvd[lo])
        }
    }

    /// Convenience initializer when you have survey stations with MD & TVD.
    convenience init(project: ProjectState,
                     currentStringBottomMD: Double,
                     surveys: [SurveyStation]) {
        let sampler = _TvdSampler(stations: surveys)
        self.init(annulus: project.annulus ?? [],
                  string: project.drillString ?? [],
                  currentStringBottomMD: currentStringBottomMD,
                  mdToTvd: { sampler.tvd(of: $0) })
    }
    
    /// Hole inner diameter at MD (m). Returns 0 if no section covers the MD.
    func holeOD_m(_ md: Double) -> Double {
        guard let sec = annulus.first(where: { $0.topDepth_m <= md && md <= $0.bottomDepth_m }) else {
            return 0.0
        }
        return max(sec.innerDiameter_m, 0.0)
    }
    
    /// Pipe outer diameter at MD (m). Returns 0 if above current string bottom or outside any DS section.
    func pipeOD_m(_ md: Double) -> Double {
        // If the string hasn’t reached this depth (POOH or early RIH), there’s no OD present here.
        guard md <= currentStringBottomMD else { return 0.0 }
        guard let sec = string.first(where: { $0.topDepth_m <= md && md <= $0.bottomDepth_m }) else {
            return 0.0
        }
        return max(sec.outerDiameter_m, 0.0)
    }
    
    /// Pipe inner diameter at MD (m). Returns 0 if above current string bottom or outside any DS section.
    func pipeID_m(_ md: Double) -> Double {
        // If the string hasn’t reached this depth (POOH or early RIH), there’s no ID present here.
        guard md <= currentStringBottomMD else { return 0.0 }
        guard let sec = string.first(where: { $0.topDepth_m <= md && md <= $0.bottomDepth_m }) else {
            return 0.0
        }
        return max(sec.innerDiameter_m, 0.0)
    }

    // MARK: - Piecewise helpers
    /// Build sorted breakpoints within [top,bottom] where geometry may change.
    private func breakpoints(in top: Double, _ bottom: Double) -> [Double] {
        let a = min(top, bottom), b = max(top, bottom)
        var pts: Set<Double> = [a, b, currentStringBottomMD]
        for s in annulus { if s.bottomDepth_m >= a && s.topDepth_m <= b { pts.insert(max(a, s.topDepth_m)); pts.insert(min(b, s.bottomDepth_m)) } }
        for s in string  { if s.bottomDepth_m  >= a && s.topDepth_m <= b { pts.insert(max(a, s.topDepth_m)); pts.insert(min(b, s.bottomDepth_m)) } }
        let arr = pts.filter { $0 >= a && $0 <= b }.sorted()
        return arr
    }

    /// Annular flow area at an MD (m²), honoring currentStringBottomMD.
    private func annulusAreaAt(_ md: Double) -> Double {
        let dh = holeOD_m(md)
        let do_ = pipeOD_m(md)
        return max(0.0, .pi * (dh*dh - do_*do_) / 4.0)
    }

    /// String flow area at an MD (m²), zero if above current string bottom.
    private func stringAreaAt(_ md: Double) -> Double {
        guard md <= currentStringBottomMD else { return 0.0 }
        let id_ = pipeID_m(md)
        return max(0.0, .pi * id_*id_ / 4.0)
    }

    // MARK: - Protocol conformance (volumes/lengths)
    func volumeInAnnulus_m3(_ topMD: Double, _ bottomMD: Double) -> Double {
        let pts = breakpoints(in: topMD, bottomMD)
        guard pts.count >= 2 else { return 0.0 }
        var vol = 0.0
        for i in 0..<(pts.count - 1) {
            let a = pts[i], b = pts[i+1]
            if b <= a { continue }
            let mid = 0.5*(a+b)
            vol += annulusAreaAt(mid) * (b - a)
        }
        return max(vol, 0.0)
    }

    func volumeInString_m3(_ topMD: Double, _ bottomMD: Double) -> Double {
        let top = max(min(topMD, bottomMD), 0.0)
        let bot = min(max(topMD, bottomMD), currentStringBottomMD)
        guard bot > top else { return 0.0 }
        let pts = breakpoints(in: top, bot)
        var vol = 0.0
        for i in 0..<(pts.count - 1) {
            let a = pts[i], b = pts[i+1]
            if b <= a { continue }
            let mid = 0.5*(a+b)
            vol += stringAreaAt(mid) * (b - a)
        }
        return max(vol, 0.0)
    }

    func volumeOfStringOD_m3(_ topMD: Double, _ bottomMD: Double) -> Double {
        let top = max(min(topMD, bottomMD), 0.0)
        let bot = min(max(topMD, bottomMD), currentStringBottomMD)
        guard bot > top else { return 0.0 }
        let pts = breakpoints(in: top, bot)
        var vol = 0.0
        for i in 0..<(pts.count - 1) {
            let a = pts[i], b = pts[i+1]
            if b <= a { continue }
            let mid = 0.5*(a+b)
            vol += steelArea_m2(mid) * (b - a)
        }
        return max(vol, 0.0)
    }

    func lengthForAnnulusVolume_m(_ startMD: Double, _ volume_m3: Double) -> Double {
        guard volume_m3 > 1e-12 else { return 0.0 }
        var remaining = volume_m3
        var cursor = max(0.0, startMD)
        let maxDepth = max(annulus.last?.bottomDepth_m ?? 0.0, string.last?.bottomDepth_m ?? 0.0)
        while cursor < maxDepth - 1e-9 {
            // Determine next breakpoint downhole
            let next = breakpoints(in: cursor, maxDepth)
            guard next.count >= 2 else { break }
            let a = next[0], b = next[1]
            let mid = 0.5*(a+b)
            let area = annulusAreaAt(mid)
            let len = b - a
            let vol = area * len
            if vol >= remaining - 1e-12 {
                return (remaining / max(area, 1e-12)) + (a - startMD)
            } else {
                remaining -= vol
                cursor = b
            }
        }
        // If we run out of geometry, return total traversed length
        return max(0.0, cursor - startMD)
    }

    func lengthForStringVolume_m(_ startMD: Double, _ volume_m3: Double) -> Double {
        guard volume_m3 > 1e-12 else { return 0.0 }
        var remaining = volume_m3
        var cursor = max(0.0, startMD)
        let cap = currentStringBottomMD
        while cursor < cap - 1e-9 {
            let next = breakpoints(in: cursor, cap)
            guard next.count >= 2 else { break }
            let a = next[0], b = next[1]
            let mid = 0.5*(a+b)
            let area = stringAreaAt(mid)
            let len = b - a
            let vol = area * len
            if vol >= remaining - 1e-12 {
                return (remaining / max(area, 1e-12)) + (a - startMD)
            } else {
                remaining -= vol
                cursor = b
            }
        }
        return max(0.0, cursor - startMD)
    }

    // MARK: - Protocol conformance (TVD)
    func tvd(of md: Double) -> Double { mdToTvd(md) }
}
