//
//  iPadEnhancedDashboard.swift
//  Josh Well Control for Mac
//
//  iPad-optimized dashboard with touch interactions and multi-column layout
//

import SwiftUI
import SwiftData

#if os(iOS)

struct iPadEnhancedDashboard: View {
    let project: ProjectState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20, pinnedViews: [.sectionHeaders]) {
                // Project Header
                iPadDashboardHeader(project: project)

                // Metrics Grid
                Section {
                    iPadMetricsGrid(project: project)
                } header: {
                    SectionHeaderView(title: "Key Metrics", icon: "chart.bar.fill")
                }

                // Quick Actions
                Section {
                    iPadQuickActions(project: project)
                } header: {
                    SectionHeaderView(title: "Quick Actions", icon: "bolt.fill")
                }

                // Recent Activity
                Section {
                    iPadRecentActivity(project: project)
                } header: {
                    SectionHeaderView(title: "Recent Activity", icon: "clock.fill")
                }

                // Data Summary
                Section {
                    iPadDataSummary(project: project)
                } header: {
                    SectionHeaderView(title: "Data Summary", icon: "list.bullet.rectangle")
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }
}

struct SectionHeaderView: View {
    let title: String
    let icon: String

    var body: some View {
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
}

struct iPadDashboardHeader: View {
    let project: ProjectState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    HStack(spacing: 12) {
                        Label(project.well?.name ?? "Unknown Well", systemImage: "building.2")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Label("Updated \(project.updatedAt.formatted(.relative(presentation: .named)))", systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                // Project Status Indicator
                VStack(spacing: 4) {
                    Circle()
                        .fill(.green)
                        .frame(width: 12, height: 12)
                    Text("Active")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
    }
}

struct iPadMetricsGrid: View {
    let project: ProjectState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var columns: [GridItem] {
        if horizontalSizeClass == .regular {
            return Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)
        } else {
            return Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)
        }
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            MetricCardView(
                title: "Surveys",
                value: "\((project.surveys ?? []).count)",
                icon: "location.north.circle.fill",
                color: .blue
            )

            MetricCardView(
                title: "Drill String",
                value: "\((project.drillString ?? []).count)",
                icon: "cylinder.split.1x2",
                color: .orange
            )

            MetricCardView(
                title: "Annulus",
                value: "\((project.annulus ?? []).count)",
                icon: "circle.hexagonpath",
                color: .purple
            )

            MetricCardView(
                title: "Muds",
                value: "\((project.muds ?? []).count)",
                icon: "drop.fill",
                color: .green
            )

            MetricCardView(
                title: "Mud Steps",
                value: "\((project.mudSteps ?? []).count)",
                icon: "square.stack.3d.up.fill",
                color: .cyan
            )

            MetricCardView(
                title: "Final Layers",
                value: "\((project.finalLayers ?? []).count)",
                icon: "layers.fill",
                color: .indigo
            )

            MetricCardView(
                title: "Active Density",
                value: String(format: "%.0f", project.activeMudDensity_kgm3),
                subtitle: "kg/m³",
                icon: "scalemass.fill",
                color: .pink
            )

            MetricCardView(
                title: "Mud Volume",
                value: String(format: "%.1f", project.activeMudVolume_m3),
                subtitle: "m³",
                icon: "rectangle.3.group.fill",
                color: .teal
            )
        }
    }
}

struct MetricCardView: View {
    let title: String
    let value: String
    var subtitle: String? = nil
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

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(.title, design: .rounded))
                        .fontWeight(.bold)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }
}

struct iPadQuickActions: View {
    let project: ProjectState

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                QuickActionButton(title: "Add Survey", icon: "plus.circle.fill", color: .blue) {
                    // Action
                }
                QuickActionButton(title: "Edit Drill String", icon: "pencil.circle.fill", color: .orange) {
                    // Action
                }
            }

            HStack(spacing: 12) {
                QuickActionButton(title: "Define Mud", icon: "drop.circle.fill", color: .green) {
                    // Action
                }
                QuickActionButton(title: "Run Simulation", icon: "play.circle.fill", color: .purple) {
                    // Action
                }
            }
        }
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .fontWeight(.semibold)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(color.opacity(0.1))
            .foregroundStyle(color)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

struct iPadRecentActivity: View {
    let project: ProjectState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ActivityRow(
                icon: "clock.arrow.circlepath",
                title: "Project Updated",
                time: project.updatedAt,
                color: .blue
            )

            if let lastSurvey = (project.surveys ?? []).max(by: { $0.md < $1.md }) {
                ActivityRow(
                    icon: "location.north.circle.fill",
                    title: "Survey Added - MD: \(Int(lastSurvey.md))m",
                    time: project.updatedAt,
                    color: .green
                )
            }

            if let activeMud = project.activeMud {
                ActivityRow(
                    icon: "drop.fill",
                    title: "Active Mud: \(activeMud.name)",
                    time: project.updatedAt,
                    color: .purple
                )
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }
}

struct ActivityRow: View {
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
                    .fontWeight(.medium)
                Text(time.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

struct iPadDataSummary: View {
    let project: ProjectState

    var body: some View {
        VStack(spacing: 12) {
            DataSummaryRow(label: "Base Annulus Density", value: "\(Int(project.baseAnnulusDensity_kgm3)) kg/m³")
            DataSummaryRow(label: "Base String Density", value: "\(Int(project.baseStringDensity_kgm3)) kg/m³")
            DataSummaryRow(label: "Pressure Depth", value: "\(Int(project.pressureDepth_m)) m")
            DataSummaryRow(label: "Surface Line Volume", value: String(format: "%.1f m³", project.surfaceLineVolume_m3))
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }
}

struct DataSummaryRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

#endif
