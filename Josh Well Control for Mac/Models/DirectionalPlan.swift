//
//  DirectionalPlan.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-12-29.
//

import Foundation
import SwiftData

@Model
final class DirectionalPlan {
    var id: UUID = UUID()
    var name: String = ""
    var revision: String = ""
    var planDate: Date?
    var sourceFileName: String?
    var importedAt: Date = Date.now
    var notes: String = ""

    /// Vertical Section Azimuth in degrees (reference direction for VS calculations)
    /// This is the direction the VS plane faces, typically toward the target
    var vsAzimuth_deg: Double?

    // Inverse relationship back to well
    @Relationship var well: Well?

    // Child stations - cascade delete when plan is deleted
    @Relationship(deleteRule: .cascade, inverse: \DirectionalPlanStation.plan)
    var stations: [DirectionalPlanStation]?

    init(name: String = "",
         revision: String = "",
         planDate: Date? = nil,
         sourceFileName: String? = nil,
         notes: String = "",
         vsAzimuth_deg: Double? = nil,
         well: Well? = nil) {
        self.name = name
        self.revision = revision
        self.planDate = planDate
        self.sourceFileName = sourceFileName
        self.notes = notes
        self.vsAzimuth_deg = vsAzimuth_deg
        self.well = well
    }
}

// MARK: - Computed Properties

extension DirectionalPlan {
    /// Stations sorted by measured depth
    var sortedStations: [DirectionalPlanStation] {
        (stations ?? []).sorted { $0.md < $1.md }
    }

    /// Maximum MD in the plan
    var maxMD: Double {
        sortedStations.last?.md ?? 0
    }

    /// Minimum MD in the plan
    var minMD: Double {
        sortedStations.first?.md ?? 0
    }
}

// MARK: - Export

extension DirectionalPlan {
    var exportDictionary: [String: Any] {
        [
            "id": id.uuidString,
            "name": name,
            "revision": revision,
            "planDate": planDate.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
            "sourceFileName": sourceFileName ?? NSNull(),
            "importedAt": ISO8601DateFormatter().string(from: importedAt),
            "notes": notes,
            "vsAzimuth_deg": vsAzimuth_deg ?? NSNull(),
            "stations": sortedStations.map { $0.exportDictionary }
        ]
    }
}
