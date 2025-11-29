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

    private let container = AppContainer.make(
        cloudKitContainerID: "iCloud.com.josh-sallows-wellcontrolapp"
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
