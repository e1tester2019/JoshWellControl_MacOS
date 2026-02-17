//
//  FluidIdentity.swift
//  Josh Well Control for Mac
//
//  Lightweight bundle of fluid physical properties: density + color + rheology.
//  Replaces scattered loose fields across VolumeParcel, PumpOperation,
//  TripLayerSnapshot, FrozenMud, etc.
//

import Foundation

/// Codable bundle of fluid identity: density, color, and rheology.
/// All fields are non-optional with zero/default values to avoid nil-vs-0 ambiguity.
struct FluidIdentity: Codable, Equatable, Sendable {

    // MARK: - Core

    var density_kgm3: Double = 0

    // MARK: - Color (RGBA, 0...1)

    var colorR: Double = 0.5
    var colorG: Double = 0.5
    var colorB: Double = 0.5
    var colorA: Double = 1.0

    // MARK: - Rheology (Bingham)

    /// Plastic viscosity in centiPoise (mPa·s)
    var pv_cP: Double = 0

    /// Yield point in Pascals
    var yp_Pa: Double = 0

    // MARK: - Rheology (Fann dial readings for Power Law)

    var dial600: Double = 0
    var dial300: Double = 0

    // MARK: - Optional Mud Identity

    var mudID: UUID?
    var mudName: String?

    // MARK: - Computed Properties

    /// Convert to NumericalTripModel.ColorRGBA
    var colorRGBA: NumericalTripModel.ColorRGBA {
        NumericalTripModel.ColorRGBA(r: colorR, g: colorG, b: colorB, a: colorA)
    }

    /// Whether Fann dial readings are available for Power Law model
    var hasDialReadings: Bool { dial600 > 0 && dial300 > 0 }

    /// Whether Bingham parameters are available
    var hasBingham: Bool { pv_cP > 0 || yp_Pa > 0 }

    /// Power law fit from Fann readings. Returns nil if dials are not available.
    func powerLawFit() -> (n: Double, K: Double)? {
        guard hasDialReadings else { return nil }
        let n = log(dial600 / dial300) / log(600.0 / 300.0)
        let tau600 = HydraulicsDefaults.fann35_dialToPa * dial600
        let gamma600 = HydraulicsDefaults.fann35_600rpm_shearRate
        let K = tau600 / pow(gamma600, n)
        return (n, K)
    }

    // MARK: - Convenience Initializers

    /// Create from MudProperties (SwiftData model)
    init(from mud: MudProperties) {
        self.density_kgm3 = mud.density_kgm3
        self.colorR = mud.colorR
        self.colorG = mud.colorG
        self.colorB = mud.colorB
        self.colorA = mud.colorA
        self.mudID = mud.id
        self.mudName = mud.name
        self.dial600 = mud.dial600 ?? 0
        self.dial300 = mud.dial300 ?? 0
        self.pv_cP = (mud.pv_Pa_s ?? 0) * 1000.0
        self.yp_Pa = mud.yp_Pa ?? 0
    }

    /// Create from density + ColorRGBA + rheology (for NumericalTripModel conversions)
    init(
        density_kgm3: Double,
        color: NumericalTripModel.ColorRGBA?,
        pv_cP: Double = 0,
        yp_Pa: Double = 0,
        dial600: Double = 0,
        dial300: Double = 0
    ) {
        self.density_kgm3 = density_kgm3
        self.colorR = color?.r ?? 0.5
        self.colorG = color?.g ?? 0.5
        self.colorB = color?.b ?? 0.5
        self.colorA = color?.a ?? 1.0
        self.pv_cP = pv_cP
        self.yp_Pa = yp_Pa
        self.dial600 = dial600
        self.dial300 = dial300
    }
}
