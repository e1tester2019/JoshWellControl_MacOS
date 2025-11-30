//
//  PumpScheduleView.swift
//  Josh Well Control
//
//  Pump schedule simulation view
//

import SwiftUI
import SwiftData
import Observation

struct PumpScheduleView: View {
    @Bindable var project: ProjectState
    @State private var viewModel = PumpScheduleViewModel()

    var body: some View {
        VStack(spacing: 12) {
            PumpScheduleHeaderView(viewModel: viewModel, project: project)
            PumpScheduleStageInfoView(viewModel: viewModel, project: project)

            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 12) {
                    if viewModel.sourceMode == .program {
                        PumpScheduleProgramEditorView(viewModel: viewModel, project: project)
                    }
                    PumpScheduleAllStagesView(viewModel: viewModel, project: project)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    PumpScheduleReturnsView(viewModel: viewModel, project: project)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                HStack(alignment: .top, spacing: 12) {
                    PumpScheduleVisualizationView(viewModel: viewModel, project: project, maxDepth: maxDepth)
                        .frame(maxWidth: 900)
                    PumpScheduleHydraulicsPanelView(viewModel: viewModel, project: project)
                        .frame(width: 320)
                }
            }
            Divider()
        }
        .padding(12)
        .onAppear { viewModel.bootstrap(project: project) }
        .navigationTitle("Pump Schedule")
    }

    private var maxDepth: Double {
        max(
            (project.annulus ?? []).map { $0.bottomDepth_m }.max() ?? 0,
            (project.drillString ?? []).map { $0.bottomDepth_m }.max() ?? 0
        )
    }
}

#if DEBUG
import SwiftData
struct PumpSchedule_Previews: PreviewProvider {
    static var previews: some View {
        let container = try! ModelContainer(
            for: ProjectState.self,
                 FinalFluidLayer.self,
                 AnnulusSection.self,
                 DrillStringSection.self,
                 MudProperties.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let ctx = container.mainContext
        let p = ProjectState()
        ctx.insert(p)
        // Geometry
        let a = AnnulusSection(name: "Casing", topDepth_m: 0, length_m: 800, innerDiameter_m: 0.244, outerDiameter_m: 0)
        let b = AnnulusSection(name: "OpenHole", topDepth_m: 800, length_m: 5200 - 800, innerDiameter_m: 0.159, outerDiameter_m: 0)
        a.project = p; b.project = p
        if p.annulus == nil { p.annulus = [] }
        p.annulus?.append(contentsOf: [a,b]); ctx.insert(a); ctx.insert(b)
        let ds = DrillStringSection(name: "4\" DP", topDepth_m: 0, length_m: 5200, outerDiameter_m: 0.1016, innerDiameter_m: 0.0803)
        ds.project = p
        if p.drillString == nil { p.drillString = [] }
        p.drillString?.append(ds); ctx.insert(ds)
        // Muds
        let active = MudProperties(name: "Active", density_kgm3: 1260, color: .yellow, project: p)
        active.isActive = true
        let heavy = MudProperties(name: "Heavy", density_kgm3: 1855, color: .red, project: p)
        if p.muds == nil { p.muds = [] }
        p.muds?.append(contentsOf: [active, heavy])
        ctx.insert(active); ctx.insert(heavy)
        // Final layers
        let ann1 = FinalFluidLayer(project: p, name: "Annulus ECD Mud", placement: .annulus, topMD_m: 800, bottomMD_m: 1500, density_kgm3: 1855, color: .red, mud: heavy)
        let ann2 = FinalFluidLayer(project: p, name: "Base", placement: .annulus, topMD_m: 0, bottomMD_m: 800, density_kgm3: 1260, color: .yellow, mud: active)
        let str1 = FinalFluidLayer(project: p, name: "Air", placement: .string, topMD_m: 0, bottomMD_m: 320, density_kgm3: 1, color: .white, mud: nil)
        let str2 = FinalFluidLayer(project: p, name: "Base", placement: .string, topMD_m: 320, bottomMD_m: 5200, density_kgm3: 1260, color: .yellow, mud: active)
        ctx.insert(ann1); ctx.insert(ann2); ctx.insert(str1); ctx.insert(str2)
        try? ctx.save()
        return PumpScheduleView(project: p).modelContainer(container).frame(width: 900, height: 520)
    }
}
#endif
