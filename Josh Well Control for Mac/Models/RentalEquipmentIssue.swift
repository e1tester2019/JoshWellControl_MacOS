//
//  RentalEquipmentIssue.swift
//  Josh Well Control for Mac
//
//  Issue log entry for rental equipment - tracks failures, problems, repairs.
//

import Foundation
import SwiftData
import SwiftUI

enum RentalIssueType: String, Codable, CaseIterable {
    case failure = "Failure"
    case malfunction = "Malfunction"
    case damage = "Damage"
    case calibration = "Calibration Issue"
    case communication = "Communication Issue"
    case mechanical = "Mechanical Issue"
    case electrical = "Electrical Issue"
    case software = "Software Issue"
    case wear = "Wear/Maintenance"
    case other = "Other"

    var icon: String {
        switch self {
        case .failure: return "xmark.octagon.fill"
        case .malfunction: return "exclamationmark.triangle.fill"
        case .damage: return "bandage.fill"
        case .calibration: return "gauge.with.needle"
        case .communication: return "antenna.radiowaves.left.and.right.slash"
        case .mechanical: return "gearshape.2"
        case .electrical: return "bolt.slash"
        case .software: return "ladybug"
        case .wear: return "wrench.and.screwdriver"
        case .other: return "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .failure: return .red
        case .malfunction, .damage: return .orange
        case .calibration, .communication, .mechanical, .electrical, .software: return .yellow
        case .wear, .other: return .secondary
        }
    }
}

enum RentalIssueSeverity: String, Codable, CaseIterable {
    case critical = "Critical"
    case major = "Major"
    case minor = "Minor"
    case observation = "Observation"

    var color: Color {
        switch self {
        case .critical: return .red
        case .major: return .orange
        case .minor: return .yellow
        case .observation: return .secondary
        }
    }
}

@Model
final class RentalEquipmentIssue {
    var id: UUID = UUID()
    var date: Date = Date.now
    var issueTypeRaw: String = RentalIssueType.other.rawValue
    var severityRaw: String = RentalIssueSeverity.minor.rawValue
    var description_: String = ""  // 'description' is reserved
    var actionTaken: String = ""
    var reportedBy: String = ""
    var isResolved: Bool = false
    var resolvedDate: Date?
    var resolutionNotes: String = ""
    var wellName: String = ""  // Store well name at time of issue for history
    var createdAt: Date = Date.now

    // Relationship back to equipment
    @Relationship var equipment: RentalEquipment?

    init(issueType: RentalIssueType = .other,
         severity: RentalIssueSeverity = .minor,
         description: String = "",
         reportedBy: String = "") {
        self.issueTypeRaw = issueType.rawValue
        self.severityRaw = severity.rawValue
        self.description_ = description
        self.reportedBy = reportedBy
        self.date = Date.now
    }

    var issueType: RentalIssueType {
        get { RentalIssueType(rawValue: issueTypeRaw) ?? .other }
        set { issueTypeRaw = newValue.rawValue }
    }

    var severity: RentalIssueSeverity {
        get { RentalIssueSeverity(rawValue: severityRaw) ?? .minor }
        set { severityRaw = newValue.rawValue }
    }

    /// Formatted date string
    var dateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Short summary for list display
    var summary: String {
        let truncated = description_.prefix(50)
        if description_.count > 50 {
            return "\(truncated)..."
        }
        return String(truncated)
    }

    /// Mark as resolved
    func resolve(notes: String = "") {
        isResolved = true
        resolvedDate = Date.now
        resolutionNotes = notes
    }
}
