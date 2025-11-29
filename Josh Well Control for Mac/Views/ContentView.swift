//
//  ContentView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-02.
//

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
        w.projects.append(p)
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
    @State private var splitVisibility: NavigationSplitViewVisibility = .doubleColumn

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                if let _ = (vm.selectedProject ?? vm.selectedWell?.projects.first) {
                    GroupBox("Views") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)], spacing: 8) {
                            ForEach(Pane.allCases) { sec in
                                Button {
                                    selectedSection = sec
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: icon(for: sec))
                                        Text(sec.title)
                                    }
                                    .frame(maxWidth: .infinity)
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
                        .padding(8)
                    }
                } else {
                    Text("Select or create a well")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                }
                Spacer(minLength: 0)
            }
            .padding([.horizontal, .top], 12)
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
            
            Group {
                if let project = (vm.selectedProject ?? vm.selectedWell?.projects.first) {
                    Group {
                        switch selectedSection {
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
                                vm.selectedProject = w.projects.first
                            }
                            if vm.selectedWell != nil {
                                Button("New Project State", systemImage: "doc.badge.plus") {
                                    guard let w = vm.selectedWell else { return }
                                    let p = ProjectState()
                                    p.name = "Snapshot \(Date.now.formatted(date: .abbreviated, time: .shortened))"
                                    p.well = w
                                    w.projects.append(p)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle(selectedSection.title)
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
}

private extension ContentView {
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
        // Minimal duplicate now — deep copy can be added later
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
            // If currently selected, clear selections or move to another available well
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
        // Shallow-copy project states (scalar fields); deep-copy of related collections can be added later
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

    func openMaterialTransferEditor() {
        guard let well = vm.selectedWell else { return }
        // Choose latest transfer or create one
        let transfer: MaterialTransfer
        if let latest = well.transfers.sorted(by: { $0.date > $1.date }).first {
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
        case .bhp: return "waveform"
        case .rentals: return "tray.full"
        case .transfers: return "doc.richtext"
        }
    }
}

private extension ContentView {
    @ToolbarContentBuilder
    var detailToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 8) {
                // Well picker menu
                Menu {
                    ForEach(wells, id: \.id) { w in
                        Button {
                            vm.selectedWell = w
                            vm.selectedProject = w.projects.first
                        } label: {
                            if vm.selectedWell?.id == w.id { Image(systemName: "checkmark") }
                            Text(w.name)
                        }
                    }
                } label: {
                    Label(vm.selectedWell?.name ?? "Well", systemImage: "square.grid.2x2")
                }

                // Project picker menu
                if let well = vm.selectedWell {
                    Menu {
                        ForEach(well.projects.sorted(by: { $0.createdAt < $1.createdAt }), id: \.id) { p in
                            Button { vm.selectedProject = p } label: {
                                if vm.selectedProject?.id == p.id { Image(systemName: "checkmark") }
                                Text(p.name)
                            }
                        }
                    } label: {
                        Label(vm.selectedProject?.name ?? "Project", systemImage: "folder")
                    }
                }
            }
        }
        ToolbarItem { // Add menu
            Menu {
                Button("New Well", systemImage: "plus") {
                    let w = Well(name: "New Well")
                    modelContext.insert(w)
                    try? modelContext.save()
                    vm.selectedWell = w
                    vm.selectedProject = w.projects.first
                }
                Button("New Project State", systemImage: "doc.badge.plus") {
                    guard let w = vm.selectedWell else { return }
                    let p = ProjectState()
                    p.name = "Snapshot \(Date.now.formatted(date: .abbreviated, time: .shortened))"
                    p.well = w
                    w.projects.append(p)
                    try? modelContext.save()
                    vm.selectedProject = p
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
        }
        ToolbarItem { // Manage menu
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
        guard let well = vm.selectedWell, let p = vm.selectedProject,
              let idx = well.projects.sorted(by: { $0.createdAt < $1.createdAt }).firstIndex(where: { $0.id == p.id }) else { return }
        deleteProjects(offsets: IndexSet(integer: idx))
    }
}

