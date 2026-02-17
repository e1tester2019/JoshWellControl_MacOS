//
//  MudCheckView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-08.
//

import SwiftUI
import SwiftData

struct MudCheckView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectState

    @State private var selection: MudProperties? = nil

    var body: some View {
        HStack(spacing: 0) {
            // Editor on left
            Group {
                if let mud = selection {
                    MudEditor(mud: mud)
                        .id(mud.id)
                } else {
                    placeholder
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Mud list on right
            sidebar
                .frame(width: 280)
        }
        .navigationTitle("Mud Check")
        .toolbar { toolbar }
        .onAppear { attachInitialSelection() }
        .onChange(of: project) { _, _ in
            selection = nil
            attachInitialSelection()
        }
    }

    // MARK: - Sidebar
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            List(selection: $selection) {
                Section("Fluids") {
                    let sorted = (project.muds ?? []).sorted { lhs, rhs in
                        lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    }
                    ForEach(sorted) { mud in
                        HStack {
                            Button(action: { setActive(mud) }) {
                                Image(systemName: mud.isActive ? "star.fill" : "star")
                                    .foregroundStyle(mud.isActive ? .yellow : .secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Set Active Mud")

                            Rectangle()
                                .fill(mud.color)
                                .frame(width: 14, height: 10)
                                .cornerRadius(2)
                                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.black.opacity(0.15)))

                            Text(mud.name)
                            Spacer()
                            Text("\(Int(mud.density_kgm3)) kg/m³")
                                .foregroundStyle(.secondary)
                        }
                        .tag(mud as MudProperties?)
                        .contentShape(Rectangle())
                        .onTapGesture { selection = mud }
                    }
                    .onDelete { idx in
                        let sorted = (project.muds ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                        let items = idx.map { sorted[$0] }
                        items.forEach(delete)
                    }
                }
            }
            .listStyle(.inset)
            .scrollIndicators(.hidden)

            HStack {
                Button { addMud() } label: { Label("Add", systemImage: "plus") }
                Button { if let s = selection { duplicateMud(s) } } label: { Label("Duplicate", systemImage: "doc.on.doc") }
                    .disabled(selection == nil)
                Button(role: .destructive) { if let s = selection { delete(s) } } label: { Label("Delete", systemImage: "trash") }
                    .disabled(selection == nil)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Text("No mud selected").font(.title3).bold()
            Text("Add a mud or pick one from the list to edit its properties.")
                .foregroundStyle(.secondary)
            Button("Add Mud", systemImage: "plus") { addMud() }
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }

    // MARK: - Toolbar
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button("Add Mud", systemImage: "plus") { addMud() }
            Button("Duplicate", systemImage: "doc.on.doc") { if let s = selection { duplicateMud(s) } }
                .disabled(selection == nil)
            Button("Delete", systemImage: "trash", role: .destructive) { if let s = selection { delete(s) } }
                .disabled(selection == nil)
            if let s = selection {
                Button {
                    setActive(s)
                } label: {
                    Label("Set Active", systemImage: s.isActive ? "star.fill" : "star")
                        .foregroundStyle(s.isActive ? .yellow : .primary)
                }
                .disabled(selection == nil)
            } else {
                Button("Set Active", systemImage: "star") { }
                    .disabled(true)
            }
        }
    }

    // MARK: - Actions
    private func attachInitialSelection() {
        if selection == nil {
            selection = (project.muds ?? []).first
        }
    }

    private func addMud() {
        let m = MudProperties(name: "New Mud", density_kgm3: 1100, rheologyModel: "Bingham", dial600: nil, dial300: nil, color: .yellow, project: project)
        if project.muds == nil { project.muds = [] }
        project.muds?.append(m)
        modelContext.insert(m)
        try? modelContext.save()
        selection = m
    }

    private func duplicateMud(_ m0: MudProperties) {
        let m = MudProperties(
            name: m0.name + " Copy",
            density_kgm3: m0.density_kgm3,
            pv_Pa_s: m0.pv_Pa_s,
            yp_Pa: m0.yp_Pa,
            n_powerLaw: m0.n_powerLaw,
            k_powerLaw_Pa_s_n: m0.k_powerLaw_Pa_s_n,
            tau0_Pa: m0.tau0_Pa,
            rheologyModel: m0.rheologyModel,
            gel10s_Pa: m0.gel10s_Pa,
            gel10m_Pa: m0.gel10m_Pa,
            thermalExpCoeff_perC: m0.thermalExpCoeff_perC,
            compressibility_perkPa: m0.compressibility_perkPa,
            gasCutFraction: m0.gasCutFraction,
            project: project
        )
        m.colorR = m0.colorR; m.colorG = m0.colorG; m.colorB = m0.colorB; m.colorA = m0.colorA
        if project.muds == nil { project.muds = [] }
        project.muds?.append(m)
        modelContext.insert(m)
        try? modelContext.save()
        selection = m
    }

    private func setActive(_ m: MudProperties) {
        // Ensure only one active mud per project
        for x in (project.muds ?? []) { x.isActive = (x.id == m.id) }
        project.baseAnnulusDensity_kgm3 = m.density_kgm3
        project.baseStringDensity_kgm3 = m.density_kgm3
        project.activeMudDensity_kgm3 = m.density_kgm3
        try? modelContext.save()
        selection = m
    }

    private func delete(_ m: MudProperties) {
        // Determine new selection BEFORE deleting (to avoid accessing deleted objects)
        var newSelection: MudProperties? = selection
        if selection?.id == m.id {
            // Find first mud that won't be deleted
            let muds = project.muds ?? []
            newSelection = muds.first { $0.id != m.id }
        }

        // Remove from array
        if let i = (project.muds ?? []).firstIndex(where: { $0.id == m.id }) {
            project.muds?.remove(at: i)
        }

        // Delete from context (after determining new selection)
        modelContext.delete(m)
        try? modelContext.save()

        // Apply the new selection
        selection = newSelection
    }
}

