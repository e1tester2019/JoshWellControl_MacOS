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
