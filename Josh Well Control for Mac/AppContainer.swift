//
//  AppContainer.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-29.
//

import Foundation
import SwiftData

enum AppContainer {
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
            MudStep.self,
            FinalFluidLayer.self,
            MudProperties.self,
            MaterialTransfer.self,
            MaterialTransferItem.self,
            RentalItem.self,
            RentalAdditionalCost.self,
            PumpProgramStage.self
        ]
        let fullSchema = Schema(models)

        // Run one-time schema diagnosis on DEBUG to find bad types quickly.
        #if DEBUG
        diagnoseSchema(models: models)
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

        // 1) CloudKit (only if a non-empty ID is provided)
        if let id = cloudKitContainerID, !id.isEmpty {
            do {
                let ck = ModelConfiguration(schema: fullSchema, cloudKitDatabase: .private(id))
                let container = try ModelContainer(for: fullSchema, configurations: [ck])
                print("✅ Using CloudKit container:", id)
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
