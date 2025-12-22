//
//  JobCodeListView.swift
//  Josh Well Control for Mac
//
//  List view for managing job codes with learned duration statistics.
//

import SwiftUI
import SwiftData

struct JobCodeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \JobCode.code) private var jobCodes: [JobCode]

    @State private var showAddJobCode = false
    @State private var editingJobCode: JobCode?
    @State private var searchText = ""
    @State private var filterCategory: JobCodeCategory?

    private var filteredJobCodes: [JobCode] {
        jobCodes.filter { jc in
            // Category filter
            if let cat = filterCategory, jc.category != cat {
                return false
            }

            // Search filter
            if !searchText.isEmpty {
                let search = searchText.lowercased()
                return jc.code.lowercased().contains(search) ||
                       jc.name.lowercased().contains(search) ||
                       jc.category.rawValue.lowercased().contains(search)
            }

            return true
        }
    }

    // Group by category
    private var groupedJobCodes: [JobCodeCategory: [JobCode]] {
        Dictionary(grouping: filteredJobCodes) { $0.category }
    }

    var body: some View {
        List {
            // Search & Filters
            Section {
                TextField("Search job codes...", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                DisclosureGroup("Filters") {
                    Picker("Category", selection: $filterCategory) {
                        Text("All Categories").tag(nil as JobCodeCategory?)
                        ForEach(JobCodeCategory.allCases, id: \.self) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat as JobCodeCategory?)
                        }
                    }
                }
            }

            // Job Codes by Category
            if filteredJobCodes.isEmpty {
                ContentUnavailableView {
                    Label("No Job Codes", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Add job codes to categorize tasks and track duration estimates.")
                }
            } else {
                ForEach(JobCodeCategory.allCases, id: \.self) { category in
                    if let codes = groupedJobCodes[category], !codes.isEmpty {
                        Section {
                            ForEach(codes) { jc in
                                JobCodeRow(jobCode: jc)
                                    .contentShape(Rectangle())
                                    .onTapGesture { editingJobCode = jc }
                                    .contextMenu {
                                        Button("Edit") { editingJobCode = jc }
                                        Button("Reset Statistics") {
                                            resetStatistics(for: jc)
                                        }
                                        Divider()
                                        Button("Delete", role: .destructive) {
                                            modelContext.delete(jc)
                                            try? modelContext.save()
                                        }
                                    }
                            }
                            .onDelete { offsets in
                                deleteJobCodes(category: category, at: offsets)
                            }
                        } header: {
                            Label(category.rawValue, systemImage: category.icon)
                        }
                    }
                }
            }
        }
        .navigationTitle("Job Codes")
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddJobCode = true } label: {
                    Label("Add Job Code", systemImage: "plus")
                }
            }
        }
        #endif
        .sheet(isPresented: $showAddJobCode) {
            JobCodeEditorView(jobCode: nil)
        }
        .sheet(item: $editingJobCode) { jc in
            JobCodeEditorView(jobCode: jc)
        }
    }

    private func deleteJobCodes(category: JobCodeCategory, at offsets: IndexSet) {
        guard let codes = groupedJobCodes[category] else { return }
        for index in offsets {
            modelContext.delete(codes[index])
        }
        try? modelContext.save()
    }

    private func resetStatistics(for jobCode: JobCode) {
        jobCode.timesPerformed = 0
        jobCode.totalDuration_min = 0
        jobCode.totalMeterage_m = 0
        jobCode.averageDuration_min = jobCode.defaultEstimate_min
        jobCode.averageDurationPerMeter_min = 0
        jobCode.updatedAt = .now
        try? modelContext.save()
    }
}

// MARK: - Job Code Row

struct JobCodeRow: View {
    let jobCode: JobCode