// MARK: - Editor
private struct MudEditor: View {
    @Bindable var mud: MudProperties

    private let LABEL_W: CGFloat = 220
    private let FIELD_W: CGFloat = 140
    private let HSPACE: CGFloat = 8
    private let VSPACE: CGFloat = 6

    @State private var lastFitSummary: String = ""

    private func applyFannToMud() {
        guard let dial600Input = mud.dial600, let dial300Input = mud.dial300, dial600Input > 0, dial300Input > 0 else {
            lastFitSummary = "Enter 600/300 first"
            return
        }
        // Bingham from field formulas
        let pv_cP = max(0, dial600Input - dial300Input)
        let yp_lbf = dial300Input - pv_cP
        let pv_Pa_s = pv_cP * 0.001
        let yp_Pa = yp_lbf * HydraulicsDefaults.fann35_dialToPa

        // Power-law from two points
        let tau600 = dial600Input * HydraulicsDefaults.fann35_dialToPa // Pa
        let tau300 = dial300Input * HydraulicsDefaults.fann35_dialToPa // Pa
        let g600 = HydraulicsDefaults.fann35_600rpm_shearRate // 1/s
        let g300 = HydraulicsDefaults.fann35_300rpm_shearRate // 1/s
        let n = log(tau600 / tau300) / log(g600 / g300)
        let K = tau600 / pow(g600, n)

        // Apply to model
        mud.pv_Pa_s = pv_Pa_s
        mud.yp_Pa = yp_Pa
        mud.n_powerLaw = n
        mud.k_powerLaw_Pa_s_n = K

        // Friendlier summary with lab units
        lastFitSummary = String(format: "Applied  PV=%.1f mPa·s (%.3f Pa·s), YP=%.1f lbf/100ft² (%.2f Pa), n=%.3f, K=%.4f Pa·s^n",
                                pv_cP, pv_Pa_s, yp_lbf, yp_Pa, n, K)
    }

