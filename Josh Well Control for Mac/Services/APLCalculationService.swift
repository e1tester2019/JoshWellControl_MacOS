//
//  APLCalculationService.swift
//  Josh Well Control for Mac
//
//  Centralized Annular Pressure Loss (APL) calculations
//  Used by MPD tracking, cement job simulation, pump schedules
//

import Foundation

/// Centralized service for APL (Annular Pressure Loss) calculations
/// Provides consistent formulas across all features
class APLCalculationService {

    static let shared = APLCalculationService()
    private init() {}

    // MARK: - Constants

    /// Empirical constant for simplified APL formula (calibrated for m³/min and meters)
    /// Back-calculated from Excel reference: APL=4956 kPa with ρ=1330, L=3420, Q=1.13 m³/min, Dh-Dp=0.0589m
    static let empiricalK: Double = 5.0e-05

    /// Gravity constant (m/s²)
    static let g: Double = 9.81

    // MARK: - Simplified APL Formula (Preferred)

    /// Calculate APL using simplified empirical formula
    /// APL = K × ρ × L × Q² / (Dh - Dp)
    ///
    /// - Parameters:
    ///   - density_kgm3: Fluid density (kg/m³)
    ///   - length_m: Section length (m)
    ///   - flowRate_m3_per_min: Flow rate (m³/min)
    ///   - holeDiameter_m: Hole/casing ID (m)
    ///   - pipeDiameter_m: Pipe OD (m)
    /// - Returns: APL in kPa
    func aplSimplified(
        density_kgm3: Double,
        length_m: Double,
        flowRate_m3_per_min: Double,
        holeDiameter_m: Double,
        pipeDiameter_m: Double
    ) -> Double {
        let hydraulicGap = holeDiameter_m - pipeDiameter_m
        guard hydraulicGap > 1e-6, flowRate_m3_per_min > 0 else { return 0 }

        // Returns APL in kPa
        return Self.empiricalK * density_kgm3 * length_m * pow(flowRate_m3_per_min, 2) / hydraulicGap
    }

    /// Calculate total APL from surface to a depth using project geometry
    ///
    /// - Parameters:
    ///   - toDepth_m: Target depth (MD) in meters
    ///   - density_kgm3: Fluid density (kg/m³)
    ///   - flowRate_m3_per_min: Flow rate (m³/min)
    ///   - annulusSections: Array of annulus sections
    ///   - drillStringSections: Array of drill string sections
    ///   - chokeFriction_kPa: Additional choke/surface friction (kPa)
    /// - Returns: Total APL in kPa
    func aplToDepth(
        toDepth_m: Double,
        density_kgm3: Double,
        flowRate_m3_per_min: Double,
        annulusSections: [AnnulusSection],
        drillStringSections: [DrillStringSection],
        chokeFriction_kPa: Double = 0
    ) -> Double {
        guard flowRate_m3_per_min > 0.001 else { return chokeFriction_kPa }

        var totalAPL_kPa = 0.0

        for section in annulusSections {
            // Calculate overlap with target depth
            let sectionTop = section.topDepth_m
            let sectionBottom = min(section.bottomDepth_m, toDepth_m)

            guard sectionBottom > sectionTop else { continue }
            let sectionLength = sectionBottom - sectionTop

            // Get hole ID from annulus section
            let holeID = section.innerDiameter_m

            // Get pipe OD at this depth (find overlapping drill string)
            let pipeOD = pipeODAtDepth(
                depth: (sectionTop + sectionBottom) / 2,
                drillStringSections: drillStringSections
            )

            // Calculate APL for this section
            let sectionAPL = aplSimplified(
                density_kgm3: density_kgm3,
                length_m: sectionLength,
                flowRate_m3_per_min: flowRate_m3_per_min,
                holeDiameter_m: holeID,
                pipeDiameter_m: pipeOD
            )

            totalAPL_kPa += sectionAPL
        }

        return totalAPL_kPa + chokeFriction_kPa
    }

    // MARK: - Annular Velocity

