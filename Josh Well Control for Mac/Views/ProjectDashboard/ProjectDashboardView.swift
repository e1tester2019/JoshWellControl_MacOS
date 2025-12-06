//
//  ProjectDashboardView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-02.
//

// ProjectDashboardView.swift
import SwiftUI
import SwiftData
#if DEBUG
import CoreData
#endif
#if os(macOS)
import AppKit
#endif

struct ProjectDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectState
    @State private var viewmodel: ViewModel
    @State private var newTransferToEdit: MaterialTransfer?

    // DEBUG: basic "cloud sync" trigger + status
    @State private var showMudSyncAlert: Bool = false
    @State private var mudSyncStatusTitle: String = ""
    @State private var mudSyncStatusMessage: String = ""

#if DEBUG
    @State private var cloudEventLines: [String] = []
    @State private var cloudLastEventAt: Date? = nil
    @State private var cloudLastError: String? = nil
    @State private var cloudMonitorStarted: Bool = false
    @State private var cloudSyncBanner: String = "No CloudKit events observed yet"
#endif

    // Optional navigation controls for iOS
    var wells: [Well]?
    @Binding var selectedWell: Well?
    @Binding var selectedProject: ProjectState?
    var onNewWell: (() -> Void)?
    var onNewProject: (() -> Void)?
    var onRenameWell: ((Well) -> Void)?
    var onRenameProject: ((ProjectState) -> Void)?
    var onDuplicateWell: ((Well) -> Void)?
    var onDuplicateProject: ((ProjectState) -> Void)?
    var onDeleteWell: (() -> Void)?
    var onDeleteProject: (() -> Void)?

    init(
        project: ProjectState,
        wells: [Well]? = nil,
        selectedWell: Binding<Well?>? = nil,
        selectedProject: Binding<ProjectState?>? = nil,
        onNewWell: (() -> Void)? = nil,
        onNewProject: (() -> Void)? = nil,
        onRenameWell: ((Well) -> Void)? = nil,
        onRenameProject: ((ProjectState) -> Void)? = nil,
        onDuplicateWell: ((Well) -> Void)? = nil,
        onDuplicateProject: ((ProjectState) -> Void)? = nil,
        onDeleteWell: (() -> Void)? = nil,
        onDeleteProject: (() -> Void)? = nil
    ) {
        self._project = Bindable(wrappedValue: project)
        _viewmodel = State(initialValue: ViewModel(project: project))
        self.wells = wells
        self._selectedWell = selectedWell ?? .constant(nil)
        self._selectedProject = selectedProject ?? .constant(nil)
        self.onNewWell = onNewWell
        self.onNewProject = onNewProject
        self.onRenameWell = onRenameWell
        self.onRenameProject = onRenameProject
        self.onDuplicateWell = onDuplicateWell
        self.onDuplicateProject = onDuplicateProject
        self.onDeleteWell = onDeleteWell
        self.onDeleteProject = onDeleteProject
    }

    private var pageBackgroundColor: Color {
        #if os(macOS)
        Color(nsColor: .underPageBackgroundColor)
        #else
        Color(.systemGroupedBackground)
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Navigation controls (iOS only) - Fixed at top
            #if os(iOS)
            if let wells = wells {
                VStack(spacing: 12) {
                    // Well and Project pickers
                    HStack(spacing: 12) {
                        Menu {
                            ForEach(wells, id: \.id) { w in
                                Button {
                                    selectedWell = w
                                    selectedProject = (w.projects ?? []).first
                                } label: {
                                    if selectedWell?.id == w.id {
                                        Label(w.name, systemImage: "checkmark")
                                    } else {
                                        Text(w.name)
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "square.grid.2x2")
                                Text(selectedWell?.name ?? "Select Well")
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.accentColor.opacity(0.15))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.accentColor, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)

                        if let well = selectedWell {
                            let projects = well.projects ?? []
                            Menu {
                                ForEach(projects.sorted(by: { $0.createdAt < $1.createdAt }), id: \.id) { p in
                                    Button {
                                        selectedProject = p
                                    } label: {
                                        if selectedProject?.id == p.id {
                                            Label(p.name, systemImage: "checkmark")
                                        } else {
                                            Text(p.name)
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "folder")
                                    Text(selectedProject?.name ?? "Select Project")
                                        .lineLimit(1)
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .font(.caption)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.accentColor.opacity(0.15))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.accentColor, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Action buttons
                    HStack(spacing: 12) {
                        Menu {
                            Button("New Well", systemImage: "plus") {
                                onNewWell?()
                            }
                            Button("New Project State", systemImage: "doc.badge.plus") {
                                onNewProject?()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.green, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)

                        Menu {
                            if let well = selectedWell {
                                Section("Well") {
                                    Button("Rename Well", systemImage: "pencil") {
                                        onRenameWell?(well)
                                    }
                                    Button("Duplicate Well", systemImage: "doc.on.doc") {
                                        onDuplicateWell?(well)
                                    }
                                    Button("Delete Well", systemImage: "trash", role: .destructive) {
                                        onDeleteWell?()
                                    }
                                }
                            }
                            if let project = selectedProject {
                                Section("Project State") {
                                    Button("Rename Project", systemImage: "pencil") {
                                        onRenameProject?(project)
                                    }
                                    Button("Duplicate Project", systemImage: "doc.on.doc") {
                                        onDuplicateProject?(project)
                                    }
                                    Button("Delete Project", systemImage: "trash", role: .destructive) {
                                        onDeleteProject?()
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "ellipsis.circle.fill")
                                Text("Actions")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.blue, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)
                .background(Color(uiColor: .secondarySystemBackground))
            }
            #endif

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Project Dashboard")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Curate project inputs, system defaults, and a snapshot of the work already captured.")
                        .foregroundStyle(.secondary)

                    #if DEBUG
                    HStack(spacing: 12) {
                        Button {
                            debugTriggerMudCloudSync()
                        } label: {
                            Label("Debug: Sync Muds", systemImage: "icloud.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Saves mud changes locally and requests CloudKit sync.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(cloudSyncBanner)
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 10) {
                                Button {
                                    debugClearCloudEvents()
                                } label: {
                                    Label("Clear Events", systemImage: "trash")
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    debugCopyCloudEventsToClipboard()
                                } label: {
                                    Label("Copy Events", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(.bordered)
                            }
                            .font(.caption)
                        }
                    }
                    #endif
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16)], spacing: 16) {
                    WellSection(title: "Project", icon: "target", subtitle: "Name and pressure window safety margins.") {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                            GridRow {
                                Text("Name")
                                    .gridColumnAlignment(.trailing)
                                    .foregroundStyle(.secondary)
                                TextField("Project name", text: $project.name)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: .infinity)
                            }
                            GridRow {
                                Text("Pore safety (kPa)")
                                    .gridColumnAlignment(.trailing)
                                    .foregroundStyle(.secondary)
                                TextField("", value: $project.window.poreSafety_kPa, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: .infinity)
                                    .monospacedDigit()
                            }
                            GridRow {
                                Text("Frac safety (kPa)")
                                    .gridColumnAlignment(.trailing)
                                    .foregroundStyle(.secondary)
                                TextField("", value: $project.window.fracSafety_kPa, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: .infinity)
                                    .monospacedDigit()
                            }
                        }
                    }

                    WellSection(title: "Well", icon: "oilcan", subtitle: "Identity and accounting") {
                        VStack(alignment: .leading, spacing: 8) {
                            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                                GridRow {
                                    Text("Well Name")
                                        .gridColumnAlignment(.trailing)
                                        .foregroundStyle(.secondary)
                                    TextField(
                                        "Well Name",
                                        text: Binding(
                                            get: { project.well?.name ?? "" },
                                            set: { newValue in
                                                if let well = project.well {
                                                    well.name = newValue
                                                }
                                            }
                                        )
                                    )
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: .infinity)
                                }
                                GridRow {
                                    Text("UWI")
                                        .gridColumnAlignment(.trailing)
                                        .foregroundStyle(.secondary)
                                    TextField(
                                        "UWI",
                                        text: Binding(
                                            get: { project.well?.uwi ?? "" },
                                            set: { newValue in
                                                if let well = project.well {
                                                    well.uwi = newValue
                                                }
                                            }
                                        )
                                    )
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: .infinity)
                                }
                                GridRow {
                                    Text("AFE #")
                                        .gridColumnAlignment(.trailing)
                                        .foregroundStyle(.secondary)
                                    TextField(
                                        "AFE #",
                                        text: Binding(
                                            get: { project.well?.afeNumber ?? "" },
                                            set: { newValue in
                                                if let well = project.well {
                                                    well.afeNumber = newValue
                                                }
                                            }
                                        )
                                    )
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: .infinity)
                                }
                                GridRow {
                                    Text("Requisitioner")
                                        .gridColumnAlignment(.trailing)
                                        .foregroundStyle(.secondary)
                                    TextField(
                                        "Requisitioner",
                                        text: Binding(
                                            get: { project.well?.requisitioner ?? "" },
                                            set: { newValue in
                                                if let well = project.well {
                                                    well.requisitioner = newValue
                                                }
                                            }
                                        )
                                    )
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: .infinity)
                                }
                                GridRow {
                                    Button {
                                        copyProjectInfoToClipboard()
                                    } label: {
                                        Label("Copy Info", systemImage: "doc.on.doc")
                                    }
                                }
                            }
                        }
                    }

                    WellSection(title: "Active System", icon: "drop.fill", subtitle: "Current active pit & surface volumes.") {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                            GridRow {
                                Text("Active mud weight (kg/m³)")
                                    .gridColumnAlignment(.trailing)
                                    .foregroundStyle(.secondary)
                                TextField("", value: $project.activeMudDensity_kgm3, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: .infinity)
                                    .monospacedDigit()
                            }
                            GridRow {
                                Text("Active mud volume (m³)")
                                    .gridColumnAlignment(.trailing)
                                    .foregroundStyle(.secondary)
                                TextField("", value: $project.activeMudVolume_m3, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: .infinity)
                                    .monospacedDigit()
                            }
                            GridRow {
                                Text("Surface line volume (m³)")
                                    .gridColumnAlignment(.trailing)
                                    .foregroundStyle(.secondary)
                                TextField("", value: $project.surfaceLineVolume_m3, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: .infinity)
                                    .monospacedDigit()
                            }
                        }
                    }

                    WellSection(title: "Defaults", icon: "slider.horizontal.3", subtitle: "Column densities and control depth seeds.") {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                            GridRow {
                                Text("Base annulus density (kg/m³)")
                                    .gridColumnAlignment(.trailing)
                                    .foregroundStyle(.secondary)
                                TextField("", value: $project.baseAnnulusDensity_kgm3, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: .infinity)
                                    .monospacedDigit()
                            }
                            GridRow {
                                Text("Base string density (kg/m³)")
                                    .gridColumnAlignment(.trailing)
                                    .foregroundStyle(.secondary)
                                TextField("", value: $project.baseStringDensity_kgm3, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: .infinity)
                                    .monospacedDigit()
                            }
                            GridRow {
                                Text("Control measured depth (m)")
                                    .gridColumnAlignment(.trailing)
                                    .foregroundStyle(.secondary)
                                TextField("", value: $project.pressureDepth_m, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: .infinity)
                                    .monospacedDigit()
                            }
                        }
                    }
                }

                WellSection(title: "Overview", icon: "rectangle.grid.2x2", subtitle: "At-a-glance counters across each workspace.") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                        MetricCard(title: "Drill string sections", value: "\(viewmodel.drillStringCount)", caption: "Configured", icon: "cable.connector.horizontal")
                        MetricCard(title: "Annulus sections", value: "\(viewmodel.annulusCount)", caption: "Configured", icon: "circle.grid.hex")
                        MetricCard(title: "Pressure points", value: "\(viewmodel.pressurePointCount)", caption: "Pore/Frac window", icon: "waveform.path.ecg")
                        MetricCard(title: "Survey stations", value: "\(viewmodel.surveysCount)", caption: "Imported/entered", icon: "ruler")
                        MetricCard(title: "Mud checks", value: "\(viewmodel.mudChecksCount)", caption: "Lab results", icon: "testtube.2")
                    }
                }
            }
            .padding(24)
        }
        .sheet(item: $newTransferToEdit, content: { transfer in
            if let well = project.well {
                MaterialTransferEditorView(well: well, transfer: transfer)
                    .frame(minWidth: 700, minHeight: 500)
            } else {
                Text("No well available")
                    .padding()
            }
        })
        .background(pageBackgroundColor)
