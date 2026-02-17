//
//  HydraulicsDefaults.swift
//  Josh Well Control for Mac
//
//  Centralized hydraulics and simulation constants.
//  Every magic number that appears in 2+ files gets a home here.
//

import Foundation

enum HydraulicsDefaults {

    // MARK: - Physical Constants

    /// Standard gravity (m/s^2) — used by APLCalculationService, NumericalTripModel,
    /// SwabCalculator, and trip simulation engines.
    static let gravity_mps2: Double = 9.81

    /// Density of air at surface conditions (kg/m^3)
    static let rhoAir_kgm3: Double = 1.2

    // MARK: - Fann 35 Viscometer Constants

    /// Dial reading → shear stress conversion factor.
    /// τ (Pa) = dialReading × fann35_dialToPa
    static let fann35_dialToPa: Double = 0.478802

    /// Shear rate at 600 RPM (1/s) — γ = rpm × 1.7033
    static let fann35_600rpm_shearRate: Double = 1022.0

    /// Shear rate at 300 RPM (1/s)
    static let fann35_300rpm_shearRate: Double = 511.0

    // MARK: - Swab / Surge

    /// Default SABP safety factor (multiplier on calculated swab pressure)
    static let swabSafetyFactor: Double = 1.15

    /// Laminar flow threshold (generalized Reynolds number)
    static let laminarReynoldsThreshold: Double = 2100.0

    /// Burkhardt clinging constant base value
    static let clingingConstantBase: Double = 0.45

    /// Default eccentricity factor for eccentric (field) conditions
    static let eccentricityFactor: Double = 1.2

    // MARK: - Float Valve

    /// Pressure tolerance for float valve open/close detection (kPa)
    static let floatTolerance_kPa: Double = 5.0

    // MARK: - APL Empirical

    /// Calibration constant for simplified APL formula:
    /// APL = K × ρ × L × Q² / (Dh − Dp)
    static let aplEmpiricalK: Double = 5.0e-05

    // MARK: - Flow Thresholds

    /// Minimum flow rate below which friction is assumed zero (m³/min)
    static let minFlowRate_m3perMin: Double = 0.001

    // MARK: - Mud Matching

    /// Density tolerance for "same mud" comparison (kg/m³)
    static let densityTolerance_kgm3: Double = 50.0

    // MARK: - Numerical

    /// Epsilon for floating-point comparisons in layer operations
    static let epsilon: Double = 1e-9
}
