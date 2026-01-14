//
//  ShiftNotificationService.swift
//  Josh Well Control for Mac
//
//  Service for scheduling end-of-shift reminder notifications.
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
final class ShiftNotificationService {
    static let shared = ShiftNotificationService()

    private(set) var isAuthorized = false
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var nextScheduledReminder: Date?

    private let notificationIdentifier = "shift-end-reminder"

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
            print("Notification authorization failed: \(error)")
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

    // MARK: - Schedule End-of-Shift Reminder

    /// Schedule or update the next end-of-shift reminder based on current shift
    func scheduleNextReminder(context: ModelContext) async {
        guard isAuthorized else {
            print("Notifications not authorized, skipping shift reminder")
            return
        }

        let settings = ShiftRotationSettings.shared
        guard settings.endOfShiftReminderEnabled else {
            await cancelReminder()
            return
        }

        // Find the next shift end time
        guard let (nextEndTime, shiftType, shiftEntry) = await findNextShiftEnd(context: context) else {
            print("No upcoming shift found")
            await cancelReminder()
            return
        }

        // Calculate reminder time (with optional minutes before)
        let reminderTime = Calendar.current.date(
            byAdding: .minute,
            value: -settings.reminderMinutesBefore,
            to: nextEndTime
        ) ?? nextEndTime

        guard reminderTime > Date.now else {
            print("Reminder time has passed")
            return
        }

        // Cancel existing reminder first
        await cancelReminder()

        // Build notification content
        let content = UNMutableNotificationContent()
        content.title = "End of \(shiftType.displayName) Shift"

        var bodyParts: [String] = ["Time to complete your handover notes"]
        if let well = shiftEntry?.well {
            bodyParts.append("Well: \(well.name)")
        }
        content.body = bodyParts.joined(separator: "\n")

        content.sound = .default
        content.categoryIdentifier = "SHIFT_END_REMINDER"
        content.userInfo = [
            "shiftType": shiftType.rawValue,
            "shiftEntryID": shiftEntry?.id.uuidString ?? ""
        ]

        // Create date-based trigger
        let triggerDate = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminderTime
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)

        let request = UNNotificationRequest(
            identifier: notificationIdentifier,
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            nextScheduledReminder = reminderTime
            print("Scheduled shift end reminder for \(reminderTime)")
        } catch {
            print("Failed to schedule shift notification: \(error)")
        }
    }

    /// Cancel any scheduled end-of-shift reminder
    func cancelReminder() async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [notificationIdentifier]
        )
        nextScheduledReminder = nil
        print("Cancelled shift end reminder")
    }

    // MARK: - Find Next Shift End

    /// Find the next shift end time from ShiftEntry records or rotation settings
    private func findNextShiftEnd(context: ModelContext) async -> (Date, ShiftType, ShiftEntry?)? {
        let settings = ShiftRotationSettings.shared
        let calendar = Calendar.current
        let now = Date.now
        let today = calendar.startOfDay(for: now)

        // Look at today and next 30 days
        for dayOffset in 0..<30 {
            guard let checkDate = calendar.date(byAdding: .day, value: dayOffset, to: today) else {
                continue
            }

            // Try to find an existing ShiftEntry for this date
            let descriptor = FetchDescriptor<ShiftEntry>(
                predicate: #Predicate<ShiftEntry> { entry in
                    entry.date >= checkDate
                },
                sortBy: [SortDescriptor(\.date)]
            )

            if let entries = try? context.fetch(descriptor),
               let entry = entries.first(where: { calendar.isDate($0.date, inSameDayAs: checkDate) }) {
                // Use the stored shift entry
                if entry.isWorkingShift {
                    if let endTime = settings.shiftEndTime(for: entry.shiftType, on: entry.date),
                       endTime > now {
                        return (endTime, entry.shiftType, entry)
                    }
                }
            } else {
                // Fall back to rotation calculation
                let expectedType = settings.expectedShiftType(for: checkDate)
                if expectedType != .off {
                    if let endTime = settings.shiftEndTime(for: expectedType, on: checkDate),
                       endTime > now {
                        return (endTime, expectedType, nil)
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Notification Categories

    /// Register notification categories for shift end actions
    func registerNotificationCategories() {
        let openNotesAction = UNNotificationAction(
            identifier: "OPEN_HANDOVER",
            title: "Open Handover Notes",
            options: [.foreground]
        )

        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE_30",
            title: "Snooze 30 min",
            options: []
        )

        let dismissAction = UNNotificationAction(
            identifier: "DISMISS",
            title: "Dismiss",
            options: [.destructive]
        )

        let category = UNNotificationCategory(
            identifier: "SHIFT_END_REMINDER",
            actions: [openNotesAction, snoozeAction, dismissAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // Get existing categories and add this one
        UNUserNotificationCenter.current().getNotificationCategories { existingCategories in
            var categories = existingCategories
            categories.insert(category)
            UNUserNotificationCenter.current().setNotificationCategories(categories)
        }
    }

    // MARK: - Notification Handling

    /// Handle notification action response
    func handleNotificationAction(
        _ response: UNNotificationResponse,
        context: ModelContext
    ) async {
        let userInfo = response.notification.request.content.userInfo

        switch response.actionIdentifier {
        case "OPEN_HANDOVER":
            // The app will open; navigation to handover notes handled by view
            break

        case "SNOOZE_30":
            // Reschedule for 30 minutes from now
            let snoozeTime = Calendar.current.date(
                byAdding: .minute,
                value: 30,
                to: Date.now
            ) ?? Date.now

            let shiftTypeRaw = userInfo["shiftType"] as? String ?? ""
            let shiftType = ShiftType(rawValue: shiftTypeRaw) ?? .day

            let content = UNMutableNotificationContent()
            content.title = "End of \(shiftType.displayName) Shift (Snoozed)"
            content.body = "Time to complete your handover notes"
            content.sound = .default
            content.categoryIdentifier = "SHIFT_END_REMINDER"
            content.userInfo = userInfo

            let triggerDate = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: snoozeTime
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)

            let request = UNNotificationRequest(
                identifier: "\(notificationIdentifier)-snoozed",
                content: content,
                trigger: trigger
            )

            do {
                try await UNUserNotificationCenter.current().add(request)
                print("Snoozed shift reminder to \(snoozeTime)")
            } catch {
                print("Failed to snooze notification: \(error)")
            }

        case "DISMISS", UNNotificationDefaultActionIdentifier:
            // Schedule next shift's reminder
            await scheduleNextReminder(context: context)

        default:
            break
        }
    }
}
