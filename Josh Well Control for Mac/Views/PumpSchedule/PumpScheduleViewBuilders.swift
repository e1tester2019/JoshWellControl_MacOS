//
//  PumpScheduleViewBuilders.swift
//  Josh Well Control
//
//  View builders for PumpScheduleView
//

import SwiftUI

// MARK: - Program Stage Row
struct ProgramStageRow: View {
    let stage: PumpScheduleViewModel.ProgramStage
    let muds: [MudProperties]
    let onUpdate: (PumpScheduleViewModel.ProgramStage) -> Void
    let onDelete: () -> Void

    @State private var name: String
    @State private var mudID: UUID?
    @State private var color: Color
    @State private var volume_m3: Double
    @State private var rate_m3min: Double

    init(stage: PumpScheduleViewModel.ProgramStage,
         muds: [MudProperties],
         onUpdate: @escaping (PumpScheduleViewModel.ProgramStage) -> Void,
         onDelete: @escaping () -> Void) {
        self.stage = stage
        self.muds = muds
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        _name = State(initialValue: stage.name)
        _mudID = State(initialValue: stage.mudID)
        _color = State(initialValue: stage.color)
        _volume_m3 = State(initialValue: stage.volume_m3)
        _rate_m3min = State(initialValue: stage.pumpRate_m3permin ?? 0)
    }

    var body: some View {
        let selectedMud = muds.first(where: { $0.id == mudID })
        VStack {
            HStack(spacing: 8) {
                // Color swatch
                Rectangle()
                    .fill(selectedMud?.color ?? color)
                    .frame(width: 18, height: 14)
                    .cornerRadius(3)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.gray.opacity(0.3)))

                // Name
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 160)

                // Mud picker
                Picker("", selection: Binding<UUID?>(
                    get: { mudID },
                    set: { newID in
                        mudID = newID
                        if let id = newID, let m = muds.first(where: { $0.id == id }) {
                            color = m.color
                        }
                        pushUpdate()
                    }
                )) {
                    ForEach(muds, id: \.id) { m in
                        Text("\(m.name): \(Int(m.density_kgm3)) kg/m³").tag(m.id as UUID?)
                    }
                }
                .frame(maxWidth: 240)
                .pickerStyle(.menu)
            }
            HStack (spacing: 12) {
                // Volume
                HStack(spacing: 4) {
                    Text("Volume")
                        .frame(width: 60, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    TextField("m³", value: $volume_m3, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    Text("m³").foregroundStyle(.secondary)
                }

                // Optional per-stage rate
                HStack(spacing: 4) {
                    Text("Rate")
                        .frame(width: 40, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    TextField("m³/min", value: $rate_m3min, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                    Text("m³/min").foregroundStyle(.secondary)
                }

                Spacer()

                Button(role: .destructive) { onDelete() } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete stage")
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.05)))
        .onChange(of: name) { pushUpdate() }
        .onChange(of: volume_m3) { pushUpdate() }
        .onChange(of: rate_m3min) { pushUpdate() }
    }

    private func pushUpdate() {
        let updated = PumpScheduleViewModel.ProgramStage(
            id: stage.id,
            name: name,
            mudID: mudID,
            color: color,
            volume_m3: volume_m3,
            pumpRate_m3permin: rate_m3min
        )
        onUpdate(updated)
    }
}

// MARK: - Header Builder
struct PumpScheduleHeaderView: View {
    @Bindable var viewModel: PumpScheduleViewModel
    let project: ProjectState

