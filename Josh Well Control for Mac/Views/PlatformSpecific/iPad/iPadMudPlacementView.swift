//
//  iPadMudPlacementView.swift
//  Josh Well Control for Mac
//
//  iPad-optimized mud placement view with compressed inputs and adaptive layout
//

import SwiftUI
import SwiftData

#if os(iOS)

struct iPadMudPlacementView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Bindable var project: ProjectState
    @State private var viewmodel: MudPlacementViewModel

    // Interval inputs (meters)
    @State private var top_m: Double = 0
    @State private var bottom_m: Double = 0
    @State private var previewDensity_kgm3: Double = 1260
    @State private var intervalMudID: UUID? = nil

    init(project: ProjectState) {
        self._project = Bindable(wrappedValue: project)
        _viewmodel = State(initialValue: MudPlacementViewModel(project: project))

        // Smart defaults based on well geometry
        let casingShoe = (project.annulus ?? [])
            .filter { $0.isCased }
            .map { $0.bottomDepth_m }
            .max() ?? 0
        let totalDepth = max(
            (project.annulus ?? []).map { $0.bottomDepth_m }.max() ?? 0,
            (project.drillString ?? []).map { $0.bottomDepth_m }.max() ?? 0
        )
        _top_m = State(initialValue: casingShoe > 0 ? casingShoe : 0)
        _bottom_m = State(initialValue: totalDepth > 0 ? totalDepth : 1000)
    }

    private var isLandscape: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12, pinnedViews: [.sectionHeaders]) {
                // Header
                Section {
                    headerSection
                } header: {
                    EmptyView()
                }

                // Steps Editor
                Section {
                    stepsSection
                } header: {
                    sectionHeader(title: "Steps", icon: "square.stack.3d.up.fill")
                }

                // Base Fluids
                Section {
                    baseFluidsSection
                } header: {
                    sectionHeader(title: "Base Fluids", icon: "drop.fill")
                }

                // Apply Button
                applySection

                // Final Layers
                if project.finalLayers != nil {
                    Section {
                        finalLayersSection
                    } header: {
                        sectionHeader(title: "Final Spotted Fluids", icon: "layers.fill")
                    }
                }

                // Hydrostatic
                Section {
                    hydrostaticSection
                } header: {
                    sectionHeader(title: "Hydrostatic Pressure", icon: "gauge")
                }

                // Interval Calculator
                Section {
                    intervalInputsSection
                    intervalResultsSection
                } header: {
                    sectionHeader(title: "Interval Calculator", icon: "function")
                }

                // Planning Hints
                Section {
                    planningHintsSection
                } header: {
                    sectionHeader(title: "Planning Hints", icon: "lightbulb.fill")
                }
            }
            .padding(isLandscape ? 16 : 12)
        }
        .background(Color(.systemGroupedBackground))
        .onAppear {
            viewmodel.attach(context: modelContext)
            if intervalMudID == nil { intervalMudID = viewmodel.mudsSortedByName.first?.id }
            if let id = intervalMudID, let m = viewmodel.mudsSortedByName.first(where: { $0.id == id }) {
                previewDensity_kgm3 = m.density_kgm3
            }
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mud Placement")
                .font(.title2)
                .fontWeight(.bold)
            Text("Build steps and place them as final layers. The interval calculator uses your geometry.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }

    // MARK: - Steps Section
    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewmodel.steps.isEmpty {
                Text("No steps yet. Add one below.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(viewmodel.steps) { step in
                    iPadStepRowView(
                        step: step,
                        compute: { t, b in
                            let r = viewmodel.computeVolumesBetween(top: t, bottom: b)
                            return (r.annular_m3, r.stringCapacity_m3, r.stringDisp_m3, r.openHole_m3)
                        },
                        onDelete: { s in
                            viewmodel.deleteStep(s)
                        },
                        muds: viewmodel.mudsSortedByName,
                        isLandscape: isLandscape
                    )
                }
            }

            if stepsHaveOverlap(viewmodel.steps) {
                Label("Steps overlap in depth. Review tops/bottoms.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal)
            }

            // Action buttons
            HStack(spacing: 8) {
                Button(action: {
                    let active = project.activeMud
                    let s = MudStep(
                        name: "Step \(viewmodel.steps.count + 1)",
                        top_m: top_m,
                        bottom_m: bottom_m,
                        density_kgm3: active?.density_kgm3 ?? 1200,
                        color: active?.color ?? .blue,
                        placement: .both,
                        project: project,
                        mud: active
                    )
                    if project.mudSteps == nil { project.mudSteps = [] }
                    project.mudSteps?.append(s)
                    modelContext.insert(s)
                }) {
                    Label("Add Step", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: { viewmodel.seedInitialSteps() }) {
                    Label("Seed Initial", systemImage: "square.stack.3d.down.forward.fill")
                }
                .buttonStyle(.bordered)

                Button(role: .destructive, action: { viewmodel.clearAllSteps() }) {
                    Label("Clear All", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }

    // MARK: - Base Fluids Section
    private var baseFluidsSection: some View {
        VStack(spacing: 12) {
            if isLandscape {
                HStack(spacing: 16) {
                    compactInputField(label: "Annulus ρ", value: $project.baseAnnulusDensity_kgm3, unit: "kg/m³")
                    compactInputField(label: "String ρ", value: $project.baseStringDensity_kgm3, unit: "kg/m³")
                }
            } else {
                compactInputField(label: "Annulus ρ", value: $project.baseAnnulusDensity_kgm3, unit: "kg/m³")
                compactInputField(label: "String ρ", value: $project.baseStringDensity_kgm3, unit: "kg/m³")
            }

            Text("Used to fill the well before replacing with steps.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }

    // MARK: - Apply Section
    private var applySection: some View {
        VStack(spacing: 8) {
            Button(action: { rebuildFinalFromBase() }) {
                Label("Apply Base + Layers", systemImage: "arrow.down.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("Fills each domain with a base fluid, then overlays steps.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }

    // MARK: - Final Layers Section
    private var finalLayersSection: some View {
        let finalLayers = project.finalLayers ?? []
        let stringLayers = finalLayers
            .filter { $0.placement == .string || $0.placement == .both }
            .sorted { min($0.topMD_m, $0.bottomMD_m) < min($1.topMD_m, $1.bottomMD_m) }
        let annulusLayers = finalLayers
            .filter { $0.placement == .annulus || $0.placement == .both }
            .sorted { min($0.topMD_m, $0.bottomMD_m) < min($1.topMD_m, $1.bottomMD_m) }

        return VStack(spacing: 16) {
            if isLandscape {
                HStack(alignment: .top, spacing: 16) {
                    layerColumn(title: "String Layers", layers: stringLayers, domain: .string)
                    Divider()
                    layerColumn(title: "Annulus Layers", layers: annulusLayers, domain: .annulus)
                }
            } else {
                layerColumn(title: "String Layers", layers: stringLayers, domain: .string)
                Divider()
                layerColumn(title: "Annulus Layers", layers: annulusLayers, domain: .annulus)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }

    // MARK: - Hydrostatic Section
    private var hydrostaticSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            compactInputField(label: "Measured Depth", value: $project.pressureDepth_m, unit: "m")

            Text("Computed from surface to TVD using final layers (MD→TVD mapped via surveys).")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("TVD(MD) = \(fmt(viewmodel.mdToTVD(project.pressureDepth_m), 0)) m")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            let depthTVD = viewmodel.mdToTVD(project.pressureDepth_m)
            let annLayers = buildWorkingLayers(for: .annulus)
            let strLayers = buildWorkingLayers(for: .string)
            let pAnn = hydrostatic(from: annLayers, to: depthTVD)
            let pStr = hydrostatic(from: strLayers, to: depthTVD)

            let columns = isLandscape ? 3 : 1
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 12) {
                compactResultCard(title: "Annulus P", value: pAnn, unit: "kPa", color: .blue)
                compactResultCard(title: "String P", value: pStr, unit: "kPa", color: .orange)
                compactResultCard(title: "ΔP (Ann − Str)", value: pAnn - pStr, unit: "kPa", color: .purple)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }

    // MARK: - Interval Inputs Section
    private var intervalInputsSection: some View {
        VStack(spacing: 12) {
            if isLandscape {
                HStack(spacing: 12) {
                    compactStepperField(label: "Top", value: $top_m, range: 0...10_000, step: 0.1, unit: "m")
                    compactStepperField(label: "Bottom", value: $bottom_m, range: top_m...10_000, step: 0.1, unit: "m")
                }
            } else {
                compactStepperField(label: "Top", value: $top_m, range: 0...10_000, step: 0.1, unit: "m")
                compactStepperField(label: "Bottom", value: $bottom_m, range: top_m...10_000, step: 0.1, unit: "m")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Preview Mud")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("", selection: Binding<UUID?>(
                    get: { intervalMudID ?? viewmodel.mudsSortedByName.first?.id },
                    set: { newID in
                        intervalMudID = newID
                        if let id = newID, let m = viewmodel.mudsSortedByName.first(where: { $0.id == id }) {
                            previewDensity_kgm3 = m.density_kgm3
                        }
                    }
                )) {
                    ForEach(viewmodel.mudsSortedByName, id: \.id) { m in
                        Text("\(m.name): \(Int(m.density_kgm3)) kg/m³").tag(m.id as UUID?)
                    }
                }
                .pickerStyle(.menu)
            }

            Button(action: {
                let tNow = min(top_m, bottom_m)
                let bNow = max(top_m, bottom_m)
                let chosenMud = viewmodel.mudsSortedByName.first(where: { $0.id == intervalMudID })
                let s = MudStep(
                    name: "Preview Step",
                    top_m: tNow,
                    bottom_m: bNow,
                    density_kgm3: chosenMud?.density_kgm3 ?? previewDensity_kgm3,
                    color: chosenMud?.color ?? .purple,
                    placement: .both,
                    project: project,
                    mud: chosenMud
                )
                if project.mudSteps == nil { project.mudSteps = [] }
                project.mudSteps?.append(s)
                modelContext.insert(s)
            }) {
                Label("Add Step from Interval", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }

    // MARK: - Interval Results Section
    private var intervalResultsSection: some View {
        let t = min(top_m, bottom_m)
        let b = max(top_m, bottom_m)
        let r = viewmodel.computeVolumesBetween(top: t, bottom: b)
        let equal = viewmodel.solvePipeInIntervalForEqualVolume(targetTop: t, targetBottom: b)
        let tvdTop = viewmodel.mdToTVD(t)
        let tvdBot = viewmodel.mdToTVD(b)
        let tvdSpan = abs(tvdBot - tvdTop)
        let dp_kPa = previewDensity_kgm3 * g_ms2 * tvdSpan / 1000.0
        let checksum_m3 = r.openHole_m3 - (r.annular_m3 + r.stringCapacity_m3 + r.stringMetal_m3)

        let columns = isLandscape ? 4 : 2
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 12) {
            compactResultCard(title: "Annular Vol", value: r.annular_m3, unit: "m³", color: .blue)
            compactResultCard(title: "String Cap", value: r.stringCapacity_m3, unit: "m³", color: .orange)
            compactResultCard(title: "Wet Disp", value: r.stringDisp_m3, unit: "m³", color: .purple)
            compactResultCard(title: "Dry Disp", value: r.stringMetal_m3, unit: "m³", color: .pink)
            compactResultCard(title: "Open Hole", value: r.openHole_m3, unit: "m³", color: .green)
            compactResultCard(title: "Total Mud", value: equal.total_m3, unit: "m³", color: .cyan)
            compactResultCard(title: "Identity Check", value: checksum_m3, unit: "m³", color: .gray)
            compactResultCard(title: "Vol Inside+Out", value: r.annular_m3 + r.stringCapacity_m3, unit: "m³", color: .indigo)
            compactResultCard(title: "Pipe-in Length", value: equal.length_m, unit: "m", color: .teal)
            compactResultCard(title: "Mud Top", value: equal.mudTop_m, unit: "m", color: .brown)
            compactResultCard(title: "TVD Span", value: tvdSpan, unit: "m", color: .mint)
            compactResultCard(title: "ΔP Preview", value: dp_kPa, unit: "kPa", color: .yellow)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }

    // MARK: - Planning Hints Section
    private var planningHintsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("To spot a balanced mud: pump inside = outside volumes so hydrostatic heads match.", systemImage: "equal.circle")
            Label("To chase to a target top in string: add the string capacity from current top to target depth.", systemImage: "arrow.down.circle")
            Label("Results update as you change depths and respect OD changes and section boundaries.", systemImage: "arrow.triangle.2.circlepath")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func sectionHeader(title: String, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func compactInputField(label: String, value: Binding<Double>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                TextField(label, value: value, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func compactStepperField(label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                TextField(label, value: value, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                Stepper("", value: value, in: range, step: step)
                    .labelsHidden()
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func compactResultCard(title: String, value: Double, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(fmt(value, value > 100 ? 1 : 3))
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(color.gradient)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }

    @ViewBuilder
    private func layerColumn(title: String, layers: [FinalFluidLayer], domain: FinalLayer.Domain) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            if layers.isEmpty {
                Text("No layers")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(layers, id: \.id) { L in
                    let lay = FinalLayer(
                        domain: domain,
                        top: min(L.topMD_m, L.bottomMD_m),
                        bottom: max(L.topMD_m, L.bottomMD_m),
                        name: L.name,
                        color: L.color,
                        density: L.density_kgm3,
                        mud: L.mud
                    )
                    let vol = volumeForLayer(lay)
                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(lay.color)
                            .frame(width: 12, height: 12)
                            .cornerRadius(2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(lay.name)
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("\(fmt(lay.top,0))–\(fmt(lay.bottom,0)) m  •  ρ=\(fmt(lay.density,0))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(fmt(vol.total_m3)) m³")
                                .font(.caption)
                                .monospacedDigit()
                            Text("\(fmt(vol.perM_m3perm)) m³/m")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.05)))
                }
            }
        }
    }

    // MARK: - Final layering helpers
    private var maxDepth_m: Double {
        max(
            (project.annulus ?? []).map { $0.bottomDepth_m }.max() ?? 0,
            (project.drillString ?? []).map { $0.bottomDepth_m }.max() ?? 0
        )
    }

    private func baseLayer(for domain: FinalLayer.Domain) -> FinalLayer {
        let active = project.activeMud
        let rho = (domain == .annulus) ? (active?.density_kgm3 ?? project.baseAnnulusDensity_kgm3) : (active?.density_kgm3 ?? project.baseStringDensity_kgm3)
        let col = active?.color ?? Color.gray.opacity(0.35)
        return FinalLayer(domain: domain, top: 0, bottom: maxDepth_m, name: "Base", color: col, density: rho, mud: active)
    }

    private func overlay(_ layers: inout [FinalLayer], with newLay: FinalLayer) {
        var out: [FinalLayer] = []
        let t = min(newLay.top, newLay.bottom)
        let b = max(newLay.top, newLay.bottom)
        for L in layers {
            if L.bottom <= t || L.top >= b {
                out.append(L)
            } else {
                if L.top < t {
                    out.append(FinalLayer(domain: L.domain, top: L.top, bottom: t, name: L.name, color: L.color, density: L.density, mud: L.mud))
                }
                if L.bottom > b {
                    out.append(FinalLayer(domain: L.domain, top: b, bottom: L.bottom, name: L.name, color: L.color, density: L.density, mud: L.mud))
                }
            }
        }
        out.append(FinalLayer(domain: newLay.domain, top: t, bottom: b, name: newLay.name, color: newLay.color, density: newLay.density, mud: newLay.mud))
        out.sort { $0.top < $1.top }
        layers = out
    }

    private func rebuildFinalFromBase() {
        var ann: [FinalLayer] = [ baseLayer(for: .annulus) ]
        var str: [FinalLayer] = [ baseLayer(for: .string) ]

        for s in viewmodel.steps {
            let t = min(s.top_m, s.bottom_m)
            let b = max(s.top_m, s.bottom_m)
            let chosenMud = s.mud

            let layA = FinalLayer(
                domain: .annulus,
                top: t, bottom: b,
                name: s.name,
                color: chosenMud?.color ?? s.color,
                density: s.density_kgm3,
                mud: chosenMud
            )

            let layS = FinalLayer(
                domain: .string,
                top: t, bottom: b,
                name: s.name,
                color: chosenMud?.color ?? s.color,
                density: s.density_kgm3,
                mud: chosenMud
            )

            if s.placement == .annulus || s.placement == .both { overlay(&ann, with: layA) }
            if s.placement == .string  || s.placement == .both { overlay(&str, with: layS) }
        }

        viewmodel.persistFinalLayers(from: ann, str)
    }

    // MARK: - Hydrostatic calculation
    private let g_ms2 = 9.80665

    private func buildWorkingLayers(for domain: FinalLayer.Domain) -> [FinalLayer] {
        (project.finalLayers ?? [])
            .filter { domain == .annulus ? ($0.placement == .annulus || $0.placement == .both) : ($0.placement == .string || $0.placement == .both) }
            .map { L in
                FinalLayer(
                    domain: domain,
                    top: min(L.topMD_m, L.bottomMD_m),
                    bottom: max(L.topMD_m, L.bottomMD_m),
                    name: L.name,
                    color: L.color,
                    density: L.density_kgm3,
                    mud: L.mud
                )
            }
            .sorted { $0.top < $1.top }
    }

    private func hydrostatic(from layers: [FinalLayer], to depthTVD: Double) -> Double {
        let limitTVD = max(0, min(depthTVD, maxDepth_m))
        guard limitTVD > 0 else { return 0 }
        var p = 0.0
        for L in layers {
            let tTVD = viewmodel.mdToTVD(L.top)
            let bTVD = viewmodel.mdToTVD(L.bottom)
            let lo = min(tTVD, bTVD)
            let hi = max(tTVD, bTVD)
            let segTop = max(0, lo)
            let segBot = min(limitTVD, hi)
            if segBot <= segTop { continue }
            p += L.density * g_ms2 * (segBot - segTop) / 1000.0
        }
        return p
    }

    private func volumeForLayer(_ lay: FinalLayer) -> (total_m3: Double, perM_m3perm: Double) {
        let r = viewmodel.computeVolumesBetween(top: lay.top, bottom: lay.bottom)
        switch lay.domain {
        case .annulus:
            return (r.annular_m3, r.annularPerM_m3perm)
        case .string:
            return (r.stringCapacity_m3, r.stringCapacityPerM_m3perm)
        }
    }

    private func stepsHaveOverlap(_ steps: [MudStep]) -> Bool {
        guard steps.count > 1 else { return false }
        let sorted = steps.sorted { min($0.top_m, $0.bottom_m) < min($1.top_m, $1.bottom_m) }
        for i in 0..<(sorted.count - 1) {
            let aBot = max(sorted[i].top_m, sorted[i].bottom_m)
            let bTop = min(sorted[i+1].top_m, sorted[i+1].bottom_m)
            if bTop < aBot - 1e-6 { return true }
        }
        return false
    }

    // MARK: - Formatting
    private func fmt(_ v: Double, _ p: Int = 5) -> String { String(format: "%0.*f", p, v) }
}

// MARK: - iPad Step Row View

struct iPadStepRowView: View {
    @Bindable var step: MudStep
    let compute: (_ top: Double, _ bottom: Double) -> (annular_m3: Double, string_m3: Double, disp_m3: Double, openHole_m3: Double)
    let onDelete: (MudStep) -> Void
    let muds: [MudProperties]
    let isLandscape: Bool

    private func fmtLocal(_ v: Double, _ p: Int = 3) -> String { String(format: "%0.*f", p, v) }

    var body: some View {
        let t = min(step.top_m, step.bottom_m)
        let b = max(step.top_m, step.bottom_m)
        let vols = compute(t, b)

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(step.mud?.color ?? step.color)
                    .frame(width: 20, height: 20)
                    .cornerRadius(4)

                TextField("Name", text: $step.name)
                    .textFieldStyle(.roundedBorder)

                Button(role: .destructive, action: { onDelete(step) }) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
            }

            if isLandscape {
                HStack(spacing: 12) {
                    compactField(label: "Top", value: $step.top_m, unit: "m")
                    compactField(label: "Bottom", value: $step.bottom_m, unit: "m")
                }
            } else {
                compactField(label: "Top", value: $step.top_m, unit: "m")
                compactField(label: "Bottom", value: $step.bottom_m, unit: "m")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Mud")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: Binding<UUID?>(
                    get: { step.mud?.id },
                    set: { newID in
                        if let id = newID, let m = muds.first(where: { $0.id == id }) {
                            step.mud = m
                            step.density_kgm3 = m.density_kgm3
                            step.colorHex = m.color.toHexRGB() ?? step.colorHex
                        }
                    }
                )) {
                    ForEach(muds, id: \.id) { m in
                        Text("\(m.name): \(Int(m.density_kgm3)) kg/m³").tag(m.id as UUID?)
                    }
                }
                .pickerStyle(.menu)
            }

            Picker("Placement", selection: Binding(get: { step.placement }, set: { step.placement = $0 })) {
                ForEach(Placement.allCases) { p in
                    Text(p.rawValue).tag(p)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 2) {
                Text("Ann: \(fmtLocal(vols.annular_m3)) m³  •  Inside: \(fmtLocal(vols.string_m3)) m³")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Disp: \(fmtLocal(vols.disp_m3)) m³  •  OpenHole: \(fmtLocal(vols.openHole_m3)) m³")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }

    @ViewBuilder
    private func compactField(label: String, value: Binding<Double>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                TextField(label, value: value, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#endif
