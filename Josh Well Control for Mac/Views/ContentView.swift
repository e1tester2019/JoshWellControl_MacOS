//
//  ContentView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-02.
//

#if os(macOS)
import SwiftUI
import SwiftData
import Foundation
import Combine

@MainActor
final class ContentViewModel: ObservableObject {
    @Environment(\.modelContext) var modelContext

    @Published var selectedWell: Well?
    @Published var selectedProject: ProjectState?

    func ensureInitialWellIfNeeded(using wells: [Well], context: ModelContext) -> Well {
        if let w = wells.first { return w }
        let w = Well(name: "Demo Well")
        context.insert(w)
        let p = ProjectState()
        p.name = "Baseline"
        p.well = w
        if w.projects == nil { w.projects = [] }
        w.projects?.append(p)
        try? context.save()
        return w
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Well.createdAt) private var wells: [Well]

    @StateObject private var vm = ContentViewModel()
    @State private var renamingProject: ProjectState?
    @State private var renameText: String = ""
    @State private var renamingWell: Well?
    @State private var renameWellText: String = ""
    @State private var editingTransfer: MaterialTransfer?

    private enum Pane: String, CaseIterable, Identifiable {
        case dashboard, drillString, annulus, volumes, surveys, mudCheck, mixingCalc, pressureWindow, pumpSchedule, pump, swabbing, trip, rentals, transfers
        var id: String { rawValue }
        var title: String {
            switch self {
            case .dashboard: return "Dashboard"
            case .drillString: return "Drill String"
            case .annulus: return "Annulus"
            case .volumes: return "Volume Summary"
            case .surveys: return "Surveys"
            case .mudCheck: return "Mud Check"
            case .mixingCalc: return "Mixing Calculator"
            case .pressureWindow: return "Pressure Window"
            case .pumpSchedule: return "Spot Final Muds"
            case .pump: return "Pumping Simulation"
            case .swabbing: return "Swabbing"
            case .trip: return "Trip Simulation"
            case .rentals: return "Rentals"
            case .transfers: return "Material Transfers"
            }
        }
    }

    @State private var selectedSection: Pane = .dashboard
    @State private var splitVisibility: NavigationSplitViewVisibility = .doubleColumn

