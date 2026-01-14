//
//  AppContainer.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-29.
//

import Foundation
import SwiftData

enum AppContainer {
    // Schema version history (for reference only - SwiftData handles migrations automatically)
    // v2: Changed [Date] and [String] arrays to JSON-encoded Data for CloudKit compatibility
    // v3: Added TripSimulation and TripSimulationStep models
    // v4: Added TripTrack and TripTrackStep models for process-based trip tracking
    // v5: Added Look Ahead Scheduler models (JobCode, Vendor, CallLogEntry, LookAheadTask, LookAheadSchedule)
    // v6: Added TripRecord and TripRecordStep for field data vs simulation comparison
    // v7: Added TripInSimulation and TripInSimulationStep for running pipe into well
    // v8: Fixed TripInSimulation model (removed activeMud relationship)
    // v9: Added HP pressure fields to TripInSimulationStep
    // v10: Added fillMudID to TripInSimulation for mud color persistence
    // v11: Added DirectionalPlan, DirectionalPlanStation, DirectionalLimits for directional drilling features
    // v12: Added equipment registry and enhanced rentals (RentalCategory, RentalEquipment, RentalEquipmentIssue, VendorContact, VendorAddress)
    // v13: Added ShiftEntry for shift calendar feature
    private static let schemaVersion = 13
    private static let schemaVersionKey = "AppContainerSchemaVersion"

    /// Tracks whether the app is running in a degraded state (in-memory only)
    static var isRunningInMemory: Bool = false

    /// Tracks the last container creation error for diagnostics
    static var lastContainerError: String?

    /// Log schema version for debugging (no longer triggers auto-wipe)
    private static func logSchemaVersion() {
        let previousVersion = UserDefaults.standard.integer(forKey: schemaVersionKey)
        if previousVersion != schemaVersion {
            print("📋 Schema version: \(previousVersion) → \(schemaVersion) (SwiftData will handle migration)")
            UserDefaults.standard.set(schemaVersion, forKey: schemaVersionKey)
        } else {
            print("📋 Schema version: \(schemaVersion)")
        }
    }

    /// Manually reset local data store. Call this from settings if user chooses to reset.
    /// Data will resync from CloudKit after reset.
    static func resetLocalStore() {
        let fm = FileManager.default
        guard let base = try? fm.url(for: .applicationSupportDirectory,
                                     in: .userDomainMask,
                                     appropriateFor: nil,
                                     create: false) else {
            print("⚠️ Could not find Application Support directory")
            return
        }

        // Remove SwiftData store files
        let file = base.appendingPathComponent("default.store", isDirectory: false)
        let dir = base.appendingPathComponent("default.store", isDirectory: true)
        try? fm.removeItem(at: file)
        try? fm.removeItem(at: dir)

        // Remove CloudKit metadata to force full resync
        let ckMeta = base.appendingPathComponent("default.store-ck", isDirectory: true)
        try? fm.removeItem(at: ckMeta)

        // Reset schema version so it logs on next launch
        UserDefaults.standard.removeObject(forKey: schemaVersionKey)

        print("🗑️ Local store reset complete. Restart the app to resync from CloudKit.")
    }

