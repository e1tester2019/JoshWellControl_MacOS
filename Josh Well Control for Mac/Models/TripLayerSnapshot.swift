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

    /// If true, this layer is already in annulus coordinates (e.g., pumped fluid)
    /// and should NOT be expanded further when pipe advances.
    /// If false/nil, layer is in original wellbore coordinates and needs expansion.
    var isInAnnulus: Bool?

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
        colorA: Double? = nil,
        isInAnnulus: Bool? = nil
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
        self.isInAnnulus = isInAnnulus
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

// MARK: - Wellbore State Transfer

/// Bundles the complete wellbore fluid state at a point in time for transferring
/// between Trip Out, Trip In, and Pump Schedule operations.
struct WellboreStateSnapshot: Codable {
    let bitMD_m: Double
    let bitTVD_m: Double
    let layersPocket: [TripLayerSnapshot]
    let layersAnnulus: [TripLayerSnapshot]
    let layersString: [TripLayerSnapshot]
    let SABP_kPa: Double
    let ESDAtControl_kgpm3: Double
    let controlMD_m: Double
    let targetESD_kgpm3: Double
    let sourceDescription: String
    let timestamp: Date

    /// Backward-compatible initializer (controlMD and targetESD default to 0)
    init(
        bitMD_m: Double,
        bitTVD_m: Double,
        layersPocket: [TripLayerSnapshot],
        layersAnnulus: [TripLayerSnapshot],
        layersString: [TripLayerSnapshot],
        SABP_kPa: Double,
        ESDAtControl_kgpm3: Double,
        controlMD_m: Double = 0,
        targetESD_kgpm3: Double = 0,
        sourceDescription: String,
        timestamp: Date
    ) {
        self.bitMD_m = bitMD_m
        self.bitTVD_m = bitTVD_m
        self.layersPocket = layersPocket
        self.layersAnnulus = layersAnnulus
        self.layersString = layersString
        self.SABP_kPa = SABP_kPa
        self.ESDAtControl_kgpm3 = ESDAtControl_kgpm3
        self.controlMD_m = controlMD_m
        self.targetESD_kgpm3 = targetESD_kgpm3
        self.sourceDescription = sourceDescription
        self.timestamp = timestamp
    }

    /// Codable support: decode with defaults for new fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bitMD_m = try container.decode(Double.self, forKey: .bitMD_m)
        bitTVD_m = try container.decode(Double.self, forKey: .bitTVD_m)
        layersPocket = try container.decode([TripLayerSnapshot].self, forKey: .layersPocket)
        layersAnnulus = try container.decode([TripLayerSnapshot].self, forKey: .layersAnnulus)
        layersString = try container.decode([TripLayerSnapshot].self, forKey: .layersString)
        SABP_kPa = try container.decode(Double.self, forKey: .SABP_kPa)
        ESDAtControl_kgpm3 = try container.decode(Double.self, forKey: .ESDAtControl_kgpm3)
        controlMD_m = try container.decodeIfPresent(Double.self, forKey: .controlMD_m) ?? 0
        targetESD_kgpm3 = try container.decodeIfPresent(Double.self, forKey: .targetESD_kgpm3) ?? 0
        sourceDescription = try container.decode(String.self, forKey: .sourceDescription)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
    }

    private enum CodingKeys: String, CodingKey {
        case bitMD_m, bitTVD_m, layersPocket, layersAnnulus, layersString
        case SABP_kPa, ESDAtControl_kgpm3, controlMD_m, targetESD_kgpm3
        case sourceDescription, timestamp
    }
}