    /// Calculate annular velocity
    /// V = Q / A where A = π/4 × (Dh² - Dp²)
    ///
    /// - Parameters:
    ///   - flowRate_m3_per_min: Flow rate (m³/min)
    ///   - holeDiameter_m: Hole/casing ID (m)
    ///   - pipeDiameter_m: Pipe OD (m)
    /// - Returns: Velocity in m/min
    func annularVelocity(
        flowRate_m3_per_min: Double,
        holeDiameter_m: Double,
        pipeDiameter_m: Double
    ) -> Double {
        let area_m2 = Double.pi / 4.0 * (pow(holeDiameter_m, 2) - pow(pipeDiameter_m, 2))
        guard area_m2 > 1e-9 else { return 0 }
        return flowRate_m3_per_min / area_m2
    }

    // MARK: - ECD/ESD Calculations

    /// Calculate ECD (Equivalent Circulating Density)
    /// ECD = ρ + (APL × 1000) / (g × TVD)
    ///
    /// - Parameters:
    ///   - staticDensity_kgm3: Static mud density (kg/m³)
    ///   - apl_kPa: Annular pressure loss (kPa)
    ///   - tvd_m: True vertical depth (m)
    /// - Returns: ECD in kg/m³
    func ecd(
        staticDensity_kgm3: Double,
        apl_kPa: Double,
        tvd_m: Double
    ) -> Double {
        guard tvd_m > 0 else { return staticDensity_kgm3 }
        // Convert APL from kPa to Pa, then to equivalent density
        let aplContribution = (apl_kPa * 1000.0) / (Self.g * tvd_m)
        return staticDensity_kgm3 + aplContribution
    }

    /// Calculate ESD (Equivalent Static Density) with surface pressure
    /// ESD = ρ + (SIP × 1000) / (g × TVD)
    ///
    /// - Parameters:
    ///   - staticDensity_kgm3: Static mud density (kg/m³)
    ///   - surfacePressure_kPa: Shut-in pressure or backpressure (kPa)
    ///   - tvd_m: True vertical depth (m)
    /// - Returns: ESD in kg/m³
    func esd(
        staticDensity_kgm3: Double,
        surfacePressure_kPa: Double,
        tvd_m: Double
    ) -> Double {
        guard tvd_m > 0 else { return staticDensity_kgm3 }
        let pressureContribution = (surfacePressure_kPa * 1000.0) / (Self.g * tvd_m)
        return staticDensity_kgm3 + pressureContribution
    }

    // MARK: - Bingham Plastic Model (Alternative)

    /// Calculate APL using Bingham Plastic model (when rheology data available)
    /// dP/dL = (4 × YP) / (Dh - Dp) + (8 × PV × V) / (Dh - Dp)²
    ///
    /// - Parameters:
    ///   - length_m: Section length (m)
    ///   - flowRate_m3_per_min: Flow rate (m³/min)
    ///   - holeDiameter_m: Hole/casing ID (m)
    ///   - pipeDiameter_m: Pipe OD (m)
    ///   - plasticViscosity_cP: Plastic viscosity in centipoise
    ///   - yieldPoint_Pa: Yield point in Pascals
    /// - Returns: APL in kPa
    func aplBingham(
        length_m: Double,
        flowRate_m3_per_min: Double,
        holeDiameter_m: Double,
        pipeDiameter_m: Double,
        plasticViscosity_cP: Double,
        yieldPoint_Pa: Double
    ) -> Double {
        let hydraulicDiameter = holeDiameter_m - pipeDiameter_m
        guard hydraulicDiameter > 1e-6 else { return 0 }

        // Calculate velocity in m/s
        let area_m2 = Double.pi / 4.0 * (pow(holeDiameter_m, 2) - pow(pipeDiameter_m, 2))
        guard area_m2 > 1e-9 else { return 0 }
        let velocity_m_per_s = (flowRate_m3_per_min / 60.0) / area_m2

        // Convert PV from cP to Pa·s
        let pv_Pa_s = plasticViscosity_cP / 1000.0

        // Bingham plastic friction gradient (Pa/m)
        let yieldTerm = (4.0 * yieldPoint_Pa) / hydraulicDiameter
        let viscousTerm = (8.0 * pv_Pa_s * velocity_m_per_s) / pow(hydraulicDiameter, 2)
        let gradient_Pa_per_m = yieldTerm + viscousTerm

        // Total APL in kPa
        return (gradient_Pa_per_m * length_m) / 1000.0
    }

    // MARK: - Power-Law Mooney-Rabinowitsch Model