#if DEBUG
        .onAppear {
            if !cloudMonitorStarted {
                cloudMonitorStarted = true
                startCloudKitEventMonitor()
            }
        }
#endif
        .navigationTitle("Project Dashboard")
        .alert(mudSyncStatusTitle, isPresented: $showMudSyncAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(mudSyncStatusMessage)
        }
    }
}

#if DEBUG
private struct ProjectDashboardPreview: View {
    let container: ModelContainer
    let project: ProjectState

    init() {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        self.container = try! ModelContainer(
            for: ProjectState.self,
                 DrillStringSection.self,
                 AnnulusSection.self,
                 PressureWindow.self,
                 PressureWindowPoint.self,
            configurations: config
        )
        let ctx = container.mainContext
        let p = ProjectState()
        p.baseAnnulusDensity_kgm3 = 1100
        p.baseStringDensity_kgm3 = 1100
        p.pressureDepth_m = 2500
        ctx.insert(p)

        // Seed a couple of string and annulus sections
        let ds1 = DrillStringSection(name: "DP 5\"", topDepth_m: 0, length_m: 1500, outerDiameter_m: 0.127, innerDiameter_m: 0.0953)
        let ds2 = DrillStringSection(name: "DP 5\" HW", topDepth_m: 1500, length_m: 800, outerDiameter_m: 0.127, innerDiameter_m: 0.0953)
        if p.drillString == nil { p.drillString = [] }
        [ds1, ds2].forEach { s in p.drillString?.append(s); ctx.insert(s) }

        let a1 = AnnulusSection(name: "Surface", topDepth_m: 0,    length_m: 600, innerDiameter_m: 0.340, outerDiameter_m: 0.244)
        let a2 = AnnulusSection(name: "Intermediate", topDepth_m: 600, length_m: 900, innerDiameter_m: 0.244, outerDiameter_m: 0.1778)
        if p.annulus == nil { p.annulus = [] }
        [a1, a2].forEach { s in s.project = p; p.annulus?.append(s); ctx.insert(s) }

        // Seed a few pressure window points
        let w = p.window
        let pw1 = PressureWindowPoint(depth_m: 500,  pore_kPa: 6000,  frac_kPa: 11000, window: w)
        let pw2 = PressureWindowPoint(depth_m: 1500, pore_kPa: 15000, frac_kPa: 24000, window: w)
        let pw3 = PressureWindowPoint(depth_m: 2500, pore_kPa: 22000, frac_kPa: 33000, window: w)
        [pw1, pw2, pw3].forEach { ctx.insert($0) }

        try? ctx.save()
        self.project = p
    }

