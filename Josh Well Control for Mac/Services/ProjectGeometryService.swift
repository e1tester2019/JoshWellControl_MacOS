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
}

/// Geometry provider backed by the project's AnnulusSection and DrillStringSection arrays.
/// - Note: `currentStringBottomMD` controls how far down the pipe is considered present.
final class ProjectGeometryService: GeometryService {
    private let annulus: [AnnulusSection]
    private let string: [DrillStringSection]
    
    /// Update per simulation step to reflect how far the string extends.
    var currentStringBottomMD: Double
    
    /// Designated initializer with explicit section arrays.
    init(annulus: [AnnulusSection], string: [DrillStringSection], currentStringBottomMD: Double) {
        // Sort once for predictable lookups
        self.annulus = annulus.sorted { $0.topDepth_m < $1.topDepth_m }
        self.string  = string.sorted { $0.topDepth_m < $1.topDepth_m }
        self.currentStringBottomMD = currentStringBottomMD
    }
    
    /// Convenience initializer from a ProjectState
    convenience init(project: ProjectState, currentStringBottomMD: Double) {
        self.init(annulus: project.annulus, string: project.drillString, currentStringBottomMD: currentStringBottomMD)
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
}
