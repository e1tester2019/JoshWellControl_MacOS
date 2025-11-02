//
//  HydraulicsCalculator.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-02.
//


import Foundation

/// Stateless calculator that uses your SwiftData models.
/// All pressures returned in kPa; gradients in kPa/m.
struct HydraulicsCalculator {

    // MARK: - Constants
    static let g: Double = 9.80665 // m/s^2

    // MARK: - Basic building blocks

    /// Hydrostatic gradient for a uniform fluid (kPa/m)
    static func grad_kPa_per_m(density_kg_per_m3: Double) -> Double {
        (density_kg_per_m3 * g) / 1000.0
    }

    /// Hydrostatic pressure at TVD from a list of (top, bottom, density) segments (kPa).
    /// Allows mud caps / slugs / multi-fluid stacks.
    ///
    /// Assumes segments are vertical spans in TVD; ignores temperature compressibility for now.
    static func hydrostatic_kPa(
        atTVD tvd_m: Double,
        segments: [(topTVD_m: Double, bottomTVD_m: Double, density_kg_per_m3: Double)]
    ) -> Double {
        guard tvd_m > 0 else { return 0 }
        var p_kPa = 0.0
        for seg in segments {
            let t = max(0.0, min(seg.topTVD_m, seg.bottomTVD_m))
            let b = max(0.0, max(seg.topTVD_m, seg.bottomTVD_m))
            if tvd_m <= t { continue }                // entirely below current point
            let covered = min(tvd_m, b) - t
            if covered <= 0 { continue }
            p_kPa += grad_kPa_per_m(density_kg_per_m3: seg.density_kg_per_m3) * covered
        }
        return p_kPa
    }

    /// Convert an annular section’s flow to a simple friction gradient (kPa/m).
    /// This is a pragmatic placeholder: Newtonian w/ Blasius + laminar branch,
    /// using equivalent diameter De = ID − OD and bulk velocity from flow area.
    static func annularFrictionGrad_kPa_per_m(
        flowRate_m3_per_s: Double,
        density_kg_per_m3: Double,
        viscosity_Pa_s: Double,
        ID_m: Double,
        OD_m: Double,
        roughness_m: Double = 4.6e-5
    ) -> Double {
        let area = max(.pi * 0.25 * (ID_m*ID_m - OD_m*OD_m), 0)
        guard area > 0 else { return 0 }
        let De = max(ID_m - OD_m, 0)
        guard De > 0 else { return 0 }

        let v = flowRate_m3_per_s / area                       // m/s
        let Re = (density_kg_per_m3 * v * De) / max(viscosity_Pa_s, 1e-9)

        let f: Double
        if Re < 2000 {
            f = 64.0 / max(Re, 1.0)                            // laminar
        } else {
            // Blasius; (roughness ignored for now, acceptable first pass)
            f = 0.3164 / pow(Re, 0.25)
        }

        // Darcy–Weisbach: ΔP/L (Pa/m) = f * (ρ v^2 / 2) * (1/De)
        let dP_per_m_Pa = f * (density_kg_per_m3 * v * v / 2.0) * (1.0 / De)
        return dP_per_m_Pa / 1000.0                            // kPa/m
    }

    // MARK: - Putting it together for BHP

    /// Compute BHP (kPa) at a given TVD from:
    /// - multi-density column (mud cap, spacers, slugs),
    /// - dynamic annular friction up to that TVD (ECD),
    /// - surface back pressure (SBP).
    static func bhp_kPa(
        tvd_m: Double,
        fluidSegments: [(topTVD_m: Double, bottomTVD_m: Double, density_kg_per_m3: Double)],
        annulusSections: [AnnulusSectionLike],
        flowRate_m3_per_s: Double,
        apparentViscosity_Pa_s: Double,   // pick from your rheology model (PV, μ_app, etc.)
        sbp_kPa: Double
    ) -> Double {
        let pHyd_kPa = hydrostatic_kPa(atTVD: tvd_m, segments: fluidSegments)

        // Sum friction from annulus sections that contribute above this TVD
        var pFric_kPa = 0.0
        for s in annulusSections {
            let top = s.topTVD_m
            let bot = s.bottomTVD_m
            if tvd_m <= top { continue }
            let covered = min(tvd_m, bot) - top
            if covered <= 0 { continue }
            let grad = annularFrictionGrad_kPa_per_m(
                flowRate_m3_per_s: flowRate_m3_per_s,
                density_kg_per_m3: s.density_kg_per_m3,
                viscosity_Pa_s: apparentViscosity_Pa_s,
                ID_m: s.innerDiameter_m,
                OD_m: s.outerDiameter_m,
                roughness_m: s.roughness_m
            )
            pFric_kPa += max(grad, 0) * covered
        }

        // Surface back pressure adds linearly.
        return sbp_kPa + pHyd_kPa + pFric_kPa
    }

    /// Required SBP (kPa) to hit a target BHP with given fluid stack + friction.
    static func requiredSBP_kPa(
        targetBHP_kPa: Double,
        tvd_m: Double,
        fluidSegments: [(topTVD_m: Double, bottomTVD_m: Double, density_kg_per_m3: Double)],
        annulusSections: [AnnulusSectionLike],
        flowRate_m3_per_s: Double,
        apparentViscosity_Pa_s: Double
    ) -> Double {
        let currentBHP_noSBP = bhp_kPa(
            tvd_m: tvd_m,
            fluidSegments: fluidSegments,
            annulusSections: annulusSections,
            flowRate_m3_per_s: flowRate_m3_per_s,
            apparentViscosity_Pa_s: apparentViscosity_Pa_s,
            sbp_kPa: 0
        )
        return max(targetBHP_kPa - currentBHP_noSBP, 0)
    }

    /// Required *uniform* mud density (kg/m³) (single fluid, no slug/cap) to hit target BHP
    /// with a provided SBP and friction gradient (kPa/m) assumed constant.
    static func requiredUniformDensity_kg_per_m3(
        targetBHP_kPa: Double,
        tvd_m: Double,
        frictionGrad_kPa_per_m: Double,
        sbp_kPa: Double
    ) -> Double {
        guard tvd_m > 0 else { return 0 }
        let hydroNeeded_kPa = max(targetBHP_kPa - sbp_kPa - frictionGrad_kPa_per_m * tvd_m, 0)
        // hydroNeeded = grad * TVD  => density = (hydroNeeded*1000)/(g*TVD)
        return (hydroNeeded_kPa * 1000.0) / (g * tvd_m)
    }

    /// Quick safety check vs. pressure window (kPa)
    static func isSafe(
        tvd_m: Double,
        bhp_kPa: Double,
        window: PressureWindow
    ) -> (within: Bool, pore_kPa: Double?, frac_kPa: Double?) {
        let pore = window.pore_kPa(atTVD: tvd_m)
        let frac = window.frac_kPa(atTVD: tvd_m)
        if let p = pore, bhp_kPa < p { return (false, pore, frac) }
        if let f = frac, bhp_kPa > f { return (false, pore, frac) }
        return (true, pore, frac)
    }
}

/// Minimal interface so you can pass your SwiftData `AnnulusSection` without coupling this file.
protocol AnnulusSectionLike {
    var topTVD_m: Double { get }
    var bottomTVD_m: Double { get }
    var innerDiameter_m: Double { get }
    var outerDiameter_m: Double { get }
    var roughness_m: Double { get }
    var density_kg_per_m3: Double { get }
}