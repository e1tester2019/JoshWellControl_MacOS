//
//  TripSettings.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-02.
//


import Foundation
import SwiftData

@Model
final class TripSettings {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = "Trip Settings"

    // MARK: - Trip speed / movement
    /// Average tripping speed (m/s) — positive = upward (pull out), negative = downward (run in)
    var tripSpeed_m_per_s: Double = 0.3

    /// Stand length (m)
    var standLength_m: Double = 27.0

    /// Acceleration/deceleration zone per stand (m)
    var accelZone_m: Double = 3.0

    /// Pause time between stands (s)
    var pauseBetweenStands_s: Double = 5.0

    // MARK: - Swab/surge coefficients
    /// Surge/swab correction coefficient (empirical, 0–1)
    var surgeFactor: Double = 1.0
    var swabFactor: Double = 1.0

    /// Flow regime flag — for later transient model use (0 = laminar, 1 = turbulent)
    var flowRegime: Int = 0

    // MARK: - Fluid and pressure references
    /// Surface pressure offset (kPa)
    var surfacePressure_kPa: Double = 0.0

    /// Temperature (°C) if needed for fluid property adjustments
    var fluidTemperature_C: Double = 25.0

    /// Gravity constant for all hydraulic calculations
    var gravity_m_per_s2: Double = 9.80665

    // MARK: - Operational limits
    /// Minimum allowable ECD (kg/m³)
    var minECDDensity_kg_per_m3: Double = 900.0
    /// Maximum allowable ECD (kg/m³)
    var maxECDDensity_kg_per_m3: Double = 2300.0

    /// Optional auto-stop at ECD limit
    var stopOnLimit: Bool = true

    // MARK: - Relationships
    @Relationship(deleteRule: .nullify, inverse: \ProjectState.settings)
    var project: ProjectState?

    init() {}

    // MARK: - Derived / Helper Methods

    /// Duration (s) to pull one stand at current speed (including pause)
    @Transient var timePerStand_s: Double {
        guard tripSpeed_m_per_s > 0 else { return 0 }
        let moveTime = standLength_m / tripSpeed_m_per_s
        return moveTime + pauseBetweenStands_s
    }

    /// Effective tripping rate in m/hr
    @Transient var tripRate_m_per_hr: Double {
        guard timePerStand_s > 0 else { return 0 }
        return (standLength_m / timePerStand_s) * 3600.0
    }

    /// Converts fluid density to ECD (kPa/m)
    func ecdGradient_kPa_per_m(density_kg_per_m3: Double) -> Double {
        (density_kg_per_m3 * gravity_m_per_s2) / 1000.0
    }

    /// Returns whether a given ECD density (kg/m³) violates limits
    func ecdWithinLimits(_ density_kg_per_m3: Double) -> Bool {
        density_kg_per_m3 >= minECDDensity_kg_per_m3 && density_kg_per_m3 <= maxECDDensity_kg_per_m3
    }
}
