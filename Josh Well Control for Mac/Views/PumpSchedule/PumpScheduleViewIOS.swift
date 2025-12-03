//
//  PumpScheduleViewIOS.swift
//  Josh Well Control
//
//  iPad-optimized pump schedule simulation view with responsive layouts
//

import SwiftUI
import SwiftData
import Observation

struct PumpScheduleViewIOS: View {
    @Bindable var project: ProjectState
    @State private var viewModel = PumpScheduleViewModel()

    var body: some View {
        GeometryReader { geo in
            let isPortrait = geo.size.height > geo.size.width
            let isNarrow = geo.size.width < 700
            
            if isPortrait || isNarrow {
                // PORTRAIT or NARROW: Stack everything vertically
                portraitLayout(geo: geo)
            } else {
                // LANDSCAPE: Side-by-side layout
                landscapeLayout(geo: geo)
            }
        }
        .onAppear { viewModel.bootstrap(project: project) }
    }
    
    // MARK: - Portrait Layout
    private func portraitLayout(geo: GeometryProxy) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                // Compact header
                compactHeaderView
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                
                Divider()
                
                // Stage info
                PumpScheduleStageInfoView(viewModel: viewModel, project: project)
                    .padding(.horizontal, 16)
                
                // Visualization
                PumpScheduleVisualizationView(viewModel: viewModel, project: project, maxDepth: maxDepth)
                    .frame(height: 400)
                    .padding(.horizontal, 16)
                
                Divider()
                
                // Hydraulics panel
                PumpScheduleHydraulicsPanelView(viewModel: viewModel, project: project)
                    .padding(.horizontal, 16)
                
                Divider()
                
                // Program editor (if in program mode)
                if viewModel.sourceMode == .program {
                    PumpScheduleProgramEditorView(viewModel: viewModel, project: project)
                        .padding(.horizontal, 16)
                }
                
                // All stages
                PumpScheduleAllStagesView(viewModel: viewModel, project: project)
                    .padding(.horizontal, 16)
                
                // Returns
                PumpScheduleReturnsView(viewModel: viewModel, project: project)
                    .padding(.horizontal, 16)
            }
            .padding(.bottom, 16)
        }
    }
    
    // MARK: - Landscape Layout
    private func landscapeLayout(geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Header at top - compact and fixed height
            ScrollView {
                VStack(spacing: 12) {
                    compactHeaderView
                        .padding(.top, 12)
                    
                    PumpScheduleStageInfoView(viewModel: viewModel, project: project)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .frame(height: 170) // Reduced from 200 due to more compact header
            
            Divider()
            
            // Main content area
            HStack(alignment: .top, spacing: 0) {
                // LEFT SIDE: Controls and lists (50% width)
                ScrollView {
                    VStack(spacing: 16) {
                        if viewModel.sourceMode == .program {
                            PumpScheduleProgramEditorView(viewModel: viewModel, project: project)
                        }
                        PumpScheduleAllStagesView(viewModel: viewModel, project: project)
                        PumpScheduleReturnsView(viewModel: viewModel, project: project)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
                .frame(maxWidth: .infinity)
                
                Divider()
                
                // RIGHT SIDE: Visualization and hydraulics (50% width)
                ScrollView {
                    VStack(spacing: 16) {
                        PumpScheduleVisualizationView(viewModel: viewModel, project: project, maxDepth: maxDepth)
                            .frame(height: max(300, geo.size.height - 230))
                        
                        PumpScheduleHydraulicsPanelView(viewModel: viewModel, project: project)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    // MARK: - Compact Header View
    private var compactHeaderView: some View {
        VStack(spacing: 10) {
            // Mode selector and apply button in single row
            HStack(spacing: 12) {
                Picker("Mode", selection: $viewModel.sourceModeRaw) {
                    Text("Final Layers").tag(PumpScheduleViewModel.SourceMode.finalLayers.rawValue)
                    Text("Program").tag(PumpScheduleViewModel.SourceMode.program.rawValue)
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.sourceModeRaw) { _, _ in
                    viewModel.buildStages(project: project)
                }
                
                if viewModel.sourceMode == .program {
                    Button("Apply Program") {
                        viewModel.buildStages(project: project)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            
            // Current stage indicator - compact
            if let stg = viewModel.currentStage(project: project) {
                HStack(spacing: 6) {
                    Rectangle().fill(stg.color).frame(width: 14, height: 10).cornerRadius(2)
                    Text(stg.name).font(.caption).fontWeight(.medium)
                    Text(stg.side == .annulus ? "Ann" : "Str")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color(uiColor: .secondarySystemGroupedBackground)))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(viewModel.stageDisplayIndex + 1)/\(viewModel.stages.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Navigation controls - compact single row
            HStack(spacing: 8) {
                Button(action: { viewModel.prevStageOrWrap() }) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.stages.isEmpty)
                
                // Slider with inline labels
                VStack(spacing: 2) {
                    Slider(value: $viewModel.progress, in: 0...1)
                    
                    HStack(spacing: 6) {
                        if !viewModel.stages.isEmpty {
                            Text("Step \(viewModel.stageDisplayIndex + 1)/\(viewModel.stages.count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        let pct = viewModel.stages.isEmpty ? 0.0 : viewModel.progress * 100.0
                        Text(String(format: "%.0f%%", pct))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Button(action: { viewModel.nextStageOrWrap() }) {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.stages.isEmpty)
            }
        }
        .frame(height: 90) // Fixed height to prevent growing
    }
    
    // MARK: - Helper Properties
    private var maxDepth: Double {
        max(
            (project.annulus ?? []).map { $0.bottomDepth_m }.max() ?? 0,
            (project.drillString ?? []).map { $0.bottomDepth_m }.max() ?? 0
        )
    }
}

#if DEBUG
import SwiftData
struct PumpScheduleViewIOS_Previews: PreviewProvider {
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
        p.annulus?.append(contentsOf: [a,b])
        ctx.insert(a); ctx.insert(b)
        
        let ds = DrillStringSection(name: "4\" DP", topDepth_m: 0, length_m: 5200, outerDiameter_m: 0.1016, innerDiameter_m: 0.0803)
        ds.project = p
        if p.drillString == nil { p.drillString = [] }
        p.drillString?.append(ds)
        ctx.insert(ds)
        
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
        
        return Group {
            PumpScheduleViewIOS(project: p)
                .modelContainer(container)
                .previewDisplayName("iPad Landscape")
                .previewInterfaceOrientation(.landscapeLeft)
                .frame(width: 1194, height: 834)
            
            PumpScheduleViewIOS(project: p)
                .modelContainer(container)
                .previewDisplayName("iPad Portrait")
                .previewInterfaceOrientation(.portrait)
                .frame(width: 834, height: 1194)
        }
    }
}
#endif
