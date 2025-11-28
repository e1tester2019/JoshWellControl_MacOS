import SwiftUI
import SwiftData
import Observation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct PumpScheduleView: View {
    @Bindable var project: ProjectState
    @State private var vm = ViewModel()

    var body: some View {
        VStack(spacing: 12) {
            header
            stageInfo
            if vm.sourceMode == .program {
                programEditor
            }
            HStack(alignment: .top, spacing: 12) {
                allStagesInfo.frame(maxWidth: .infinity, alignment: .topLeading)
                visualization.frame(maxWidth: 900)
                hydraulicsPanel.frame(width: 320)
            }
            Divider()
        }
        .padding(12)
        .onAppear { vm.bootstrap(project: project) }
        .navigationTitle("Pump Schedule")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(vm.sourceMode == .finalLayers ? "Pump staged parcels from final layers: annulus first, then string." : "Pump program: volume-based stages down the string, up the annulus, to surface.")
                .foregroundStyle(.secondary)
            Picker("Mode", selection: $vm.sourceModeRaw) {
                Text("Final Layers").tag(PumpScheduleView.ViewModel.SourceMode.finalLayers.rawValue)
                Text("Program").tag(PumpScheduleView.ViewModel.SourceMode.program.rawValue)
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
            .onChange(of: vm.sourceModeRaw) { _, _ in
                vm.buildStages(project: project)
            }
            Button("Apply Program") { vm.buildStages(project: project) }
                .disabled(vm.sourceMode != .program)
            Spacer()
            if let stg = vm.currentStage(project: project) {
                Rectangle().fill(stg.color).frame(width: 16, height: 12).cornerRadius(2)
                Text(stg.name).font(.caption)
                Text(stg.side == .annulus ? "Annulus" : "String")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.gray.opacity(0.15)))
                    .foregroundStyle(.secondary)
                Text("\(vm.stageDisplayIndex + 1)/\(vm.stages.count)").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("No stages").font(.caption).foregroundStyle(.secondary)
            }
            Button(action: { vm.prevStageOrWrap() }) { Label("Previous", systemImage: "chevron.left") }
                .disabled(vm.stages.isEmpty)
            VStack(alignment: .leading, spacing: 2) {
                Slider(value: $vm.progress, in: 0...1)
                    .frame(width: 260)
                HStack(spacing: 6) {
                    if !vm.stages.isEmpty {
                        Text("Step \(vm.stageDisplayIndex + 1) of \(vm.stages.count)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    let pct = vm.stages.isEmpty ? 0.0 : vm.progress * 100.0
                    Text(String(format: "%.0f%%", pct))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(width: 260)
            }
            Button(action: { vm.nextStageOrWrap() }) { Label("Next", systemImage: "chevron.right") }
                .disabled(vm.stages.isEmpty)
        }
    }

    private var stageInfo: some View {
        GroupBox("Stage Info") {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                if let stg = vm.currentStage(project: project) {
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
                        let pumpedV: Double = max(0.0, min(vm.progress * totalV, totalV))
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

    private var programEditor: some View {
        GroupBox("Program Stages (string in)") {
            VStack(alignment: .leading, spacing: 8) {
                if vm.program.isEmpty {
                    Text("No program stages. Add one below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(vm.program) { stg in
                            let muds = project.muds.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                            ProgramStageRow(
                                stage: stg,
                                muds: muds,
                                onUpdate: { updated in
                                    if let i = vm.program.firstIndex(where: { $0.id == updated.id }) {
                                        vm.program[i] = updated
                                        vm.saveProgram(to: project)
                                    }
                                },
                                onDelete: {
                                    vm.program.removeAll { $0.id == stg.id }
                                    vm.saveProgram(to: project)
                                }
                            )
                        }
                        .onMove { indices, newOffset in
                            vm.program.move(fromOffsets: indices, toOffset: newOffset)
                            vm.saveProgram(to: project)
                        }
                        .onDelete { indexSet in
                            vm.program.remove(atOffsets: indexSet)
                            vm.saveProgram(to: project)
                        }
                    }
                    .frame(maxHeight: 260)
                    .listStyle(.plain)
                }
                HStack(spacing: 8) {
                    Button("Add Stage") {
                        let mud = project.activeMud
                        vm.program.append(ViewModel.ProgramStage(
                            id: UUID(),
                            name: "Stage \(vm.program.count + 1)",
                            mudID: mud?.id,
                            color: mud?.color ?? .blue,
                            volume_m3: 5.0,
                            pumpRate_m3permin: nil
                        ))
                        vm.saveProgram(to: project)
                    }
                    Button("Clear All", role: .destructive) {
                        vm.program.removeAll()
                        vm.saveProgram(to: project)
                    }
                    Spacer()
                    Button("Apply Program") { vm.buildStages(project: project) }
                        .buttonStyle(.borderedProminent)
                }
                .controlSize(.small)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Program Stage Row (isolated to keep bindings simple for the compiler)
    private struct ProgramStageRow: View {
        let stage: PumpScheduleView.ViewModel.ProgramStage
        let muds: [MudProperties]
        let onUpdate: (PumpScheduleView.ViewModel.ProgramStage) -> Void
        let onDelete: () -> Void

        @State private var name: String
        @State private var mudID: UUID?
        @State private var color: Color
        @State private var volume_m3: Double
        @State private var rate_m3min: Double

        init(stage: PumpScheduleView.ViewModel.ProgramStage,
             muds: [MudProperties],
             onUpdate: @escaping (PumpScheduleView.ViewModel.ProgramStage) -> Void,
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
            HStack(spacing: 8) {
                // Color swatch (mud color if selected, otherwise stage color)
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
                .frame(width: 240)
                .pickerStyle(.menu)

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

                Button(role: .destructive) { onDelete() } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete stage")
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.05)))
            .onChange(of: name) { _ in pushUpdate() }
            .onChange(of: volume_m3) { _ in pushUpdate() }
            .onChange(of: rate_m3min) { _ in pushUpdate() }
        }

        private func pushUpdate() {
            let updated = PumpScheduleView.ViewModel.ProgramStage(
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

    private var allStagesInfo: some View {
        GroupBox("All Stages") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(vm.stages.indices, id: \.self) { idx in
                    let stg = vm.stages[idx]
                    // Compute pumped/remaining for this stage based on current index/progress
                    let totalV: Double = max(0.0, stg.totalVolume_m3)
                    let pumpedFrac: Double = idx < vm.stageDisplayIndex ? 1.0 : (idx == vm.stageDisplayIndex ? max(0.0, min(vm.progress, 1.0)) : 0.0)
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
                        if idx == vm.stageDisplayIndex {
                            Text("Current")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        }
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(idx == vm.stageDisplayIndex ? Color.accentColor.opacity(0.5) : Color.gray.opacity(0.2), lineWidth: 1))
                }
            }
        }
    }

    /*
    private var stepsStrip: some View {
        GroupBox("Stages") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: 12) {
                    ForEach(vm.stages.indices, id: \.self) { idx in
                        let stg = vm.stages[idx]
                        Button(action: { vm.stageIndex = idx; vm.progress = 0 }) {
                            HStack(spacing: 8) {
                                ZStack {
                                    Circle().fill(idx == vm.stageDisplayIndex ? stg.color.opacity(0.9) : stg.color.opacity(0.5))
                                        .frame(width: 22, height: 22)
                                    Text("\(idx + 1)")
                                        .font(.caption2).bold()
                                        .foregroundStyle(.white)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stg.name)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Text(stg.side == .annulus ? "Annulus" : "String")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(idx == vm.stageDisplayIndex ? Color.accentColor.opacity(0.08) : Color.gray.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(idx == vm.stageDisplayIndex ? Color.accentColor.opacity(0.5) : Color.gray.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
    */

    private var visualization: some View {
        GroupBox("Well Snapshot") {
            GeometryReader { geo in
                let stage = vm.currentStage(project: project)
                let totalV = stage?.totalVolume_m3 ?? 0
                let pumpedV = max(0.0, min(vm.progress * max(totalV, 0), totalV))
                Canvas { ctx, size in
                    let stacks = vm.stacksFor(project: project, stageIndex: vm.stageDisplayIndex, pumpedV: pumpedV)
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

                    // Depth ticks (MD right, TVD left)
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

    private var hydraulicsPanel: some View {
        GroupBox("Hydraulics") {
            VStack(alignment: .leading, spacing: 10) {
                // Inputs
                HStack {
                    Text("Pump rate")
                        .frame(width: 120, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    TextField("m³/min", value: $vm.pumpRate_m3permin, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .monospacedDigit()
                    Text("m³/min").foregroundStyle(.secondary)
                }
                Toggle("Managed pressure drilling (MPD)", isOn: $vm.mpdEnabled)
                HStack {
                    Text("Target EMD")
                        .frame(width: 120, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    TextField("kg/m³", value: $vm.targetEMD_kgm3, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .monospacedDigit()
                    Text("kg/m³").foregroundStyle(.secondary)
                }
                Picker("Control depth", selection: $vm.controlDepthModeRaw) {
                        Text("Bit").tag(0)
                        Text("Custom").tag(1)
                    }
                    .pickerStyle(.segmented)

                HStack {
                    Text("Control MD")
                        .frame(width: 120, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    TextField("m", value: $vm.controlMD_m, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .monospacedDigit()
                    Text("m").foregroundStyle(.secondary)
                }
                .disabled(vm.controlDepthMode != .custom)
                
                let controlMDForDisplay = (vm.controlDepthMode == .bit) ? vm.maxDepthMD(project: project) : vm.controlMD_m
                let controlTVDForDisplay = project.tvd(of: controlMDForDisplay)
                HStack {
                    Text("Control TVD").frame(width: 120, alignment: .trailing).foregroundStyle(.secondary)
                    Text(String(format: "%.0f m", controlTVDForDisplay)).monospacedDigit()
                }
                Divider()
#if DEBUG
Button("Debug Annulus Stack (Visual HP)") {
    vm.debugCurrentAnnulus(project: project)
}
.buttonStyle(.bordered)
#endif
#if DEBUG
Button("Export Debug Log") {
    vm.exportAnnulusDebugLog(project: project)
}
.buttonStyle(.bordered)
#endif
                // Outputs
                let h = vm.hydraulicsForCurrent(project: project)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Hydrostatic Annulus")
                            .frame(width: 140, alignment: .trailing)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.0f kPa", (h.annulusAtControl_Pa - h.annulusFriction_kPa * 1000.0 - h.sbp_kPa * 1000.0) / 1000.0)) // show hydrostatic-only
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
                        Text(String(format: "%.0f kPa", (h.stringAtControl_Pa - h.stringFriction_kPa * 1000.0) / 1000.0)) // show hydrostatic-only
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
                        // hydrostatic + friction + SBP
                        Text(String(format: "%.0f kPa", h.annulusAtControl_Pa / 1000.0)).monospacedDigit()
                    }
                    HStack {
                        Text("String at control")
                            .frame(width: 140, alignment: .trailing)
                            .foregroundStyle(.secondary)
                        // hydrostatic + friction (no SBP on string side)
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

    private var maxDepth: Double {
        max(
            project.annulus.map { $0.bottomDepth_m }.max() ?? 0,
            project.drillString.map { $0.bottomDepth_m }.max() ?? 0
        )
    }

    // MARK: - Layer building
    private struct Layer { var topMD: Double; var bottomMD: Double; var color: Color }

    // MARK: - Stack for volume displacement model visualization
    private struct Seg {
        var topMD: Double
        var bottomMD: Double
        var color: Color
        var mud: MudProperties?
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

    // MARK: - VM
    @Observable
    class ViewModel {
        enum Side { case annulus, string }
        struct Stage {
            let name: String
            let color: Color
            let totalVolume_m3: Double
            let side: Side
            let mud: MudProperties?
        }
        var stages: [Stage] = []
        var stageIndex: Int = 0
        var progress: Double = 0
        var stageDisplayIndex: Int { min(max(stageIndex, 0), max(stages.count - 1, 0)) }

        // Hydraulics inputs
        var pumpRate_m3permin: Double = 0.50
        var mpdEnabled: Bool = false
        var targetEMD_kgm3: Double = 1300
        var controlMD_m: Double = 0

        enum ControlDepthMode: Int, Codable { case bit = 0, custom }
        var controlDepthModeRaw: Int = ControlDepthMode.bit.rawValue
        var controlDepthMode: ControlDepthMode { get { ControlDepthMode(rawValue: controlDepthModeRaw) ?? .bit } set { controlDepthModeRaw = newValue.rawValue } }

        // Source mode: build from final layers (existing) or from a custom program of volume-based stages
        enum SourceMode: Int, Codable { case finalLayers = 0, program = 1 }
        var sourceModeRaw: Int = SourceMode.finalLayers.rawValue
        var sourceMode: SourceMode {
            get { SourceMode(rawValue: sourceModeRaw) ?? .finalLayers }
            set { sourceModeRaw = newValue.rawValue }
        }

        // Program stages (volume-based) to pump down the string
        struct ProgramStage: Identifiable {
            let id: UUID
            var name: String
            var mudID: UUID?
            var color: Color
            var volume_m3: Double
            var pumpRate_m3permin: Double?
        }
        var program: [ProgramStage] = []

        func loadProgram(from project: ProjectState) {
            program = project.programStages
                .sorted { $0.orderIndex < $1.orderIndex }
                .map { s in
                    ProgramStage(
                        id: s.id,
                        name: s.name,
                        mudID: s.mud?.id,
                        color: s.color,
                        volume_m3: s.volume_m3,
                        pumpRate_m3permin: s.pumpRate_m3permin
                    )
                }
        }

        func saveProgram(to project: ProjectState) {
            // Build a lookup of existing models by id
            var byID: [UUID: PumpProgramStage] = [:]
            for s in project.programStages { byID[s.id] = s }

            // Track the next order index
            let maxOrder = project.programStages.map { $0.orderIndex }.max() ?? -1
            var nextOrder = maxOrder + 1

            // Delete removed
            let desiredIDs = Set(program.map { $0.id })
            project.programStages.removeAll { !desiredIDs.contains($0.id) }

            // Update existing and add new, maintaining orderIndex
            for stage in program {
                if let existing = byID[stage.id] {
                    existing.name = stage.name
                    existing.volume_m3 = stage.volume_m3
                    existing.pumpRate_m3permin = stage.pumpRate_m3permin
                    existing.color = stage.color
                    existing.mud = stage.mudID.flatMap { id in project.muds.first(where: { $0.id == id }) }
                    // keep existing.orderIndex as-is
                } else {
                    let mud = stage.mudID.flatMap { id in project.muds.first(where: { $0.id == id }) }
                    let s = PumpProgramStage(name: stage.name,
                                             volume_m3: stage.volume_m3,
                                             pumpRate_m3permin: stage.pumpRate_m3permin,
                                             color: stage.color,
                                             project: project,
                                             mud: mud)
                    s.id = stage.id
                    s.orderIndex = nextOrder
                    nextOrder += 1
                    project.programStages.append(s)
                }
            }
        }

        func currentStage(project: ProjectState) -> Stage? { stages.isEmpty ? nil : stages[stageDisplayIndex] }
        func currentStageMud(project: ProjectState) -> MudProperties? { print("\(currentStage(project: project)?.mud?.density_kgm3 ?? 0)"); return currentStage(project: project)?.mud }

        func buildStages(project: ProjectState) {
            switch sourceMode {
            case .finalLayers:
                buildStagesFromFinalLayers(project: project)
            case .program:
                buildStagesFromProgram(project: project)
            }
            saveProgram(to: project)
        }

        private func buildStagesFromFinalLayers(project: ProjectState) {
            stages.removeAll()
            let bitMD = max(
                project.annulus.map { $0.bottomDepth_m }.max() ?? 0,
                project.drillString.map { $0.bottomDepth_m }.max() ?? 0
            )
            let geom = ProjectGeometryService(project: project, currentStringBottomMD: bitMD)
            let activeMud = project.activeMud
            // Annulus first – order by shallow to deep (top MD ascending)
            let ann = project.finalLayers.filter { $0.placement == .annulus || $0.placement == .both }
                .sorted { min($0.topMD_m, $0.bottomMD_m) < min($1.topMD_m, $1.bottomMD_m) }
            for L in ann {
                let t = min(L.topMD_m, L.bottomMD_m)
                let b = max(L.topMD_m, L.bottomMD_m)
                let vol = geom.volumeInAnnulus_m3(t, b)
                let col = L.mud?.color ?? L.color
                stages.append(Stage(name: L.name, color: col, totalVolume_m3: vol, side: .annulus, mud: L.mud ?? activeMud))
            }
            // Then string – order deepest to shallowest as per spec
            let str = project.finalLayers.filter { $0.placement == .string || $0.placement == .both }
                .sorted { min($0.topMD_m, $0.bottomMD_m) < min($1.topMD_m, $1.bottomMD_m) }
                .reversed()
            for L in str {
                let t = min(L.topMD_m, L.bottomMD_m)
                let b = max(L.topMD_m, L.bottomMD_m)
                let vol = geom.volumeInString_m3(t, b)
                let col = L.mud?.color ?? L.color
                stages.append(Stage(name: L.name, color: col, totalVolume_m3: vol, side: .string, mud: L.mud ?? activeMud))
            }
            stageIndex = 0
            progress = 0
        }

        private func mudFor(id: UUID?, in project: ProjectState) -> MudProperties? {
            guard let id else { return project.activeMud }
            return project.muds.first(where: { $0.id == id }) ?? project.activeMud
        }

        private func buildStagesFromProgram(project: ProjectState) {
            stages.removeAll()
            for s in program {
                let mud = mudFor(id: s.mudID, in: project)
                let col = mud?.color ?? s.color
                stages.append(Stage(name: s.name, color: col, totalVolume_m3: max(0, s.volume_m3), side: .string, mud: mud))
            }
            stageIndex = 0
            progress = 0
        }

        func bootstrap(project: ProjectState) {
            loadProgram(from: project)
            buildStages(project: project)
            controlMD_m = project.pressureDepth_m
        }
        func nextStageOrWrap() {
            if progress >= 0.9999 { stageIndex = min(stageIndex + 1, max(stages.count - 1, 0)); progress = 0 }
            else { progress = 1 }
        }
        func prevStageOrWrap() {
            if progress <= 0.0001 { stageIndex = max(stageIndex - 1, 0); progress = 1 }
            else { progress = 0 }
        }

        struct Seg {
            var top: Double
            var bottom: Double
            var color: Color
            var mud: MudProperties?
        }

        private func merge(_ segs: [Seg]) -> [Seg] {
            let tol = 1e-6
            var out: [Seg] = []
            for s0 in segs.sorted(by: { $0.top < $1.top }) {
                var s = s0
                if let last = out.last {
                    let sameMud = (last.mud?.id == s.mud?.id)
                    let sameColor = (last.color == s.color)
                    if abs(last.bottom - s.top) <= tol && (sameMud || sameColor) {
                        // extend last
                        out[out.count - 1].bottom = s.bottom
                        // prefer keeping mud identity if any
                        if out[out.count - 1].mud == nil { out[out.count - 1].mud = s.mud }
                    } else {
                        // Snap tiny overlaps/gaps
                        if abs(s.top - last.bottom) <= tol { s.top = last.bottom }
                        out.append(s)
                    }
                } else {
                    out.append(s)
                }
            }
            return out
        }

        private func takeFromBottom(_ segs: [Seg], length: Double, bitMD: Double, geom: ProjectGeometryService) -> (remaining: [Seg], parcels: [(volume_m3: Double, color: Color, mud: MudProperties?)]) {
            let tol = 1e-9
            var need = max(0, length)
            var parcels: [(Double, Color, MudProperties?)] = []
            var remaining: [Seg] = []
            let ordered = segs.sorted { $0.top < $1.top }
            // Walk from bottom toward surface
            for s in ordered.reversed() {
                if need <= tol { remaining.insert(s, at: 0); continue }
                let span = max(0, s.bottom - s.top)
                if span <= tol { continue }
                let take = min(span, need)
                let sliceTop = max(0, s.bottom - take)
                let sliceBot = s.bottom
                let vol = geom.volumeInString_m3(sliceTop, sliceBot)
                parcels.append((vol, s.color, s.mud))
                need -= take
                // Keep the upper part if any remains
                if span - take > tol {
                    remaining.insert(Seg(top: s.top, bottom: s.bottom - take, color: s.color, mud: s.mud), at: 0)
                }
            }
            // If we still need more, we've consumed everything; otherwise the earlier loop inserted untouched upper segments when need dropped to zero.
            return (merge(remaining), parcels)
        }

        private func injectAtSurfaceString(_ segs: [Seg], length: Double, color: Color, mud: MudProperties?, bitMD: Double) -> [Seg] {
            let L = max(0, length)
            guard L > 1e-9 else { return segs }
            // Shift down by L and clip to [0, bitMD]
            var shifted: [Seg] = []
            for s in segs {
                let nt = min(bitMD, s.top + L)
                let nb = min(bitMD, s.bottom + L)
                if nb > nt + 1e-9 {
                    shifted.append(Seg(top: nt, bottom: nb, color: s.color, mud: s.mud))
                }
            }
            // Insert new parcel at top with the stage's mud (this is what will later exit the bit)
            let head = Seg(top: 0, bottom: min(bitMD, L), color: color, mud: mud)
            shifted.append(head)
            return merge(shifted)
        }

        private func annulusLengthFromBottom(forVolume vol: Double, bitMD: Double, geom: ProjectGeometryService) -> Double {
            let target = max(0, vol)
            if target <= 1e-12 { return 0 }
            var lo: Double = 0
            var hi: Double = bitMD
            // If full column volume is still less than target, clamp to bitMD (with tiny tolerance)
            let full = geom.volumeInAnnulus_m3(0.0, bitMD)
            if target >= full * (1.0 - 1e-9) { return bitMD }
            // Binary search for length from bottom that gives target volume
            for _ in 0..<96 { // a few more iters for stability on complex profiles
                let mid = 0.5 * (lo + hi)
                let v = geom.volumeInAnnulus_m3(max(0, bitMD - mid), bitMD)
                let err = v - target
                if abs(err) <= 1e-9 * max(1.0, target) { return mid }
                if err < 0 { lo = mid } else { hi = mid }
            }
            return 0.5 * (lo + hi)
        }

        private func pushUpFromBitAnnulus(_ segs: [Seg], parcels: [(volume_m3: Double, color: Color, mud: MudProperties?)], bitMD: Double, geom: ProjectGeometryService) -> [Seg] {
            var current = segs
            guard !parcels.isEmpty else { return current }

            // Compute initial lengths for each parcel
            var lengths: [Double] = parcels.map { annulusLengthFromBottom(forVolume: max(0, $0.volume_m3), bitMD: bitMD, geom: geom) }
            var totalL = lengths.reduce(0, +)
            if totalL <= 1e-9 { return current }

            // Volume-conserving scaling: ensure that the annulus volume of [bitMD-totalL, bitMD]
            // matches the sum of parcel volumes. If not, scale lengths uniformly.
            let targetV = parcels.reduce(0.0) { $0 + max(0, $1.volume_m3) }
            let achievedV = geom.volumeInAnnulus_m3(max(0, bitMD - totalL), bitMD)
            let relErr = (achievedV - targetV) / max(1.0, targetV)
            if abs(relErr) > 1e-6 && achievedV > 0 {
                let scale = max(0.0, min(10.0, targetV / achievedV))
                for i in lengths.indices { lengths[i] *= scale }
                totalL = lengths.reduce(0, +)
            }

            if totalL <= 1e-9 { return current }

            // Shift existing stack up by totalL
            var shifted: [Seg] = []
            for s in current {
                let nt = max(0, s.top - totalL)
                let nb = max(0, s.bottom - totalL)
                if nb > nt + 1e-9 { shifted.append(Seg(top: nt, bottom: nb, color: s.color, mud: s.mud)) }
            }

            // Insert the batch at the bottom, contiguous from [bit-totalL, bit]
            var cursorTop = max(0, bitMD - totalL)
            for (i, p) in parcels.enumerated() {
                let L = max(0, lengths[i])
                guard L > 1e-9 else { continue }
                let seg = Seg(top: cursorTop, bottom: min(bitMD, cursorTop + L), color: p.color, mud: p.mud)
                shifted.append(seg)
                cursorTop += L
            }

            return merge(shifted)
        }

        // Recompute stacks from base for a given stage index and pumped volume
        func stacksFor(project: ProjectState, stageIndex: Int, pumpedV: Double) -> (string: [Seg], annulus: [Seg]) {
            let bitMD = max(
                project.annulus.map { $0.bottomDepth_m }.max() ?? 0,
                project.drillString.map { $0.bottomDepth_m }.max() ?? 0
            )
            let geom = ProjectGeometryService(project: project, currentStringBottomMD: bitMD)
            let base = project.activeMud?.color ?? Color.gray.opacity(0.35)
            var string: [Seg] = [Seg(top: 0, bottom: bitMD, color: base, mud: project.activeMud)]
            var annulus: [Seg] = [Seg(top: 0, bottom: bitMD, color: base, mud: project.activeMud)]
            // Apply all previous stages fully
            for i in 0..<max(0, min(stageIndex, stages.count)) {
                // REPLACED BLOCK START
                let st = stages[i]
                let pV = max(0, st.totalVolume_m3)
                let Ls = geom.lengthForStringVolume_m(0.0, pV)
                let taken = takeFromBottom(string, length: Ls, bitMD: bitMD, geom: geom)
                string = injectAtSurfaceString(string, length: Ls, color: st.color, mud: st.mud, bitMD: bitMD)

                // Compute excess beyond what the string could provide; this exits the bit immediately.
                let takenV = taken.parcels.reduce(0.0) { $0 + max(0, $1.volume_m3) }
                let excessV = max(0.0, pV - takenV)
                var parcels = taken.parcels
                if excessV > 1e-9 {
                    parcels.append((volume_m3: excessV, color: st.color, mud: st.mud))
                }
                annulus = pushUpFromBitAnnulus(annulus, parcels: parcels, bitMD: bitMD, geom: geom)
                // REPLACED BLOCK END
            }
            // Apply current stage partially
            if stages.indices.contains(stageIndex) {
                // REPLACED BLOCK START
                let st = stages[stageIndex]
                let pV = max(0, min(pumpedV, st.totalVolume_m3))
                let Ls = geom.lengthForStringVolume_m(0.0, pV)
                let taken = takeFromBottom(string, length: Ls, bitMD: bitMD, geom: geom)
                string = injectAtSurfaceString(string, length: Ls, color: st.color, mud: st.mud, bitMD: bitMD)

                let takenV = taken.parcels.reduce(0.0) { $0 + max(0, $1.volume_m3) }
                let excessV = max(0.0, pV - takenV)
                var parcels = taken.parcels
                if excessV > 1e-9 {
                    parcels.append((volume_m3: excessV, color: st.color, mud: st.mud))
                }
                annulus = pushUpFromBitAnnulus(annulus, parcels: parcels, bitMD: bitMD, geom: geom)
                // REPLACED BLOCK END
            }
            return (string, annulus)
        }

        struct HydraulicsReadout {
            let annulusAtControl_Pa: Double
            let stringAtControl_Pa: Double
            let annulusFriction_kPa: Double
            let stringFriction_kPa: Double
            let totalFriction_kPa: Double
            let sbp_kPa: Double
            let bhp_kPa: Double
            /// Total circulating pressure at surface (string + annulus friction + SBP)
            let tcp_kPa: Double
            let ecd_kgm3: Double
        }

        #if DEBUG
        /// Debug snapshot based directly on the visual annulus stack.
        /// Uses the same segments and TVD mapping as the Well Snapshot view
        /// to compute per-layer and total hydrostatic pressure.
        func debugCurrentAnnulus(project: ProjectState) {
            let bitMD = max(
                project.annulus.map { $0.bottomDepth_m }.max() ?? 0,
                project.drillString.map { $0.bottomDepth_m }.max() ?? 0
            )

            let stg = currentStage(project: project)
            let totalV = stg?.totalVolume_m3 ?? 0
            let pumpedV = max(0.0, min(progress * max(totalV, 0), totalV))

            // Same stack as the visual
            let stacks = stacksFor(project: project,
                                   stageIndex: stageDisplayIndex,
                                   pumpedV: pumpedV)

            print("===== Annulus Stack Debug (Visual-Based HP) =====")
            print("Stage index: \(stageDisplayIndex) name: \(stg?.name ?? "<none>")")
            print(String(format: "Bit MD: %.1f m", bitMD))
            print(String(format: "Pumped volume: %.3f m³ (of %.3f m³)",
                         pumpedV, totalV))
            print("-- Annulus segments (as drawn) --")

            let g = 9.80665
            var totalHydrostatic_Pa: Double = 0

            for (i, seg) in stacks.annulus.enumerated() {
                let mudName = seg.mud?.name ?? "<active / unknown>"
                let rho = seg.mud?.density_kgm3 ?? project.activeMudDensity_kgm3

                // Use the same mapping as the visual: MD -> TVD
                let tvdTop = project.tvd(of: seg.top)
                let tvdBot = project.tvd(of: seg.bottom)
                let dTVD   = max(0.0, tvdBot - tvdTop)

                let dP = rho * g * dTVD
                totalHydrostatic_Pa += dP

                let colorDescription = String(describing: seg.color)

                print(String(
                    format: "[%02d] MD %.1f–%.1f m, TVD %.1f–%.1f m, dTVD = %.1f m, mud = %@, ρ = %.0f kg/m³, dP = %.0f kPa, color = %@",
                    i,
                    seg.top,
                    seg.bottom,
                    tvdTop,
                    tvdBot,
                    dTVD,
                    mudName,
                    rho,
                    dP / 1000.0,
                    colorDescription
                ))
            }

            print(String(format: "Total hydrostatic from visual stack: %.0f kPa",
                         totalHydrostatic_Pa / 1000.0))
            print("===== End Annulus Stack Debug =====")
        }
        #endif

        #if DEBUG
        /// Exports a detailed debug log of the current stage behavior across progress steps
        /// to a text file in the temporary directory. Prints the file URL to the console.
        func exportAnnulusDebugLog(project: ProjectState) {
            let bitMD = max(
                project.annulus.map { $0.bottomDepth_m }.max() ?? 0,
                project.drillString.map { $0.bottomDepth_m }.max() ?? 0
            )
            let g = 9.80665

            var lines: [String] = []
            func add(_ s: String) { lines.append(s) }

            add("===== Pump Schedule Debug Export =====")
            add(String(format: "Bit MD: %.3f m", bitMD))
            add("Project active mud density: \(project.activeMudDensity_kgm3) kg/m³")
            add("")

            // Iterate over a set of progress samples for the current stage
            let samples = Array(stride(from: 0.0, through: 1.0, by: 0.05))
            for prog in samples {
                let oldProgress = self.progress
                self.progress = prog
                defer { self.progress = oldProgress }

                let stg = currentStage(project: project)
                let totalV = stg?.totalVolume_m3 ?? 0
                let pumpedV = max(0.0, min(self.progress * max(totalV, 0), totalV))

                add(String(format: "-- Progress: %.2f (pumpedV = %.4f m³ of %.4f m³) --", self.progress, pumpedV, totalV))

                // Build stacks for this progress
                let stacks = stacksFor(project: project, stageIndex: stageDisplayIndex, pumpedV: pumpedV)
                let ann = stacks.annulus.sorted { $0.bottom < $1.bottom }
                if let bottom = ann.last {
                    let mudName = bottom.mud?.name ?? "<active/unknown>"
                    add(String(format: "Bottom annulus seg: top=%.3f, bottom=%.3f, mud=%@", bottom.top, bottom.bottom, mudName))
                } else {
                    add("Bottom annulus seg: <none>")
                }

                // Parcel accounting for current stage only
                if stages.indices.contains(stageDisplayIndex) {
                    let geom = ProjectGeometryService(project: project, currentStringBottomMD: bitMD)
                    let st = stages[stageDisplayIndex]
                    let pV = max(0, min(pumpedV, st.totalVolume_m3))
                    let Ls = geom.lengthForStringVolume_m(0.0, pV)

                    // Recreate string before taking current partial by replaying previous full stages
                    var string: [Seg] = [Seg(top: 0, bottom: bitMD, color: project.activeMud?.color ?? .gray.opacity(0.35), mud: project.activeMud)]
                    var annulus: [Seg] = [Seg(top: 0, bottom: bitMD, color: project.activeMud?.color ?? .gray.opacity(0.35), mud: project.activeMud)]
                    for i in 0..<max(0, min(stageDisplayIndex, stages.count)) {
                        let pst = stages[i]
                        let pVol = max(0, pst.totalVolume_m3)
                        let Lprev = geom.lengthForStringVolume_m(0.0, pVol)
                        let takenPrev = takeFromBottom(string, length: Lprev, bitMD: bitMD, geom: geom)
                        string = injectAtSurfaceString(string, length: Lprev, color: pst.color, mud: pst.mud, bitMD: bitMD)
                        annulus = pushUpFromBitAnnulus(annulus, parcels: takenPrev.parcels, bitMD: bitMD, geom: geom)
                    }

                    let taken = takeFromBottom(string, length: Ls, bitMD: bitMD, geom: geom)
                    add(String(format: "String length for current pumpedV (Ls): %.4f m", Ls))
                    var sumParcels = 0.0
                    for (i, parcel) in taken.parcels.enumerated() {
                        sumParcels += parcel.volume_m3
                        let mudName = parcel.mud?.name ?? "<active/unknown>"
                        add(String(format: "  Parcel[%02d] V=%.4f m³, mud=%@", i, parcel.volume_m3, mudName))
                    }
                    add(String(format: "  Sum parcel volume: %.4f m³", sumParcels))

                    var lengths: [Double] = taken.parcels.map { annulusLengthFromBottom(forVolume: max(0, $0.volume_m3), bitMD: bitMD, geom: geom) }
                    let totalL = lengths.reduce(0, +)
                    let achievedV = (totalL > 0) ? geom.volumeInAnnulus_m3(max(0, bitMD - totalL), bitMD) : 0.0
                    add(String(format: "  Annulus totalL: %.4f m", totalL))
                    for (i, L) in lengths.enumerated() {
                        add(String(format: "    length[%02d] = %.4f m", i, L))
                    }
                    add(String(format: "  Achieved annulus volume for [bit-totalL, bit]: %.4f m³", achievedV))
                    add(String(format: "  Target parcel volume: %.4f m³", sumParcels))
                }

                add("")
            }

            // Write to a temp file
            let text = lines.joined(separator: "\n")
            let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            let fileURL = tmp.appendingPathComponent("PumpScheduleDebug_\(UUID().uuidString).txt")
            do {
                try text.data(using: .utf8)?.write(to: fileURL)
                print("[PumpSchedule] Debug export written to: \(fileURL.path)")
            } catch {
                print("[PumpSchedule] Failed writing debug export: \(error)")
            }
        }
        #endif

        func hydraulicsForCurrent(project: ProjectState) -> HydraulicsReadout {
            // Guard
            let bitMD = max(
                project.annulus.map { $0.bottomDepth_m }.max() ?? 0,
                project.drillString.map { $0.bottomDepth_m }.max() ?? 0
            )
            let controlMD: Double = {
                switch controlDepthMode {
                case .bit: return bitMD
                case .custom: return max(0.0, min(controlMD_m, bitMD))
                }
            }()
            let controlTVD = project.tvd(of: controlMD)
            let g = 9.80665
            
            // Build current stacks to know which fluids are where
            let stg = currentStage(project: project)
            let totalV = stg?.totalVolume_m3 ?? 0
            let pumpedV = max(0.0, min(progress * max(totalV, 0), totalV))
            let stacks = stacksFor(project: project, stageIndex: stageDisplayIndex, pumpedV: pumpedV)
            
            // Helper to get annulus area and fluid density at MD
            let geom = ProjectGeometryService(project: project, currentStringBottomMD: bitMD)
            
            // Segment-exact hydrostatic (TVD) and segment-wise friction (MD)
            var annulusHydrostatic_Pa: Double = 0
            var stringHydrostatic_Pa: Double = 0
            var annulusFriction_Pa: Double = 0
            var stringFriction_Pa: Double = 0
            
            
            // Clip each annulus segment to [0, controlMD] and integrate
            for seg in stacks.annulus {
                let topMD = max(0.0, min(seg.top, controlMD))
                let botMD = max(0.0, min(seg.bottom, controlMD))
                if botMD <= topMD { continue }

                // Hydrostatic: integrate rho*g*dTVD between the TVDs of the clipped segment
                let tvdTop = project.tvd(of: topMD)
                let tvdBot = project.tvd(of: botMD)
                let dTVD = max(0.0, tvdBot - tvdTop)
                let rho = seg.mud?.density_kgm3 ?? 1260
                annulusHydrostatic_Pa += rho * g * dTVD

                // Friction: along the flow path (MD)
                let dMD = botMD - topMD
                let Q_m3s = max(pumpRate_m3permin, 0) / 60.0
                if Q_m3s > 0 && dMD > 0 {
                    let mdMid = 0.5 * (topMD + botMD)
                    let Do = max(geom.pipeOD_m(mdMid), 0.001)
                    let Dhole = max(geom.holeOD_m(mdMid), Do + 0.0001)
                    let Dh = max(Dhole - Do, 1e-6)
                    let Aann = .pi * (Dhole * Dhole - Do * Do) / 4.0
                    let Va = Q_m3s / max(Aann, 1e-12)

                    // Power-law K/n: prefer annulus-specific lab fit if available,
                    // otherwise fall back to 600/300 universal fit.
                    var K: Double = 0
                    var n: Double = 1
                    if let m = seg.mud {
                        if let nAnn = m.n_annulus, let KAnn = m.K_annulus {
                            n = nAnn
                            K = KAnn
                        } else if let t600 = m.dial600, let t300 = m.dial300, t600 > 0, t300 > 0 {
                            n = log(t600/t300) / log(600.0/300.0)
                            let tau600 = 0.4788 * t600
                            let gamma600 = 1022.0
                            K = tau600 / pow(gamma600, n)
                        }
                    }
                    // Mooney–Rabinowitsch laminar ΔP/L (Pa/m)
                    let gamma_w = ((3.0 * n + 1.0) / (4.0 * n)) * (8.0 * Va / Dh)
                    let tau_w = K > 0 ? K * pow(gamma_w, n) : 0
                    let dPperM = 4.0 * tau_w / Dh
                    annulusFriction_Pa += dPperM * dMD
                }
            }
            
            // Clip each string segment to [0, controlMD] and integrate friction inside the drill string
            for seg in stacks.string {
                let topMD = max(0.0, min(seg.top, controlMD))
                let botMD = max(0.0, min(seg.bottom, controlMD))
                if botMD <= topMD { continue }

                let tvdTop = project.tvd(of: topMD)
                let tvdBot = project.tvd(of: botMD)
                let dTVD = max(0.0, tvdBot - tvdTop)
                let rhoString = seg.mud?.density_kgm3 ?? project.activeMudDensity_kgm3
                stringHydrostatic_Pa += rhoString * g * dTVD

                let dMD = botMD - topMD
                let Q_m3s = max(pumpRate_m3permin, 0) / 60.0
                if Q_m3s > 0 && dMD > 0 {
                    let mdMid = 0.5 * (topMD + botMD)

                    // Internal flow: use pipe ID and internal flow area
                    let Di = max(geom.pipeID_m(mdMid), 0.001)   // <— if your geometry API uses a different name, adjust this
                    let Apipe = .pi * Di * Di / 4.0
                    let Vp = Q_m3s / max(Apipe, 1e-12)

                    // Power-law K/n: prefer pipe-specific lab fit if available,
                    // otherwise fall back to 600/300 universal fit.
                    var K: Double = 0
                    var n: Double = 1
                    if let m = seg.mud {
                        if let nPipe = m.n_pipe, let KPipe = m.K_pipe {
                            n = nPipe
                            K = KPipe
                        } else if let t600 = m.dial600, let t300 = m.dial300, t600 > 0, t300 > 0 {
                            n = log(t600/t300) / log(600.0/300.0)
                            let tau600 = 0.4788 * t600
                            let gamma600 = 1022.0
                            K = tau600 / pow(gamma600, n)
                        }
                    }
                    // Mooney–Rabinowitsch laminar ΔP/L (Pa/m) for pipe flow
                    let gamma_w = ((3.0 * n + 1.0) / (4.0 * n)) * (8.0 * Vp / Di)
                    let tau_w = K > 0 ? K * pow(gamma_w, n) : 0
                    let dPperM = 4.0 * tau_w / Di
                    stringFriction_Pa += dPperM * dMD
                }
            }
            
            let ann_kPa = annulusFriction_Pa / 1000.0
            let str_kPa = stringFriction_Pa / 1000.0
            let totalFric_kPa = ann_kPa + str_kPa
            
            // MPD SBP to hit target EMD at control depth.
            // For bottomhole pressure, only annulus friction contributes (string friction is upstream of the bit).
            var sbp_kPa: Double = 0
            if mpdEnabled {
                let targetBHP_Pa = max(0, targetEMD_kgm3) * g * controlTVD
                let currentBHP_Pa = annulusHydrostatic_Pa + annulusFriction_Pa
                sbp_kPa = max(0, (targetBHP_Pa - currentBHP_Pa) / 1000.0)
            }
            
            let annulusAtControl_Pa = annulusHydrostatic_Pa + annulusFriction_Pa + sbp_kPa * 1000.0
            let stringAtControl_Pa  = stringHydrostatic_Pa + stringFriction_Pa
            let deltaStringMinusAnnulus_kPa = (stringAtControl_Pa - annulusAtControl_Pa) / 1000.0
            
            let bhp_kPa = (annulusHydrostatic_Pa / 1000) + sbp_kPa
            
            // Total circulating pressure at surface: all friction + any surface backpressure.
            let tcp_kPa = totalFric_kPa + sbp_kPa
            
            // ECD at control depth: only hydrostatic + annulus friction + SBP affect downhole pressure.
            let ecd_kgm3 = controlTVD > 0
            ? ((annulusHydrostatic_Pa + annulusFriction_Pa + sbp_kPa * 1000.0) / (g * controlTVD))
            : 0
            
            return HydraulicsReadout(
                annulusAtControl_Pa: annulusAtControl_Pa,
                stringAtControl_Pa: stringAtControl_Pa,
                annulusFriction_kPa: ann_kPa,
                stringFriction_kPa: str_kPa,
                totalFriction_kPa: totalFric_kPa,
                sbp_kPa: sbp_kPa,
                bhp_kPa: bhp_kPa,
                tcp_kPa: tcp_kPa,
                ecd_kgm3: ecd_kgm3
            )
        }

        func maxDepthMD(project: ProjectState) -> Double {
            max(
                project.annulus.map { $0.bottomDepth_m }.max() ?? 0,
                project.drillString.map { $0.bottomDepth_m }.max() ?? 0
            )
        }
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
        a.project = p; b.project = p; p.annulus.append(contentsOf: [a,b]); ctx.insert(a); ctx.insert(b)
        let ds = DrillStringSection(name: "4\" DP", topDepth_m: 0, length_m: 5200, outerDiameter_m: 0.1016, innerDiameter_m: 0.0803)
        ds.project = p; p.drillString.append(ds); ctx.insert(ds)
        // Muds
        let active = MudProperties(name: "Active", density_kgm3: 1260, color: .yellow, project: p)
        active.isActive = true
        let heavy = MudProperties(name: "Heavy", density_kgm3: 1855, color: .red, project: p)
        p.muds.append(contentsOf: [active, heavy])
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

