//
//  RigDataImport.swift
//  Josh Well Control for Mac
//
//  SwiftData model for persisting processed rig sensor data (hook load, bit depth)
//  linked to a ProjectState for sim vs rig comparison.
//

import Foundation
import SwiftData

// MARK: - Codable structs for JSON-encoded processed data

/// Per-stand averaged rig hook load data
struct RigStandData: Codable, Identifiable {
    var id: UUID = UUID()
    var standMidMD_m: Double
    var avgHL_kDaN: Double
    var minHL_kDaN: Double
    var maxHL_kDaN: Double
    var count: Int
}

/// Static weight measurement extracted at connection height crossings (trip-in only)
struct RigStaticWeight: Codable, Identifiable {
    var id: UUID = UUID()
    var depth_m: Double
    var hookLoad_kDaN: Double
}

// MARK: - SwiftData Model

@Model
final class RigDataImport {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date.now
    var tripType: String = "in"       // "in" or "out"
    var sourceFileName: String = ""

    // Import config (all with defaults for CloudKit)
    var standLength_m: Double = 28.0
    var blockHeightThreshold_m: Double = 19.9
    var connectionHeight_m: Double = 19.4
    var topDriveWeight_kDaN: Double = 20.0
    var maxMinusFilter_kDaN: Double = 15.0

    // Hook load correction (for mid-trip sensor recalibration)
    // Applies offset to all data at and deeper than correctionDepth
    var correctionDepth_m: Double = 0
    var correctionOffset_kDaN: Double = 0

    // Detected metadata
    var maxBitDepth_m: Double = 0
    var minBitDepth_m: Double = 0
    var totalRawRows: Int = 0
    var filteredRows: Int = 0
    var standCount: Int = 0

    // Processed data (JSON-encoded Data, CloudKit-safe)
    var standDataJSON: Data?
    var staticWeightsJSON: Data?

    @Relationship(deleteRule: .nullify) var project: ProjectState?

    init() {}

    // MARK: - Computed accessors (encode/decode JSON)

    @Transient var standData: [RigStandData] {
        get {
            guard let data = standDataJSON else { return [] }
            return (try? JSONDecoder().decode([RigStandData].self, from: data)) ?? []
        }
        set {
            standDataJSON = try? JSONEncoder().encode(newValue)
            standCount = newValue.count
        }
    }

    @Transient var staticWeights: [RigStaticWeight] {
        get {
            guard let data = staticWeightsJSON else { return [] }
            return (try? JSONDecoder().decode([RigStaticWeight].self, from: data)) ?? []
        }
        set {
            staticWeightsJSON = try? JSONEncoder().encode(newValue)
        }
    }

    /// Stand data with hook load correction applied
    @Transient var correctedStandData: [RigStandData] {
        guard correctionDepth_m > 0 && correctionOffset_kDaN != 0 else { return standData }
        return standData.map { stand in
            if stand.standMidMD_m >= correctionDepth_m {
                var s = stand
                s.avgHL_kDaN -= correctionOffset_kDaN
                s.minHL_kDaN -= correctionOffset_kDaN
                s.maxHL_kDaN -= correctionOffset_kDaN
                return s
            }
            return stand
        }
    }

    /// Static weights with hook load correction applied
    @Transient var correctedStaticWeights: [RigStaticWeight] {
        guard correctionDepth_m > 0 && correctionOffset_kDaN != 0 else { return staticWeights }
        return staticWeights.map { sw in
            if sw.depth_m >= correctionDepth_m {
                var w = sw
                w.hookLoad_kDaN -= correctionOffset_kDaN
                return w
            }
            return sw
        }
    }
}
