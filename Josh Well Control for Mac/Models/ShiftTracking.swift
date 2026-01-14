//
//  ShiftTracking.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2026-01-13.
//

import Foundation
import SwiftData

// MARK: - ShiftType

enum ShiftType: String, Codable, CaseIterable {
    case day = "Day"
    case night = "Night"
    case off = "Off"

    var displayName: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .day: return "sun.max.fill"
        case .night: return "moon.fill"
        case .off: return "house.fill"
        }
    }
}

// MARK: - ShiftEntry

@Model
final class ShiftEntry {
    var id: UUID = UUID()
    var date: Date = Date.now

    // Store as raw string for SwiftData compatibility
    var shiftTypeRaw: String = ShiftType.off.rawValue
    var shiftType: ShiftType {
        get { ShiftType(rawValue: shiftTypeRaw) ?? .off }
        set { shiftTypeRaw = newValue.rawValue }
    }

    var notes: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    // Relationships
    @Relationship(deleteRule: .nullify) var well: Well?
    @Relationship(deleteRule: .nullify) var client: Client?
    @Relationship(deleteRule: .cascade) var workDay: WorkDay?

    init(date: Date = Date.now, shiftType: ShiftType = .off) {
        self.date = Calendar.current.startOfDay(for: date)
        self.shiftTypeRaw = shiftType.rawValue
    }

    /// Whether this is a working shift (day or night, not off)
    var isWorkingShift: Bool {
        shiftType != .off
    }

    /// Display string for the date
    var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }

    /// Short display string for calendar
    var shortDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
}

// MARK: - ShiftRotationSettings

struct ShiftRotationSettings: Codable {
    var daysInRotation: Int = 10
    var nightsInRotation: Int = 10
    var daysOffInRotation: Int = 10

    /// The start date of the current rotation cycle
    var rotationStartDate: Date?

    /// Time when day shift starts (default 6:30 AM)
    var dayShiftStartHour: Int = 6
    var dayShiftStartMinute: Int = 30

    /// Time when night shift starts (default 6:30 PM)
    var nightShiftStartHour: Int = 18
    var nightShiftStartMinute: Int = 30

    /// Whether end-of-shift reminders are enabled
    var endOfShiftReminderEnabled: Bool = true

    /// Minutes before shift end to send reminder (default 0 = at shift end)
    var reminderMinutesBefore: Int = 0

    /// Total days in one complete rotation cycle
    var totalCycleDays: Int {
        daysInRotation + nightsInRotation + daysOffInRotation
    }

    // MARK: - UserDefaults Storage

    private static let storageKey = "ShiftRotationSettings"

    static var shared: ShiftRotationSettings {
        get {
            if let data = UserDefaults.standard.data(forKey: storageKey),
               let settings = try? JSONDecoder().decode(ShiftRotationSettings.self, from: data) {
                return settings
            }
            return ShiftRotationSettings()
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: storageKey)
            }
        }
    }

    // MARK: - Shift Type Calculation

    /// Calculate the expected shift type for a given date based on rotation settings
    func expectedShiftType(for date: Date) -> ShiftType {
        guard let startDate = rotationStartDate else {
            return .off
        }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let target = calendar.startOfDay(for: date)

        guard let daysDiff = calendar.dateComponents([.day], from: start, to: target).day else {
            return .off
        }

        // Handle negative days (before rotation start)
        let adjustedDays = daysDiff >= 0 ? daysDiff : (totalCycleDays + (daysDiff % totalCycleDays)) % totalCycleDays
        let dayInCycle = adjustedDays % totalCycleDays

        if dayInCycle < daysInRotation {
            return .day
        } else if dayInCycle < daysInRotation + nightsInRotation {
            return .night
        } else {
            return .off
        }
    }

    /// Get the end time for a shift type
    func shiftEndTime(for shiftType: ShiftType, on date: Date) -> Date? {
        guard shiftType != .off else { return nil }

        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: date)

        if shiftType == .day {
            // Day shift ends at night shift start time (6:30 PM)
            components.hour = nightShiftStartHour
            components.minute = nightShiftStartMinute
        } else {
            // Night shift ends at day shift start time next day (6:30 AM)
            components.hour = dayShiftStartHour
            components.minute = dayShiftStartMinute
            if let nextDay = calendar.date(byAdding: .day, value: 1, to: date) {
                components = calendar.dateComponents([.year, .month, .day], from: nextDay)
                components.hour = dayShiftStartHour
                components.minute = dayShiftStartMinute
            }
        }

        return calendar.date(from: components)
    }
}
