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
    var body: some Scene {
        WindowGroup {
            #if os(macOS)
            // Use the original ContentView for macOS
            ContentView()
            #else
            // Use iPad-optimized ContentView for iOS/iPadOS
            ContentView_iPadOS()
            #endif
        }
        .modelContainer(for: [
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
        ])
    }
}
