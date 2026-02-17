//
//  OperationConfigView.swift
//  Josh Well Control for Mac
//
//  Configuration forms for each operation type in the Super Simulation.
//

import SwiftUI

struct OperationConfigView: View {
    @Binding var operation: SuperSimOperation
    var project: ProjectState

    private var sortedMuds: [MudProperties] {
        (project.muds ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Steel displacement volume (OD volume - ID volume) over the trip out range
    private var computedDisplacementVolume: Double {
        let annulusSections = project.annulus ?? []
        let drillString = project.drillString ?? []
        guard !annulusSections.isEmpty, !drillString.isEmpty else { return 0 }
        let tvdSampler = TvdSampler(project: project)
        let geom = ProjectGeometryService(
            annulus: annulusSections,
            string: drillString,
            currentStringBottomMD: operation.startMD_m,
            mdToTvd: { md in tvdSampler.tvd(of: md) }
        )
        let odVolume = geom.volumeOfStringOD_m3(operation.endMD_m, operation.startMD_m)
        let idVolume = geom.volumeInString_m3(operation.endMD_m, operation.startMD_m)
        return max(0, odVolume - idVolume)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configuration")
                .font(.headline)

            switch operation.type {
            case .tripOut:
                tripOutConfig
            case .tripIn:
                tripInConfig
            case .circulate:
                circulateConfig
            case .reamOut:
                reamOutConfig
            case .reamIn:
                reamInConfig
            }
        }
    }

    // MARK: - Trip Out Config

    private var tripOutConfig: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("Start MD (m):")
                    .frame(width: 140, alignment: .trailing)
                TextField("Start", value: $operation.startMD_m, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            GridRow {
                Text("End MD (m):")
                    .frame(width: 140, alignment: .trailing)
                TextField("End", value: $operation.endMD_m, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            GridRow {
                Text("Target ESD (kg/m\u{00B3}):")
                    .frame(width: 140, alignment: .trailing)
                TextField("ESD", value: $operation.targetESD_kgpm3, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            GridRow {
                Text("Base Mud:")
                    .frame(width: 140, alignment: .trailing)
                Picker("", selection: $operation.baseMudID) {
                    Text("Select Mud").tag(nil as UUID?)
                    ForEach(sortedMuds, id: \.id) { mud in
                        Text("\(mud.name): \(String(format: "%.0f", mud.density_kgm3)) kg/m\u{00B3}")
                            .tag(mud.id as UUID?)
                    }
                }
                .labelsHidden()
                .frame(width: 240)
                .pickerStyle(.menu)
            }
            GridRow {
                Text("Backfill Mud:")
                    .frame(width: 140, alignment: .trailing)
                Picker("", selection: $operation.backfillMudID) {
                    Text("Select Mud").tag(nil as UUID?)
                    ForEach(sortedMuds, id: \.id) { mud in
                        Text("\(mud.name): \(String(format: "%.0f", mud.density_kgm3)) kg/m\u{00B3}")
                            .tag(mud.id as UUID?)
                    }
                }
                .labelsHidden()
                .frame(width: 240)
                .pickerStyle(.menu)
            }
            GridRow {
                Text("Step Size (m):")
                    .frame(width: 140, alignment: .trailing)
                TextField("Step", value: $operation.step_m, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            GridRow {
                Text("Trip Speed (m/min):")
                    .frame(width: 140, alignment: .trailing)
                TextField("Speed", value: Binding(
                    get: { operation.tripSpeed_m_per_s * 60 },
                    set: { operation.tripSpeed_m_per_s = $0 / 60 }
                ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            GridRow {
                Text("Control MD (m):")
                    .frame(width: 140, alignment: .trailing)
                TextField("Control", value: $operation.controlMD_m, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            GridRow {
                Text("Float Crack (kPa):")
                    .frame(width: 140, alignment: .trailing)
                TextField("Crack", value: $operation.crackFloat_kPa, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            GridRow {
                Text("")
                    .frame(width: 140, alignment: .trailing)
                Toggle("Switch to active after displacement", isOn: $operation.switchToActiveAfterDisplacement)
                    .controlSize(.small)
                    .help("Pump backfill mud for the drill string displacement volume, then switch to active mud for the remaining pit gain portion")
                    .onChange(of: operation.switchToActiveAfterDisplacement) { _, newValue in
                        if newValue && operation.overrideDisplacementVolume_m3 < 0.001 {
                            operation.overrideDisplacementVolume_m3 = computedDisplacementVolume
                        }
                    }
            }
            if operation.switchToActiveAfterDisplacement {
                GridRow {
                    Text("")
                        .frame(width: 140, alignment: .trailing)
                    HStack(spacing: 4) {
                        Text("Vol:")
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.2f", computedDisplacementVolume))
                            .monospacedDigit()
                            .foregroundStyle(.blue)
                            .help("Computed steel displacement volume")
                        Toggle("Override:", isOn: $operation.useOverrideDisplacementVolume)
                            .controlSize(.small)
                        TextField("", value: $operation.overrideDisplacementVolume_m3, format: .number.precision(.fractionLength(2)))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                            .disabled(!operation.useOverrideDisplacementVolume)
                        Text("m\u{00B3}")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            GridRow {
                Text("Eccentricity:")
                    .frame(width: 140, alignment: .trailing)
                TextField("Factor", value: $operation.eccentricityFactor, format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .help("Pipe eccentricity factor for swab calculation (1.0 = concentric)")
            }
            GridRow {
                Text("")
                    .frame(width: 140, alignment: .trailing)
                Toggle("Hold SABP open", isOn: $operation.holdSABPOpen)
                    .controlSize(.small)
                    .help("Keep surface annulus back-pressure at zero throughout the trip")
            }
            GridRow {
                Text("")
                    .frame(width: 140, alignment: .trailing)
                Toggle("Use observed pit gain", isOn: $operation.useObservedPitGain)
                    .controlSize(.small)
                    .help("Calibrate initial U-tube equalization to an observed pit gain value")
            }
            if operation.useObservedPitGain {
                GridRow {
                    Text("Observed Gain (m\u{00B3}):")
                        .frame(width: 140, alignment: .trailing)
                    TextField("Gain", value: Binding(
                        get: { operation.observedInitialPitGain_m3 ?? 0 },
                        set: { operation.observedInitialPitGain_m3 = $0 }
                    ), format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
            }
        }
        .onChange(of: operation.baseMudID) { _, newID in
            if let newID, let mud = sortedMuds.first(where: { $0.id == newID }) {
                operation.baseMudDensity_kgpm3 = mud.density_kgm3
            }
        }
        .onChange(of: operation.backfillMudID) { _, newID in
            if let newID, let mud = sortedMuds.first(where: { $0.id == newID }) {
                operation.backfillDensity_kgpm3 = mud.density_kgm3
                operation.backfillColorR = mud.colorR
                operation.backfillColorG = mud.colorG
                operation.backfillColorB = mud.colorB
                operation.backfillColorA = mud.colorA
            }
        }
    }

    // MARK: - Trip In Config

    private var tripInConfig: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("Start MD (m):")
                    .frame(width: 140, alignment: .trailing)
                TextField("Start", value: $operation.startMD_m, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            GridRow {
                Text("End MD (m):")
                    .frame(width: 140, alignment: .trailing)
                TextField("End", value: $operation.endMD_m, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            GridRow {
                Text("Target ESD (kg/m\u{00B3}):")
                    .frame(width: 140, alignment: .trailing)
                TextField("ESD", value: $operation.targetESD_kgpm3, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            GridRow {
                Text("Pipe OD (m):")
                    .frame(width: 140, alignment: .trailing)
                TextField("OD", value: $operation.pipeOD_m, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            GridRow {
                Text("Pipe ID (m):")
                    .frame(width: 140, alignment: .trailing)
                TextField("ID", value: $operation.pipeID_m, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            GridRow {
                Text("Fill Mud:")
                    .frame(width: 140, alignment: .trailing)
                Picker("", selection: $operation.fillMudID) {
                    Text("Select Mud").tag(nil as UUID?)
                    ForEach(sortedMuds, id: \.id) { mud in
                        Text("\(mud.name): \(String(format: "%.0f", mud.density_kgm3)) kg/m\u{00B3}")
                            .tag(mud.id as UUID?)
                    }
                }
                .labelsHidden()
                .frame(width: 240)
                .pickerStyle(.menu)
            }
            GridRow {
                Text("Step Size (m):")
                    .frame(width: 140, alignment: .trailing)
                TextField("Step", value: $operation.tripInStep_m, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            GridRow {
                Text("Trip Speed (m/min):")
                    .frame(width: 140, alignment: .trailing)
                HStack {
                    TextField("Speed", value: Binding(
                        get: { operation.tripInSpeed_m_per_s * 60 },
                        set: { operation.tripInSpeed_m_per_s = $0 / 60 }
                    ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    if operation.tripInSpeed_m_per_s <= 0 {
                        Text("(no surge)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            GridRow {
                Text("Control MD (m):")
                    .frame(width: 140, alignment: .trailing)
                TextField("Control", value: $operation.controlMD_m, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            GridRow {
                Text("Floated Casing:")
                    .frame(width: 140, alignment: .trailing)
                Toggle("", isOn: $operation.isFloatedCasing)
                    .labelsHidden()
            }
        }
        .onChange(of: operation.fillMudID) { _, newID in
            if let newID, let mud = sortedMuds.first(where: { $0.id == newID }) {
                operation.fillMudDensity_kgpm3 = mud.density_kgm3
                operation.fillMudColorR = mud.colorR
                operation.fillMudColorG = mud.colorG
                operation.fillMudColorB = mud.colorB
                operation.fillMudColorA = mud.colorA
            }
        }
    }

    // MARK: - Ream Out Config

    private var reamOutConfig: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("Start MD (m):")
                    .frame(width: 140, alignment: .trailing)
                TextField("Start", value: $operation.startMD_m, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            GridRow {
                Text("End MD (m):")
                    .frame(width: 140, alignment: .trailing)
                TextField("End", value: $operation.endMD_m, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            GridRow {
                Text("Target ESD (kg/m\u{00B3}):")
                    .frame(width: 140, alignment: .trailing)
                TextField("ESD", value: $operation.targetESD_kgpm3, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            GridRow {
                Text("Base Mud:")
                    .frame(width: 140, alignment: .trailing)
                Picker("", selection: $operation.baseMudID) {
                    Text("Select Mud").tag(nil as UUID?)
                    ForEach(sortedMuds, id: \.id) { mud in
                        Text("\(mud.name): \(String(format: "%.0f", mud.density_kgm3)) kg/m\u{00B3}")
                            .tag(mud.id as UUID?)
                    }
                }
                .labelsHidden()
                .frame(width: 240)
                .pickerStyle(.menu)
            }
            GridRow {
                Text("Backfill Mud:")
                    .frame(width: 140, alignment: .trailing)
                Picker("", selection: $operation.backfillMudID) {
                    Text("Select Mud").tag(nil as UUID?)
                    ForEach(sortedMuds, id: \.id) { mud in
                        Text("\(mud.name): \(String(format: "%.0f", mud.density_kgm3)) kg/m\u{00B3}")
                            .tag(mud.id as UUID?)
                    }
                }
                .labelsHidden()
                .frame(width: 240)
                .pickerStyle(.menu)
            }
            GridRow {
                Text("Step Size (m):")
                    .frame(width: 140, alignment: .trailing)
                TextField("Step", value: $operation.step_m, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            GridRow {
                Text("Trip Speed (m/min):")
                    .frame(width: 140, alignment: .trailing)
                TextField("Speed", value: Binding(
                    get: { operation.tripSpeed_m_per_s * 60 },
                    set: { operation.tripSpeed_m_per_s = $0 / 60 }
                ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            GridRow {
                Text("Pump Rate (m\u{00B3}/min):")
                    .frame(width: 140, alignment: .trailing)
                TextField("Rate", value: $operation.reamPumpRate_m3perMin, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            GridRow {
                Text("Control MD (m):")
                    .frame(width: 140, alignment: .trailing)
                TextField("Control", value: $operation.controlMD_m, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            GridRow {
                Text("Float Crack (kPa):")
                    .frame(width: 140, alignment: .trailing)
                TextField("Crack", value: $operation.crackFloat_kPa, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            GridRow {
                Text("Eccentricity:")
                    .frame(width: 140, alignment: .trailing)
                TextField("Factor", value: $operation.eccentricityFactor, format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .help("Pipe eccentricity factor for swab calculation (1.0 = concentric)")
            }
            GridRow {
                Text("")
                    .frame(width: 140, alignment: .trailing)
                Toggle("Hold SABP open", isOn: $operation.holdSABPOpen)
                    .controlSize(.small)
            }
        }
        .onChange(of: operation.baseMudID) { _, newID in
            if let newID, let mud = sortedMuds.first(where: { $0.id == newID }) {
                operation.baseMudDensity_kgpm3 = mud.density_kgm3
            }
        }
        .onChange(of: operation.backfillMudID) { _, newID in
            if let newID, let mud = sortedMuds.first(where: { $0.id == newID }) {
                operation.backfillDensity_kgpm3 = mud.density_kgm3
                operation.backfillColorR = mud.colorR
                operation.backfillColorG = mud.colorG
                operation.backfillColorB = mud.colorB
                operation.backfillColorA = mud.colorA
            }
        }
    }

    // MARK: - Ream In Config

    private var reamInConfig: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("Start MD (m):")
                    .frame(width: 140, alignment: .trailing)
                TextField("Start", value: $operation.startMD_m, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            GridRow {
                Text("End MD (m):")
                    .frame(width: 140, alignment: .trailing)
                TextField("End", value: $operation.endMD_m, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            GridRow {
                Text("Target ESD (kg/m\u{00B3}):")
                    .frame(width: 140, alignment: .trailing)
                TextField("ESD", value: $operation.targetESD_kgpm3, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            GridRow {
                Text("Pipe OD (m):")
                    .frame(width: 140, alignment: .trailing)
                TextField("OD", value: $operation.pipeOD_m, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            GridRow {
                Text("Pipe ID (m):")
                    .frame(width: 140, alignment: .trailing)
                TextField("ID", value: $operation.pipeID_m, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            GridRow {
                Text("Fill Mud:")
                    .frame(width: 140, alignment: .trailing)
                Picker("", selection: $operation.fillMudID) {
                    Text("Select Mud").tag(nil as UUID?)
                    ForEach(sortedMuds, id: \.id) { mud in
                        Text("\(mud.name): \(String(format: "%.0f", mud.density_kgm3)) kg/m\u{00B3}")
                            .tag(mud.id as UUID?)
                    }
                }
                .labelsHidden()
                .frame(width: 240)
                .pickerStyle(.menu)
            }
            GridRow {
                Text("Step Size (m):")
                    .frame(width: 140, alignment: .trailing)
                TextField("Step", value: $operation.tripInStep_m, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            GridRow {
                Text("Trip Speed (m/min):")
                    .frame(width: 140, alignment: .trailing)
                HStack {
                    TextField("Speed", value: Binding(
                        get: { operation.tripInSpeed_m_per_s * 60 },
                        set: { operation.tripInSpeed_m_per_s = $0 / 60 }
                    ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    if operation.tripInSpeed_m_per_s <= 0 {
                        Text("(no surge)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            GridRow {
                Text("Pump Rate (m\u{00B3}/min):")
                    .frame(width: 140, alignment: .trailing)
                TextField("Rate", value: $operation.reamPumpRate_m3perMin, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            GridRow {
                Text("Control MD (m):")
                    .frame(width: 140, alignment: .trailing)
                TextField("Control", value: $operation.controlMD_m, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            GridRow {
                Text("Floated Casing:")
                    .frame(width: 140, alignment: .trailing)
                Toggle("", isOn: $operation.isFloatedCasing)
                    .labelsHidden()
            }
        }
        .onChange(of: operation.fillMudID) { _, newID in
            if let newID, let mud = sortedMuds.first(where: { $0.id == newID }) {
                operation.fillMudDensity_kgpm3 = mud.density_kgm3
                operation.fillMudColorR = mud.colorR
                operation.fillMudColorG = mud.colorG
                operation.fillMudColorB = mud.colorB
                operation.fillMudColorA = mud.colorA
            }
        }
    }

    // MARK: - Circulate Config

    private var circulateConfig: some View {
        VStack(alignment: .leading, spacing: 8) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("At MD (m):")
                        .frame(width: 140, alignment: .trailing)
                    TextField("MD", value: $operation.startMD_m, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
                GridRow {
                    Text("Target ESD (kg/m\u{00B3}):")
                        .frame(width: 140, alignment: .trailing)
                    TextField("ESD", value: $operation.targetESD_kgpm3, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
                GridRow {
                    Text("Control MD (m):")
                        .frame(width: 140, alignment: .trailing)
                    TextField("Control", value: $operation.controlMD_m, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
                GridRow {
                    Text("Max Pump Rate (m\u{00B3}/min):")
                        .frame(width: 140, alignment: .trailing)
                    TextField("Max", value: $operation.maxPumpRate_m3perMin, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
                GridRow {
                    Text("Min Pump Rate (m\u{00B3}/min):")
                        .frame(width: 140, alignment: .trailing)
                    TextField("Min", value: $operation.minPumpRate_m3perMin, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
            }

            Divider()

            Text("Pump Queue")
                .font(.subheadline.weight(.medium))
            Text("Configure the pump queue using the mud selector below. Each entry represents a volume of mud to pump down the string.")
                .font(.caption)
                .foregroundStyle(.secondary)

            PumpQueueEditor(operation: $operation, project: project)
        }
    }
}

// MARK: - Pump Queue Editor

struct PumpQueueEditor: View {
    @Binding var operation: SuperSimOperation
    var project: ProjectState

    @State private var entries: [PumpEntry] = []
    @State private var selectedMudID: UUID?
    @State private var pumpVolume: Double = 5.0

    struct PumpEntry: Identifiable {
        let id = UUID()
        var mudID: UUID
        var mudName: String
        var density: Double
        var volume: Double
        var colorR: Double
        var colorG: Double
        var colorB: Double
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Existing queue entries
            ForEach(entries) { entry in
                HStack {
                    Circle()
                        .fill(Color(red: entry.colorR, green: entry.colorG, blue: entry.colorB))
                        .frame(width: 12, height: 12)
                    Text(entry.mudName)
                        .font(.subheadline)
                    Spacer()
                    Text("\(String(format: "%.1f", entry.density)) kg/m\u{00B3}")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(String(format: "%.1f", entry.volume)) m\u{00B3}")
                        .font(.caption)
                    Button {
                        entries.removeAll { $0.id == entry.id }
                        encodeQueue()
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }

            // Add new entry
            HStack {
                Picker("Mud", selection: $selectedMudID) {
                    Text("Select Mud").tag(nil as UUID?)
                    ForEach(project.muds ?? [], id: \.id) { mud in
                        Text("\(mud.name) (\(String(format: "%.0f", mud.density_kgm3)))").tag(mud.id as UUID?)
                    }
                }
                .frame(width: 200)

                TextField("Vol (m\u{00B3})", value: $pumpVolume, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)

                Button("Add") {
                    addEntry()
                }
                .disabled(selectedMudID == nil)
            }
        }
        .onAppear {
            decodeQueue()
        }
    }

    private func addEntry() {
        guard let mudID = selectedMudID,
              let mud = (project.muds ?? []).first(where: { $0.id == mudID }) else { return }

        entries.append(PumpEntry(
            mudID: mudID,
            mudName: mud.name,
            density: mud.density_kgm3,
            volume: pumpVolume,
            colorR: mud.colorR,
            colorG: mud.colorG,
            colorB: mud.colorB
        ))
        encodeQueue()
    }

    private func encodeQueue() {
        struct CodableEntry: Codable {
            let mudID: UUID
            let mudName: String
            let mudDensity_kgpm3: Double
            let mudColorR: Double
            let mudColorG: Double
            let mudColorB: Double
            let volume_m3: Double
        }
        let codable = entries.map { e in
            CodableEntry(
                mudID: e.mudID,
                mudName: e.mudName,
                mudDensity_kgpm3: e.density,
                mudColorR: e.colorR,
                mudColorG: e.colorG,
                mudColorB: e.colorB,
                volume_m3: e.volume
            )
        }
        operation.pumpQueueEncoded = try? JSONEncoder().encode(codable)
    }

    private func decodeQueue() {
        guard let data = operation.pumpQueueEncoded else { return }
        struct CodableEntry: Codable {
            let mudID: UUID
            let mudName: String
            let mudDensity_kgpm3: Double
            let mudColorR: Double
            let mudColorG: Double
            let mudColorB: Double
            let volume_m3: Double
        }
        if let decoded = try? JSONDecoder().decode([CodableEntry].self, from: data) {
            entries = decoded.map { e in
                PumpEntry(
                    mudID: e.mudID,
                    mudName: e.mudName,
                    density: e.mudDensity_kgpm3,
                    volume: e.volume_m3,
                    colorR: e.mudColorR,
                    colorG: e.mudColorG,
                    colorB: e.mudColorB
                )
            }
        }
    }
}
