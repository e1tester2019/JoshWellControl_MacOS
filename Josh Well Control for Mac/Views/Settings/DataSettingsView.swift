//
//  DataSettingsView.swift
//  Josh Well Control for Mac
//
//  Cross-platform data management settings with iCloud sync controls.
//

import SwiftUI
import SwiftData

struct DataSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showResetConfirmation = false
    @State private var resetComplete = false
    @State private var isResetting = false
    @State private var syncStalled = false

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

                if syncStalled {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.icloud.fill")
                            .foregroundStyle(.orange)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sync May Be Stalled")
                                .font(.headline)
                            Text("No data loaded after 30 seconds. Try Force Pull below.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
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

            // Data backup section
            DataBackupSection(modelContext: modelContext)

            // Orphan diagnostics section
            OrphanDiagnosticsSection(modelContext: modelContext)

            // Duplicate wells section
            DuplicateWellsSection(modelContext: modelContext)

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
        .onReceive(NotificationCenter.default.publisher(for: .syncHealthWarning)) { _ in
            syncStalled = true
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

            // Auto-exit after 2 seconds to ensure clean restart
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                #if os(macOS)
                NSApplication.shared.terminate(nil)
                #else
                exit(0)
                #endif
            }
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

// MARK: - Data Backup Section

struct DataBackupSection: View {
    let modelContext: ModelContext
    @State private var isExporting = false
    @State private var backupResult: DataBackupService.BackupResult?

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Export your financial data (work days, expenses, mileage logs) as CSV files with receipt images and GPS route data. Files can be opened in any spreadsheet app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    runExport()
                } label: {
                    HStack {
                        if isExporting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Text("Export Backup")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(isExporting)

                if let result = backupResult {
                    HStack(alignment: .top) {
                        Image(systemName: result.workDayCount + result.expenseCount + result.mileageLogCount > 0
                              ? "checkmark.circle.fill" : "info.circle.fill")
                            .foregroundStyle(result.workDayCount + result.expenseCount + result.mileageLogCount > 0 ? .green : .secondary)
                        Text(result.summary)
                            .font(.caption)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Data Backup")
        } footer: {
            Text("Exports: WorkDays.csv, Expenses.csv, MileageLogs.csv, RoutePoints.csv, receipt images, and map snapshots.")
        }
    }

    private func runExport() {
        isExporting = true
        backupResult = nil
        Task { @MainActor in
            backupResult = await DataBackupService.exportBackup(context: modelContext)
            isExporting = false
        }
    }
}

// MARK: - Orphan Diagnostics Section

struct OrphanDiagnosticsSection: View {
    let modelContext: ModelContext
    @State private var diagnosisResult: OrphanRepairService.DiagnosisResult?
    @State private var repairResult: OrphanRepairService.RepairResult?
    @State private var isScanning = false
    @State private var isRepairing = false

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("After an iCloud re-sync, some records may lose their parent relationship and become invisible. Use this tool to detect and repair orphaned data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Scan button
                Button {
                    runScan()
                } label: {
                    HStack {
                        if isScanning {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "magnifyingglass")
                        }
                        Text("Scan for Orphans")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isScanning || isRepairing)

                // Diagnosis results
                if let diagnosis = diagnosisResult {
                    if diagnosis.hasOrphans {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("Found \(diagnosis.totalOrphans) orphaned record(s)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }

                            ForEach(diagnosis.orphanCounts.filter { $0.count > 0 }, id: \.type) { entry in
                                HStack {
                                    Text(entry.type)
                                        .font(.caption)
                                    Spacer()
                                    Text("\(entry.count)")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                        .padding(10)
                        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

                        // Repair button
                        Button {
                            runRepair()
                        } label: {
                            HStack {
                                if isRepairing {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "wrench.and.screwdriver")
                                }
                                Text("Attempt Auto-Repair")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(isScanning || isRepairing)
                    } else {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("No orphaned records found")
                                .font(.subheadline)
                        }
                    }
                }

                // Repair results
                if let repair = repairResult {
                    VStack(alignment: .leading, spacing: 6) {
                        if repair.relinked > 0 {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Re-linked \(repair.relinked) record(s)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                        }

                        if repair.unresolvable > 0 {
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                                Text("\(repair.unresolvable) record(s) need manual resolution")
                                    .font(.subheadline)
                            }
                        }

                        ForEach(Array(repair.actions.enumerated()), id: \.offset) { _, action in
                            Text(action)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if !repair.saveSucceeded, let error = repair.saveError {
                            Text("Save error: \(error)")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(10)
                    .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Orphan Diagnostics")
        } footer: {
            Text("Orphans are records that lost their parent link during iCloud sync. Auto-repair works best with a single well.")
        }
    }

    private func runScan() {
        isScanning = true
        repairResult = nil
        Task { @MainActor in
            diagnosisResult = OrphanRepairService.quickDiagnose(context: modelContext)
            isScanning = false
        }
    }

    private func runRepair() {
        isRepairing = true
        Task { @MainActor in
            var combined = OrphanRepairService.RepairResult()

            let projectResult = OrphanRepairService.repairOrphanedProjects(context: modelContext)
            combined.merge(projectResult)

            let wellChildResult = OrphanRepairService.repairOrphanedWellChildren(context: modelContext)
            combined.merge(wellChildResult)

            let projectChildResult = OrphanRepairService.repairOrphanedProjectChildren(context: modelContext)
            combined.merge(projectChildResult)

            combined.saveSucceeded = projectResult.saveSucceeded && wellChildResult.saveSucceeded && projectChildResult.saveSucceeded

            repairResult = combined
            isRepairing = false

            // Re-scan to update counts
            diagnosisResult = OrphanRepairService.quickDiagnose(context: modelContext)
        }
    }
}

// MARK: - Duplicate Wells Section

/// Wraps a Well with a stable identity based on SwiftData's PersistentIdentifier,
/// since duplicate wells share the same UUID (which breaks ForEach).
private struct IdentifiedWell: Identifiable {
    let well: Well
    var id: PersistentIdentifier { well.persistentModelID }
}

/// Groups duplicate wells under a stable ID for ForEach.
private struct DuplicateGroup: Identifiable {
    let id: UUID  // the shared Well.id
    let name: String
    let uwi: String?
    let wells: [IdentifiedWell]
}

struct DuplicateWellsSection: View {
    let modelContext: ModelContext
    @State private var duplicateGroups: [DuplicateGroup] = []
    @State private var hasScanned = false
    @State private var wellToDelete: IdentifiedWell?
    @State private var showDeleteConfirmation = false

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Detect duplicate wells created by iCloud sync issues (same UUID appearing multiple times). Review which copy has data before removing the empty one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    scanForDuplicates()
                } label: {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text("Scan for Duplicates")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                if hasScanned {
                    duplicateResultsView
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Duplicate Wells")
        }
        .alert("Delete Duplicate Well?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { wellToDelete = nil }
            Button("Delete", role: .destructive) {
                if let item = wellToDelete {
                    modelContext.delete(item.well)
                    try? modelContext.save()
                    scanForDuplicates()
                }
                wellToDelete = nil
            }
        } message: {
            Text("This will permanently delete one copy of this well which has 0 child records. This cannot be undone.")
        }
    }

    @ViewBuilder
    private var duplicateResultsView: some View {
        if duplicateGroups.isEmpty {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("No duplicate wells found")
                    .font(.subheadline)
            }
        } else {
            ForEach(duplicateGroups) { group in
                duplicateGroupView(group)
            }
        }
    }

    private func duplicateGroupView(_ group: DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.name)
                .font(.subheadline)
                .fontWeight(.semibold)
            if let uwi = group.uwi, !uwi.isEmpty {
                Text(uwi)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("UUID: \(group.id.uuidString)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            ForEach(group.wells) { item in
                wellRowView(item)
            }
        }
        .padding(10)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func wellRowView(_ item: IdentifiedWell) -> some View {
        let childCount = wellChildCount(item.well)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Store ID: \(String(describing: item.id).prefix(20))...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(wellDataSummary(item.well))
                    .font(.caption)
            }
            Spacer()
            if childCount == 0 {
                Button("Remove", role: .destructive) {
                    wellToDelete = item
                    showDeleteConfirmation = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Text("Has data")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    private func scanForDuplicates() {
        let descriptor = FetchDescriptor<Well>(sortBy: [SortDescriptor(\Well.name)])
        guard let allWells = try? modelContext.fetch(descriptor) else {
            hasScanned = true
            return
        }

        // Group by Well.id (UUID) — duplicates share the same UUID
        var grouped: [UUID: [Well]] = [:]
        for well in allWells {
            grouped[well.id, default: []].append(well)
        }

        duplicateGroups = grouped
            .filter { $0.value.count > 1 }
            .map { (uuid, wells) in
                DuplicateGroup(
                    id: uuid,
                    name: wells.first?.name ?? "Unknown",
                    uwi: wells.first?.uwi,
                    wells: wells.map { IdentifiedWell(well: $0) }
                )
            }
            .sorted { $0.name < $1.name }

        hasScanned = true
    }

    private func wellChildCount(_ well: Well) -> Int {
        var count = 0
        count += well.projects?.count ?? 0
        count += well.transfers?.count ?? 0
        count += well.rentals?.count ?? 0
        count += well.workDays?.count ?? 0
        count += well.notes?.count ?? 0
        count += well.tasks?.count ?? 0
        count += well.directionalPlans?.count ?? 0
        count += well.tripSimulations?.count ?? 0
        count += well.tripInSimulations?.count ?? 0
        count += well.lookAheadTasks?.count ?? 0
        count += well.shiftEntries?.count ?? 0
        return count
    }

    private func wellDataSummary(_ well: Well) -> String {
        let count = wellChildCount(well)
        if count == 0 { return "No child records (safe to remove)" }
        var parts: [String] = []
        if let p = well.projects, !p.isEmpty { parts.append("\(p.count) projects") }
        if let w = well.workDays, !w.isEmpty { parts.append("\(w.count) work days") }
        if let r = well.rentals, !r.isEmpty { parts.append("\(r.count) rentals") }
        if let t = well.transfers, !t.isEmpty { parts.append("\(t.count) transfers") }
        if let n = well.notes, !n.isEmpty { parts.append("\(n.count) notes") }
        if let t = well.tasks, !t.isEmpty { parts.append("\(t.count) tasks") }
        if let d = well.directionalPlans, !d.isEmpty { parts.append("\(d.count) dir. plans") }
        if let s = well.shiftEntries, !s.isEmpty { parts.append("\(s.count) shifts") }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    NavigationStack {
        DataSettingsView()
    }
}
