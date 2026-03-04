//
//  MPDTrackingViewIOS.swift
//  Josh Well Control for Mac
//
//  iOS/iPadOS optimized view for MPD Tracking
//  Real-time ECD/ESD monitoring with chart visualization
//

import SwiftUI
import SwiftData
import Charts

#if os(iOS)
import UIKit

struct MPDTrackingViewIOS: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) var sizeClass
    @Environment(\.verticalSizeClass) var vSizeClass
    
    @Bindable var project: ProjectState
    @State private var viewModel = MPDTrackingViewModel()
    @State private var selectedTab = 0
    @State private var showingDeleteConfirmation = false
    @State private var readingToDelete: UUID?
    @State private var editingBitMD: Double = 0
    @FocusState private var bitMDFieldFocused: Bool
    
    // Query readings directly for reactive updates
    @Query(sort: \MPDReading.timestamp, order: .reverse) private var allReadings: [MPDReading]
    
    /// Readings filtered to current sheet
    private var readings: [MPDReading] {
        guard let sheetID = viewModel.boundSheet?.id else { return [] }
        return allReadings.filter { $0.mpdSheet?.id == sheetID }
    }
    
    init(project: ProjectState) {
        self.project = project
    }
    
    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .phone {
                // iPhone: Tab-based navigation
                phoneLayout
            } else {
                // iPad: Adaptive layout
                if sizeClass == .regular && vSizeClass == .regular {
                    iPadLandscapeLayout
                } else {
                    iPadPortraitLayout
                }
            }
        }
        .navigationTitle("MPD Tracking")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button("Export CSV", systemImage: "doc.text") {
                        viewModel.exportReadings()
                    }
                    .disabled(readings.isEmpty)
                    
                    Button("Clear All", systemImage: "trash", role: .destructive) {
                        viewModel.clearAllReadings()
                    }
                    .disabled(readings.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Delete Reading?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let id = readingToDelete {
                    viewModel.deleteReading(id)
                    try? modelContext.save()
                    readingToDelete = nil
                }
            }
        }
        .onAppear {
            viewModel.bootstrap(project: project, context: modelContext)
            editingBitMD = viewModel.bitMD_m
        }
    }
    
    // MARK: - iPhone Layout (Tabbed)
    
    private var phoneLayout: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: Quick Add Reading
            quickAddView
                .tabItem {
                    Label("Add", systemImage: "plus.circle.fill")
                }
                .tag(0)
            
            // Tab 2: Chart
            chartView
                .tabItem {
                    Label("Chart", systemImage: "chart.xyaxis.line")
                }
                .tag(1)
            
            // Tab 3: History
            historyView
                .tabItem {
                    Label("History", systemImage: "list.bullet")
                }
                .tag(2)
        }
    }
    
    // MARK: - iPad Portrait Layout
    
    private var iPadPortraitLayout: some View {
        VStack(spacing: 0) {
            // Segmented control
            Picker("View", selection: $selectedTab) {
                Text("Add").tag(0)
                Text("Chart").tag(1)
                Text("History").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Content
            Group {
                switch selectedTab {
                case 0:
                    quickAddView
                case 1:
                    chartView
                case 2:
                    historyView
                default:
                    quickAddView
                }
            }
        }
    }
    
    // MARK: - iPad Landscape Layout
    
    private var iPadLandscapeLayout: some View {
        HStack(spacing: 0) {
            // Left: Quick add form (compact)
            quickAddView
                .frame(width: 350)
            
            Divider()
            
            // Center: Chart (large)
            chartView
                .frame(maxWidth: .infinity)
            
            Divider()
            
            // Right: History (scrollable list)
            historyView
                .frame(width: 320)
        }
    }
    
    // MARK: - Quick Add View
    
    private var quickAddView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Configuration section
                configurationSection
                
                // Input section
                inputSection
                
                // Preview section
                previewSection
                
                // Add button
                Button {
                    viewModel.addReading()
                    // Reset focus after adding
                    bitMDFieldFocused = false
                } label: {
                    Label("Add Reading", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewModel.canAddReading)
            }
            .padding()
        }
    }
    
    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configuration")
                .font(.headline)
            
            // Sheet selector
            if !viewModel.availableSheets.isEmpty {
                Picker("Sheet", selection: Binding(
                    get: { viewModel.boundSheet?.id },
                    set: { newID in
                        if let newID = newID,
                           let sheet = viewModel.availableSheets.first(where: { $0.id == newID }) {
                            viewModel.loadSheet(sheet)
                        }
                    }
                )) {
                    Text("Select Sheet").tag(nil as UUID?)
                    ForEach(viewModel.availableSheets) { sheet in
                        Text(sheet.name).tag(sheet.id as UUID?)
                    }
                }
                .pickerStyle(.menu)
            } else {
                Button("Create Sheet") {
                    viewModel.createSheet()
                }
                .buttonStyle(.bordered)
            }
            
            // Heel/Toe depths
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Text("Heel MD:")
                        .foregroundStyle(.secondary)
                    TextField("m", value: $viewModel.heelMD_m, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                        .frame(maxWidth: 120)
                }
                
                GridRow {
                    Text("Toe MD:")
                        .foregroundStyle(.secondary)
                    TextField("m", value: $viewModel.toeMD_m, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                        .frame(maxWidth: 120)
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current Reading")
                .font(.headline)
            
            // Bit MD
            VStack(alignment: .leading, spacing: 6) {
                Text("Bit MD (m)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("Measured depth", value: $editingBitMD, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                    .focused($bitMDFieldFocused)
                    .onChange(of: editingBitMD) {
                        viewModel.bitMD_m = editingBitMD
                    }
            }
            
            // Heel readings (preview - computed from inputs)
            VStack(alignment: .leading, spacing: 6) {
                Text("Heel (Preview)")
                    .font(.subheadline.weight(.medium))
                
                HStack(spacing: 12) {
                    VStack(alignment: .leading) {
                        Text("ECD (Circ)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.0f kg/m³", viewModel.previewECDAtHeel_kgm3))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    VStack(alignment: .leading) {
                        Text("ESD (Shut-In)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.0f kg/m³", viewModel.previewESDAtHeel_kgm3))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            
            // Toe readings (preview - computed from inputs)
            VStack(alignment: .leading, spacing: 6) {
                Text("Toe (Preview)")
                    .font(.subheadline.weight(.medium))
                
                HStack(spacing: 12) {
                    VStack(alignment: .leading) {
                        Text("ECD (Circ)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.0f kg/m³", viewModel.previewECDAtToe_kgm3))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    VStack(alignment: .leading) {
                        Text("ESD (Shut-In)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.0f kg/m³", viewModel.previewESDAtToe_kgm3))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.headline)
            
            if viewModel.canAddReading {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bit: \(String(format: "%.1f", viewModel.bitMD_m)) m")
                    if viewModel.inputIsCirculating {
                        Text("Heel ECD: \(String(format: "%.0f", viewModel.previewECDAtHeel_kgm3)) kg/m³")
                        Text("Toe ECD: \(String(format: "%.0f", viewModel.previewECDAtToe_kgm3)) kg/m³")
                    } else {
                        Text("Heel ESD: \(String(format: "%.0f", viewModel.previewESDAtHeel_kgm3)) kg/m³")
                        Text("Toe ESD: \(String(format: "%.0f", viewModel.previewESDAtToe_kgm3)) kg/m³")
                    }
                }
                .font(.subheadline)
            } else {
                Text("Fill in all fields to add reading")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Chart View
    
    private var chartView: some View {
        ScrollView {
            VStack(spacing: 20) {
                if readings.isEmpty {
                    emptyChartView
                } else {
                    // Heel chart
                    chartSection(
                        title: "Heel Pressures",
                        readings: readings,
                        ecdKeyPath: \.ecdAtHeel_kgm3,
                        esdKeyPath: \.esdAtHeel_kgm3
                    )
                    
                    // Toe chart
                    chartSection(
                        title: "Toe Pressures",
                        readings: readings,
                        ecdKeyPath: \.ecdAtToe_kgm3,
                        esdKeyPath: \.esdAtToe_kgm3
                    )
                }
            }
            .padding()
        }
    }
    
    private var emptyChartView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("No Readings Yet")
                .font(.title2.bold())
            Text("Add pressure readings to see charts.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
    
    private func chartSection(
        title: String,
        readings: [MPDReading],
        ecdKeyPath: KeyPath<MPDReading, Double>,
        esdKeyPath: KeyPath<MPDReading, Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            
            Chart {
                ForEach(readings) { reading in
                    LineMark(
                        x: .value("MD", reading.bitMD_m),
                        y: .value("ECD", reading[keyPath: ecdKeyPath])
                    )
                    .foregroundStyle(.blue)
                    .symbol(.circle)
                    
                    LineMark(
                        x: .value("MD", reading.bitMD_m),
                        y: .value("ESD", reading[keyPath: esdKeyPath])
                    )
                    .foregroundStyle(.green)
                    .symbol(.square)
                }
            }
            .frame(height: 250)
            .chartXAxisLabel("Bit MD (m)")
            .chartYAxisLabel("Density (kg/m³)")
            .chartLegend {
                HStack(spacing: 20) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.blue)
                            .frame(width: 10, height: 10)
                        Text("ECD (Circulating)")
                            .font(.caption)
                    }
                    HStack(spacing: 6) {
                        Rectangle()
                            .fill(.green)
                            .frame(width: 10, height: 10)
                        Text("ESD (Shut-In)")
                            .font(.caption)
                    }
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - History View
    
    private var historyView: some View {
        Group {
            if readings.isEmpty {
                emptyHistoryView
            } else {
                List {
                    ForEach(readings) { reading in
                        readingRow(reading)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    readingToDelete = reading.id
                                    showingDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }
    
    private var emptyHistoryView: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Readings")
                .font(.headline)
            Text("Add pressure readings to see history.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
    
    private func readingRow(_ reading: MPDReading) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("\(String(format: "%.1f", reading.bitMD_m)) m MD")
                    .font(.headline)
                Spacer()
                Text(reading.timestamp, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Heel values
            VStack(alignment: .leading, spacing: 4) {
                Text("Heel")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.blue)
                            .frame(width: 8, height: 8)
                        Text("ECD: \(String(format: "%.0f", reading.ecdAtHeel_kgm3))")
                            .font(.caption)
                    }
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text("ESD: \(String(format: "%.0f", reading.esdAtHeel_kgm3))")
                            .font(.caption)
                    }
                }
            }
            
            // Toe values
            VStack(alignment: .leading, spacing: 4) {
                Text("Toe")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.blue)
                            .frame(width: 8, height: 8)
                        Text("ECD: \(String(format: "%.0f", reading.ecdAtToe_kgm3))")
                            .font(.caption)
                    }
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text("ESD: \(String(format: "%.0f", reading.esdAtToe_kgm3))")
                            .font(.caption)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#endif