    var body: some View {
        NavigationSplitView(columnVisibility: $splitVisibility) {
            // Sidebar
            VStack(alignment: .leading, spacing: 12) {
                let firstProject = vm.selectedWell.map { ($0.projects ?? []).first }
                if let _ = (vm.selectedProject ?? firstProject ?? nil) {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                            ForEach(Pane.allCases) { sec in
                                Button {
                                    selectedSection = sec
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: icon(for: sec))
                                            .font(.title3)
                                        Text(sec.title)
                                            .font(.caption)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.center)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.roundedRectangle)
                                .tint(selectedSection == sec ? .accentColor : .secondary)
                                .background(selectedSection == sec ? Color.accentColor.opacity(0.12) : .clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedSection == sec ? Color.accentColor : Color.secondary.opacity(0.6), lineWidth: selectedSection == sec ? 1.5 : 1)
                                )
                                .opacity(selectedSection == sec ? 1.0 : 0.92)
                                .animation(.default, value: selectedSection)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                } else {
                    Text("Select or create a well")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                }
                Spacer(minLength: 0)
            }
            .navigationTitle("Views")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        } detail: {
            // Detail content
            Group {
                let firstProject = vm.selectedWell.map { ($0.projects ?? []).first }
                if let project = (vm.selectedProject ?? firstProject ?? nil) {
                    Group {
                        switch selectedSection {
                        case .dashboard:
                            #if os(iOS)
                            ProjectDashboardView(
                                project: project,
                                wells: wells,
                                selectedWell: $vm.selectedWell,
                                selectedProject: $vm.selectedProject,
                                onNewWell: {
                                    let w = Well(name: "New Well")
                                    modelContext.insert(w)
                                    try? modelContext.save()
                                    vm.selectedWell = w
                                    vm.selectedProject = (w.projects ?? []).first
                                },
                                onNewProject: {
                                    guard let w = vm.selectedWell else { return }
                                    let p = ProjectState()
                                    p.name = "Snapshot \(Date.now.formatted(date: .abbreviated, time: .shortened))"
                                    p.well = w
                                    if w.projects == nil { w.projects = [] }
                                    w.projects?.append(p)
                                    try? modelContext.save()
                                    vm.selectedProject = p
                                },
                                onRenameWell: { well in beginRename(well) },
                                onRenameProject: { project in beginRename(project) },
                                onDuplicateWell: { well in duplicateWell(from: well) },
                                onDuplicateProject: { project in duplicateProject(from: project) },
                                onDeleteWell: { deleteCurrentWell() },
                                onDeleteProject: { deleteCurrentProject() }
                            )
                            #else
                            ProjectDashboardView(project: project)
                            #endif
                        case .drillString:
                            DrillStringListView(project: project)
                        case .annulus:
                            AnnulusListView(project: project)
                        case .volumes:
                            VolumeSummaryView(project: project)
                        case .surveys:
                            SurveyListView(project: project)
                        case .mudCheck:
                            MudCheckView(project: project)
                        case .mixingCalc:
                            MixingCalculatorView(project: project)
                        case .pressureWindow:
                            PressureWindowView(project: project)
                        case .pumpSchedule:
                            MudPlacementView(project: project)
                        case .pump:
                            PumpScheduleView(project: project)
                        case .swabbing:
                            SwabbingView(project: project)
                        case .trip:
                            TripSimulationView(project: project)
                        case .rentals:
                            if let well = project.well {
                                RentalItemsView(well: well)
                            } else {
                                Text("No well available")
                            }
                        case .transfers:
                            if let well = project.well {
                                MaterialTransferListView(well: well)
                            } else {
                                Text("No well available")
                            }
                        }
                    }
                    .id(project.id) // force rebuild when project changes
                } else {
                    VStack(spacing: 12) {
                        Text("No selection").font(.title3).bold()
                        Text("Create a well and a project state to get started.")
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Button("New Well", systemImage: "plus") {
                                let w = Well(name: "New Well")
                                modelContext.insert(w)
                                try? modelContext.save()
                                vm.selectedWell = w
                                vm.selectedProject = (w.projects ?? []).first
                            }
                            if vm.selectedWell != nil {
                                Button("New Project State", systemImage: "doc.badge.plus") {
                                    guard let w = vm.selectedWell else { return }
                                    let p = ProjectState()
                                    p.name = "Snapshot \(Date.now.formatted(date: .abbreviated, time: .shortened))"
                                    p.well = w
                                    if w.projects == nil { w.projects = [] }
                                    w.projects?.append(p)
                                    try? modelContext.save()
                                    vm.selectedProject = p
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding(24)
                }
            }
            .navigationTitle(selectedSection.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { detailToolbar }
        }
        .sheet(item: $renamingProject) { project in
            VStack(spacing: 12) {
                Text("Rename Project State").font(.headline)
                TextField("Name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 320)
                HStack {
                    Spacer()
                    Button("Cancel") { renamingProject = nil }
                    Button("Save") { commitRename(project) }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .onAppear { renameText = project.name }
        }
        .sheet(item: $renamingWell) { well in
            VStack(spacing: 12) {
                Text("Rename Well").font(.headline)
                TextField("Name", text: $renameWellText)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 320)
                HStack {
                    Spacer()
                    Button("Cancel") { renamingWell = nil }
                    Button("Save") { commitRename(well) }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .onAppear { renameWellText = well.name }
        }
        .sheet(item: $editingTransfer) { transfer in
            if let well = vm.selectedWell {
                MaterialTransferEditorView(well: well, transfer: transfer)
                    #if os(macOS)
                    .frame(minWidth: 900, minHeight: 600)
                    #endif
            }
        }
        .onAppear {
            if vm.selectedWell == nil {
                vm.selectedWell = vm.ensureInitialWellIfNeeded(using: wells, context: modelContext)
            }
        }
        .onChange(of: wells) { oldWells, newWells in
            // Validate selectedWell still exists after changes
            // CRITICAL: Always use objects from newWells array, never from stale references
            if let selectedWellID = vm.selectedWell?.id {
                // Find the well in the updated array by ID
                if let freshWell = newWells.first(where: { $0.id == selectedWellID }) {
                    // Well still exists, update reference to fresh object
                    if vm.selectedWell !== freshWell {
                        vm.selectedWell = freshWell
                    }
                    // Validate the project using the fresh well reference
                    if let selectedProjectID = vm.selectedProject?.id {
                        let projects = freshWell.projects ?? []
                        if let freshProject = projects.first(where: { $0.id == selectedProjectID }) {
                            // Project still exists, update reference if needed
                            if vm.selectedProject !== freshProject {
                                vm.selectedProject = freshProject
                            }
                        } else {
                            // Current project was deleted, select another
                            vm.selectedProject = projects.first
                        }
                    } else {
                        // No project selected, select first available
                        let projects = freshWell.projects ?? []
                        vm.selectedProject = projects.first
                    }
                } else {
                    // Current well was deleted, select another
                    vm.selectedWell = newWells.first
                    vm.selectedProject = newWells.first.flatMap { ($0.projects ?? []).first }
                }
            } else {
                // No well selected, select first available
                vm.selectedWell = newWells.first
                vm.selectedProject = newWells.first.flatMap { ($0.projects ?? []).first }
            }
        }
        .environment(\.locale, Locale(identifier: "en_GB"))
    }
}

private extension ContentView {
    func index(of project: ProjectState, in well: Well) -> Int? {
        let projects = well.projects ?? []
        return projects
            .sorted { $0.createdAt < $1.createdAt }
            .firstIndex(where: { $0.id == project.id })
    }

    /// Helper function to properly delete a project with all its child collections to prevent cascade overflow
    /// CRITICAL: ProjectState has 13+ cascade relationships. Deleting child collections first
    /// breaks up the cascade into manageable chunks and prevents stack overflow.
    nonisolated static func deleteProject(_ project: ProjectState, from context: ModelContext) {
        // Delete array collections first
        if let surveys = project.surveys {
            for item in surveys { context.delete(item) }
        }
        if let drillString = project.drillString {
            for item in drillString { context.delete(item) }
        }
        if let annulus = project.annulus {
            for item in annulus { context.delete(item) }
        }
        if let mudSteps = project.mudSteps {
            for item in mudSteps { context.delete(item) }
        }
        if let finalLayers = project.finalLayers {
            for item in finalLayers { context.delete(item) }
        }
        if let muds = project.muds {
            for item in muds { context.delete(item) }
        }
        if let programStages = project.programStages {
            for item in programStages { context.delete(item) }
        }

        // Now delete the project itself (no more cascade overflow)
        context.delete(project)
    }

    func deleteProjects(offsets: IndexSet) {
        // Find the well in the current wells array to ensure we have a fresh reference
        guard let selectedWellID = vm.selectedWell?.id,
              let well = wells.first(where: { $0.id == selectedWellID }) else { return }

        let projects = well.projects ?? []
        let sorted = projects.sorted { $0.createdAt < $1.createdAt }

        // Collect IDs to delete (not object references)
        var toDeleteIDs: Set<UUID> = []
        for i in offsets {
            guard i < sorted.count else { continue }
            toDeleteIDs.insert(sorted[i].id)
        }

        guard !toDeleteIDs.isEmpty else { return }

        // CRITICAL: Clear selection IMMEDIATELY if it will be deleted
        let willDeleteCurrent = vm.selectedProject.map { toDeleteIDs.contains($0.id) } ?? false

        if willDeleteCurrent {
            // Find ID of first remaining project that won't be deleted
            let newProjectID = sorted.first { p in !toDeleteIDs.contains(p.id) }?.id

            // ATOMIC UPDATE: Clear selection to nil immediately to prevent accessing stale objects
            vm.selectedProject = nil

            // Perform deletion on background context to prevent stack overflow
            let container = modelContext.container
            Task.detached {
                let backgroundContext = ModelContext(container)

                // Fetch projects to delete in background context
                let descriptor = FetchDescriptor<ProjectState>()
                let allProjects = try? backgroundContext.fetch(descriptor)
                let toDelete = allProjects?.filter { toDeleteIDs.contains($0.id) } ?? []

                // Delete from background context using helper function
                for p in toDelete {
                    ContentView.deleteProject(p, from: backgroundContext)
                }
                try? backgroundContext.save()

                // Update UI on main thread after deletion completes
                await MainActor.run {
                    // Re-fetch the well to ensure fresh reference
                    if let freshWell = self.wells.first(where: { $0.id == selectedWellID }) {
                        let freshProjects = freshWell.projects ?? []
                        // Restore selection using ID if it still exists
                        if let newProjectID = newProjectID {
                            self.vm.selectedProject = freshProjects.first { $0.id == newProjectID }
                        } else {
                            self.vm.selectedProject = freshProjects.first
                        }
                    }
                }
            }
        } else {
            // Current selection is NOT being deleted, delete in background
            let container = modelContext.container
            Task.detached {
                let backgroundContext = ModelContext(container)

                // Fetch projects to delete in background context
                let descriptor = FetchDescriptor<ProjectState>()
                let allProjects = try? backgroundContext.fetch(descriptor)
                let toDelete = allProjects?.filter { toDeleteIDs.contains($0.id) } ?? []

                // Delete from background context using helper function
                for p in toDelete {
                    ContentView.deleteProject(p, from: backgroundContext)
                }
                try? backgroundContext.save()
            }
        }
    }

    func beginRename(_ p: ProjectState) {
        renamingProject = p
        renameText = p.name
    }

    func commitRename(_ p: ProjectState) {
        let newName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newName.isEmpty { p.name = newName; p.updatedAt = .now }
        try? modelContext.save()
        renamingProject = nil
    }

    func duplicateProject(from source: ProjectState) {
        guard let well = source.well else { return }
        // Minimal duplicate now — deep copy can be added later
        let p = source.deepClone(into: well, using: modelContext)
        vm.selectedProject = p
        p.name = source.name + " (Copy)"
        p.baseAnnulusDensity_kgm3 = source.baseAnnulusDensity_kgm3
        p.baseStringDensity_kgm3 = source.baseStringDensity_kgm3
        p.pressureDepth_m = source.pressureDepth_m
        p.well = well
        if well.projects == nil { well.projects = [] }
        well.projects?.append(p)
        try? modelContext.save()
        vm.selectedProject = p
    }

    func deleteWells(at offsets: IndexSet) {
        let arr = wells

        // Collect IDs to delete (not object references)
        var toDeleteIDs: Set<UUID> = []
        for i in offsets {
            guard i < arr.count else { continue }
            toDeleteIDs.insert(arr[i].id)
        }

        guard !toDeleteIDs.isEmpty else { return }

        // CRITICAL: Clear selections IMMEDIATELY if they will be deleted
        let willDeleteCurrent = vm.selectedWell.map { toDeleteIDs.contains($0.id) } ?? false

        if willDeleteCurrent {
            // Find ID of first remaining well that won't be deleted (use ID only, not object reference)
            let newWellID = arr.first { w in !toDeleteIDs.contains(w.id) }?.id

            // ATOMIC UPDATE: Clear selections to nil first to prevent onChange from accessing stale objects
            vm.selectedWell = nil
            vm.selectedProject = nil

            // Perform deletion on background context to prevent stack overflow
            let container = modelContext.container
            Task.detached {
                let backgroundContext = ModelContext(container)

                // Fetch wells to delete in background context
                let descriptor = FetchDescriptor<Well>()
                let allWells = try? backgroundContext.fetch(descriptor)
                let toDelete = allWells?.filter { toDeleteIDs.contains($0.id) } ?? []

                // Delete from background context
                for w in toDelete {
                    // CRITICAL: Delete all child collections first to prevent cascade overflow

                    // 1. Delete projects (each has 13+ cascade relationships)
                    if let projects = w.projects {
                        for project in projects {
                            // Use helper function to properly delete each project with all its children
                            ContentView.deleteProject(project, from: backgroundContext)
                        }
                    }

                    // 2. Delete material transfers (each has cascade to items)
                    if let transfers = w.transfers {
                        for transfer in transfers {
                            backgroundContext.delete(transfer)
                        }
                    }

                    // 3. Delete rental items (each has cascade to additional costs)
                    if let rentals = w.rentals {
                        for rental in rentals {
                            backgroundContext.delete(rental)
                        }
                    }

                    // Now delete the well itself (no more cascade issues)
                    backgroundContext.delete(w)
                }
                try? backgroundContext.save()

                // Update UI on main thread
                await MainActor.run {
                    if let newWellID = newWellID {
                        self.vm.selectedWell = self.wells.first { $0.id == newWellID }
                        if let freshWell = self.vm.selectedWell {
                            self.vm.selectedProject = (freshWell.projects ?? []).first
                        }
                    }
                }
            }
        } else {
            // Current selection is NOT being deleted, delete in background
            let container = modelContext.container
            Task.detached {
                let backgroundContext = ModelContext(container)

                // Fetch wells to delete in background context
                let descriptor = FetchDescriptor<Well>()
                let allWells = try? backgroundContext.fetch(descriptor)
                let toDelete = allWells?.filter { toDeleteIDs.contains($0.id) } ?? []

                // Delete from background context
                for w in toDelete {
                    // CRITICAL: Delete all child collections first to prevent cascade overflow

                    // 1. Delete projects (each has 13+ cascade relationships)
                    if let projects = w.projects {
                        for project in projects {
                            // Use helper function to properly delete each project with all its children
                            ContentView.deleteProject(project, from: backgroundContext)
                        }
                    }

                    // 2. Delete material transfers (each has cascade to items)
                    if let transfers = w.transfers {
                        for transfer in transfers {
                            backgroundContext.delete(transfer)
                        }
                    }

                    // 3. Delete rental items (each has cascade to additional costs)
                    if let rentals = w.rentals {
                        for rental in rentals {
                            backgroundContext.delete(rental)
                        }
                    }

                    // Now delete the well itself (no more cascade issues)
                    backgroundContext.delete(w)
                }
                try? backgroundContext.save()
            }
        }
    }

    func beginRename(_ well: Well) {
        renamingWell = well
        renameWellText = well.name
    }

    func commitRename(_ well: Well) {
        let newName = renameWellText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newName.isEmpty { well.name = newName; well.updatedAt = .now }
        try? modelContext.save()
        renamingWell = nil
    }

    func duplicateWell(from source: Well) {
        let w = Well(name: source.name + " (Copy)")
        modelContext.insert(w)
        if w.projects == nil { w.projects = [] }
        // Shallow-copy project states (scalar fields); deep-copy of related collections can be added later
        for p0 in (source.projects ?? []).sorted(by: { $0.createdAt < $1.createdAt }) {
            let p = ProjectState()
            p.name = p0.name
            p.baseAnnulusDensity_kgm3 = p0.baseAnnulusDensity_kgm3
            p.baseStringDensity_kgm3 = p0.baseStringDensity_kgm3
            p.pressureDepth_m = p0.pressureDepth_m
            p.well = w
            if w.projects == nil { w.projects = [] }
            w.projects?.append(p)
        }
        try? modelContext.save()
        vm.selectedWell = w
        vm.selectedProject = (w.projects ?? []).first
    }

    func openMaterialTransferEditor() {
        guard let well = vm.selectedWell else { return }
        // Choose latest transfer or create one
        let transfers = well.transfers ?? []
        let transfer: MaterialTransfer
        if let latest = transfers.sorted(by: { $0.date > $1.date }).first {
            transfer = latest
        } else {
            transfer = well.createTransfer(context: modelContext)
        }
        editingTransfer = transfer
    }

    private func icon(for pane: Pane) -> String {
        switch pane {
        case .dashboard: return "speedometer"
        case .drillString: return "wrench.and.screwdriver"
        case .annulus: return "seal"
        case .volumes: return "chart.bar"
        case .surveys: return "map"
        case .mudCheck: return "checkmark.diamond"
        case .mixingCalc: return "tornado"
        case .pressureWindow: return "barometer"
        case .pumpSchedule: return "drop.triangle"
        case .pump: return "drop"
        case .swabbing: return "arrow.up.and.down"
        case .trip: return "figure.walk"
        case .rentals: return "tray.full"
        case .transfers: return "doc.richtext"
        }
    }
}

private extension ContentView {
    /// Safely get the name of the currently selected well (defensive against deleted objects)
    var currentWellName: String {
        guard let well = vm.selectedWell else { return "Well" }
        guard wells.contains(where: { $0.id == well.id }) else { return "Well" }
        return well.name
    }

    /// Safely get the name of the currently selected project (defensive against deleted objects)
    var currentProjectName: String {
        guard let project = vm.selectedProject else { return "Project" }
        guard let well = vm.selectedWell, wells.contains(where: { $0.id == well.id }) else { return "Project" }
        let projects = well.projects ?? []
        guard projects.contains(where: { $0.id == project.id }) else { return "Project" }
        return project.name
    }

    /// Safely get the name of a well (defensive against deleted objects)
    func safeName(of well: Well) -> String {
        guard wells.contains(where: { $0.id == well.id }) else { return "(Deleted)" }
        return well.name
    }

    /// Safely get the name of a project (defensive against deleted objects)
    func safeName(of project: ProjectState) -> String {
        guard let well = project.well, wells.contains(where: { $0.id == well.id }) else { return "(Deleted)" }
        let projects = well.projects ?? []
        guard projects.contains(where: { $0.id == project.id }) else { return "(Deleted)" }
        return project.name
    }

    @ToolbarContentBuilder
    var detailToolbar: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .principal) {
            HStack(spacing: 8) {
                // Well picker menu
                Menu {
                    ForEach(wells, id: \.id) { w in
                        Button {
                            vm.selectedWell = w
                            vm.selectedProject = (w.projects ?? []).first
                        } label: {
                            if vm.selectedWell?.id == w.id { Image(systemName: "checkmark") }
                            Text(safeName(of: w))
                        }
                    }
                } label: {
                    Label(currentWellName, systemImage: "square.grid.2x2")
                }

                // Project picker menu
                if let well = vm.selectedWell, wells.contains(where: { $0.id == well.id }) {
                    let projects = well.projects ?? []
                    Menu {
                        ForEach(projects.sorted(by: { $0.createdAt < $1.createdAt }), id: \.id) { p in
                            Button { vm.selectedProject = p } label: {
                                if vm.selectedProject?.id == p.id { Image(systemName: "checkmark") }
                                Text(safeName(of: p))
                            }
                        }
                    } label: {
                        Label(currentProjectName, systemImage: "folder")
                    }
                }
            }
        }
        #else
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 8) {
                // Well picker menu
                Menu {
                    ForEach(wells, id: \.id) { w in
                        Button {
                            vm.selectedWell = w
                            vm.selectedProject = (w.projects ?? []).first
                        } label: {
                            if vm.selectedWell?.id == w.id { Image(systemName: "checkmark") }
                            Text(safeName(of: w))
                        }
                    }
                } label: {
                    Label(currentWellName, systemImage: "square.grid.2x2")
                }

                // Project picker menu
                if let well = vm.selectedWell, wells.contains(where: { $0.id == well.id }) {
                    let projects = well.projects ?? []
                    Menu {
                        ForEach(projects.sorted(by: { $0.createdAt < $1.createdAt }), id: \.id) { p in
                            Button { vm.selectedProject = p } label: {
                                if vm.selectedProject?.id == p.id { Image(systemName: "checkmark") }
                                Text(safeName(of: p))
                            }
                        }
                    } label: {
                        Label(currentProjectName, systemImage: "folder")
                    }
                }
            }
        }
        #endif
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("New Well", systemImage: "plus") {
                    let w = Well(name: "New Well")
                    modelContext.insert(w)
                    try? modelContext.save()
                    vm.selectedWell = w
                    vm.selectedProject = (w.projects ?? []).first
                }
                Button("New Project State", systemImage: "doc.badge.plus") {
                    guard let w = vm.selectedWell else { return }
                    let p = ProjectState()
                    p.name = "Snapshot \(Date.now.formatted(date: .abbreviated, time: .shortened))"
                    p.well = w
                    if w.projects == nil { w.projects = [] }
                    w.projects?.append(p)
                    try? modelContext.save()
                    vm.selectedProject = p
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                if let well = vm.selectedWell {
                    Section("Well") {
                        Button("Rename Well", systemImage: "pencil") { beginRename(well) }
                        Button("Duplicate Well", systemImage: "doc.on.doc") { duplicateWell(from: well) }
                        Button(role: .destructive) { deleteCurrentWell() } label: { Label("Delete Well", systemImage: "trash") }
                        Button("Material Transfers", systemImage: "doc.richtext") {
                            selectedSection = .transfers
                        }
                    }
                }
                if let project = vm.selectedProject {
                    Section("Project State") {
                        Button("Rename Project", systemImage: "pencil") { beginRename(project) }
                        Button("Duplicate Project", systemImage: "doc.on.doc") { duplicateProject(from: project) }
                        Button(role: .destructive) { deleteCurrentProject() } label: { Label("Delete Project", systemImage: "trash") }
                    }
                }
            } label: {
                Label("Actions", systemImage: "ellipsis.circle")
            }
        }
    }
}


private extension ContentView {
    func deleteCurrentWell() {
        guard let w = vm.selectedWell, let idx = wells.firstIndex(where: { $0.id == w.id }) else { return }
        deleteWells(at: IndexSet(integer: idx))
    }

    func deleteCurrentProject() {
        guard let well = vm.selectedWell, let p = vm.selectedProject else { return }
        let projects = well.projects ?? []
        if let idx = projects.sorted(by: { $0.createdAt < $1.createdAt }).firstIndex(where: { $0.id == p.id }) {
            deleteProjects(offsets: IndexSet(integer: idx))
        }
    }
}
#endif