    static func make(cloudKitContainerID: String? = nil) -> ModelContainer {
        // Reset state
        isRunningInMemory = false
        lastContainerError = nil

        // Log schema version (informational only)
        logSchemaVersion()

        let models: [any PersistentModel.Type] = [
            Well.self,
            ProjectState.self,
            SurveyStation.self,
            DrillStringSection.self,
            AnnulusSection.self,
            PressureWindow.self,
            PressureWindowPoint.self,
            SlugPlan.self,
            SlugStep.self,
            BackfillPlan.self,
            BackfillRule.self,
            TripSettings.self,
            SwabInput.self,
            SwabRun.self,
            SwabSample.self,
            TripRun.self,
            TripSample.self,
            MudStep.self,
            FinalFluidLayer.self,
            MudProperties.self,
            MaterialTransfer.self,
            MaterialTransferItem.self,
            RentalItem.self,
            RentalAdditionalCost.self,
            PumpProgramStage.self,
            CementJob.self,
            CementJobStage.self,
            Client.self,
            WorkDay.self,
            Invoice.self,
            InvoiceLineItem.self,
            Expense.self,
            MileageLog.self,
            TripRoutePoint.self,
            Employee.self,
            PayRun.self,
            PayStub.self,
            Shareholder.self,
            Dividend.self,
            WellTask.self,
            HandoverNote.self,
            Pad.self,
            HandoverReportArchive.self,
            TripSimulation.self,
            TripSimulationStep.self,
            TripTrack.self,
            TripTrackStep.self,
            TripRecord.self,
            TripRecordStep.self,
            TripInSimulation.self,
            TripInSimulationStep.self,
            MPDSheet.self,
            MPDReading.self,
            // Look Ahead Scheduler
            JobCode.self,
            Vendor.self,
            CallLogEntry.self,
            TaskVendorAssignment.self,
            LookAheadTask.self,
            LookAheadSchedule.self,
            // Directional Drilling
            DirectionalPlan.self,
            DirectionalPlanStation.self,
            DirectionalLimits.self,
            // Equipment Registry & Enhanced Rentals
            RentalCategory.self,
            RentalEquipment.self,
            RentalEquipmentIssue.self,
            VendorContact.self,
            VendorAddress.self,
            // Shift Calendar
            ShiftEntry.self
        ]
        let fullSchema = Schema(models)

        // Run one-time schema diagnosis on DEBUG to find bad types quickly.
        // Skip when CloudKit is enabled to avoid interference with mirroring delegate.
        #if DEBUG
        if cloudKitContainerID == nil || cloudKitContainerID?.isEmpty == true {
            diagnoseSchema(models: models)
        }
        #endif

        // 1) CloudKit (only if a non-empty ID is provided)
        // SwiftData handles lightweight migrations automatically
        if let id = cloudKitContainerID, !id.isEmpty {
            do {
                let ck = ModelConfiguration(schema: fullSchema, cloudKitDatabase: .private(id))
                let container = try ModelContainer(for: fullSchema, configurations: [ck])
                print("✅ Using CloudKit container:", id)

                // Debug: Log counts on launch
                Task { @MainActor in
                    let ctx = container.mainContext
                    let cementJobCount = (try? ctx.fetchCount(FetchDescriptor<CementJob>())) ?? -1
                    let projectCount = (try? ctx.fetchCount(FetchDescriptor<ProjectState>())) ?? -1
                    print("📊 [Sync Debug] Launch state: \(projectCount) projects, \(cementJobCount) cement jobs")

                    // One-time migrations
                    migrateExpenseReceiptFlags(context: ctx)
                    migrateRentalsToEquipmentRegistry(context: ctx)
                }

                return container
            } catch {
                let errorMsg = "CloudKit container failed: \(error.localizedDescription)"
                print("⚠️ \(errorMsg)")
                lastContainerError = errorMsg
                // Don't wipe - fall through to try local disk
            }
        } else {
            print("ℹ️ CloudKit disabled for this run.")
        }

        // 2) Local disk store - SwiftData handles migrations automatically
        do {
            let cfg = ModelConfiguration(schema: fullSchema)
            let container = try ModelContainer(for: fullSchema, configurations: [cfg])
            print("✅ Using local on-disk store")
            return container
        } catch {
            let errorMsg = "Local disk store failed: \(error.localizedDescription)"
            print("⚠️ \(errorMsg)")
            lastContainerError = errorMsg
            // Don't auto-wipe - fall through to in-memory as safe fallback
        }

        // 3) In-memory with full schema - app works but data won't persist
        // This is a SAFE FALLBACK - no data is lost, user can try resetting manually
        do {
            let mem = ModelConfiguration(schema: fullSchema, isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: fullSchema, configurations: [mem])
            isRunningInMemory = true
            print("🧪 Using in-memory store (full schema). Data won't persist!")
            print("⚠️ App is in degraded mode. User should check Settings → Reset Local Data")
            return container
        } catch {
            print("⛔️ In-memory store with full schema failed:", error)
            print("🚨 This almost always means a schema issue: duplicated @Model type,")
            print("   non-optional attribute without default, or relationship missing inverse.")
            lastContainerError = "In-memory store failed: \(error.localizedDescription)"
        }

        // 4) Last-ditch: EMPTY schema so the app never crashes
        do {
            let empty = Schema([])
            let mem = ModelConfiguration(schema: empty, isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: empty, configurations: [mem])
            isRunningInMemory = true
            print("🆘 Falling back to EMPTY in-memory schema so the app can launch.")
            return container
        } catch {
            // Truly unrecoverable (should never happen)
            fatalError("💥 All containers failed even with empty schema: \(error)")
        }
    }
}