    var body: some View {
        NavigationStack { ProjectDashboardView(project: project) }
            .modelContainer(container)
            .frame(width: 2000, height: 600)
    }
}

#Preview("Project Dashboard – Sample Data") {
    ProjectDashboardPreview()
}
#endif

private struct InputNumberBox: View {
    let title: String
    @Binding var value: Double
    let caption: String
    let min: Double
    let max: Double
    let step: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Stepper(value: $value, in: min...max, step: step) {
                Text("\(value)")
                    .monospacedDigit()
            }
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2)))
    }
}






extension ProjectDashboardView {
    /// Builds the multiline string representing key project and well info.
    fileprivate func makeProjectInfoString() -> String {
        let well = project.well
        return """
        Well Name: \(well?.name ?? "-")
        UWI: \(well?.uwi ?? "-")
        AFE: \(well?.afeNumber ?? "-")
        Requisitioner: \(well?.requisitioner ?? "-")
        """
    }

    /// Copies the project info string to the clipboard.
    fileprivate func copyProjectInfoToClipboard() {
        ClipboardService.shared.copyToClipboard(makeProjectInfoString())
    }

#if DEBUG
    /// Attempts to force a save of any pending mud changes and nudge SwiftData/CloudKit to upload.
    /// This will confirm whether the local save succeeded. CloudKit upload completion isn't directly
    /// observable from SwiftData here without additional container/event plumbing.
    fileprivate func debugTriggerMudCloudSync() {
        appendCloudEventLine("[Manual] Requested mud sync: save() + expect CloudKit event")
        // Nudge the relationship so SwiftUI/SwiftData see a mutation attempt.
        // (This does not change values, but ensures access of the relationship occurs.)
        _ = (project.muds ?? []).count

        do {
            try modelContext.save()
            appendCloudEventLine("[Local] modelContext.save() OK")
            mudSyncStatusTitle = "Mud Sync: Local Save OK"
            mudSyncStatusMessage = "Local SwiftData save succeeded. If iCloud sync is enabled, CloudKit upload will be attempted automatically when possible.\n\nTip: if you need definitive CloudKit success/failure, we can wire CloudKit event callbacks (NSPersistentCloudKitContainer event notifications) or add explicit CloudKit status tracking."
        } catch {
            appendCloudEventLine("[Local] modelContext.save() FAILED: \(error.localizedDescription)")
            cloudLastError = error.localizedDescription
            mudSyncStatusTitle = "Mud Sync: Save FAILED"
            mudSyncStatusMessage = "Local save failed: \(error.localizedDescription)"
        }

        showMudSyncAlert = true
    }