    var body: some View {
        HStack(spacing: 12) {
            // Category icon
            Image(systemName: jobCode.category.icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(jobCode.code)
                        .font(.headline)
                        .fontDesign(.monospaced)

                    if jobCode.isMetarageBased {
                        Image(systemName: "ruler")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Text(jobCode.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Statistics
                HStack(spacing: 12) {
                    if jobCode.timesPerformed > 0 {
                        Label("\(jobCode.timesPerformed)x", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }

                    Label(jobCode.averageDurationFormatted, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let perMeter = jobCode.perMeterRateFormatted {
                        Label(perMeter, systemImage: "ruler")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Confidence indicator based on sample size
            VStack(alignment: .trailing) {
                if jobCode.timesPerformed >= 10 {
                    Label("High", systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if jobCode.timesPerformed >= 3 {
                    Label("Medium", systemImage: "star.leadinghalf.filled")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Label("Low", systemImage: "star")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
                Text("confidence")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Job Code Editor

struct JobCodeEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Vendor.companyName) private var vendors: [Vendor]

    let jobCode: JobCode?

    @State private var code = ""
    @State private var name = ""
    @State private var category: JobCodeCategory = .other
    @State private var defaultEstimate: Double = 60
    @State private var isMetarageBased = false
    @State private var defaultVendorRequired = false
    @State private var selectedVendor: Vendor?
    @State private var notes = ""

    private var isEditing: Bool { jobCode != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Job Code") {
                    TextField("Code (e.g., DRILL-159)", text: $code)
                        .textFieldStyle(.roundedBorder)
                        #if os(macOS)
                        .textCase(.uppercase)
                        #endif

                    TextField("Name", text: $name)

                    Picker("Category", selection: $category) {
                        ForEach(JobCodeCategory.allCases, id: \.self) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                        }
                    }
                }

                Section("Duration Estimation") {
                    Toggle("Meterage-Based", isOn: $isMetarageBased)

                    HStack {
                        Text("Default Estimate")
                        Spacer()
                        TextField("", value: $defaultEstimate, format: .number)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                        Text("min")
                            .foregroundStyle(.secondary)
                    }

                    if isMetarageBased {
                        Text("Duration will be calculated as: meters × average min/m")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Vendor") {
                    Toggle("Vendor Required", isOn: $defaultVendorRequired)

                    if defaultVendorRequired {
                        Picker("Default Vendor", selection: $selectedVendor) {
                            Text("None").tag(nil as Vendor?)
                            ForEach(vendors.filter { $0.isActive }) { v in
                                Text(v.displayName).tag(v as Vendor?)
                            }
                        }
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }

                if isEditing, let jc = jobCode {
                    Section("Statistics (Read-Only)") {
                        HStack {
                            Text("Times Performed")
                            Spacer()
                            Text("\(jc.timesPerformed)")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Average Duration")
                            Spacer()
                            Text(jc.averageDurationFormatted)
                                .foregroundStyle(.secondary)
                        }
                        if jc.isMetarageBased {
                            HStack {
                                Text("Total Meterage")
                                Spacer()
                                Text(String(format: "%.1f m", jc.totalMeterage_m))
                                    .foregroundStyle(.secondary)
                            }
                            if jc.averageDurationPerMeter_min > 0 {
                                HStack {
                                    Text("Average Rate")
                                    Spacer()
                                    Text(String(format: "%.2f min/m", jc.averageDurationPerMeter_min))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Job Code" : "Add Job Code")
            #if os(macOS)
            .frame(minWidth: 450, minHeight: 500)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(code.isEmpty || name.isEmpty)
                }
            }
            .onAppear { loadJobCode() }
        }
    }

    private func loadJobCode() {
        guard let jc = jobCode else { return }
        code = jc.code
        name = jc.name
        category = jc.category
        defaultEstimate = jc.defaultEstimate_min
        isMetarageBased = jc.isMetarageBased
        defaultVendorRequired = jc.defaultVendorRequired
        selectedVendor = jc.defaultVendor
        notes = jc.notes
    }

    private func save() {
        if let jc = jobCode {
            jc.code = code.uppercased()
            jc.name = name
            jc.category = category
            jc.defaultEstimate_min = defaultEstimate
            jc.isMetarageBased = isMetarageBased
            jc.defaultVendorRequired = defaultVendorRequired
            jc.defaultVendor = selectedVendor
            jc.notes = notes
            jc.updatedAt = .now
        } else {
            let jc = JobCode(code: code.uppercased(), name: name, category: category, defaultEstimate_min: defaultEstimate, isMetarageBased: isMetarageBased)
            jc.defaultVendorRequired = defaultVendorRequired
            jc.defaultVendor = selectedVendor
            jc.notes = notes
            modelContext.insert(jc)
        }

        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    JobCodeListView()
        .modelContainer(for: JobCode.self)
}
