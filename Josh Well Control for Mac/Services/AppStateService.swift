//
//  AppStateService.swift
//  Josh Well Control for Mac
//
//  Persists app state (last selected well/project/view) across launches
//

import Foundation
import SwiftUI
import SwiftData

/// Service for persisting and restoring app navigation state across launches
@Observable
final class AppStateService {
    static let shared = AppStateService()

    // MARK: - Stored State (via @AppStorage-compatible UserDefaults)

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let lastWellID = "AppState.lastSelectedWellID"
        static let lastProjectID = "AppState.lastSelectedProjectID"
        static let lastView = "AppState.lastSelectedView"
    }

    // MARK: - Last Selected IDs

    var lastSelectedWellID: UUID? {
        get {
            guard let string = defaults.string(forKey: Keys.lastWellID) else { return nil }
            return UUID(uuidString: string)
        }
        set {
            defaults.set(newValue?.uuidString, forKey: Keys.lastWellID)
        }
    }

    var lastSelectedProjectID: UUID? {
        get {
            guard let string = defaults.string(forKey: Keys.lastProjectID) else { return nil }
            return UUID(uuidString: string)
        }
        set {
            defaults.set(newValue?.uuidString, forKey: Keys.lastProjectID)
        }
    }

    var lastSelectedViewRaw: String {
        get { defaults.string(forKey: Keys.lastView) ?? "dashboard" }
        set { defaults.set(newValue, forKey: Keys.lastView) }
    }

    // MARK: - Restore State

    /// Attempts to restore the last selected well and project from the given wells array
    /// - Parameter wells: Array of available wells
    /// - Returns: Tuple of (well, project) if found, or first available well/project as fallback
    func restore(from wells: [Well]) -> (well: Well?, project: ProjectState?) {
        // Try to find the last selected well
        if let wellID = lastSelectedWellID,
           let well = wells.first(where: { $0.id == wellID }) {
            // Found the well, now try to find the project
            let project: ProjectState?
            if let projectID = lastSelectedProjectID {
                project = well.projects?.first(where: { $0.id == projectID })
            } else {
                project = well.projects?.first
            }
            return (well, project ?? well.projects?.first)
        }

        // Fallback to first available well
        if let firstWell = wells.first {
            return (firstWell, firstWell.projects?.first)
        }

        return (nil, nil)
    }

    // MARK: - Save State

    /// Saves the current selection state
    /// - Parameters:
    ///   - well: Currently selected well
    ///   - project: Currently selected project
    ///   - viewRaw: Raw string value of the selected view
    func save(well: Well?, project: ProjectState?, viewRaw: String? = nil) {
        lastSelectedWellID = well?.id
        lastSelectedProjectID = project?.id
        if let viewRaw = viewRaw {
            lastSelectedViewRaw = viewRaw
        }
    }

    // MARK: - Mark Well Accessed

    /// Updates the lastAccessedAt timestamp for a well
    /// - Parameters:
    ///   - well: The well being accessed
    ///   - context: ModelContext for saving
    func markAccessed(_ well: Well, context: ModelContext) {
        well.lastAccessedAt = .now
        well.updatedAt = .now
        try? context.save()
    }

    private init() {}
}
