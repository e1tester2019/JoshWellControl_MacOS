//
//  ContentView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-02.
//


// ContentView.swift
import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ProjectState.id) private var projects: [ProjectState]

    var body: some View {
        NavigationSplitView {
            List {
                NavigationLink("Project Dashboard") { ProjectDashboardView(project: ensureProject()) }
                NavigationLink("Drill String") { DrillStringListView(project: ensureProject()) }
                NavigationLink("Annulus") { AnnulusListView(project: ensureProject()) }
                NavigationLink("Volume Summary") { VolumeSummaryView(project: ensureProject()) }
                NavigationLink("Surveys") { SurveyListView(project: ensureProject()) }
                NavigationLink("Pressure Window") { PressureWindowView(project: ensureProject()) }
                NavigationLink("Pump Schedule") { MudPlacementView(project: ensureProject()) }
                NavigationLink("Swabbing View") {SwabbingView(project: ensureProject())}
                NavigationLink("BHP Preview") { BHPPreviewView(project: ensureProject()) }
            }
            .navigationTitle("Well Control")
        } detail: {
            ProjectDashboardView(project: ensureProject())
        }
        .task { _ = ensureProject() }
    }

    private func ensureProject() -> ProjectState {
        if let first = projects.first { return first }
        let p = ProjectState()
        modelContext.insert(p)
        try? modelContext.save()
        return p
    }
}
