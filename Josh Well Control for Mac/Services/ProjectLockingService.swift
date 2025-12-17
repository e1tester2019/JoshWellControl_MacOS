//
//  ProjectLockingService.swift
//  Josh Well Control for Mac
//
//  Manages edit locking for projects across multiple windows to prevent conflicts
//

import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#endif

/// Represents an active edit lock on a project
struct ProjectEditLock: Identifiable, Equatable {
    let id: UUID
    let projectID: UUID
    let windowID: UUID
    let lockedAt: Date
    let fieldPath: String?

    init(projectID: UUID, windowID: UUID, fieldPath: String? = nil) {
        self.id = UUID()
        self.projectID = projectID
        self.windowID = windowID
        self.lockedAt = .now
        self.fieldPath = fieldPath
    }
}

/// Service for managing project edit locks across multiple windows
@Observable
@MainActor
final class ProjectLockingService {
    static let shared = ProjectLockingService()

    /// Active locks keyed by project ID
    private(set) var activeLocks: [UUID: ProjectEditLock] = [:]

    /// Lock timeout (locks expire after inactivity)
    private let lockTimeout: TimeInterval = 30 // seconds

    /// Timer for cleaning up stale locks
    private var cleanupTimer: Timer?

    private init() {
        startCleanupTimer()
    }

    // MARK: - Lock Management

    /// Attempts to acquire or refresh a lock for a project
    /// - Parameters:
    ///   - projectID: The project to lock
    ///   - windowID: The window requesting the lock
    ///   - fieldPath: Optional specific field being edited
    /// - Returns: True if lock was acquired/refreshed, false if locked by another window
    @discardableResult
    func acquireLock(for projectID: UUID, windowID: UUID, fieldPath: String? = nil) -> Bool {
        // Check for existing lock
        if let existingLock = activeLocks[projectID] {
            // Same window can refresh its lock
            if existingLock.windowID == windowID {
                activeLocks[projectID] = ProjectEditLock(
                    projectID: projectID,
                    windowID: windowID,
                    fieldPath: fieldPath
                )
                return true
            }

            // Check if existing lock has expired
            if Date.now.timeIntervalSince(existingLock.lockedAt) > lockTimeout {
                // Take over expired lock
                activeLocks[projectID] = ProjectEditLock(
                    projectID: projectID,
                    windowID: windowID,
                    fieldPath: fieldPath
                )
                return true
            }

            // Locked by another window
            return false
        }

        // No existing lock, acquire it
        activeLocks[projectID] = ProjectEditLock(
            projectID: projectID,
            windowID: windowID,
            fieldPath: fieldPath
        )
        return true
    }

    /// Releases a lock held by a window
    /// - Parameters:
    ///   - projectID: The project to unlock
    ///   - windowID: The window releasing the lock
    func releaseLock(for projectID: UUID, windowID: UUID) {
        if let lock = activeLocks[projectID], lock.windowID == windowID {
            activeLocks.removeValue(forKey: projectID)
        }
    }

    /// Releases all locks held by a window (call when window closes)
    /// - Parameter windowID: The window being closed
    func releaseAllLocks(for windowID: UUID) {
        activeLocks = activeLocks.filter { $0.value.windowID != windowID }
    }

    /// Checks if a project is locked by a different window
    /// - Parameters:
    ///   - projectID: The project to check
    ///   - windowID: The current window (to exclude from check)
    /// - Returns: True if locked by another window
    func isLocked(_ projectID: UUID, byOtherThan windowID: UUID) -> Bool {
        guard let lock = activeLocks[projectID] else { return false }

        // Check if lock is expired
        if Date.now.timeIntervalSince(lock.lockedAt) > lockTimeout {
            activeLocks.removeValue(forKey: projectID)
            return false
        }

        return lock.windowID != windowID
    }

    /// Gets the lock info if a project is locked by another window
    /// - Parameters:
    ///   - projectID: The project to check
    ///   - windowID: The current window
    /// - Returns: The lock if held by another window, nil otherwise
    func lockInfo(for projectID: UUID, excludingWindow windowID: UUID) -> ProjectEditLock? {
        guard let lock = activeLocks[projectID],
              lock.windowID != windowID,
              Date.now.timeIntervalSince(lock.lockedAt) <= lockTimeout else {
            return nil
        }
        return lock
    }

    // MARK: - Cleanup

    private func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            Task { @MainActor [weak self] in
                self?.cleanupExpiredLocks()
            }
        }
    }

    private func cleanupExpiredLocks() {
        let now = Date.now
        activeLocks = activeLocks.filter { entry in
            now.timeIntervalSince(entry.value.lockedAt) <= lockTimeout
        }
    }
}

// MARK: - Window ID Helper

#if os(macOS)
extension NSWindow {
    /// Unique identifier for this window instance
    var windowUUID: UUID {
        // Use associated object to maintain a consistent UUID per window
        if let uuid = objc_getAssociatedObject(self, &AssociatedKeys.windowUUID) as? UUID {
            return uuid
        }
        let newUUID = UUID()
        objc_setAssociatedObject(self, &AssociatedKeys.windowUUID, newUUID, .OBJC_ASSOCIATION_RETAIN)
        return newUUID
    }
}

private enum AssociatedKeys {
    static var windowUUID: UInt8 = 0
}
#endif

// MARK: - Environment Key

private struct WindowIDKey: EnvironmentKey {
    static let defaultValue: UUID = UUID()
}

extension EnvironmentValues {
    var windowID: UUID {
        get { self[WindowIDKey.self] }
        set { self[WindowIDKey.self] = newValue }
    }
}
