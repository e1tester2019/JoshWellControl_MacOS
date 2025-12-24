//
//  AppContainer.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-29.
//

import Foundation
import SwiftData

enum AppContainer {
    // Increment this when schema changes require a local store wipe
    // v2: Changed [Date] and [String] arrays to JSON-encoded Data for CloudKit compatibility
    // v3: Added TripSimulation and TripSimulationStep models
    // v4: Added TripTrack and TripTrackStep models for process-based trip tracking
    // v5: Added Look Ahead Scheduler models (JobCode, Vendor, CallLogEntry, LookAheadTask, LookAheadSchedule)
    // v6: Added TripRecord and TripRecordStep for field data vs simulation comparison
    private static let schemaVersion = 6
    private static let schemaVersionKey = "AppContainerSchemaVersion"

    private static func shouldWipeForSchemaMigration() -> Bool {
        let currentVersion = UserDefaults.standard.integer(forKey: schemaVersionKey)
        if currentVersion < schemaVersion {
            UserDefaults.standard.set(schemaVersion, forKey: schemaVersionKey)
            print("🔄 Schema version changed from \(currentVersion) to \(schemaVersion) - will wipe local store")
            return true
        }
        return false
    }

    static func make(cloudKitContainerID: String? = nil) -> ModelContainer {
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
            MPDSheet.self,
            MPDReading.self,
            // Look Ahead Scheduler
            JobCode.self,
            Vendor.self,
            CallLogEntry.self,
            TaskVendorAssignment.self,
            LookAheadTask.self,
            LookAheadSchedule.self
        ]
        let fullSchema = Schema(models)

        // Run one-time schema diagnosis on DEBUG to find bad types quickly.
        // Skip when CloudKit is enabled to avoid interference with mirroring delegate.
        #if DEBUG
        if cloudKitContainerID == nil || cloudKitContainerID?.isEmpty == true {
            diagnoseSchema(models: models)
        }
        #endif

        func buildDiskContainer(schema: Schema, wipe: Bool) throws -> ModelContainer {
            if wipe {
                let fm = FileManager.default
                let base = try fm.url(for: .applicationSupportDirectory,
                                      in: .userDomainMask,
                                      appropriateFor: nil,
                                      create: true)
                // SwiftData store can be file or directory depending on OS/version.
                let file = base.appendingPathComponent("default.store", isDirectory: false)
                let dir  = base.appendingPathComponent("default.store", isDirectory: true)
                try? fm.removeItem(at: file)
                try? fm.removeItem(at: dir)
            }
            let cfg = ModelConfiguration(schema: schema)
            return try ModelContainer(for: schema, configurations: [cfg])
        }

        // Check if we need to wipe local store due to schema migration
        let needsSchemaMigration = shouldWipeForSchemaMigration()
        if needsSchemaMigration {
            // Wipe local store files before creating CloudKit container
            let fm = FileManager.default
            if let base = try? fm.url(for: .applicationSupportDirectory,
                                      in: .userDomainMask,
                                      appropriateFor: nil,
                                      create: false) {
                let file = base.appendingPathComponent("default.store", isDirectory: false)
                let dir = base.appendingPathComponent("default.store", isDirectory: true)
                try? fm.removeItem(at: file)
                try? fm.removeItem(at: dir)
                // Also remove CloudKit metadata to force full resync
                let ckMeta = base.appendingPathComponent("default.store-ck", isDirectory: true)
                try? fm.removeItem(at: ckMeta)
                print("🗑️ Wiped local store for schema migration")
            }
        }

        // 1) CloudKit (only if a non-empty ID is provided)
        if let id = cloudKitContainerID, !id.isEmpty {
            do {
                let ck = ModelConfiguration(schema: fullSchema, cloudKitDatabase: .private(id))
                let container = try ModelContainer(for: fullSchema, configurations: [ck])
                print("✅ Using CloudKit container:", id)

                // Debug: Log CementJob count on launch
                Task { @MainActor in
                    let ctx = container.mainContext
                    let cementJobCount = (try? ctx.fetchCount(FetchDescriptor<CementJob>())) ?? -1
                    let projectCount = (try? ctx.fetchCount(FetchDescriptor<ProjectState>())) ?? -1
                    print("📊 [Sync Debug] Launch state: \(projectCount) projects, \(cementJobCount) cement jobs")

                    // One-time migration: update hasReceiptAttached flag for existing expenses
                    migrateExpenseReceiptFlags(context: ctx)
                }

                return container
            } catch {
                print("⚠️ CloudKit container failed:", error)
            }
        } else {
            print("ℹ️ CloudKit disabled for this run.")
        }

        // 2) Local disk store
        do {
            let container = try buildDiskContainer(schema: fullSchema, wipe: false)
            print("✅ Using local on-disk store")
            return container
        } catch {
            print("⚠️ Local on-disk store failed:", error)
            print("🔁 Wiping on-disk store and retrying once…")
            do {
                let container = try buildDiskContainer(schema: fullSchema, wipe: true)
                print("✅ Recovered after wiping on-disk store")
                return container
            } catch {
                print("⛔️ Disk store still failed after wipe:", error)
            }
        }

        // 3) In-memory with full schema
        do {
            let mem = ModelConfiguration(schema: fullSchema, isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: fullSchema, configurations: [mem])
            print("🧪 Using in-memory store (full schema). Data won't persist.")
            return container
        } catch {
            print("⛔️ In-memory store with full schema failed:", error)
            print("🚨 This almost always means a schema issue: duplicated @Model type,")
            print("   non-optional attribute without default, or relationship missing inverse.")
        }

        // 4) Last-ditch: EMPTY schema so the app never crashes
        do {
            let empty = Schema([])
            let mem = ModelConfiguration(schema: empty, isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: empty, configurations: [mem])
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
