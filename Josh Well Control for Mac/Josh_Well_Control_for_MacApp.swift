//
//  Josh_Well_Control_for_MacApp.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-01.
//

// Josh_Well_Control_for_MacApp.swift
import SwiftUI
import SwiftData

@main
struct Josh_Well_Control_for_MacApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema([
                Well.self,
                ProjectState.self,
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
            ])

            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitContainerIdentifier: "iCloud.com.josh-sallows-wellcontrolapp"
            )

            self.modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