// MARK: - DEBUG schema diagnosis

#if DEBUG
private func diagnoseSchema(models: [any PersistentModel.Type]) {
    // Try each model by itself to see which one crashes SwiftData.
    for m in models {
        do {
            let s = Schema([m])
            let cfg = ModelConfiguration(schema: s, isStoredInMemoryOnly: true)
            _ = try ModelContainer(for: s, configurations: [cfg])
            print("✅ Model OK:", String(describing: m))
        } catch {
            print("❌ Model FAILED:", String(describing: m), "→", error)
        }
    }
}
#endif

// MARK: - Migrations

private let expenseReceiptMigrationKey = "hasRunExpenseReceiptMigration_v1"
private let rentalEquipmentMigrationKey = "hasRunRentalEquipmentMigration_v1"

@MainActor
private func migrateExpenseReceiptFlags(context: ModelContext) {
    // Only run this migration once
    guard !UserDefaults.standard.bool(forKey: expenseReceiptMigrationKey) else {
        return
    }

    do {
        let descriptor = FetchDescriptor<Expense>()
        let expenses = try context.fetch(descriptor)

        var updatedCount = 0
        for expense in expenses {
            // Check if receipt data exists and flag isn't set correctly
            let hasData = expense.receiptImageData != nil
            if expense.hasReceiptAttached != hasData {
                expense.hasReceiptAttached = hasData
                updatedCount += 1
            }
        }

        if updatedCount > 0 {
            try context.save()
            print("📝 Migrated \(updatedCount) expenses with receipt flags")
        }

        UserDefaults.standard.set(true, forKey: expenseReceiptMigrationKey)
    } catch {
        print("⚠️ Failed to migrate expense receipt flags: \(error)")
    }
}

/// Migration: Convert existing RentalItems to RentalEquipment registry entries.
/// Groups rentals by name + serial number and creates equipment records, then links them.
@MainActor
private func migrateRentalsToEquipmentRegistry(context: ModelContext) {
    // Only run this migration once
    guard !UserDefaults.standard.bool(forKey: rentalEquipmentMigrationKey) else {
        return
    }

    do {
        // Fetch all RentalItems that don't have equipment links
        let descriptor = FetchDescriptor<RentalItem>(
            predicate: #Predicate { $0.equipment == nil }
        )
        let rentals = try context.fetch(descriptor)

        if rentals.isEmpty {
            UserDefaults.standard.set(true, forKey: rentalEquipmentMigrationKey)
            print("📦 No unlinked rentals to migrate to equipment registry")
            return
        }

        // Group by name + serial number to find unique equipment
        var equipmentGroups: [String: [RentalItem]] = [:]
        for rental in rentals {
            let serial = rental.serialNumber ?? ""
            let key = "\(rental.name)||||\(serial)"
            equipmentGroups[key, default: []].append(rental)
        }

        var createdCount = 0
        var linkedCount = 0

        for (_, groupRentals) in equipmentGroups {
            guard let firstRental = groupRentals.first else { continue }

            // Create equipment record from the rental info
            let equipment = RentalEquipment(
                serialNumber: firstRental.serialNumber ?? "",
                name: firstRental.name,
                description: firstRental.detail ?? "",
                model: ""
            )
            equipment.isActive = true
            context.insert(equipment)
            createdCount += 1

            // Link all matching rentals to this equipment
            for rental in groupRentals {
                rental.equipment = equipment
                linkedCount += 1
            }
        }

        try context.save()
        UserDefaults.standard.set(true, forKey: rentalEquipmentMigrationKey)
        print("📦 Migrated rentals to equipment registry: \(createdCount) equipment created, \(linkedCount) rentals linked")
    } catch {
        print("⚠️ Failed to migrate rentals to equipment registry: \(error)")
    }
}
