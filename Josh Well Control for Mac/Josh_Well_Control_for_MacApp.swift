//
//  Josh_Well_Control_for_MacApp.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-01.
//

// Josh_Well_Control_for_MacApp.swift
import SwiftUI
import SwiftData

#if os(macOS)
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
#endif

@main
struct Josh_Well_Control_for_MacApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    private let container = AppContainer.make(
        cloudKitContainerID: "iCloud.com.josh-sallows-wellcontrolapp"
    )

    var body: some Scene {
        WindowGroup {
            PlatformAdaptiveContentView()
        }
        .modelContainer(container)
    }
}
