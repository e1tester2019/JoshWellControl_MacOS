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
        #if os(macOS)
        .commands {
            CommandGroup(replacing: .help) {
                OpenDocumentationButton()
            }
        }
        #endif

        #if os(macOS)
        Settings {
            AppSettingsView()
        }
        .modelContainer(container)

        Window("Documentation", id: "documentation") {
            DocumentationView()
        }
        .defaultSize(width: 900, height: 650)
        #endif
    }
}

#if os(macOS)
/// Button that opens the documentation window using environment
struct OpenDocumentationButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Documentation") {
            openWindow(id: "documentation")
        }
        .keyboardShortcut("?", modifiers: [.command])
    }
}
#endif

// MARK: - App Settings View

#if os(macOS)
struct AppSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showResetConfirmation = false
    @State private var resetComplete = false

    var body: some View {
        TabView {
            dataSettingsTab
                .tabItem {
                    Label("Data", systemImage: "cylinder.split.1x2")
                }

            diagnosticsTab
                .tabItem {
                    Label("Diagnostics", systemImage: "stethoscope")
                }
        }
        .frame(width: 450, height: 500)
    }

    private var dataSettingsTab: some View {
        Form {
            Section {
                // Status indicator
                if AppContainer.isRunningInMemory {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading) {
                            Text("Running in Memory Mode")
                                .font(.headline)
                            Text("Data will not persist. Try resetting local data below.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    if let error = AppContainer.lastContainerError {
                        Text("Error: \(error)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Data store is working normally")
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reset Local Data")
                        .font(.headline)

                    Text("If you're experiencing sync issues or data corruption, you can reset the local data store. Your data will resync from iCloud after restarting the app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("Reset Local Data...") {
                            showResetConfirmation = true
                        }
                        .foregroundStyle(.red)

                        if resetComplete {
                            Text("Reset complete. Please restart the app.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("About Data Storage")
                        .font(.headline)
                    Text("Your data is stored locally and synced to iCloud. The local store allows offline access, while iCloud keeps everything backed up and synced across devices.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("Reset Local Data?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset & Restart", role: .destructive) {
                AppContainer.resetLocalStore()
                resetComplete = true
                // Auto-exit after 2 seconds to ensure clean restart
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    NSApplication.shared.terminate(nil)
                }
            }
        } message: {
            Text("This will delete the local data store and restart the app. Your data will resync from iCloud.\n\nMake sure you have a good internet connection.")
        }
    }

    private var diagnosticsTab: some View {
        Form {
            DuplicateWellsSection(modelContext: modelContext)
            DataBackupSection(modelContext: modelContext)
            OrphanDiagnosticsSection(modelContext: modelContext)
        }
        .formStyle(.grouped)
        .padding()
    }
}
#endif
