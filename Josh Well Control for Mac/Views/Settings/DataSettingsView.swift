//
//  DataSettingsView.swift
//  Josh Well Control for Mac
//
//  Cross-platform data management settings with iCloud sync controls.
//

import SwiftUI

struct DataSettingsView: View {
    @State private var showResetConfirmation = false
    @State private var resetComplete = false
    @State private var isResetting = false

    var body: some View {
        Form {
            // Status section
            Section {
                if AppContainer.isRunningInMemory {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 4) {
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
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.icloud.fill")
                            .foregroundStyle(.green)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("iCloud Sync Active")
                                .font(.headline)
                            Text("Data is syncing with iCloud")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Sync Status")
            }

            // Force pull section
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Use this if your data seems out of sync or you want to pull the latest from iCloud. This will:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        bulletPoint("Delete local data cache")
                        bulletPoint("Remove sync metadata")
                        bulletPoint("Force a fresh pull from iCloud on restart")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if resetComplete {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Reset complete. Please restart the app.")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                        }
                        .padding(.top, 4)
                    }

                    Button {
                        showResetConfirmation = true
                    } label: {
                        HStack {
                            if isResetting {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise.icloud")
                            }
                            Text("Force Pull from iCloud...")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(isResetting || resetComplete)
                    .padding(.top, 4)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Force Sync")
            } footer: {
                Text("Make sure you have a good internet connection before restarting the app.")
            }

            // Destructive reset section
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("If you're experiencing persistent issues, you can reset all local data. This is the same as Force Pull but useful if the sync itself is failing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button(role: .destructive) {
                        showResetConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Reset Local Data...")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isResetting || resetComplete)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Troubleshooting")
            }

            // Info section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    InfoRow(icon: "icloud", title: "iCloud Backup", detail: "Your data is automatically backed up to iCloud")
                    InfoRow(icon: "arrow.triangle.2.circlepath", title: "Sync", detail: "Changes sync across all your devices")
                    InfoRow(icon: "internaldrive", title: "Offline Access", detail: "Data is cached locally for offline use")
                }
            } header: {
                Text("About Data Storage")
            }
        }
        #if os(iOS)
        .navigationTitle("Data & Sync")
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("Reset Local Data?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset & Restart", role: .destructive) {
                performReset()
            }
        } message: {
            Text("This will delete the local data cache. Your data will resync from iCloud when you restart the app.\n\nMake sure you have a good internet connection before restarting.")
        }
    }

    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
            Text(text)
        }
    }

    private func performReset() {
        isResetting = true

        // Small delay for UI feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            AppContainer.resetLocalStore()
            isResetting = false
            resetComplete = true
        }
    }
}

// MARK: - Info Row

private struct InfoRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack {
        DataSettingsView()
    }
}
