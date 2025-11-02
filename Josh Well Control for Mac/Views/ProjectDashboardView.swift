//
//  ProjectDashboardView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-02.
//


// ProjectDashboardView.swift
import SwiftUI
import SwiftData

struct ProjectDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectState

    var body: some View {
        Form {
            Section("Project") {
                TextField("Name", text: $project.window.name)
                Stepper("Pore safety (kPa): \(Int(project.window.poreSafety_kPa))", value: $project.window.poreSafety_kPa, in: 0...3000, step: 50)
                Stepper("Frac safety (kPa): \(Int(project.window.fracSafety_kPa))", value: $project.window.fracSafety_kPa, in: 0...3000, step: 50)
            }
            Section("Counts") {
                LabeledContent("Drill string sections", value: "\(project.drillString.count)")
                LabeledContent("Annulus sections", value: "\(project.annulus.count)")
                LabeledContent("Pressure points", value: "\(project.window.points.count)")
            }
        }
        .navigationTitle("Project Dashboard")
    }
}