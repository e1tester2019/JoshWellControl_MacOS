//
//  CallLogEntry.swift
//  Josh Well Control for Mac
//
//  Record of vendor communications for look ahead scheduling.
//

import Foundation
import SwiftData

enum CallOutcome: String, Codable, CaseIterable {
    case confirmed = "Confirmed"
    case noAnswer = "No Answer"
    case leftMessage = "Left Message"
    case rescheduled = "Rescheduled"
    case cancelled = "Cancelled"
    case standby = "On Standby"
    case callback = "Callback Requested"

    var icon: String {
        switch self {
        case .confirmed: return "checkmark.circle.fill"
        case .noAnswer: return "phone.arrow.up.right"
        case .leftMessage: return "envelope.fill"
        case .rescheduled: return "calendar.badge.clock"
        case .cancelled: return "xmark.circle"
        case .standby: return "clock.badge.questionmark"
        case .callback: return "phone.arrow.down.left"
        }
    }

    var color: String {
        switch self {
        case .confirmed: return "green"
        case .noAnswer: return "orange"
        case .leftMessage: return "blue"
        case .rescheduled: return "purple"
        case .cancelled: return "red"
        case .standby: return "yellow"
        case .callback: return "cyan"
        }
    }
}

@Model
final class CallLogEntry {
    var id: UUID = UUID()
    var timestamp: Date = Date.now
    var callerName: String = ""
    var contactedName: String = ""
    var outcomeRaw: String = CallOutcome.confirmed.rawValue
    var notes: String = ""
    var followUpRequired: Bool = false
    var followUpTime: Date?
    var durationSeconds: Int = 0

    // Relationships
    @Relationship(deleteRule: .nullify) var task: LookAheadTask?
    @Relationship(deleteRule: .nullify) var vendor: Vendor?

    init(callerName: String = "",
         contactedName: String = "",
         outcome: CallOutcome = .confirmed,
         notes: String = "") {
        self.callerName = callerName
        self.contactedName = contactedName
        self.outcomeRaw = outcome.rawValue
        self.notes = notes
    }

    var outcome: CallOutcome {
        get { CallOutcome(rawValue: outcomeRaw) ?? .confirmed }
        set { outcomeRaw = newValue.rawValue }
    }

    /// Formatted timestamp for display
    var timestampFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }

    /// Time since call was made
    var timeSinceCall: String {
        let interval = Date.now.timeIntervalSince(timestamp)
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60

        if hours > 24 {
            let days = hours / 24
            return "\(days)d ago"
        } else if hours > 0 {
            return "\(hours)h ago"
        } else if minutes > 0 {
            return "\(minutes)m ago"
        }
        return "Just now"
    }

    /// Summary line for list display
    var summaryLine: String {
        var parts: [String] = []
        if !contactedName.isEmpty {
            parts.append("Spoke with \(contactedName)")
        }
        parts.append(outcome.rawValue)
        if followUpRequired {
            parts.append("Follow-up required")
        }
        return parts.joined(separator: " - ")
    }

    /// Check if follow-up is overdue
    var isFollowUpOverdue: Bool {
        guard followUpRequired, let followUp = followUpTime else { return false }
        return followUp < Date.now
    }
}
