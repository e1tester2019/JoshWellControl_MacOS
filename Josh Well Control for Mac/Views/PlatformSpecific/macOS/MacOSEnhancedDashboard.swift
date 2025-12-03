//
//  MacOSEnhancedDashboard.swift
//  Josh Well Control for Mac
//
//  macOS-optimized dashboard with native controls and window-based layout
//

import SwiftUI
import SwiftData

#if os(macOS)
import AppKit

struct MacOSEnhancedDashboard: View {
    let project: ProjectState
    @Environment(\.modelContext) private var modelContext
    @State private var selectedSection: DashboardSection = .overview

    enum DashboardSection: String, CaseIterable, Identifiable {
        case overview
        case geometry
        case fluids
        case operations

        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: return "Overview"
            case .geometry: return "Well Geometry"
            case .fluids: return "Fluids & Mud"
            case .operations: return "Operations"
            }
        }

        var icon: String {
            switch self {
            case .overview: return "gauge.with.dots.needle.67percent"
            case .geometry: return "cylinder.split.1x2"
            case .fluids: return "drop.fill"
            case .operations: return "gearshape.2.fill"
            }
        }
    }

    var body: some View {
        HSplitView {
            // Left sidebar - section selection
            VStack(alignment: .leading, spacing: 0) {
                Text("Dashboard")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding()

                Divider()

                List(DashboardSection.allCases, id: \.self, selection: $selectedSection) { section in
                    Label(section.title, systemImage: section.icon)
                        .padding(.vertical, 4)
                }
                .listStyle(.sidebar)

                Spacer()

                // Project info at bottom
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.headline)
                    Text("Last updated: \(project.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5))
            }
            .frame(minWidth: 200, idealWidth: 240, maxWidth: 280)

            // Main content area
            ScrollView {
                Group {
                    switch selectedSection {
                    case .overview:
                        MacOSOverviewSection(project: project)
                    case .geometry:
                        MacOSGeometrySection(project: project)
                    case .fluids:
                        MacOSFluidsSection(project: project)
                    case .operations:
                        MacOSOperationsSection(project: project)
                    }
                }
                .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Overview Section

struct MacOSOverviewSection: View {
    let project: ProjectState

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header with project details
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.name)
                            .font(.system(.largeTitle, design: .rounded))
                            .fontWeight(.bold)

                        if let wellName = project.well?.name {
                            Label(wellName, systemImage: "building.2")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    // Status indicator
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.green)
                            .frame(width: 10, height: 10)
                        Text("Active")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.quaternary.opacity(0.5))
                    .cornerRadius(8)
                }

                Divider()
            }

            // Key metrics in grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 16) {
                MacOSMetricCard(
                    title: "Surveys",
                    value: "\((project.surveys ?? []).count)",
                    icon: "location.north.circle.fill",
                    color: .blue
                )

                MacOSMetricCard(
                    title: "Drill String Sections",
                    value: "\((project.drillString ?? []).count)",
                    icon: "cylinder.split.1x2",
                    color: .orange
                )

                MacOSMetricCard(
                    title: "Annulus Sections",
                    value: "\((project.annulus ?? []).count)",
                    icon: "circle.hexagonpath",
                    color: .purple
                )

                MacOSMetricCard(
                    title: "Mud Types",
                    value: "\((project.muds ?? []).count)",
                    icon: "drop.fill",
                    color: .green
                )
            }

            // Quick stats table
            GroupBox("Project Parameters") {
                VStack(spacing: 12) {
                    MacOSParameterRow(label: "Base Annulus Density", value: "\(Int(project.baseAnnulusDensity_kgm3)) kg/m³")
                    Divider()
                    MacOSParameterRow(label: "Base String Density", value: "\(Int(project.baseStringDensity_kgm3)) kg/m³")
                    Divider()
                    MacOSParameterRow(label: "Pressure Depth", value: "\(Int(project.pressureDepth_m)) m")
                    Divider()
                    MacOSParameterRow(label: "Active Mud Density", value: "\(Int(project.activeMudDensity_kgm3)) kg/m³")
                    Divider()
                    MacOSParameterRow(label: "Active Mud Volume", value: String(format: "%.1f m³", project.activeMudVolume_m3))
                    Divider()
                    MacOSParameterRow(label: "Surface Line Volume", value: String(format: "%.1f m³", project.surfaceLineVolume_m3))
                }
                .padding()
            }

            // Recent activity
            GroupBox("Recent Activity") {
                VStack(alignment: .leading, spacing: 8) {
                    MacOSActivityItem(
                        icon: "clock.arrow.circlepath",
                        title: "Project updated",
                        time: project.updatedAt,
                        color: .blue
                    )

                    if let lastSurvey = (project.surveys ?? []).max(by: { $0.md < $1.md }) {
                        MacOSActivityItem(
                            icon: "location.north.circle.fill",
                            title: "Survey at MD: \(Int(lastSurvey.md))m",
                            time: project.updatedAt,
                            color: .green
                        )
                    }

                    if let activeMud = project.activeMud {
                        MacOSActivityItem(
                            icon: "drop.fill",
                            title: "Active mud: \(activeMud.name)",
                            time: project.updatedAt,
                            color: activeMud.color
                        )
                    }
                }
                .padding()
            }
        }
    }
}

