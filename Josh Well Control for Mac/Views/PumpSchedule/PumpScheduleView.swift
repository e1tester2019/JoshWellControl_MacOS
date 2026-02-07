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
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectState
    @State private var viewModel = PumpScheduleViewModel()

    // Export state
    @State private var showingExportErrorAlert = false
    @State private var exportErrorMessage = ""

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                PumpScheduleHeaderView(viewModel: viewModel, project: project)
                Spacer()
                Button("Export HTML Report") { exportHTMLReport() }
                    .disabled(viewModel.stages.isEmpty)
            }
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
        .onAppear { viewModel.bootstrap(project: project, context: modelContext) }
        .onChange(of: project) { _, newProject in
            viewModel.bootstrap(project: newProject, context: modelContext)
        }
        .navigationTitle("Pump Schedule")
        .alert("Export Error", isPresented: $showingExportErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportErrorMessage)
        }
    }

    private var maxDepth: Double {
        max(
            (project.annulus ?? []).map { $0.bottomDepth_m }.max() ?? 0,
            (project.drillString ?? []).map { $0.bottomDepth_m }.max() ?? 0
        )
    }
    
    init(project: ProjectState, viewModel: PumpScheduleViewModel = PumpScheduleViewModel()) {
        self._project = Bindable(project)
        self._viewModel = State(initialValue: viewModel)
    }

    // MARK: - Export HTML Report

    private func exportHTMLReport() {
        guard !viewModel.stages.isEmpty else {
            exportErrorMessage = "Build stages first before exporting."
            showingExportErrorAlert = true
            return
        }

        let reportData = buildReportData()
        let htmlContent = PumpScheduleHTMLGenerator.shared.generateHTML(for: reportData)

        let wellName = (project.well?.name ?? "PumpSchedule").replacingOccurrences(of: " ", with: "_")
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStr = dateFormatter.string(from: Date())
        let defaultName = "PumpSchedule_\(wellName)_\(dateStr).html"

        Task {
            let success = await FileService.shared.saveTextFile(
                text: htmlContent,
                defaultName: defaultName,
                allowedFileTypes: ["html"]
            )

            if !success {
                await MainActor.run {
                    exportErrorMessage = "Failed to save HTML report."
                    showingExportErrorAlert = true
                }
            }
        }
    }

    // MARK: - Build Report Data

    private func buildReportData() -> PumpScheduleReportData {
        let bitMD = maxDepth
        let controlMD = viewModel.controlDepthMode == .bit ? bitMD : viewModel.controlMD_m

        // Build geometry sections
        let drillStringSections: [PDFSectionData] = (project.drillString ?? []).sorted { $0.topDepth_m < $1.topDepth_m }.map { ds in
            let id = ds.innerDiameter_m
            let od = ds.outerDiameter_m
            let capacity = .pi * (id * id) / 4.0
            let displacement = .pi * (od * od - id * id) / 4.0
            return PDFSectionData(
                name: ds.name,
                topMD: ds.topDepth_m,
                bottomMD: ds.bottomDepth_m,
                length: ds.length_m,
                innerDiameter: id,
                outerDiameter: od,
                capacity_m3_per_m: capacity,
                displacement_m3_per_m: displacement,
                totalVolume: capacity * ds.length_m
            )
        }

        let drillStringSorted = (project.drillString ?? []).sorted { $0.topDepth_m < $1.topDepth_m }
        func pipeODAtDepth(_ md: Double) -> Double {
            for ds in drillStringSorted {
                if ds.topDepth_m <= md && md <= ds.bottomDepth_m {
                    return ds.outerDiameter_m
                }
            }
            return 0.0
        }

        let annulusSections: [PDFSectionData] = (project.annulus ?? []).sorted { $0.topDepth_m < $1.topDepth_m }.map { ann in
            let holeID = ann.innerDiameter_m
            let midDepth = (ann.topDepth_m + ann.bottomDepth_m) / 2.0
            let pipeOD = pipeODAtDepth(midDepth)
            let capacity = .pi * (holeID * holeID - pipeOD * pipeOD) / 4.0
            return PDFSectionData(
                name: ann.name,
                topMD: ann.topDepth_m,
                bottomMD: ann.bottomDepth_m,
                length: ann.length_m,
                innerDiameter: holeID,
                outerDiameter: pipeOD,
                capacity_m3_per_m: capacity,
                displacement_m3_per_m: 0,
                totalVolume: capacity * ann.length_m
            )
        }

        // Build stage definitions
        let stageDefs: [PumpScheduleReportData.StageDef] = viewModel.stages.map { stage in
            PumpScheduleReportData.StageDef(
                name: stage.name,
                mudName: stage.mud?.name ?? "Unknown",
                mudDensity: stage.mud?.density_kgm3 ?? 1000,
                volume_m3: stage.totalVolume_m3,
                colorHex: colorToHex(stage.color)
            )
        }

        // Build snapshots by iterating through stages and progress
        var snapshots: [PumpScheduleReportData.StageSnapshot] = []

        // Save current state
        let savedStageIndex = viewModel.stageIndex
        let savedProgress = viewModel.progress

        // Generate snapshots: for each stage, sample at 0%, 25%, 50%, 75%, 100%
        var cumulativeVolume: Double = 0

        for stageIdx in 0..<viewModel.stages.count {
            let stage = viewModel.stages[stageIdx]
            let progressSteps: [Double] = [0.0, 0.25, 0.5, 0.75, 1.0]

            for prog in progressSteps {
                viewModel.stageIndex = stageIdx
                viewModel.progress = prog

                let pumpedThisStage = prog * stage.totalVolume_m3
                let cumVolume = cumulativeVolume + pumpedThisStage

                // Get current hydraulics
                let h = viewModel.hydraulicsForCurrent(project: project)

                // Get current stack visualization
                let stacks = viewModel.stacksFor(project: project, stageIndex: stageIdx, pumpedV: pumpedThisStage)

                // Convert segments to fluid layers
                let stringLayers = stacks.string.map { seg in
                    PumpScheduleReportData.StageSnapshot.FluidLayer(
                        topMD: seg.top,
                        bottomMD: seg.bottom,
                        mudName: seg.mud?.name ?? "Unknown",
                        density_kgm3: seg.mud?.density_kgm3 ?? 1000,
                        colorHex: colorToHex(seg.color)
                    )
                }

                let annulusLayers = stacks.annulus.map { seg in
                    PumpScheduleReportData.StageSnapshot.FluidLayer(
                        topMD: seg.top,
                        bottomMD: seg.bottom,
                        mudName: seg.mud?.name ?? "Unknown",
                        density_kgm3: seg.mud?.density_kgm3 ?? 1000,
                        colorHex: colorToHex(seg.color)
                    )
                }

                let snapshot = PumpScheduleReportData.StageSnapshot(
                    stageName: stage.name,
                    stageIndex: stageIdx,
                    progress: prog,
                    pumpedVolume_m3: pumpedThisStage,
                    totalStageVolume_m3: stage.totalVolume_m3,
                    cumulativePumpedVolume_m3: cumVolume,
                    ecd_kgm3: h.ecd_kgm3,
                    bhp_kPa: h.bhp_kPa,
                    sbp_kPa: h.sbp_kPa,
                    tcp_kPa: h.tcp_kPa,
                    annulusFriction_kPa: h.annulusFriction_kPa,
                    stringFriction_kPa: h.stringFriction_kPa,
                    stringLayers: stringLayers,
                    annulusLayers: annulusLayers
                )

                snapshots.append(snapshot)
            }

            cumulativeVolume += stage.totalVolume_m3
        }

        // Restore original state
        viewModel.stageIndex = savedStageIndex
        viewModel.progress = savedProgress

        return PumpScheduleReportData(
            wellName: project.well?.name ?? "Unknown Well",
            projectName: project.name,
            generatedDate: Date(),
            bitMD: bitMD,
            controlMD: controlMD,
            pumpRate_m3permin: viewModel.pumpRate_m3permin,
            mpdEnabled: viewModel.mpdEnabled,
            targetEMD_kgm3: viewModel.targetEMD_kgm3,
            activeMudName: project.activeMud?.name ?? "Active Mud",
            activeMudDensity: project.activeMud?.density_kgm3 ?? 1260,
            snapshots: snapshots,
            stages: stageDefs,
            drillStringSections: drillStringSections,
            annulusSections: annulusSections
        )
    }

    private func colorToHex(_ color: Color) -> String {
        #if os(macOS)
        let nsColor = NSColor(color)
        guard let rgbColor = nsColor.usingColorSpace(.deviceRGB) else {
            return "#888888"
        }
        let r = Int(rgbColor.redComponent * 255)
        let g = Int(rgbColor.greenComponent * 255)
        let b = Int(rgbColor.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
        #else
        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        #endif
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

