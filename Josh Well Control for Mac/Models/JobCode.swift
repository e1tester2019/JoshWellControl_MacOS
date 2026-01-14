//
//  JobCode.swift
//  Josh Well Control for Mac
//
//  Job codes for drilling operations with self-learning duration estimation.
//

import Foundation
import SwiftData
import SwiftUI

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

    /// Default color hex for this category
    var defaultColorHex: String {
        switch self {
        case .drilling: return "#3B82F6"    // Blue
        case .casing: return "#8B5CF6"      // Purple
        case .cementing: return "#6B7280"   // Gray
        case .tripping: return "#F59E0B"    // Amber
        case .testing: return "#10B981"     // Emerald
        case .logging: return "#06B6D4"     // Cyan
        case .completions: return "#22C55E" // Green
        case .rigMove: return "#EF4444"     // Red
        case .maintenance: return "#F97316" // Orange
        case .other: return "#64748B"       // Slate
        }
    }

    var defaultColor: Color {
        Color(hex: defaultColorHex) ?? .blue
    }
}

/// Preset colors for job codes
enum JobCodeColor: String, CaseIterable, Identifiable {
    case blue = "#3B82F6"
    case purple = "#8B5CF6"
    case pink = "#EC4899"
    case red = "#EF4444"
    case orange = "#F97316"
    case amber = "#F59E0B"
    case yellow = "#EAB308"
    case lime = "#84CC16"
    case green = "#22C55E"
    case emerald = "#10B981"
    case teal = "#14B8A6"
    case cyan = "#06B6D4"
    case sky = "#0EA5E9"
    case indigo = "#6366F1"
    case violet = "#7C3AED"
    case slate = "#64748B"
    case gray = "#6B7280"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .pink: return "Pink"
        case .red: return "Red"
        case .orange: return "Orange"
        case .amber: return "Amber"
        case .yellow: return "Yellow"
        case .lime: return "Lime"
        case .green: return "Green"
        case .emerald: return "Emerald"
        case .teal: return "Teal"
        case .cyan: return "Cyan"
        case .sky: return "Sky"
        case .indigo: return "Indigo"
        case .violet: return "Violet"
        case .slate: return "Slate"
        case .gray: return "Gray"
        }
    }

    var color: Color {
        Color(hex: rawValue) ?? .blue
    }
}

@Model
final class JobCode {
    var id: UUID = UUID()
    var code: String = ""
    var name: String = ""
    var categoryRaw: String = JobCodeCategory.other.rawValue
    var colorHex: String?  // Custom color, falls back to category default if nil
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

    /// The color for this job code (custom or category default)
    var color: Color {
        if let hex = colorHex, let customColor = Color(hex: hex) {
            return customColor
        }
        return category.defaultColor
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