    var body: some View {
        HStack(spacing: 12) {
            Text(viewModel.sourceMode == .finalLayers ? "Pump staged parcels from final layers: annulus first, then string." : "Pump program: volume-based stages down the string, up the annulus, to surface.")
                .foregroundStyle(.secondary)
            Picker("Mode", selection: $viewModel.sourceModeRaw) {
                Text("Final Layers").tag(PumpScheduleViewModel.SourceMode.finalLayers.rawValue)
                Text("Program").tag(PumpScheduleViewModel.SourceMode.program.rawValue)
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
            .onChange(of: viewModel.sourceModeRaw) { _, _ in
                viewModel.buildStages(project: project)
            }
            Button("Apply Program") { viewModel.buildStages(project: project) }
                .disabled(viewModel.sourceMode != .program)
            Spacer()
            if let stg = viewModel.currentStage(project: project) {
                Rectangle().fill(stg.color).frame(width: 16, height: 12).cornerRadius(2)
                Text(stg.name).font(.caption)
                Text(stg.side == .annulus ? "Annulus" : "String")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.gray.opacity(0.15)))
                    .foregroundStyle(.secondary)
                Text("\(viewModel.stageDisplayIndex + 1)/\(viewModel.stages.count)").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("No stages").font(.caption).foregroundStyle(.secondary)
            }
            Button(action: { viewModel.prevStageOrWrap() }) { Label("Previous", systemImage: "chevron.left") }
                .disabled(viewModel.stages.isEmpty)
            VStack(alignment: .leading, spacing: 2) {
                Slider(value: $viewModel.progress, in: 0...1)
                    .frame(width: 260)
                HStack(spacing: 6) {
                    if !viewModel.stages.isEmpty {
                        Text("Step \(viewModel.stageDisplayIndex + 1) of \(viewModel.stages.count)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    let pct = viewModel.stages.isEmpty ? 0.0 : viewModel.progress * 100.0
                    Text(String(format: "%.0f%%", pct))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(width: 260)
            }
            Button(action: { viewModel.nextStageOrWrap() }) { Label("Next", systemImage: "chevron.right") }
                .disabled(viewModel.stages.isEmpty)
        }
    }
}

// MARK: - Stage Info Builder
struct PumpScheduleStageInfoView: View {
    @Bindable var viewModel: PumpScheduleViewModel
    let project: ProjectState

    var body: some View {
        GroupBox("Stage Info") {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                if let stg = viewModel.currentStage(project: project) {
                    HStack(spacing: 8) {
                        Rectangle().fill(stg.color).frame(width: 18, height: 14).cornerRadius(3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stg.name).font(.headline)
                            Text(stg.side == .annulus ? "Annulus" : "String").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Divider().frame(height: 28)
                    Group {
                        let totalV: Double = max(0.0, stg.totalVolume_m3)
                        let pumpedV: Double = max(0.0, min(viewModel.progress * totalV, totalV))
                        let remainingV: Double = max(0.0, totalV - pumpedV)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text("Pumped:")
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.2f m³", pumpedV)).monospacedDigit()
                            }
                            HStack(spacing: 8) {
                                Text("Remaining:")
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.2f m³", remainingV)).monospacedDigit()
                            }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text("Total:")
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.2f m³", totalV)).monospacedDigit()
                            }
                            HStack(spacing: 8) {
                                Text("Progress:")
                                    .foregroundStyle(.secondary)
                                let pct: Double = (totalV > 0 ? (pumpedV/totalV) : 0) * 100.0
                                Text(String(format: "%.0f%%", pct)).monospacedDigit()
                            }
                        }
                    }
                    Spacer()
                } else {
                    Text("No stage selected").foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Program Editor Builder
struct PumpScheduleProgramEditorView: View {
    @Bindable var viewModel: PumpScheduleViewModel
    let project: ProjectState

    var body: some View {
        GroupBox("Program Stages (string in)") {
            VStack(alignment: .leading, spacing: 8) {
                if viewModel.program.isEmpty {
                    Text("No program stages. Add one below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(viewModel.program) { stg in
                            let muds = project.muds.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                            ProgramStageRow(
                                stage: stg,
                                muds: muds,
                                onUpdate: { updated in
                                    if let i = viewModel.program.firstIndex(where: { $0.id == updated.id }) {
                                        viewModel.program[i] = updated
                                        viewModel.saveProgram(to: project)
                                    }
                                },
                                onDelete: {
                                    viewModel.program.removeAll { $0.id == stg.id }
                                    viewModel.saveProgram(to: project)
                                }
                            )
                        }
                        .onMove { indices, newOffset in
                            viewModel.program.move(fromOffsets: indices, toOffset: newOffset)
                            viewModel.saveProgram(to: project)
                        }
                        .onDelete { indexSet in
                            viewModel.program.remove(atOffsets: indexSet)
                            viewModel.saveProgram(to: project)
                        }
                    }
                    .frame(maxHeight: 260)
                    .listStyle(.plain)
                }
                HStack(spacing: 8) {
                    Button("Add Stage") {
                        let mud = project.activeMud
                        viewModel.program.append(PumpScheduleViewModel.ProgramStage(
                            id: UUID(),
                            name: "Stage \(viewModel.program.count + 1)",
                            mudID: mud?.id,
                            color: mud?.color ?? .blue,
                            volume_m3: 5.0,
                            pumpRate_m3permin: nil
                        ))
                        viewModel.saveProgram(to: project)
                    }
                    Button("Clear All", role: .destructive) {
                        viewModel.program.removeAll()
                        viewModel.saveProgram(to: project)
                    }
                    Spacer()
                    Button("Apply Program") { viewModel.buildStages(project: project) }
                        .buttonStyle(.borderedProminent)
                }
                .controlSize(.small)
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - All Stages Info Builder
struct PumpScheduleAllStagesView: View {
    @Bindable var viewModel: PumpScheduleViewModel
    let project: ProjectState

    var body: some View {
        GroupBox("All Stages") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(viewModel.stages.indices, id: \.self) { idx in
                    let stg = viewModel.stages[idx]
                    let totalV: Double = max(0.0, stg.totalVolume_m3)
                    let pumpedFrac: Double = idx < viewModel.stageDisplayIndex ? 1.0 : (idx == viewModel.stageDisplayIndex ? max(0.0, min(viewModel.progress, 1.0)) : 0.0)
                    let pumpedV: Double = pumpedFrac * totalV
                    let remainingV: Double = max(0.0, totalV - pumpedV)

                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        HStack(spacing: 8) {
                            Rectangle().fill(stg.color).frame(width: 14, height: 12).cornerRadius(3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stg.name).font(.headline)
                                Text(stg.side == .annulus ? "Annulus" : "String").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Divider().frame(height: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text("Pumped:").foregroundStyle(.secondary)
                                Text(String(format: "%.2f m³", pumpedV)).monospacedDigit()
                            }
                            HStack(spacing: 8) {
                                Text("Remaining:").foregroundStyle(.secondary)
                                Text(String(format: "%.2f m³", remainingV)).monospacedDigit()
                            }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text("Total:").foregroundStyle(.secondary)
                                Text(String(format: "%.2f m³", totalV)).monospacedDigit()
                            }
                            HStack(spacing: 8) {
                                Text("Progress:").foregroundStyle(.secondary)
                                let pct: Double = (totalV > 0 ? pumpedV/totalV : 0) * 100.0
                                Text(String(format: "%.0f%%", pct)).monospacedDigit()
                            }
                        }
                        Spacer()
                        if idx == viewModel.stageDisplayIndex {
                            Text("Current")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        }
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(idx == viewModel.stageDisplayIndex ? Color.accentColor.opacity(0.5) : Color.gray.opacity(0.2), lineWidth: 1))
                }
            }
        }
    }
}

// MARK: - Returns Info Builder
struct PumpScheduleReturnsView: View {
    @Bindable var viewModel: PumpScheduleViewModel
    let project: ProjectState

    var body: some View {
        GroupBox("Returns") {
            VStack(alignment: .leading, spacing: 8) {
                let expelled = viewModel.expelledFluidsForCurrent(project: project)

                ForEach(expelled) { row in
                    HStack {
                        Rectangle()
                            .fill(row.color)
                            .frame(width: 14, height: 12)
                            .cornerRadius(3)
                        Text(row.mudName)
                            .frame(width: 120, alignment: .leading)
                        Spacer()
                        Text(String(format: "%.2f m³", row.volume_m3))
                            .monospacedDigit()
                    }
                }
            }
        }
    }
}

// MARK: - Visualization Builder
struct PumpScheduleVisualizationView: View {
    @Bindable var viewModel: PumpScheduleViewModel
    let project: ProjectState
    let maxDepth: Double

    var body: some View {
        GroupBox("Well Snapshot") {
            GeometryReader { geo in
                let stage = viewModel.currentStage(project: project)
                let totalV = stage?.totalVolume_m3 ?? 0
                let pumpedV = max(0.0, min(viewModel.progress * max(totalV, 0), totalV))
                Canvas { ctx, size in
                    let stacks = viewModel.stacksFor(project: project, stageIndex: viewModel.stageDisplayIndex, pumpedV: pumpedV)
                    let stringSegs: [Seg] = stacks.string.map { Seg(topMD: $0.top, bottomMD: $0.bottom, color: $0.color, mud: $0.mud) }
                    let annulusSegs: [Seg] = stacks.annulus.map { Seg(topMD: $0.top, bottomMD: $0.bottom, color: $0.color, mud: $0.mud) }

                    // Draw columns
                    let bitMD = maxDepth
                    let gap: CGFloat = 8
                    let colW = (size.width - 2*gap) / 3
                    let annLeft  = CGRect(x: 0, y: 0, width: colW, height: size.height)
                    let strRect  = CGRect(x: colW + gap, y: 0, width: colW, height: size.height)
                    let annRight = CGRect(x: 2*(colW + gap), y: 0, width: colW, height: size.height)

                    func yGlobal(_ md: Double) -> CGFloat {
                        guard bitMD > 0 else { return 0 }
                        return CGFloat(md / bitMD) * size.height
                    }

                    drawColumn(&ctx, layers: annulusSegs, in: annLeft, yGlobal: yGlobal)
                    drawColumn(&ctx, layers: stringSegs, in: strRect, yGlobal: yGlobal)
                    drawColumn(&ctx, layers: annulusSegs, in: annRight, yGlobal: yGlobal)

                    ctx.draw(Text("Annulus"), at: CGPoint(x: annLeft.midX,  y: 12))
                    ctx.draw(Text("String"),  at: CGPoint(x: strRect.midX,  y: 12))
                    ctx.draw(Text("Annulus"), at: CGPoint(x: annRight.midX, y: 12))

                    // Depth ticks
                    let tickCount = 6
                    for i in 0...tickCount {
                        let md = Double(i) / Double(tickCount) * bitMD
                        let yy = yGlobal(md)
                        let tvd = project.tvd(of: md)
                        ctx.fill(Path(CGRect(x: size.width - 10, y: yy - 0.5, width: 10, height: 1)), with: .color(.secondary))
                        ctx.draw(Text(String(format: "%.0f", md)), at: CGPoint(x: size.width - 12, y: yy - 6), anchor: .trailing)
                        ctx.fill(Path(CGRect(x: 0, y: yy - 0.5, width: 10, height: 1)), with: .color(.secondary))
                        ctx.draw(Text(String(format: "%.0f", tvd)), at: CGPoint(x: 12, y: yy - 6), anchor: .leading)
                    }
                }
            }
            .frame(minHeight: 260)
        }
        .frame(maxWidth: 900)
    }

    private func drawColumn(_ ctx: inout GraphicsContext, layers: [Seg], in rect: CGRect, yGlobal: (Double)->CGFloat) {
        for L in layers {
            let yTop = yGlobal(L.topMD)
            let yBot = yGlobal(L.bottomMD)
            let yMin = min(yTop, yBot)
            let h = max(1, abs(yBot - yTop))
            let sub = CGRect(x: rect.minX, y: yMin, width: rect.width, height: h)
            ctx.fill(Path(sub), with: .color(L.color))
        }
        ctx.stroke(Path(rect), with: .color(.black.opacity(0.8)), lineWidth: 1)
    }
}

// MARK: - Hydraulics Panel Builder
struct PumpScheduleHydraulicsPanelView: View {
    @Bindable var viewModel: PumpScheduleViewModel
    let project: ProjectState

    var body: some View {
        GroupBox("Hydraulics") {
            VStack(alignment: .leading, spacing: 10) {
                // Inputs
                HStack {
                    Text("Pump rate")
                        .frame(width: 120, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    TextField("m³/min", value: $viewModel.pumpRate_m3permin, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .monospacedDigit()
                    Text("m³/min").foregroundStyle(.secondary)
                }
                Toggle("Managed pressure drilling (MPD)", isOn: $viewModel.mpdEnabled)
                HStack {
                    Text("Target EMD")
                        .frame(width: 120, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    TextField("kg/m³", value: $viewModel.targetEMD_kgm3, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .monospacedDigit()
                    Text("kg/m³").foregroundStyle(.secondary)
                }
                Picker("Control depth", selection: $viewModel.controlDepthModeRaw) {
                        Text("Bit").tag(0)
                        Text("Custom").tag(1)
                    }
                    .pickerStyle(.segmented)

                HStack {
                    Text("Control MD")
                        .frame(width: 120, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    TextField("m", value: $viewModel.controlMD_m, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .monospacedDigit()
                    Text("m").foregroundStyle(.secondary)
                }
                .disabled(viewModel.controlDepthMode != .custom)

                let controlMDForDisplay = (viewModel.controlDepthMode == .bit) ? viewModel.maxDepthMD(project: project) : viewModel.controlMD_m
                let controlTVDForDisplay = project.tvd(of: controlMDForDisplay)
                HStack {
                    Text("Control TVD").frame(width: 120, alignment: .trailing).foregroundStyle(.secondary)
                    Text(String(format: "%.0f m", controlTVDForDisplay)).monospacedDigit()
                }
                Divider()
                #if DEBUG
                Button("Debug Annulus Stack (Visual HP)") {
                    viewModel.debugCurrentAnnulus(project: project)
                }
                .buttonStyle(.bordered)
                #endif
                #if DEBUG
                Button("Export Debug Log") {
                    viewModel.exportAnnulusDebugLog(project: project)
                }
                .buttonStyle(.bordered)
                #endif
                // Outputs
                let h = viewModel.hydraulicsForCurrent(project: project)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Hydrostatic Annulus")
                            .frame(width: 140, alignment: .trailing)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.0f kPa", (h.annulusAtControl_Pa - h.annulusFriction_kPa * 1000.0 - h.sbp_kPa * 1000.0) / 1000.0))
                            .monospacedDigit()
                    }
                    HStack {
                        Text("Friction (annulus)")
                            .frame(width: 140, alignment: .trailing)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.0f kPa", h.annulusFriction_kPa)).monospacedDigit()
                    }
                    HStack {
                        Text("Hydrostatic String")
                            .frame(width: 140, alignment: .trailing)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.0f kPa", (h.stringAtControl_Pa - h.stringFriction_kPa * 1000.0) / 1000.0))
                            .monospacedDigit()
                    }
                    HStack {
                        Text("Friction (string)")
                            .frame(width: 140, alignment: .trailing)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.0f kPa", h.stringFriction_kPa)).monospacedDigit()
                    }
                    HStack {
                        Text("Total friction")
                            .frame(width: 140, alignment: .trailing)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.0f kPa", h.totalFriction_kPa)).monospacedDigit()
                    }
                    HStack {
                        Text("Annulus at control")
                            .frame(width: 140, alignment: .trailing)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.0f kPa", h.annulusAtControl_Pa / 1000.0)).monospacedDigit()
                    }
                    HStack {
                        Text("String at control")
                            .frame(width: 140, alignment: .trailing)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.0f kPa", h.stringAtControl_Pa / 1000.0)).monospacedDigit()
                    }
                    Divider()
                    HStack {
                        Text("SBP")
                            .frame(width: 140, alignment: .trailing)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.0f kPa", h.sbp_kPa)).monospacedDigit()
                    }
                    Divider()
                    HStack {
                        Text("BHP")
                            .frame(width: 140, alignment: .trailing)
                            .font(.headline)
                        Text(String(format: "%.0f kPa", h.bhp_kPa))
                            .font(.headline)
                            .monospacedDigit()
                    }
                    HStack {
                        Text("TCP (total circ)")
                            .frame(width: 140, alignment: .trailing)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.0f kPa", h.tcp_kPa)).monospacedDigit()
                    }
                    HStack {
                        Text("ECD")
                            .frame(width: 140, alignment: .trailing)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.0f kg/m³", h.ecd_kgm3)).monospacedDigit()
                    }
                }
            }
            .padding(4)
        }
    }
}

// MARK: - Supporting Types
private struct Seg {
    var topMD: Double
    var bottomMD: Double
    var color: Color
    var mud: MudProperties?
}
