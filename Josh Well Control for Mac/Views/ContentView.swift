//
//  ContentView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-02.
//

//// ContentView.swift
//import SwiftUI
//import SwiftData
//
//struct ContentView: View {
//    @Environment(\.modelContext) private var modelContext
//    @Query(sort: \ProjectState.id) private var projects: [ProjectState]
//
//    var body: some View {
//        NavigationSplitView {
//            List {
//                NavigationLink("Project Dashboard") { ProjectDashboardView(project: ensureProject()) }
//                NavigationLink("Drill String") { DrillStringListView(project: ensureProject()) }
//                NavigationLink("Annulus") { AnnulusListView(project: ensureProject()) }
//                NavigationLink("Volume Summary") { VolumeSummaryView(project: ensureProject()) }
//                NavigationLink("Surveys") { SurveyListView(project: ensureProject()) }
//                NavigationLink("Pressure Window") { PressureWindowView(project: ensureProject()) }
//                NavigationLink("Pump Schedule") { MudPlacementView(project: ensureProject()) }
//                NavigationLink("Swabbing") {SwabbingView(project: ensureProject())}
//                NavigationLink("Trip Simulation") {TripSimulationView(project: ensureProject())}
//                NavigationLink("BHP Preview") { BHPPreviewView(project: ensureProject()) }
//            }
//            .navigationTitle("Well Control")
//        } detail: {
//            ProjectDashboardView(project: ensureProject())
//        }
//        .task { _ = ensureProject() }
//    }
//
//    private func ensureProject() -> ProjectState {
//        if let first = projects.first { return first }
//        let p = ProjectState()
//        modelContext.insert(p)
//        try? modelContext.save()
//        return p
//    }
//}

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

    var body: some View {
        NavigationSplitView {
            List(selection: $vm.selectedWell) {
                Section("Wells") {
                    ForEach(wells, id: \.id) { well in
                        HStack {
                            Text(well.name)
                            Spacer()
                            Text(well.createdAt, style: .date).foregroundStyle(.secondary)
                        }
                        .tag(well as Well?)
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button("Rename", systemImage: "pencil") { beginRename(well) }
                            Button("Copy", systemImage: "doc.on.doc") { duplicateWell(from: well) }
                            Divider()
                            Button(role: .destructive) {
                                if let idx = wells.firstIndex(where: { $0.id == well.id }) { deleteWells(at: IndexSet(integer: idx)) }
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                    .onDelete(perform: deleteWells)
                }
            }
            .navigationTitle("Wells")
            .toolbar {
                Button {
                    let w = Well(name: "New Well")
                    modelContext.insert(w)
                    try? modelContext.save()
                    vm.selectedWell = w
                } label: { Label("Add Well", systemImage: "plus") }
            }
            .onAppear {
                if vm.selectedWell == nil {
                    vm.selectedWell = vm.ensureInitialWellIfNeeded(using: wells, context: modelContext)
                }
            }
        } content: {
            if let well = vm.selectedWell {
                List(selection: $vm.selectedProject) {
                    Section("\(well.name) – Project States") {
                        ForEach(well.projects.sorted(by: { $0.createdAt < $1.createdAt }), id: \.id) { p in
                            HStack {
                                Text(p.name)
                                Spacer()
                                Text(p.createdAt, style: .date).foregroundStyle(.secondary)
                            }
                            .tag(p as ProjectState?)
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button("Rename", systemImage: "pencil") { beginRename(p) }
                                Button("Copy", systemImage: "doc.on.doc") { duplicateProject(from: p) }
                                Divider()
                                Button(role: .destructive) {
                                    if let idx = index(of: p, in: well) { deleteProjects(offsets: IndexSet(integer: idx)) }
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                        .onDelete { indexSet in deleteProjects(offsets: indexSet) }
                    }
                }
                .toolbar {
                    Button {
                        guard let w = vm.selectedWell else { return }
                        let p = ProjectState()
                        p.name = "Snapshot \(Date.now.formatted(date: .abbreviated, time: .shortened))"
                        p.well = w
                        w.projects.append(p)
                        try? modelContext.save()
                        vm.selectedProject = p
                    } label: { Label("Add Project", systemImage: "plus") }
                }
                .navigationTitle("Projects")
            } else {
                Text("Select or create a well")
            }
        } detail: {
            if let project = vm.selectedProject {
                ProjectDashboardView(project: project)
            } else if let well = vm.selectedWell, let first = well.projects.first {
                ProjectDashboardView(project: first)
            } else {
                Text("Select a project")
            }
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
        let p = ProjectState()
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
}