// MARK: - Geometry Section

struct MacOSGeometrySection: View {
    let project: ProjectState

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Well Geometry")
                .font(.title)
                .fontWeight(.bold)

            HStack(spacing: 16) {
                // Drill String summary
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Drill String", systemImage: "cylinder.split.1x2")
                            .font(.headline)

                        Divider()

                        if let drillString = project.drillString, !drillString.isEmpty {
                            ForEach(drillString.prefix(5)) { section in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(section.name)
                                            .font(.subheadline)
                                        Text("Top: \(Int(section.topDepth_m))m, Length: \(Int(section.length_m))m")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                if section != drillString.prefix(5).last {
                                    Divider()
                                }
                            }

                            if drillString.count > 5 {
                                Text("+\(drillString.count - 5) more sections")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("No drill string sections defined")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                }
                .frame(maxWidth: .infinity)

                // Annulus summary
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Annulus", systemImage: "circle.hexagonpath")
                            .font(.headline)

                        Divider()

                        if let annulus = project.annulus, !annulus.isEmpty {
                            ForEach(annulus.prefix(5)) { section in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(section.name)
                                            .font(.subheadline)
                                        Text("Top: \(Int(section.topDepth_m))m, Length: \(Int(section.length_m))m")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                if section != annulus.prefix(5).last {
                                    Divider()
                                }
                            }

                            if annulus.count > 5 {
                                Text("+\(annulus.count - 5) more sections")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("No annulus sections defined")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                }
                .frame(maxWidth: .infinity)
            }

            // Survey summary
            GroupBox("Surveys") {
                if let surveys = project.surveys, !surveys.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Total Surveys: \(surveys.count)")
                                .font(.headline)
                            Spacer()
                        }

                        Divider()

                        HStack(spacing: 32) {
                            VStack(alignment: .leading) {
                                Text("Deepest MD")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(Int((surveys.max(by: { $0.md < $1.md })?.md ?? 0))) m")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                            }

                            VStack(alignment: .leading) {
                                Text("Max Inclination")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.1f°", (surveys.max(by: { $0.inc < $1.inc })?.inc ?? 0)))
                                    .font(.title2)
                                    .fontWeight(.semibold)
                            }

                            Spacer()
                        }
                    }
                    .padding()
                } else {
                    Text("No surveys defined")
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
        }
    }
}

// MARK: - Fluids Section

struct MacOSFluidsSection: View {
    let project: ProjectState

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Fluids & Mud")
                .font(.title)
                .fontWeight(.bold)

            // Active mud highlight
            if let activeMud = project.activeMud {
                GroupBox {
                    HStack(spacing: 16) {
                        Circle()
                            .fill(activeMud.color.gradient)
                            .frame(width: 60, height: 60)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Active Mud")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(activeMud.name)
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("\(Int(activeMud.density_kgm3)) kg/m³")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Rheology")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(activeMud.rheologyModel.rawValue)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }
                    .padding()
                }
            }

            // All muds
            GroupBox("Defined Muds (\((project.muds ?? []).count))") {
                if let muds = project.muds, !muds.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(muds, id: \.id) { mud in
                            HStack {
                                Circle()
                                    .fill(mud.color)
                                    .frame(width: 24, height: 24)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mud.name)
                                        .font(.subheadline)
                                    Text("\(Int(mud.density_kgm3)) kg/m³ • \(mud.rheologyModel.rawValue)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if mud.isActive {
                                    Label("Active", systemImage: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            }
                            .padding(.vertical, 4)

                            if mud != muds.last {
                                Divider()
                            }
                        }
                    }
                    .padding()
                } else {
                    Text("No muds defined")
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }

            // Mud placement summary
            GroupBox("Mud Placement") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Mud Steps")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\((project.mudSteps ?? []).count)")
                                .font(.title2)
                                .fontWeight(.semibold)
                        }

                        Spacer()

                        VStack(alignment: .leading) {
                            Text("Final Layers")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\((project.finalLayers ?? []).count)")
                                .font(.title2)
                                .fontWeight(.semibold)
                        }

                        Spacer()
                    }
                }
                .padding()
            }
        }
    }
}

// MARK: - Operations Section

struct MacOSOperationsSection: View {
    let project: ProjectState

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Operations")
                .font(.title)
                .fontWeight(.bold)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 2), spacing: 16) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Swab Runs", systemImage: "arrow.up.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.blue)

                        Text("\((project.swabRuns ?? []).count) runs")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Trip Runs", systemImage: "play.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.purple)

                        Text("\((project.tripRuns ?? []).count) runs")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Pump Stages", systemImage: "timer")
                            .font(.headline)
                            .foregroundStyle(.green)

                        Text("\((project.programStages ?? []).count) stages")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Well Data", systemImage: "doc.text.fill")
                            .font(.headline)
                            .foregroundStyle(.orange)

                        Text("Export Available")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
            }
        }
    }
}

// MARK: - Supporting Components

struct MacOSMetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color.gradient)
                Spacer()
            }

            Text(value)
                .font(.system(.title, design: .rounded))
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3))
        .cornerRadius(8)
    }
}

struct MacOSParameterRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
        }
    }
}

struct MacOSActivityItem: View {
    let icon: String
    let title: String
    let time: Date
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                Text(time.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

#endif
