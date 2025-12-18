//
//  TripLayerSnapshot.swift
//  Josh Well Control for Mac
//
//  Created for storing layer snapshots in trip simulation persistence.
//

import Foundation

/// Codable snapshot of a fluid layer for trip simulation persistence.
/// Captures all LayerRow properties for visualization replay.
struct TripLayerSnapshot: Codable, Equatable {
    var side: String
    var topMD: Double
    var bottomMD: Double
    var topTVD: Double
    var bottomTVD: Double
    var rho_kgpm3: Double
    var deltaHydroStatic_kPa: Double
    var volume_m3: Double

    // Color stored as separate components
    var colorR: Double?
    var colorG: Double?
    var colorB: Double?
    var colorA: Double?

    // MARK: - Convenience Initializer from LayerRow

    /// Create from a NumericalTripModel.LayerRow
    init(from layerRow: NumericalTripModel.LayerRow) {
        self.side = layerRow.side
        self.topMD = layerRow.topMD
        self.bottomMD = layerRow.bottomMD
        self.topTVD = layerRow.topTVD
        self.bottomTVD = layerRow.bottomTVD
        self.rho_kgpm3 = layerRow.rho_kgpm3
        self.deltaHydroStatic_kPa = layerRow.deltaHydroStatic_kPa
        self.volume_m3 = layerRow.volume_m3

        if let color = layerRow.color {
            self.colorR = color.r
            self.colorG = color.g
            self.colorB = color.b
            self.colorA = color.a
        }
    }

    /// Direct initializer for all properties
    init(
        side: String,
        topMD: Double,
        bottomMD: Double,
        topTVD: Double,
        bottomTVD: Double,
        rho_kgpm3: Double,
        deltaHydroStatic_kPa: Double,
        volume_m3: Double,
        colorR: Double? = nil,
        colorG: Double? = nil,
        colorB: Double? = nil,
        colorA: Double? = nil
    ) {
        self.side = side
        self.topMD = topMD
        self.bottomMD = bottomMD
        self.topTVD = topTVD
        self.bottomTVD = bottomTVD
        self.rho_kgpm3 = rho_kgpm3
        self.deltaHydroStatic_kPa = deltaHydroStatic_kPa
        self.volume_m3 = volume_m3
        self.colorR = colorR
        self.colorG = colorG
        self.colorB = colorB
        self.colorA = colorA
    }

    // MARK: - Convert Back to LayerRow

    /// Convert back to a LayerRow for visualization
    func toLayerRow() -> NumericalTripModel.LayerRow {
        var color: NumericalTripModel.ColorRGBA? = nil
        if let r = colorR, let g = colorG, let b = colorB, let a = colorA {
            color = NumericalTripModel.ColorRGBA(r: r, g: g, b: b, a: a)
        }

        return NumericalTripModel.LayerRow(
            side: side,
            topMD: topMD,
            bottomMD: bottomMD,
            topTVD: topTVD,
            bottomTVD: bottomTVD,
            rho_kgpm3: rho_kgpm3,
            deltaHydroStatic_kPa: deltaHydroStatic_kPa,
            volume_m3: volume_m3,
            color: color
        )
    }

    // MARK: - Export Dictionary

    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "side": side,
            "topMD": topMD,
            "bottomMD": bottomMD,
            "topTVD": topTVD,
            "bottomTVD": bottomTVD,
            "rho_kgpm3": rho_kgpm3,
            "deltaHydroStatic_kPa": deltaHydroStatic_kPa,
            "volume_m3": volume_m3
        ]

        if let r = colorR { dict["colorR"] = r }
        if let g = colorG { dict["colorG"] = g }
        if let b = colorB { dict["colorB"] = b }
        if let a = colorA { dict["colorA"] = a }

        return dict
    }
}
