//
//  FrozenInputsDetailView.swift
//  Josh Well Control for Mac
//
//  Displays the frozen simulation inputs for verification.
//

import SwiftUI

/// Shows the frozen inputs captured when a simulation was saved
struct FrozenInputsDetailView: View {
    let simulation: TripSimulation
    let currentProject: ProjectState?

    @Environment(\.dismiss) private var dismiss

    private var frozen: FrozenSimulationInputs? {
        simulation.frozenInputs
    }

    private var isStale: Bool {
        guard let project = currentProject else { return false }
        return simulation.isStale(comparedTo: project)
    }

    private var changes: [String] {
        guard let project = currentProject else { return [] }
        return simulation.getChanges(comparedTo: project)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Frozen Inputs")
                        .font(.headline)
                    Text(simulation.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()
            .background(.bar)

            Divider()

            if let frozen = frozen {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Capture info
                        captureInfoSection(frozen)

                        // Staleness warning
                        if isStale {
                            stalenessWarning
                        }

                        // Drill String
                        drillStringSection(frozen)

                        // Annulus
                        annulusSection(frozen)

                        // Muds
                        mudsSection(frozen)

                        // Surveys
                        surveysSection(frozen)
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "No Frozen Inputs",
                    systemImage: "snowflake.slash",
                    description: Text("This simulation was created before input freezing was implemented.\n\nRe-run the simulation to capture inputs.")
                )
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    // MARK: - Sections

    private func captureInfoSection(_ frozen: FrozenSimulationInputs) -> some View {
        GroupBox {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Captured At:")
                        .foregroundStyle(.secondary)
                    Text(frozen.capturedAt, style: .date) +
                    Text(" at ") +
                    Text(frozen.capturedAt, style: .time)
                }
                GridRow {
                    Text("Input Hash:")
                        .foregroundStyle(.secondary)
                    Text(frozen.inputHash)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Max DS Depth:")
                        .foregroundStyle(.secondary)
                    Text("\(frozen.maxDrillStringDepth_m, specifier: "%.1f") m")
                }
                GridRow {
                    Text("Total Annulus Vol:")
                        .foregroundStyle(.secondary)
                    Text("\(frozen.totalAnnulusVolume_m3, specifier: "%.2f") m³")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Capture Info", systemImage: "clock")
        }
    }

    private var stalenessWarning: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Inputs Have Changed", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.headline)

                Text("The project geometry has changed since this simulation was run. The simulation results are still valid for the frozen inputs shown below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !changes.isEmpty {
                    Divider()
                    Text("Changes detected:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(changes, id: \.self) { change in
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            Text(change)
                                .font(.caption)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .backgroundStyle(.orange.opacity(0.1))
    }

    private func drillStringSection(_ frozen: FrozenSimulationInputs) -> some View {
        GroupBox {
            if frozen.drillString.isEmpty {
                Text("No drill string sections")
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                Table(frozen.drillString) {
                    TableColumn("Name") { section in
                        Text(section.name)
                    }
                    .width(min: 80, ideal: 120)

                    TableColumn("Top (m)") { section in
                        Text("\(section.topDepth_m, specifier: "%.1f")")
                            .monospacedDigit()
                    }
                    .width(min: 60, ideal: 70)

                    TableColumn("Length (m)") { section in
                        Text("\(section.length_m, specifier: "%.1f")")
                            .monospacedDigit()
                    }
                    .width(min: 60, ideal: 80)

                    TableColumn("OD (mm)") { section in
                        Text("\(section.outerDiameter_m * 1000, specifier: "%.1f")")
                            .monospacedDigit()
                    }
                    .width(min: 60, ideal: 70)

                    TableColumn("ID (mm)") { section in
                        Text("\(section.innerDiameter_m * 1000, specifier: "%.1f")")
                            .monospacedDigit()
                    }
                    .width(min: 60, ideal: 70)
                }
                .frame(height: CGFloat(min(frozen.drillString.count, 6)) * 28 + 30)
            }
        } label: {
            Label("Drill String (\(frozen.drillString.count) sections)", systemImage: "cylinder.split.1x2")
        }
    }

    private func annulusSection(_ frozen: FrozenSimulationInputs) -> some View {
        GroupBox {
            if frozen.annulus.isEmpty {
                Text("No annulus sections")
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                Table(frozen.annulus) {
                    TableColumn("Name") { section in
                        Text(section.name)
                    }
                    .width(min: 80, ideal: 120)

                    TableColumn("Top (m)") { section in
                        Text("\(section.topDepth_m, specifier: "%.1f")")
                            .monospacedDigit()
                    }
                    .width(min: 60, ideal: 70)

                    TableColumn("Length (m)") { section in
                        Text("\(section.length_m, specifier: "%.1f")")
                            .monospacedDigit()
                    }
                    .width(min: 60, ideal: 80)

                    TableColumn("Hole ID (mm)") { section in
                        Text("\(section.innerDiameter_m * 1000, specifier: "%.1f")")
                            .monospacedDigit()
                    }
                    .width(min: 70, ideal: 80)

                    TableColumn("Pipe OD (mm)") { section in
                        Text("\(section.outerDiameter_m * 1000, specifier: "%.1f")")
                            .monospacedDigit()
                    }
                    .width(min: 70, ideal: 80)

                    TableColumn("Vol (m³)") { section in
                        Text("\(section.volume_m3, specifier: "%.2f")")
                            .monospacedDigit()
                    }
                    .width(min: 60, ideal: 70)
                }
                .frame(height: CGFloat(min(frozen.annulus.count, 6)) * 28 + 30)
            }
        } label: {
            Label("Annulus (\(frozen.annulus.count) sections)", systemImage: "circle.circle")
        }
    }

    private func mudsSection(_ frozen: FrozenSimulationInputs) -> some View {
        GroupBox {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                // Active mud
                GridRow {
                    Text("Active Mud:")
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    if let mud = frozen.activeMud {
                        mudRow(mud)
                    } else {
                        Text("Not set")
                            .italic()
                            .foregroundStyle(.secondary)
                    }
                }

                // Backfill mud
                GridRow {
                    Text("Backfill Mud:")
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    if let mud = frozen.backfillMud {
                        mudRow(mud)
                    } else {
                        Text("Not set")
                            .italic()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Mud Properties", systemImage: "drop.fill")
        }
    }

    private func mudRow(_ mud: FrozenMud) -> some View {
        HStack(spacing: 12) {
            // Color swatch
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(red: mud.colorR, green: mud.colorG, blue: mud.colorB, opacity: mud.colorA))
                .frame(width: 16, height: 16)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(.secondary, lineWidth: 0.5))

            Text(mud.name)

            Text("•")
                .foregroundStyle(.secondary)

            Text("\(mud.density_kgm3, specifier: "%.0f") kg/m³")
                .monospacedDigit()

            if let d600 = mud.dial600, let d300 = mud.dial300 {
                Text("•")
                    .foregroundStyle(.secondary)
                Text("θ600: \(d600, specifier: "%.0f"), θ300: \(d300, specifier: "%.0f")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func surveysSection(_ frozen: FrozenSimulationInputs) -> some View {
        GroupBox {
            if frozen.surveys.isEmpty {
                Text("No survey data (vertical well assumed)")
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(frozen.surveys.count) survey stations")

                    HStack(spacing: 16) {
                        VStack(alignment: .leading) {
                            Text("First:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let first = frozen.surveys.first {
                                Text("MD: \(first.md, specifier: "%.1f") m → TVD: \(first.tvd, specifier: "%.1f") m")
                                    .font(.caption)
                                    .monospacedDigit()
                            }
                        }

                        VStack(alignment: .leading) {
                            Text("Last:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let last = frozen.surveys.last {
                                Text("MD: \(last.md, specifier: "%.1f") m → TVD: \(last.tvd, specifier: "%.1f") m")
                                    .font(.caption)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
        } label: {
            Label("Surveys (\(frozen.surveys.count) stations)", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
        }
    }
}

// MARK: - Trip In Simulation Support

/// Shows the frozen inputs for a TripInSimulation
struct FrozenInputsDetailViewTripIn: View {
    let simulation: TripInSimulation
    let currentProject: ProjectState?

    @Environment(\.dismiss) private var dismiss

    private var frozen: FrozenSimulationInputs? {
        simulation.frozenInputs
    }

    private var isStale: Bool {
        guard let project = currentProject else { return false }
        return simulation.isStale(comparedTo: project)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Frozen Inputs")
                        .font(.headline)
                    Text(simulation.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()
            .background(.bar)

            Divider()

            if let frozen = frozen {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Capture info
                        captureInfoSection(frozen)

                        // Staleness warning
                        if isStale {
                            stalenessWarning
                        }

                        // Annulus (primary for trip-in)
                        annulusSection(frozen)

                        // Muds
                        mudsSection(frozen)

                        // Surveys
                        surveysSection(frozen)
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "No Frozen Inputs",
                    systemImage: "snowflake.slash",
                    description: Text("This simulation was created before input freezing was implemented.\n\nRe-run the simulation to capture inputs.")
                )
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    // Reuse the same section builders (simplified for brevity)
    private func captureInfoSection(_ frozen: FrozenSimulationInputs) -> some View {
        GroupBox {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Captured At:")
                        .foregroundStyle(.secondary)
                    Text(frozen.capturedAt, style: .date) +
                    Text(" at ") +
                    Text(frozen.capturedAt, style: .time)
                }
                GridRow {
                    Text("Input Hash:")
                        .foregroundStyle(.secondary)
                    Text(frozen.inputHash)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Capture Info", systemImage: "clock")
        }
    }

    private var stalenessWarning: some View {
        GroupBox {
            Label("Inputs Have Changed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.headline)
            Text("The project geometry has changed since this simulation was run.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .backgroundStyle(.orange.opacity(0.1))
    }

    private func annulusSection(_ frozen: FrozenSimulationInputs) -> some View {
        GroupBox {
            if frozen.annulus.isEmpty {
                Text("No annulus sections")
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                Table(frozen.annulus) {
                    TableColumn("Name") { section in
                        Text(section.name)
                    }
                    TableColumn("Top (m)") { section in
                        Text("\(section.topDepth_m, specifier: "%.1f")")
                            .monospacedDigit()
                    }
                    TableColumn("Length (m)") { section in
                        Text("\(section.length_m, specifier: "%.1f")")
                            .monospacedDigit()
                    }
                    TableColumn("Vol (m³)") { section in
                        Text("\(section.volume_m3, specifier: "%.2f")")
                            .monospacedDigit()
                    }
                }
                .frame(height: CGFloat(min(frozen.annulus.count, 6)) * 28 + 30)
            }
        } label: {
            Label("Annulus (\(frozen.annulus.count) sections)", systemImage: "circle.circle")
        }
    }

    private func mudsSection(_ frozen: FrozenSimulationInputs) -> some View {
        GroupBox {
            if let mud = frozen.activeMud {
                HStack {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(red: mud.colorR, green: mud.colorG, blue: mud.colorB))
                        .frame(width: 16, height: 16)
                    Text(mud.name)
                    Text("•").foregroundStyle(.secondary)
                    Text("\(mud.density_kgm3, specifier: "%.0f") kg/m³")
                        .monospacedDigit()
                }
            } else {
                Text("No mud data captured")
                    .foregroundStyle(.secondary)
                    .italic()
            }
        } label: {
            Label("Mud", systemImage: "drop.fill")
        }
    }

    private func surveysSection(_ frozen: FrozenSimulationInputs) -> some View {
        GroupBox {
            Text("\(frozen.surveys.count) survey stations")
                .foregroundStyle(frozen.surveys.isEmpty ? .secondary : .primary)
        } label: {
            Label("Surveys", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
        }
    }
}

// MARK: - Identifiable conformance for Table

extension FrozenDrillString: Identifiable {
    var id: String { "\(name)-\(topDepth_m)-\(length_m)" }
}

extension FrozenAnnulus: Identifiable {
    var id: String { "\(name)-\(topDepth_m)-\(length_m)" }
}
