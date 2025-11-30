//
//  ContentView_iPadOS.swift
//  Josh Well Control for Mac
//
//  iPad-optimized ContentView with responsive layout
//

import SwiftUI
import SwiftData
import Foundation
import Combine

@MainActor
final class ContentViewModel_iPadOS: ObservableObject {
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
        w.projects.append(p)
        try? context.save()
        return w
    }
}

struct ContentView_iPadOS: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Well.createdAt) private var wells: [Well]

    @StateObject private var vm = ContentViewModel_iPadOS()
    @State private var renamingProject: ProjectState?
    @State private var renameText: String = ""
    @State private var renamingWell: Well?
    @State private var renameWellText: String = ""
    @State private var navigationPath = NavigationPath()

    enum Pane: String, CaseIterable, Identifiable {
        case dashboard, drillString, annulus, volumes, surveys, mudCheck, mixingCalc, pressureWindow, pumpSchedule, pump, swabbing, trip, bhp, rentals, transfers
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
            case .bhp: return "BHP Preview"
            case .rentals: return "Rentals"
            case .transfers: return "Material Transfers"
            }
        }
    }

    @State private var selectedSection: Pane = .dashboard

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if let project = (vm.selectedProject ?? vm.selectedWell?.projects.first) {
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 16)
                        ], spacing: 16) {
                            ForEach(Pane.allCases) { pane in
                                Button {
                                    selectedSection = pane
                                    navigationPath.append(pane)
                                } label: {
                                    VStack(spacing: 12) {
                                        Image(systemName: icon(for: pane))
                                            .font(.system(size: 40))
                                            .foregroundStyle(.blue)
                                        Text(pane.title)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 140)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(.systemBackground))
                                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                    .navigationTitle("Josh Well Control")
                    .navigationBarTitleDisplayMode(.large)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            wellAndProjectPicker
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            actionsMenu
                        }
                    }
                    .navigationDestination(for: Pane.self) { pane in
                        viewForPane(pane, project: project)
                            .navigationTitle(pane.title)
                            .navigationBarTitleDisplayMode(.inline)
                    }
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 80))
                            .foregroundStyle(.secondary)
                        Text("No Well Selected")
                            .font(.title)
                            .bold()
                        Text("Create a well and a project to get started.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        VStack(spacing: 12) {
                            Button {
                                createNewWell()
                            } label: {
                                Label("New Well", systemImage: "plus.circle.fill")
                                    .frame(maxWidth: 300)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)

                            if vm.selectedWell != nil {
                                Button {
                                    createNewProject()
                                } label: {
                                    Label("New Project State", systemImage: "doc.badge.plus")
                                        .frame(maxWidth: 300)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                            }
                        }
                        .padding(.top)
                    }
                    .padding(40)
                    .navigationTitle("Josh Well Control")
                }
            }
        }
        .sheet(item: $renamingProject) { project in
            NavigationStack {
                Form {
                    Section {
                        TextField("Name", text: $renameText)
                    }
                }
                .navigationTitle("Rename Project")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { renamingProject = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { commitRename(project) }
                    }
                }
                .onAppear { renameText = project.name }
            }
        }
        .sheet(item: $renamingWell) { well in
            NavigationStack {
                Form {
                    Section {
                        TextField("Name", text: $renameWellText)
                    }
                }
                .navigationTitle("Rename Well")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { renamingWell = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { commitRename(well) }
                    }
                }
                .onAppear { renameWellText = well.name }
            }
        }
        .onAppear {
            if vm.selectedWell == nil {
                vm.selectedWell = vm.ensureInitialWellIfNeeded(using: wells, context: modelContext)
            }
        }
        .onChange(of: vm.selectedWell) { _, newVal in
            vm.selectedProject = newVal?.projects.first
        }
        .onChange(of: vm.selectedProject) { _, newVal in
            if newVal == nil, let w = vm.selectedWell {
                vm.selectedProject = w.projects.first
            }
        }
        .environment(\.locale, Locale(identifier: "en_GB"))
    }

    @ViewBuilder
    private func viewForPane(_ pane: Pane, project: ProjectState) -> some View {
        ScrollView {
            Group {
                switch pane {
                case .dashboard:
                    ProjectDashboardView(project: project)
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
                case .bhp:
                    BHPPreviewView(project: project)
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
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var wellAndProjectPicker: some View {
        HStack(spacing: 8) {
            // Well picker
            Menu {
                ForEach(wells, id: \.id) { w in
                    Button {
                        vm.selectedWell = w
                        vm.selectedProject = w.projects.first
                    } label: {
                        if vm.selectedWell?.id == w.id {
                            Label(w.name, systemImage: "checkmark")
                        } else {
                            Text(w.name)
                        }
                    }
                }
            } label: {
                Label(vm.selectedWell?.name ?? "Well", systemImage: "square.grid.2x2")
                    .lineLimit(1)
            }

            // Project picker
            if let well = vm.selectedWell {
                Menu {
                    ForEach(well.projects.sorted(by: { $0.createdAt < $1.createdAt }), id: \.id) { p in
                        Button {
                            vm.selectedProject = p
                        } label: {
                            if vm.selectedProject?.id == p.id {
                                Label(p.name, systemImage: "checkmark")
                            } else {
                                Text(p.name)
                            }
                        }
                    }
                } label: {
                    Label(vm.selectedProject?.name ?? "Project", systemImage: "folder")
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private var actionsMenu: some View {
        Menu {
            Section {
                Button {
                    createNewWell()
                } label: {
                    Label("New Well", systemImage: "plus")
                }

                Button {
                    createNewProject()
                } label: {
                    Label("New Project State", systemImage: "doc.badge.plus")
                }
                .disabled(vm.selectedWell == nil)
            }

            if let well = vm.selectedWell {
                Section("Well") {
                    Button {
                        beginRename(well)
                    } label: {
                        Label("Rename Well", systemImage: "pencil")
                    }

                    Button {
                        duplicateWell(from: well)
                    } label: {
                        Label("Duplicate Well", systemImage: "doc.on.doc")
                    }

                    Button(role: .destructive) {
                        deleteCurrentWell()
                    } label: {
                        Label("Delete Well", systemImage: "trash")
                    }
                }
            }

            if let project = vm.selectedProject {
                Section("Project State") {
                    Button {
                        beginRename(project)
                    } label: {
                        Label("Rename Project", systemImage: "pencil")
                    }

                    Button {
                        duplicateProject(from: project)
                    } label: {
                        Label("Duplicate Project", systemImage: "doc.on.doc")
                    }

                    Button(role: .destructive) {
                        deleteCurrentProject()
                    } label: {
                        Label("Delete Project", systemImage: "trash")
                    }
                }
            }
        } label: {
            Label("Menu", systemImage: "ellipsis.circle")
        }
    }
}

// MARK: - Helper Functions
private extension ContentView {
    func createNewWell() {
        let w = Well(name: "New Well")
        modelContext.insert(w)
        try? modelContext.save()
        vm.selectedWell = w
        vm.selectedProject = w.projects.first
    }

    func createNewProject() {
        guard let w = vm.selectedWell else { return }
        let p = ProjectState()
        p.name = "Snapshot \(Date.now.formatted(date: .abbreviated, time: .shortened))"
        p.well = w
        w.projects.append(p)
        try? modelContext.save()
        vm.selectedProject = p
    }

    func index(of project: ProjectState, in well: Well) -> Int? {
        well.projects
            .sorted { $0.createdAt < $1.createdAt }
            .firstIndex(where: { $0.id == project.id })
    }

    func deleteProjects(offsets: IndexSet) {
        guard let well = vm.selectedWell else { return }
        let sorted = well.projects.sorted { $0.createdAt < $1.createdAt }
        for i in offsets {
            let p = sorted[i]
            modelContext.delete(p)
            if vm.selectedProject?.id == p.id { vm.selectedProject = nil }
        }
        try? modelContext.save()
        if vm.selectedProject == nil { vm.selectedProject = well.projects.first }
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
        let p = source.deepClone(into: well, using: modelContext)
        vm.selectedProject = p
        p.name = source.name + " (Copy)"
        p.baseAnnulusDensity_kgm3 = source.baseAnnulusDensity_kgm3
        p.baseStringDensity_kgm3 = source.baseStringDensity_kgm3
        p.pressureDepth_m = source.pressureDepth_m
        p.well = well
        well.projects.append(p)
        try? modelContext.save()
        vm.selectedProject = p
    }

    func deleteWells(at offsets: IndexSet) {
        let arr = wells
        for i in offsets {
            let w = arr[i]
            if vm.selectedWell?.id == w.id { vm.selectedWell = nil; vm.selectedProject = nil }
            modelContext.delete(w)
        }
        try? modelContext.save()
        if let first = wells.first { vm.selectedWell = first; vm.selectedProject = first.projects.first }
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
        for p0 in source.projects.sorted(by: { $0.createdAt < $1.createdAt }) {
            let p = ProjectState()
            p.name = p0.name
            p.baseAnnulusDensity_kgm3 = p0.baseAnnulusDensity_kgm3
            p.baseStringDensity_kgm3 = p0.baseStringDensity_kgm3
            p.pressureDepth_m = p0.pressureDepth_m
            p.well = w
            w.projects.append(p)
        }
        try? modelContext.save()
        vm.selectedWell = w
        vm.selectedProject = w.projects.first
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
        case .bhp: return "waveform"
        case .rentals: return "tray.full"
        case .transfers: return "doc.richtext"
        }
    }

    func deleteCurrentWell() {
        guard let w = vm.selectedWell, let idx = wells.firstIndex(where: { $0.id == w.id }) else { return }
        deleteWells(at: IndexSet(integer: idx))
    }

    func deleteCurrentProject() {
        guard let well = vm.selectedWell, let p = vm.selectedProject,
              let idx = well.projects.sorted(by: { $0.createdAt < $1.createdAt }).firstIndex(where: { $0.id == p.id }) else { return }
        deleteProjects(offsets: IndexSet(integer: idx))
    }
}