    private enum Rheology: String, CaseIterable, Identifiable { case bingham = "Bingham", powerLaw = "PowerLaw", hb = "HB"; var id: String { rawValue } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                GroupBox("Identity") {
                    Grid(alignment: .leading, horizontalSpacing: HSPACE, verticalSpacing: VSPACE) {
                        GridRow {
                            Text("Name").frame(width: LABEL_W, alignment: .trailing).foregroundStyle(.secondary)
                            TextField("Name", text: $mud.name)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: .infinity)
                                .controlSize(.small)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                GroupBox("Appearance") {
                    HStack(spacing: 12) {
                        Text("Color").frame(width: LABEL_W, alignment: .trailing).foregroundStyle(.secondary)
                        ColorPicker("", selection: Binding(get: { mud.color }, set: { mud.color = $0 }))
                            .labelsHidden()
                            .frame(width: 44)
                        Spacer()
                    }
                    .padding(8)
                }

                VStack(alignment: .leading, spacing: 12) {
                    GroupBox("Density & Environment") {
                        Grid(alignment: .leading, horizontalSpacing: HSPACE, verticalSpacing: VSPACE) {
                            GridRow {
                                Text("Density (kg/m³)").frame(width: LABEL_W, alignment: .trailing).foregroundStyle(.secondary)
                                TextField("", value: $mud.density_kgm3, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .monospacedDigit()
                                    .frame(maxWidth: .infinity)
                                    .controlSize(.small)
                            }
                            GridRow {
                                Text("Gas cut (0–1)").frame(width: LABEL_W, alignment: .trailing).foregroundStyle(.secondary)
                                TextField("", value: Binding(get: { mud.gasCutFraction ?? 0 }, set: { mud.gasCutFraction = $0 }), format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .monospacedDigit()
                                    .frame(maxWidth: .infinity)
                                    .controlSize(.small)
                            }
                            GridRow {
                                Text("Thermal expansion (1/°C)").frame(width: LABEL_W, alignment: .trailing).foregroundStyle(.secondary)
                                TextField("", value: Binding(get: { mud.thermalExpCoeff_perC ?? 0 }, set: { mud.thermalExpCoeff_perC = $0 }), format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .monospacedDigit()
                                    .frame(maxWidth: .infinity)
                                    .controlSize(.small)
                            }
                            GridRow {
                                Text("Compressibility (1/kPa)").frame(width: LABEL_W, alignment: .trailing).foregroundStyle(.secondary)
                                TextField("", value: Binding(get: { mud.compressibility_perkPa ?? 0 }, set: { mud.compressibility_perkPa = $0 }), format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .monospacedDigit()
                                    .frame(maxWidth: .infinity)
                                    .controlSize(.small)
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    GroupBox("Gels") {
                        Grid(alignment: .leading, horizontalSpacing: HSPACE, verticalSpacing: VSPACE) {
                            GridRow {
                                Text("10s Gel (Pa)").frame(width: LABEL_W, alignment: .trailing).foregroundStyle(.secondary)
                                TextField("", value: Binding(get: { mud.gel10s_Pa ?? 0 }, set: { mud.gel10s_Pa = $0 }), format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .monospacedDigit()
                                    .frame(maxWidth: .infinity)
                                    .controlSize(.small)
                            }
                            GridRow {
                                Text("10m Gel (Pa)").frame(width: LABEL_W, alignment: .trailing).foregroundStyle(.secondary)
                                TextField("", value: Binding(get: { mud.gel10m_Pa ?? 0 }, set: { mud.gel10m_Pa = $0 }), format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .monospacedDigit()
                                    .frame(maxWidth: .infinity)
                                    .controlSize(.small)
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                GroupBox("Quick Check") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Effective density is used for hydrostatics with simple corrections:")
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Text("ρₑff @ ΔT=0°C, ΔP=0 kPa:")
                            Text("\(Int(mud.effectiveDensity(baseT_C: nil, atT_C: nil, baseP_kPa: nil, atP_kPa: nil))) kg/m³")
                                .monospacedDigit()
                        }
                    }
                    .padding(6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                GroupBox("Rheology Model") {
                    VStack(alignment: .leading, spacing: 8) {
                        Grid(alignment: .leading, horizontalSpacing: HSPACE, verticalSpacing: VSPACE) {
                            GridRow {
                                Text("Model")
                                    .frame(width: LABEL_W, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                                Picker("Model", selection: Binding(
                                    get: { Rheology(rawValue: mud.rheologyModel) ?? .bingham },
                                    set: { mud.rheologyModel = $0.rawValue }
                                )) {
                                    ForEach(Rheology.allCases) { Text($0.rawValue).tag($0) }
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                                .frame(maxWidth: .infinity)
                                .controlSize(.small)
                            }
                            // Bingham fields
                            GridRow {
                                Text("Plastic Viscosity (mPa·s)")
                                    .frame(width: LABEL_W, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                                TextField("", value: Binding(get: { mud.pv_mPa_s ?? 0 }, set: { mud.pv_mPa_s = $0 }), format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .monospacedDigit()
                                    .frame(maxWidth: .infinity)
                                    .controlSize(.small)
                            }
                            GridRow {
                                Text("Yield Point (Pa)")
                                    .frame(width: LABEL_W, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                                TextField("", value: Binding(get: { mud.yp_Pa ?? 0 }, set: { mud.yp_Pa = $0 }), format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .monospacedDigit()
                                    .frame(maxWidth: .infinity)
                                    .controlSize(.small)
                            }
                            Divider()
                            // Power Law / HB fields
                            GridRow {
                                Text("n (–)").frame(width: LABEL_W, alignment: .trailing).foregroundStyle(.secondary)
                                TextField("", value: Binding(get: { mud.n_powerLaw ?? 0 }, set: { mud.n_powerLaw = $0 }), format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .monospacedDigit()
                                    .frame(maxWidth: .infinity)
                                    .controlSize(.small)
                            }
                            GridRow {
                                Text("K (Pa·sⁿ)").frame(width: LABEL_W, alignment: .trailing).foregroundStyle(.secondary)
                                TextField("", value: Binding(get: { mud.k_powerLaw_Pa_s_n ?? 0 }, set: { mud.k_powerLaw_Pa_s_n = $0 }), format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .monospacedDigit()
                                    .frame(maxWidth: .infinity)
                                    .controlSize(.small)
                            }
                            GridRow {
                                Text("τ₀ (Pa) – HB only").frame(width: LABEL_W, alignment: .trailing).foregroundStyle(.secondary)
                                TextField("", value: Binding(get: { mud.tau0_Pa ?? 0 }, set: { mud.tau0_Pa = $0 }), format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .monospacedDigit()
                                    .frame(maxWidth: .infinity)
                                    .controlSize(.small)
                            }

                            // Geometry-specific Power Law fits (optional)
                            GridRow {
                                Text("n (pipe) – optional")
                                    .frame(width: LABEL_W, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                                TextField("", value: Binding(
                                    get: { mud.n_pipe ?? 0 },
                                    set: { mud.n_pipe = $0 }
                                ), format: .number)
                                .textFieldStyle(.roundedBorder)
                                .monospacedDigit()
                                .frame(maxWidth: .infinity)
                                .controlSize(.small)
                            }
                            GridRow {
                                Text("K (pipe, Pa·sⁿ) – optional")
                                    .frame(width: LABEL_W, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                                TextField("", value: Binding(
                                    get: { mud.K_pipe ?? 0 },
                                    set: { mud.K_pipe = $0 }
                                ), format: .number)
                                .textFieldStyle(.roundedBorder)
                                .monospacedDigit()
                                .frame(maxWidth: .infinity)
                                .controlSize(.small)
                            }
                            GridRow {
                                Text("n (annulus) – optional")
                                    .frame(width: LABEL_W, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                                TextField("", value: Binding(
                                    get: { mud.n_annulus ?? 0 },
                                    set: { mud.n_annulus = $0 }
                                ), format: .number)
                                .textFieldStyle(.roundedBorder)
                                .monospacedDigit()
                                .frame(maxWidth: .infinity)
                                .controlSize(.small)
                            }
                            GridRow {
                                Text("K (annulus, Pa·sⁿ) – optional")
                                    .frame(width: LABEL_W, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                                TextField("", value: Binding(
                                    get: { mud.K_annulus ?? 0 },
                                    set: { mud.K_annulus = $0 }
                                ), format: .number)
                                .textFieldStyle(.roundedBorder)
                                .monospacedDigit()
                                .frame(maxWidth: .infinity)
                                .controlSize(.small)
                            }

                            GridRow {
                                Text("600 rpm dial").frame(width: LABEL_W, alignment: .trailing).foregroundStyle(.secondary)
                                TextField("", value: Binding(get: { mud.dial600 ?? 0 }, set: { mud.dial600 = $0 }), format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .monospacedDigit()
                                    .frame(maxWidth: .infinity)
                                    .controlSize(.small)
                            }
                            GridRow {
                                Text("300 rpm dial").frame(width: LABEL_W, alignment: .trailing).foregroundStyle(.secondary)
                                TextField("", value: Binding(get: { mud.dial300 ?? 0 }, set: { mud.dial300 = $0 }), format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .monospacedDigit()
                                    .frame(maxWidth: .infinity)
                                    .controlSize(.small)
                            }
                            GridRow {
                                Text("")
                                    .frame(width: LABEL_W, alignment: .trailing)
                                Button("Fit from 600/300 & Apply") { applyFannToMud() }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity)

                        if !lastFitSummary.isEmpty {
                            Text(lastFitSummary)
                                .foregroundStyle(.secondary)
                                .monospaced()
                                .font(.footnote)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
        }
        .onChange(of: mud.dial600) { _, _ in
            applyFannToMud()
        }
        .onChange(of: mud.dial300) { _, _ in
            applyFannToMud()
        }
    }
}

// MARK: - Preview
private struct MudCheckPreviewHost: View {
    let container: ModelContainer?
    let project: ProjectState?

    init() {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        if let c = try? ModelContainer(for: ProjectState.self, MudProperties.self, configurations: config) {
            container = c
            let ctx = c.mainContext
            let p = ProjectState()
            ctx.insert(p)
            let m = MudProperties(name: "Active System", density_kgm3: 1180, n_powerLaw: 0.6, k_powerLaw_Pa_s_n: 0.45, tau0_Pa: 6, rheologyModel: "HB", gel10s_Pa: 5, gel10m_Pa: 9, project: p)
            if p.muds == nil { p.muds = [] }
            p.muds?.append(m)
            m.isActive = true
            try? ctx.save()
            project = p
        } else {
            container = nil
            project = nil
        }
    }

    var body: some View {
        Group {
            if let container, let project {
                MudCheckView(project: project)
                    .modelContainer(container)
                    .frame(width: 900, height: 640)
            } else {
                Text("Preview failed to build container")
            }
        }
    }
}

#Preview("Mud Check – Sample") {
    MudCheckPreviewHost()
}
