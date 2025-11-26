//
//  MudProperties.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-08.
//

import Foundation
import SwiftData
import SwiftUI

@Model
final class MudProperties {
    @Attribute(.unique) var id: UUID = UUID()

    // Optional relationship back to a project (no inverse required)
    @Relationship(deleteRule: .nullify)
    var project: ProjectState?

    var name: String
    var density_kgm3: Double
    var pv_Pa_s: Double?
    var yp_Pa: Double?
    var n_powerLaw: Double?
    var k_powerLaw_Pa_s_n: Double?
    var tau0_Pa: Double?
    var rheologyModel: String // "Bingham", "PowerLaw", "HB"
    var gel10s_Pa: Double?
    var gel10m_Pa: Double?
    var thermalExpCoeff_perC: Double?
    var compressibility_perkPa: Double?
    var gasCutFraction: Double?
    var isActive: Bool = false
    
    // Persisted UI color (RGBA 0..1)
    var colorR: Double = 0.8
    var colorG: Double = 0.8
    var colorB: Double = 0.0
    var colorA: Double = 1.0

    // Fann viscometer dial readings (dimensionless)
    var dial600: Double?   // 600 rpm dial
    var dial300: Double?   // 300 rpm dial

    // Optional geometry-specific Power Law parameters (from mud report)
    // If provided, these override the generic 600/300 Fann fit.
    var n_pipe: Double?        // n value for pipe flow
    var K_pipe: Double?        // k value for pipe flow (Pa·sⁿ)
    var n_annulus: Double?     // n value for annular flow
    var K_annulus: Double?     // k value for annular flow (Pa·sⁿ)

    // Computed SwiftUI Color bridge
    var color: Color {
        get { Color(red: colorR, green: colorG, blue: colorB, opacity: colorA) }
        set {
            #if canImport(AppKit)
            let ns = NSColor(newValue)
            if let rgb = ns.usingColorSpace(.sRGB) {
                colorR = Double(rgb.redComponent)
                colorG = Double(rgb.greenComponent)
                colorB = Double(rgb.blueComponent)
                colorA = Double(rgb.alphaComponent)
            }
            #endif
        }
    }

    // MARK: - Unit-convenience accessors (bridge UI units ↔ storage in SI)
    /// PV stored in Pa·s, but mud checks often show mPa·s (≈ cP). These bridge both ways.
    var pv_mPa_s: Double? {
        get { pv_Pa_s.map { $0 * 1000.0 } }
        set { pv_Pa_s = newValue.map { $0 / 1000.0 } }
    }

    /// YP stored in Pa; mud checks often show lbf/100ft². These bridge both ways.
    var yp_lbf_per_100ft2: Double? {
        get { yp_Pa.map { $0 / 0.478802 } }
        set { yp_Pa = newValue.map { $0 * 0.478802 } }
    }

    init(name: String = "Mud",
         density_kgm3: Double = 1100,
         pv_Pa_s: Double? = nil,
         yp_Pa: Double? = nil,
         n_powerLaw: Double? = nil,
         k_powerLaw_Pa_s_n: Double? = nil,
         tau0_Pa: Double? = nil,
         rheologyModel: String = "Bingham", // or "PowerLaw", "HB"
         gel10s_Pa: Double? = nil,
         gel10m_Pa: Double? = nil,
         thermalExpCoeff_perC: Double? = nil,
         compressibility_perkPa: Double? = nil,
         gasCutFraction: Double? = nil,
         dial600: Double? = nil,
         dial300: Double? = nil,
         color: Color = .yellow,
         project: ProjectState? = nil) {
        self.name = name
        self.density_kgm3 = density_kgm3
        self.pv_Pa_s = pv_Pa_s
        self.yp_Pa = yp_Pa
        self.n_powerLaw = n_powerLaw
        self.k_powerLaw_Pa_s_n = k_powerLaw_Pa_s_n
        self.tau0_Pa = tau0_Pa
        self.rheologyModel = rheologyModel
        self.gel10s_Pa = gel10s_Pa
        self.gel10m_Pa = gel10m_Pa
        self.thermalExpCoeff_perC = thermalExpCoeff_perC
        self.compressibility_perkPa = compressibility_perkPa
        self.gasCutFraction = gasCutFraction
        self.project = project
        self.dial600 = dial600
        self.dial300 = dial300
        // set color components
        #if canImport(AppKit)
        let ns = NSColor(color)
        if let rgb = ns.usingColorSpace(.sRGB) {
            self.colorR = Double(rgb.redComponent)
            self.colorG = Double(rgb.greenComponent)
            self.colorB = Double(rgb.blueComponent)
            self.colorA = Double(rgb.alphaComponent)
        } else {
            self.colorR = 0.8; self.colorG = 0.8; self.colorB = 0.0; self.colorA = 1.0
        }
        #else
        self.colorR = 0.8; self.colorG = 0.8; self.colorB = 0.0; self.colorA = 1.0
        #endif
    }

    // Effective density with simple T/P/gas-cut correction (optional; nil means "use inputs")
    func effectiveDensity(baseT_C: Double?, atT_C: Double?, baseP_kPa: Double?, atP_kPa: Double?) -> Double {
        let rho0 = density_kgm3
        let alpha = thermalExpCoeff_perC ?? 0
        let comp  = compressibility_perkPa ?? 0
        let gc    = gasCutFraction ?? 0
        let dT = (atT_C ?? baseT_C ?? 0) - (baseT_C ?? 0)
        let dP = (atP_kPa ?? baseP_kPa ?? 0) - (baseP_kPa ?? 0)
        let rhoT = rho0 * (1 - alpha * dT)
        let rhoTP = rhoT * (1 + comp * dP)
        return rhoTP * max(0, 1 - gc)
    }

    // MARK: - Rheology fitting from Fann 600/300
    /// Note: Pipe vs Annulus "effective" n & K differences arise from geometry-specific wall
    /// shear-rate definitions. Store base rheology here; compute geometry-corrected values in
    /// the hydraulics layer using appropriate shear-rate correlations.

    func powerLawFitFromFann() -> (n: Double, K: Double)? {
        guard let d600 = dial600, let d300 = dial300, d600 > 0, d300 > 0 else { return nil }
        let tau600 = d600 * 0.478802 // Pa
        let tau300 = d300 * 0.478802 // Pa
        let g600 = 1022.0
        let g300 = 511.0
        let n = log(tau600 / tau300) / log(g600 / g300)
        let K = tau600 / pow(g600, n)
        return (n, K)
    }

    func binghamFromFann() -> (pv_Pa_s: Double, yp_Pa: Double)? {
        guard let d600 = dial600, let d300 = dial300 else { return nil }
        let pv_cP = max(0, d600 - d300)
        let yp_lbf = d300 - pv_cP
        let pv_Pa_s = pv_cP * 0.001
        let yp_Pa = yp_lbf * 0.478802
        return (pv_Pa_s, yp_Pa)
    }

    func updateRheologyFromFann() {
        if let bl = binghamFromFann() {
            pv_Pa_s = bl.pv_Pa_s
            yp_Pa = bl.yp_Pa
        }
        if let pl = powerLawFitFromFann() {
            n_powerLaw = pl.n
            k_powerLaw_Pa_s_n = pl.K
        }
    }
}
