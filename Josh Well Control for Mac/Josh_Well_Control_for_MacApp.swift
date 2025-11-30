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
            // Platform-specific ContentView selected via EXCLUDED_SOURCE_FILE_NAMES
            // macOS uses ContentView.swift (excludes Views/iPadOS/*)
            // iOS/iPadOS uses ContentView_iPadOS.swift (excludes Views/ContentView.swift and Views/macOS/*)
            #if os(macOS)
            ContentView()
            #else
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
