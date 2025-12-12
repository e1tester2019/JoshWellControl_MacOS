//
//  MudCheckViewIOS.swift
//  Josh Well Control for Mac
//
//  iOS-optimized mud check view with form-based editing
//

#if os(iOS)
import SwiftUI
import SwiftData

struct MudCheckViewIOS: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectState
    @State private var selectedMud: MudProperties?
    @State private var showingAddSheet = false

    private var sortedMuds: [MudProperties] {
        (project.muds ?? []).sorted { $0.name < $1.name }
    }

    @ViewBuilder
    private var activeMudSection: some View {
        Section("Active Mud") {
            if let activeMud = project.activeMud {
                HStack {
                    Circle()
                        .fill(activeMud.color)
                        .frame(width: 12, height: 12)
                    Text(activeMud.name)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(activeMud.density_kgm3, format: .number) kg/m³")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No active mud selected")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var mudLibrarySection: some View {
        Section("Mud Library") {
            ForEach(sortedMuds) { mud in
                NavigationLink {
                    MudDetailViewIOS(mud: mud, project: project)
                } label: {
                    MudRowIOS(mud: mud, isActive: mud.isActive)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        deleteMud(mud)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        setActiveMud(mud)
                    } label: {
                        Label("Set Active", systemImage: "checkmark.circle")
                    }
                    .tint(.green)
                }
            }

            Button {
                showingAddSheet = true
            } label: {
                Label("Add Mud", systemImage: "plus")
            }
        }
    }

    private func setActiveMud(_ mud: MudProperties) {
        // Deactivate all other muds
        for m in (project.muds ?? []) {
            m.isActive = false
        }
        // Activate selected mud
        mud.isActive = true
        try? modelContext.save()
    }

    var body: some View {
        List {
            // Active Mud Section
            activeMudSection

            // Mud Library Section
            mudLibrarySection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Mud Check")
        .sheet(isPresented: $showingAddSheet) {
            AddMudSheetIOS(project: project, isPresented: $showingAddSheet)
        }
    }

    private func deleteMud(_ mud: MudProperties) {
        // If this was the active mud, it will be deactivated when deleted
        if let idx = project.muds?.firstIndex(where: { $0.id == mud.id }) {
            project.muds?.remove(at: idx)
        }
        modelContext.delete(mud)
        try? modelContext.save()
    }
}

// MARK: - Mud Row

private struct MudRowIOS: View {
    let mud: MudProperties
    let isActive: Bool

    var body: some View {
        HStack {
            Circle()
                .fill(mud.color)
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(mud.name)
                        .fontWeight(.medium)
                    if isActive {
                        Text("Active")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .foregroundStyle(.green)
                            .cornerRadius(4)
                    }
                }

                HStack {
                    Text("\(mud.density_kgm3, format: .number) kg/m³")
                    if let pv = mud.pv_mPa_s {
                        Text("• PV: \(pv, format: .number)")
                    }
                    if let yp = mud.yp_Pa {
                        Text("• YP: \(yp, format: .number)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

// MARK: - Mud Detail View

struct MudDetailViewIOS: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var mud: MudProperties
    let project: ProjectState

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Name", text: $mud.name)

                ColorPicker("Color", selection: $mud.color)
            }

            Section("Properties") {
                HStack {
                    Text("Density")
                    Spacer()
                    TextField("Density", value: $mud.density_kgm3, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    Text("kg/m³")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("PV")
                    Spacer()
                    TextField("PV", value: $mud.pv_mPa_s, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    Text("cP")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("YP")
                    Spacer()
                    TextField("YP", value: $mud.yp_Pa, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    Text("Pa")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Fann Readings") {
                HStack {
                    Text("600 RPM")
                    Spacer()
                    TextField("600", value: $mud.dial600, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }

                HStack {
                    Text("300 RPM")
                    Spacer()
                    TextField("300", value: $mud.dial300, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }

                Button("Update Rheology from Fann") {
                    mud.updateRheologyFromFann()
                    try? modelContext.save()
                }
            }

            Section("Rheology Model") {
                Picker("Model", selection: $mud.rheologyModel) {
                    Text("Bingham").tag("Bingham")
                    Text("Power Law").tag("PowerLaw")
                    Text("Herschel-Bulkley").tag("HB")
                }
            }

            Section("Gel Strengths") {
                HStack {
                    Text("10 sec")
                    Spacer()
                    TextField("10s", value: $mud.gel10s_Pa, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    Text("Pa")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("10 min")
                    Spacer()
                    TextField("10m", value: $mud.gel10m_Pa, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    Text("Pa")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    setActiveMud(mud)
                } label: {
                    Label("Set as Active Mud", systemImage: "checkmark.circle")
                }
                .disabled(mud.isActive)
            }
        }
        .navigationTitle(mud.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func setActiveMud(_ mud: MudProperties) {
        // Deactivate all other muds
        for m in (project.muds ?? []) {
            m.isActive = false
        }
        // Activate selected mud
        mud.isActive = true
        try? modelContext.save()
    }
}

// MARK: - Add Mud Sheet

private struct AddMudSheetIOS: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let project: ProjectState
    @Binding var isPresented: Bool

    @State private var name = "New Mud"
    @State private var density: Double = 1200
    @State private var color = Color.brown

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)

                HStack {
                    Text("Density")
                    Spacer()
                    TextField("Density", value: $density, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    Text("kg/m³")
                        .foregroundStyle(.secondary)
                }

                ColorPicker("Color", selection: $color)
            }
            .navigationTitle("Add Mud")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addMud()
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }

    private func addMud() {
        let mud = MudProperties(
            name: name,
            density_kgm3: density,
            pv_Pa_s: 0.020,    // 20 mPa·s = 0.020 Pa·s
            yp_Pa: 10,
            rheologyModel: "Bingham",
            gel10s_Pa: 5,
            gel10m_Pa: 10,
            dial600: 40,
            dial300: 20,
            color: color
        )
        mud.project = project
        if project.muds == nil { project.muds = [] }
        project.muds?.append(mud)
        modelContext.insert(mud)
        try? modelContext.save()
    }
}

#endif
