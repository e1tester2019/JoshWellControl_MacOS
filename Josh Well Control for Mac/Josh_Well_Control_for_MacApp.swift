//
//  Josh_Well_Control_for_MacApp.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-01.
//

import SwiftUI
import SwiftData

@main
struct Josh_Well_Control_for_MacApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
