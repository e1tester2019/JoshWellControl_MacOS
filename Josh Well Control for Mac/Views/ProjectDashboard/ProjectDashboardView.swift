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
    @State private var viewmodel: ViewModel

    init(project: ProjectState) {
        self._project = Bindable(wrappedValue: project)
        _viewmodel = State(initialValue: ViewModel(project: project))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Project Dashboard")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Curate project inputs, system defaults, and a snapshot of the work already captured.")
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16)], spacing: 16) {
                    WellSection(title: "Project", icon: "target", subtitle: "Name and pressure window safety margins.") {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                            GridRow {
                                Text("Name")
                                    .frame(width: 140, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                                TextField("Project name", text: $project.name)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 360)
                            }
                            GridRow {
                                Text("Pore safety (kPa)")
                                    .frame(width: 140, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                                TextField("", value: $project.window.poreSafety_kPa, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 160)
                                    .monospacedDigit()
                            }
                            GridRow {
                                Text("Frac safety (kPa)")
                                    .frame(width: 140, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                                TextField("", value: $project.window.fracSafety_kPa, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 160)
                                    .monospacedDigit()
                            }
                        }
                    }

                    WellSection(title: "Active System", icon: "drop.fill", subtitle: "Current active pit & surface volumes.") {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                            GridRow {
                                Text("Active mud weight (kg/m³)")
                                    .frame(width: 220, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                                TextField("", value: $project.activeMudDensity_kgm3, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 160)
                                    .monospacedDigit()
                            }
                            GridRow {
                                Text("Active mud volume (m³)")
                                    .frame(width: 220, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                                TextField("", value: $project.activeMudVolume_m3, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 160)
                                    .monospacedDigit()
                            }
                            GridRow {
                                Text("Surface line volume (m³)")
                                    .frame(width: 220, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                                TextField("", value: $project.surfaceLineVolume_m3, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 160)
                                    .monospacedDigit()
                            }
                        }
                    }

                    WellSection(title: "Defaults", icon: "slider.horizontal.3", subtitle: "Column densities and control depth seeds.") {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                            GridRow {
                                Text("Base annulus density (kg/m³)")
                                    .frame(width: 220, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                                TextField("", value: $project.baseAnnulusDensity_kgm3, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 160)
                                    .monospacedDigit()
                            }
                            GridRow {
                                Text("Base string density (kg/m³)")
                                    .frame(width: 220, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                                TextField("", value: $project.baseStringDensity_kgm3, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 160)
                                    .monospacedDigit()
                            }
                            GridRow {
                                Text("Control measured depth (m)")
                                    .frame(width: 220, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                                TextField("", value: $project.pressureDepth_m, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 160)
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
        .background(Color(nsColor: .underPageBackgroundColor))
        .navigationTitle("Project Dashboard")
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
        [ds1, ds2].forEach { s in p.drillString.append(s); ctx.insert(s) }

        let a1 = AnnulusSection(name: "Surface", topDepth_m: 0,    length_m: 600, innerDiameter_m: 0.340, outerDiameter_m: 0.244)
        let a2 = AnnulusSection(name: "Intermediate", topDepth_m: 600, length_m: 900, innerDiameter_m: 0.244, outerDiameter_m: 0.1778)
        [a1, a2].forEach { s in s.project = p; p.annulus.append(s); ctx.insert(s) }

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
            .frame(width: 900, height: 600)
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
    @Observable
    class ViewModel {
        var project: ProjectState
        init(project: ProjectState) { self.project = project }

        var drillStringCount: Int { project.drillString.count }
        var annulusCount: Int { project.annulus.count }
        var pressurePointCount: Int { project.window.points.count }
        var surveysCount: Int { project.surveys.count }
        var mudChecksCount: Int { project.muds.count }
    }
}