    /// Annular APL from pre-computed Power-Law K and n values.
    /// This is the primary method — `aplPowerLaw(dial600:dial300:)` derives K/n and delegates here.
    ///
    /// - Parameters:
    ///   - length_m: Section length (m)
    ///   - flowRate_m3_per_min: Flow rate (m³/min)
    ///   - holeDiameter_m: Hole/casing ID (m)
    ///   - pipeDiameter_m: Pipe OD (m)
    ///   - K: Power-law consistency index (Pa·sⁿ)
    ///   - n: Power-law flow behavior index
    /// - Returns: APL in kPa
    func aplFromKN(
        length_m: Double,
        flowRate_m3_per_min: Double,
        holeDiameter_m: Double,
        pipeDiameter_m: Double,
        K: Double,
        n: Double
    ) -> Double {
        guard K > 0, n > 0, flowRate_m3_per_min > 0 else { return 0 }
        let hydraulicDiameter = holeDiameter_m - pipeDiameter_m
        guard hydraulicDiameter > 1e-6 else { return 0 }

        let area_m2 = Double.pi / 4.0 * (pow(holeDiameter_m, 2) - pow(pipeDiameter_m, 2))
        guard area_m2 > 1e-9 else { return 0 }
        let velocity_m_per_s = (flowRate_m3_per_min / 60.0) / area_m2

        let gamma_w = ((3.0 * n + 1.0) / (4.0 * n)) * (8.0 * velocity_m_per_s / hydraulicDiameter)
        let tau_w = K * pow(gamma_w, n)
        let gradient_Pa_per_m = 4.0 * tau_w / hydraulicDiameter

        return (gradient_Pa_per_m * length_m) / 1000.0
    }

    /// Pipe (internal) flow APL from pre-computed Power-Law K and n values.
    ///
    /// - Parameters:
    ///   - length_m: Section length (m)
    ///   - flowRate_m3_per_min: Flow rate (m³/min)
    ///   - pipeDiameter_m: Pipe internal diameter (m)
    ///   - K: Power-law consistency index (Pa·sⁿ)
    ///   - n: Power-law flow behavior index
    /// - Returns: Friction pressure loss in kPa
    func pipeFlowAPLFromKN(
        length_m: Double,
        flowRate_m3_per_min: Double,
        pipeDiameter_m: Double,
        K: Double,
        n: Double
    ) -> Double {
        guard K > 0, n > 0, flowRate_m3_per_min > 0 else { return 0 }
        guard pipeDiameter_m > 1e-6 else { return 0 }

        let area_m2 = Double.pi / 4.0 * pow(pipeDiameter_m, 2)
        guard area_m2 > 1e-9 else { return 0 }
        let velocity_m_per_s = (flowRate_m3_per_min / 60.0) / area_m2

        let gamma_w = ((3.0 * n + 1.0) / (4.0 * n)) * (8.0 * velocity_m_per_s / pipeDiameter_m)
        let tau_w = K * pow(gamma_w, n)
        let gradient_Pa_per_m = 4.0 * tau_w / pipeDiameter_m

        return (gradient_Pa_per_m * length_m) / 1000.0
    }

    /// Annular APL from Fann dial readings using Power-Law Mooney-Rabinowitsch model.
    /// Convenience wrapper that derives K/n from dials and delegates to `aplFromKN()`.
    func aplPowerLaw(
        length_m: Double,
        flowRate_m3_per_min: Double,
        holeDiameter_m: Double,
        pipeDiameter_m: Double,
        dial600: Double,
        dial300: Double
    ) -> Double {
        guard dial600 > 0, dial300 > 0 else { return 0 }
        let n = log(dial600 / dial300) / log(600.0 / 300.0)
        let tau600 = HydraulicsDefaults.fann35_dialToPa * dial600
        let gamma600 = HydraulicsDefaults.fann35_600rpm_shearRate
        let K = tau600 / pow(gamma600, n)

        return aplFromKN(
            length_m: length_m,
            flowRate_m3_per_min: flowRate_m3_per_min,
            holeDiameter_m: holeDiameter_m,
            pipeDiameter_m: pipeDiameter_m,
            K: K, n: n
        )
    }

    // MARK: - Helper Functions

    /// Get pipe OD at a specific depth
    private func pipeODAtDepth(depth: Double, drillStringSections: [DrillStringSection]) -> Double {
        for section in drillStringSections {
            if depth >= section.topDepth_m && depth <= section.bottomDepth_m {
                return section.outerDiameter_m
            }
        }
        // Default if no match found
        return drillStringSections.first?.outerDiameter_m ?? 0.127  // ~5" default
    }
}
