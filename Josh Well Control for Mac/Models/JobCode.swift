//
//  JobCode.swift
//  Josh Well Control for Mac
//
//  Job codes for drilling operations with self-learning duration estimation.
//

import Foundation
import SwiftData

enum JobCodeCategory: String, Codable, CaseIterable {
    case drilling = "Drilling"
    case casing = "Casing"
    case cementing = "Cementing"
    case tripping = "Tripping"
    case testing = "Testing"
    case logging = "Logging"
    case completions = "Completions"
    case rigMove = "Rig Move"
    case maintenance = "Maintenance"
    case other = "Other"

    var icon: String {
        switch self {
        case .drilling: return "arrow.down.circle"
        case .casing: return "cylinder"
        case .cementing: return "drop.fill"
        case .tripping: return "arrow.up.arrow.down"
        case .testing: return "gauge"
        case .logging: return "waveform"
        case .completions: return "checkmark.seal"
        case .rigMove: return "truck.box"
        case .maintenance: return "wrench.and.screwdriver"
        case .other: return "ellipsis.circle"
        }
    }
}

@Model
final class JobCode {
    var id: UUID = UUID()
    var code: String = ""
    var name: String = ""
    var categoryRaw: String = JobCodeCategory.other.rawValue
    var notes: String = ""

    // Duration statistics (learned from completed tasks)
    var averageDuration_min: Double = 60
    var averageDurationPerMeter_min: Double = 0
    var timesPerformed: Int = 0
    var totalDuration_min: Double = 0
    var totalMeterage_m: Double = 0

    // Default settings
    var defaultEstimate_min: Double = 60
    var isMetarageBased: Bool = false
    var defaultVendorRequired: Bool = false

    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    // Relationships
    @Relationship(deleteRule: .nullify) var defaultVendor: Vendor?
    @Relationship(deleteRule: .nullify, inverse: \LookAheadTask.jobCode) var tasks: [LookAheadTask]?

    init(code: String = "",
         name: String = "",
         category: JobCodeCategory = .other,
         defaultEstimate_min: Double = 60,
         isMetarageBased: Bool = false) {
        self.code = code
        self.name = name
        self.categoryRaw = category.rawValue
        self.defaultEstimate_min = defaultEstimate_min
        self.isMetarageBased = isMetarageBased
    }

    var category: JobCodeCategory {
        get { JobCodeCategory(rawValue: categoryRaw) ?? .other }
        set {
            categoryRaw = newValue.rawValue
            updatedAt = .now
        }
    }

    var displayName: String {
        if code.isEmpty {
            return name
        }
        return "\(code) - \(name)"
    }

    /// Calculate estimated duration based on meterage or flat average
    func estimateDuration(forMeters meters: Double?) -> Double {
        if isMetarageBased, let m = meters, m > 0, averageDurationPerMeter_min > 0 {
            return m * averageDurationPerMeter_min
        }
        return timesPerformed > 0 ? averageDuration_min : defaultEstimate_min
    }

    /// Update running averages when a task using this job code completes
    func recordCompletion(duration_min: Double, meterage_m: Double?) {
        timesPerformed += 1
        totalDuration_min += duration_min
        averageDuration_min = totalDuration_min / Double(timesPerformed)

        if let m = meterage_m, m > 0 {
            totalMeterage_m += m
            averageDurationPerMeter_min = totalDuration_min / totalMeterage_m
        }

        updatedAt = .now
    }

    /// Formatted average duration display
    var averageDurationFormatted: String {
        let hours = Int(averageDuration_min) / 60
        let mins = Int(averageDuration_min) % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }

    /// Formatted per-meter rate display
    var perMeterRateFormatted: String? {
        guard isMetarageBased, averageDurationPerMeter_min > 0 else { return nil }
        return String(format: "%.2f min/m", averageDurationPerMeter_min)
    }
}
