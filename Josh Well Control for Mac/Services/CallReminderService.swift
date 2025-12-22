//
//  CallReminderService.swift
//  Josh Well Control for Mac
//
//  Service for scheduling local notifications for vendor call reminders.
//

import Foundation
import UserNotifications
import SwiftData
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@Observable
final class CallReminderService {
    static let shared = CallReminderService()

    private(set) var isAuthorized = false
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private init() {
        Task {
            await checkAuthorizationStatus()
        }
    }

    // MARK: - Authorization

    @MainActor
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            isAuthorized = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await checkAuthorizationStatus()
            return isAuthorized
        } catch {
            print("⚠️ Notification authorization failed: \(error)")
            return false
        }
    }

    @MainActor
    func checkAuthorizationStatus() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        isAuthorized = settings.authorizationStatus == .authorized
    }

    // MARK: - Schedule Notifications

    /// Schedule a call reminder notification for a task
    func scheduleCallReminder(for task: LookAheadTask) {
        guard isAuthorized else {
            print("ℹ️ Notifications not authorized, skipping reminder for: \(task.name)")
            return
        }
        let vendors = task.assignedVendors
        guard !vendors.isEmpty else {
            print("ℹ️ No vendors assigned, skipping reminder for: \(task.name)")
            return
        }

        let reminderTime = task.reminderTime
        guard reminderTime > Date.now else {
            print("ℹ️ Reminder time has passed, skipping for: \(task.name)")
            return
        }

        let content = UNMutableNotificationContent()
        let vendorCount = vendors.count
        content.title = vendorCount == 1
            ? "Call Reminder: \(task.name)"
            : "Call Reminder: \(task.name) (\(vendorCount) vendors)"

        var bodyParts: [String] = []
        for vendor in vendors {
            var vendorInfo = "• \(vendor.companyName)"
            if !vendor.phone.isEmpty {
                vendorInfo += " - \(vendor.phone)"
            }
            bodyParts.append(vendorInfo)
        }
        if let well = task.well {
            bodyParts.append("Well: \(well.name)")
        }
        content.body = bodyParts.joined(separator: "\n")

        content.sound = .default
        content.categoryIdentifier = "CALL_REMINDER"
        content.userInfo = [
            "taskID": task.id.uuidString,
            "vendorIDs": vendors.map { $0.id.uuidString },
            "taskName": task.name
        ]

        // Create date-based trigger
        let triggerDate = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminderTime
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)

        let identifier = notificationIdentifier(for: task)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("⚠️ Failed to schedule notification: \(error)")
            } else {
                print("✅ Scheduled call reminder for '\(task.name)' at \(reminderTime)")
            }
        }

        task.notificationScheduled = true
    }

    /// Cancel a scheduled reminder for a task
    func cancelReminder(for task: LookAheadTask) {
        let identifier = notificationIdentifier(for: task)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        task.notificationScheduled = false
        print("🗑️ Cancelled reminder for: \(task.name)")
    }

    /// Reschedule reminder when task time changes
    func rescheduleReminder(for task: LookAheadTask) {
        cancelReminder(for: task)
        scheduleCallReminder(for: task)
    }

    /// Cancel all reminders for a schedule
    func cancelAllReminders(for schedule: LookAheadSchedule) {
        let identifiers = (schedule.tasks ?? []).map { notificationIdentifier(for: $0) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)

        for task in (schedule.tasks ?? []) {
            task.notificationScheduled = false
        }
        print("🗑️ Cancelled all reminders for schedule: \(schedule.name)")
    }

    /// Reschedule all reminders for a schedule (e.g., after cascading time updates)
    func rescheduleAllReminders(for schedule: LookAheadSchedule) {
        cancelAllReminders(for: schedule)

        for task in (schedule.tasks ?? []) where !task.assignedVendors.isEmpty && task.isActive {
            scheduleCallReminder(for: task)
        }
    }

    // MARK: - Pending Notifications

    /// Get count of pending notifications
    func getPendingNotificationCount() async -> Int {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return requests.filter { $0.identifier.hasPrefix("call-") }.count
    }

    /// List all pending call reminders
    func getPendingReminders() async -> [UNNotificationRequest] {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return requests.filter { $0.identifier.hasPrefix("call-") }
    }

    // MARK: - Helpers

    private func notificationIdentifier(for task: LookAheadTask) -> String {
        "call-\(task.id.uuidString)"
    }

    // MARK: - Notification Categories

    /// Register notification categories for actions (call now, snooze, etc.)
    func registerNotificationCategories() {
        let callAction = UNNotificationAction(
            identifier: "CALL_NOW",
            title: "Call Now",
            options: [.foreground]
        )

        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE_15",
            title: "Snooze 15 min",
            options: []
        )

        let dismissAction = UNNotificationAction(
            identifier: "DISMISS",
            title: "Dismiss",
            options: [.destructive]
        )

        let category = UNNotificationCategory(
            identifier: "CALL_REMINDER",
            actions: [callAction, snoozeAction, dismissAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}

// MARK: - Notification handling extension

extension CallReminderService {

    /// Handle notification action (to be called from app delegate / scene delegate)
    func handleNotificationAction(
        _ response: UNNotificationResponse,
        context: ModelContext
    ) {
        let userInfo = response.notification.request.content.userInfo

        guard let taskIDString = userInfo["taskID"] as? String,
              let taskID = UUID(uuidString: taskIDString) else {
            return
        }

        switch response.actionIdentifier {
        case "CALL_NOW":
            // Open phone app with vendor number
            if let phone = userInfo["vendorPhone"] as? String, !phone.isEmpty {
                let cleaned = phone.replacingOccurrences(of: " ", with: "")
                    .replacingOccurrences(of: "-", with: "")
                    .replacingOccurrences(of: "(", with: "")
                    .replacingOccurrences(of: ")", with: "")

                #if os(iOS)
                if let url = URL(string: "tel://\(cleaned)") {
                    UIApplication.shared.open(url)
                }
                #elseif os(macOS)
                if let url = URL(string: "tel://\(cleaned)") {
                    NSWorkspace.shared.open(url)
                }
                #endif
            }

        case "SNOOZE_15":
            // Reschedule for 15 minutes from now
            let descriptor = FetchDescriptor<LookAheadTask>(
                predicate: #Predicate { $0.id == taskID }
            )
            if let tasks = try? context.fetch(descriptor), let task = tasks.first {
                task.callReminderMinutesBefore = max(0, task.callReminderMinutesBefore - 15)
                rescheduleReminder(for: task)
                try? context.save()
            }

        case "DISMISS", UNNotificationDefaultActionIdentifier:
            // Just dismiss, no action needed
            break

        default:
            break
        }
    }
}
