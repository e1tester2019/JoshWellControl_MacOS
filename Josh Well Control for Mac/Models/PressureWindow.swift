//
//  PressureWindow.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-02.
//


import Foundation
import SwiftData

// MARK: - Pressure Window (piecewise-linear vs TVD)

@Model
final class PressureWindow {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = "Default Window"

    /// If true, your table x-axis is TVD (m). If false, it’s MD (m).
    /// All helpers here assume TVD; you can map MD→TVD before using.
    var usesTVD: Bool = true

    /// Optional operational safety margins you might want to apply at evaluation time (kPa)
    var poreSafety_kPa: Double = 0.0      // extra overbalance above pore pressure
    var fracSafety_kPa: Double = 0.0      // margin below fracture pressure

    /// Relationship to tabulated points
    @Relationship(deleteRule: .cascade)
    var points: [PressureWindowPoint] = []

    // Link back to project (must match internal _window property)
    @Relationship(deleteRule: .cascade, inverse: \ProjectState._window)
    var project: ProjectState?

    init() {}

    // MARK: - Evaluation (linear interpolation)

    /// Interpolated pore pressure at a given TVD (m), in kPa.
    func pore_kPa(atTVD tvd_m: Double) -> Double? {
        interpolate(at: tvd_m, keyPath: \.pore_kPa)
    }

    /// Interpolated fracture pressure at a given TVD (m), in kPa.
    func frac_kPa(atTVD tvd_m: Double) -> Double? {
        interpolate(at: tvd_m, keyPath: \.frac_kPa)
    }

    /// Pressure window (kPa) at TVD with optional margins applied.
    /// Returns (minPore, maxFrac) or nil if either side is missing.
    func window_kPa(atTVD tvd_m: Double,
                    applySafety: Bool = true) -> (min_kPa: Double, max_kPa: Double)? {
        guard let pPore = pore_kPa(atTVD: tvd_m),
              let pFrac = frac_kPa(atTVD: tvd_m) else { return nil }

        let minP = applySafety ? (pPore + poreSafety_kPa) : pPore
        let maxP = applySafety ? (pFrac - fracSafety_kPa) : pFrac
        return minP <= maxP ? (minP, maxP) : nil
    }

    // MARK: - Convert window to mud density (kg/m³)

    /// Minimum density to maintain overbalance vs pore (kg/m³).
    func minDensity_kg_per_m3(atTVD tvd_m: Double,
                              applySafety: Bool = true) -> Double? {
        guard tvd_m > 0,
              let minP = (applySafety
                          ? pore_kPa(atTVD: tvd_m).map { $0 + poreSafety_kPa }
                          : pore_kPa(atTVD: tvd_m)) else { return nil }
        // P(kPa) = rho(kg/m3) * g(m/s2) * TVD(m) / 1000
        // => rho = P(kPa) * 1000 / (g * TVD)
        let g = 9.80665
        return (minP * 1000.0) / (g * tvd_m)
    }

    /// Maximum density before breaking down the formation (kg/m³).
    func maxDensity_kg_per_m3(atTVD tvd_m: Double,
                              applySafety: Bool = true) -> Double? {
        guard tvd_m > 0,
              let maxP = (applySafety
                          ? frac_kPa(atTVD: tvd_m).map { $0 - fracSafety_kPa }
                          : frac_kPa(atTVD: tvd_m)) else { return nil }
        let g = 9.80665
        return (maxP * 1000.0) / (g * tvd_m)
    }

    /// Full density window (kg/m³), or nil if undefined.
    func densityWindow_kg_per_m3(atTVD tvd_m: Double,
                                 applySafety: Bool = true) -> (min: Double, max: Double)? {
        guard let lo = minDensity_kg_per_m3(atTVD: tvd_m, applySafety: applySafety),
              let hi = maxDensity_kg_per_m3(atTVD: tvd_m, applySafety: applySafety),
              lo <= hi else { return nil }
        return (lo, hi)
    }

    // MARK: - Helpers

    /// Returns points sorted by depth (ascending). Call this before interpolation.
    @Transient private var sortedPoints: [PressureWindowPoint] {
        points.sorted { $0.depth_m < $1.depth_m }
    }

    /// Generic linear interpolation across table for the given keyPath (pore or frac).
    private func interpolate(at depth_m: Double,
                             keyPath: KeyPath<PressureWindowPoint, Double?>) -> Double? {
        let pts = sortedPoints
        guard let first = pts.first, let last = pts.last, !pts.isEmpty else { return nil }

        // Clamp outside range if endpoint has a value; otherwise nil.
        if depth_m <= first.depth_m { return first[keyPath: keyPath] }
        if depth_m >= last.depth_m  { return last[keyPath: keyPath]  }

        // Find bounding pair with values
        var lower: PressureWindowPoint?
        var upper: PressureWindowPoint?
        for i in 0..<(pts.count - 1) {
            let a = pts[i], b = pts[i+1]
            if a.depth_m <= depth_m, depth_m <= b.depth_m {
                lower = a; upper = b; break
            }
        }
        guard let a = lower, let b = upper else { return nil }

        guard let ya = a[keyPath: keyPath],
              let yb = b[keyPath: keyPath] else { return nil }

        let x0 = a.depth_m, x1 = b.depth_m
        if x1 == x0 { return ya } // degenerate
        let t = (depth_m - x0) / (x1 - x0)
        return ya + t * (yb - ya)
    }
}

// MARK: - Table point

@Model
final class PressureWindowPoint {
    @Attribute(.unique) var id: UUID = UUID()

    /// Depth coordinate for this row (m). Use TVD if `usesTVD == true` on the window.
    var depth_m: Double = 0.0

    /// Pore pressure at depth (kPa). Optional to allow sparse rows.
    var pore_kPa: Double?

    /// Fracture pressure at depth (kPa). Optional to allow sparse rows.
    var frac_kPa: Double?

    // Link to parent
    @Relationship(deleteRule: .nullify, inverse: \PressureWindow.points)
    var window: PressureWindow?

    init(depth_m: Double,
         pore_kPa: Double? = nil,
         frac_kPa: Double? = nil,
         window: PressureWindow? = nil) {
        self.depth_m = depth_m
        self.pore_kPa = pore_kPa
        self.frac_kPa = frac_kPa
        self.window = window
    }
}