    // MARK: - CloudKit Event Monitoring (DEBUG)

    fileprivate func startCloudKitEventMonitor() {
        // NSPersistentCloudKitContainer posts these when it schedules/completes import/export work.
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else {
                appendCloudEventLine("[CloudKit] eventChangedNotification (no event in userInfo)")
                cloudSyncBanner = "CloudKit event notification received (unparsed)"
                return
            }

            cloudLastEventAt = Date()

            // Type: .import / .export / .setup
            let typeStr: String
            switch event.type {
            case .setup: typeStr = "setup"
            case .import: typeStr = "import"
            case .export: typeStr = "export"
            @unknown default: typeStr = "unknown"
            }

            let endStr = event.endDate == nil ? "(running)" : "(ended)"
            var line = "[CloudKit] \(typeStr) \(endStr)"

            let storeID = event.storeIdentifier
            if !storeID.isEmpty {
                line += " store=\(storeID)"
            }

            if let err = event.error as NSError? {
                cloudLastError = err.localizedDescription
                line += " ERROR=\(err.localizedDescription)"
            }

            appendCloudEventLine(line)

            // Banner for quick glance
            if let err = event.error {
                cloudSyncBanner = "Last CloudKit \(typeStr): ERROR – \(err.localizedDescription)"
            } else {
                if event.endDate == nil {
                    cloudSyncBanner = "CloudKit \(typeStr) in progress…"
                } else {
                    cloudSyncBanner = "Last CloudKit \(typeStr) completed successfully"
                }
            }
        }

        // Also listen for remote changes coming in (useful to verify the OTHER device pushed data).
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { _ in
            cloudLastEventAt = Date()
            appendCloudEventLine("[CloudKit] NSPersistentStoreRemoteChange")
            if cloudLastError == nil {
                cloudSyncBanner = "Remote change received (import likely occurred)"
            }
        }

        appendCloudEventLine("[Monitor] CloudKit event monitor started")
        cloudSyncBanner = "CloudKit monitor running — trigger a save to see export/import"
    }

    fileprivate func appendCloudEventLine(_ s: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        cloudEventLines.append("\(ts) \(s)")
        // Avoid unbounded growth
        if cloudEventLines.count > 200 {
            cloudEventLines.removeFirst(cloudEventLines.count - 200)
        }
    }

    fileprivate func debugClearCloudEvents() {
        cloudEventLines.removeAll()
        cloudLastEventAt = nil
        cloudLastError = nil
        cloudSyncBanner = "Cleared. Trigger a save to observe CloudKit events."
    }

    fileprivate func debugCopyCloudEventsToClipboard() {
        let text = cloudEventLines.joined(separator: "\n")
        ClipboardService.shared.copyToClipboard(text.isEmpty ? "<no cloud events captured>" : text)
        appendCloudEventLine("[Manual] Copied events to clipboard")
    }
#endif
}

extension ProjectDashboardView {
    @Observable
    class ViewModel {
        var project: ProjectState
        init(project: ProjectState) { self.project = project }

        var drillStringCount: Int { (project.drillString ?? []).count }
        var annulusCount: Int { (project.annulus ?? []).count }
        var pressurePointCount: Int { (project.window.points ?? []).count }
        var surveysCount: Int { (project.surveys ?? []).count }
        var mudChecksCount: Int { (project.muds ?? []).count }
    }
}

