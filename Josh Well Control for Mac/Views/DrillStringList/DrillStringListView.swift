//
//  DrillStringListView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-02.
//


// DrillStringListView.swift
import SwiftUI
import SwiftData

struct DrillStringListView: View {
    @Environment(\.modelContext) private var modelContext
    let project: ProjectState
    @State private var viewmodel: ViewModel
    @State private var itemToDelete: DrillStringSection?
    
    init(project: ProjectState) {
        self.project = project
        _viewmodel = State(initialValue: ViewModel(project: project))
    }

    var body: some View {
        VStack {
            List(selection: $viewmodel.selection) {
                ForEach(Array(viewmodel.sortedSections.enumerated()), id: \.element.id) { index, sec in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(sec.name)")
                            Text(viewmodel.detailsString(sec))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            let prevBottom = index > 0 ? viewmodel.sortedSections[index - 1].bottomDepth_m : nil
                            if let prevBottom, sec.topDepth_m > prevBottom {
                                Text("Gap above: \(sec.topDepth_m - prevBottom, format: .number) m")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        Spacer()
                        HStack(spacing: 8) {
                            Button("Edit") { viewmodel.navigateToDetail(for: sec) }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                                .help("Open details")
                            Button(role: .destructive) { itemToDelete = sec } label: {
                                Label("Delete", systemImage: "trash").labelStyle(.iconOnly)
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                            .help("Delete this section")
                        }
                    }
                    .contentShape(Rectangle())
                    .tag(sec)
                }
                .onDelete { idx in
                    let items = idx.map { viewmodel.sortedSections[$0] }
                    items.forEach { viewmodel.delete($0) }
                }

                // Summary row
                if !viewmodel.sortedSections.isEmpty {
                    let totalCapacity = viewmodel.sortedSections.reduce(0.0) { $0 + viewmodel.sectionCapacity_m3($1) }
                    let totalDisplacement = viewmodel.sortedSections.reduce(0.0) { $0 + viewmodel.sectionDisplacement_m3($1) }
                    Section {
                        HStack {
                            Text("Total")
                                .font(.headline)
                            Spacer()
                            Text(String(format: "Cap: %.3f m\u{00B3}   Disp: %.3f m\u{00B3}", totalCapacity, totalDisplacement))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            HStack {
                TextField("New section name", text: $viewmodel.newName).textFieldStyle(.roundedBorder)
                Button {
                    viewmodel.add()
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
            .padding()
        }
        .navigationTitle("Drill String")
        .onAppear {
            viewmodel.attach(context: modelContext)
        }
        .onChange(of: project) { _, newProject in
            viewmodel.project = newProject
        }
        .toolbar {
            if viewmodel.hasGaps {
                ToolbarItemGroup {
                    Button("Fill Gaps") { viewmodel.fillGaps() }
                        .help("Extend previous section to remove gaps up to the next section")
                }
            }
        }
        .alert("Delete Section?", isPresented: Binding(
            get: { itemToDelete != nil },
            set: { if !$0 { itemToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let item = itemToDelete {
                    viewmodel.delete(item)
                    itemToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                itemToDelete = nil
            }
        } message: {
            Text("Are you sure you want to delete this section? This cannot be undone.")
        }
        .sheet(item: $viewmodel.activeSection) { sec in
            DrillStringDetailView(section: sec)
                .frame(minWidth:640, minHeight: 420)
        }
    }
}

extension DrillStringListView {
    @Observable
    class ViewModel {
        
        var project: ProjectState
        var isAdding = false
        var newName = "5\" DP"
        var selection: DrillStringSection?
        var activeSection: DrillStringSection?
        private var context: ModelContext?
        func attach(context: ModelContext) { self.context = context }
        init(project: ProjectState) { self.project = project }
        
        func detailsString(_ s: DrillStringSection) -> String {
            let top = s.topDepth_m
            let bottom = s.bottomDepth_m
            let len = s.length_m
            let cap = sectionCapacity_m3(s)
            let capPerM = sectionCapacityPerM_m3perm(s)
            let disp = sectionDisplacement_m3(s)
            let dispPerM = sectionDisplacementPerM_m3perm(s)
            return String(
                format: "Top: %.2f m   Bottom: %.2f m   Length: %.2f m   Pipe Cap: %.1f m³ ( %.5f m³/m)   Pipe Disp: %.1f m³ (%.5f m³/m)",
                top, bottom, len, cap, capPerM, disp, dispPerM
            )
        }

        var sortedSections: [DrillStringSection] {
            (project.drillString ?? []).sorted { a, b in a.topDepth_m < b.topDepth_m }
        }

        var hasGaps: Bool {
            let secs = sortedSections
            guard secs.count > 1 else { return false }
            for i in 1..<secs.count {
                if secs[i].topDepth_m > secs[i - 1].bottomDepth_m { return true }
            }
            return false
        }
        
        func add() {
            // Compute next available top as the max bottom among sections
            let nextTop = (project.drillString ?? []).map { $0.bottomDepth_m }.max() ?? 0
            let s = DrillStringSection(
                name: newName,
                topDepth_m: nextTop,
                length_m: 100,
                outerDiameter_m: 0.127,
                innerDiameter_m: 0.0953
            )
            s.project = project
            if project.drillString == nil {
                project.drillString = []
            }
            project.drillString?.append(s)
            try? context?.save()
            newName = "New Section"
        }

        func delete(_ section: DrillStringSection) {
            // CRITICAL: Clear selections IMMEDIATELY if they match the object being deleted
            if selection?.id == section.id {
                selection = nil
            }
            if activeSection?.id == section.id {
                activeSection = nil
            }

            if let i = (project.drillString ?? []).firstIndex(where: { $0.id == section.id }) {
                project.drillString?.remove(at: i)
            }
            context?.delete(section)
            try? context?.save()
        }

        func deleteSelected() {
            guard let sel = selection else { return }
            delete(sel)
            selection = nil
            // Clear selection after deletion
        }

        func navigateToDetail(for section: DrillStringSection) {
            activeSection = section
        }

        func fillGaps() {
            let sections = sortedSections
            guard sections.count > 1 else { return }
            for i in 1..<sections.count {
                let prev = sections[i - 1]
                let curr = sections[i]
                let gap = curr.topDepth_m - prev.bottomDepth_m
                if gap > 0 { prev.length_m += gap }
            }
            try? context?.save()
        }

        func sectionCapacity_m3(_ s: DrillStringSection) -> Double {
            let id = max(s.innerDiameter_m, 0)
            let L = max(s.length_m, 0)
            return .pi * pow(id, 2) / 4.0 * L
        }
        func sectionDisplacement_m3(_ s: DrillStringSection) -> Double {
            let od = max(s.outerDiameter_m, 0)
            let L = max(s.length_m, 0)
            return .pi * pow(od, 2) / 4.0 * L
        }
        func sectionCapacityPerM_m3perm(_ s: DrillStringSection) -> Double {
            let id = max(s.innerDiameter_m, 0)
            return .pi * pow(id, 2) / 4.0
        }
        func sectionDisplacementPerM_m3perm(_ s: DrillStringSection) -> Double {
            let od = max(s.outerDiameter_m, 0)
            return .pi * pow(od, 2) / 4.0
        }
    }
}

#if DEBUG
import SwiftData

private struct DrillStringListPreview: View {
    let container: ModelContainer
    let project: ProjectState
    
    init() {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        self.container = try! ModelContainer(
            for: ProjectState.self,
            DrillStringSection.self,
            AnnulusSection.self,
            configurations: config
        )
        let context = container.mainContext
        let p = ProjectState()
        context.insert(p)
        
        let s1 = DrillStringSection(name: "5\" DP", topDepth_m: 0, length_m: 500, outerDiameter_m: 0.127, innerDiameter_m: 0.0953)
        let s2 = DrillStringSection(name: "5\" HWDP", topDepth_m: 500, length_m: 100, outerDiameter_m: 0.127, innerDiameter_m: 0.0953)
        let s3 = DrillStringSection(name: "6-1/2\" Collar", topDepth_m: 600, length_m: 90, outerDiameter_m: 0.165, innerDiameter_m: 0.070)
        if p.drillString == nil { p.drillString = [] }
        [s1, s2, s3].forEach { s in s.project = p; p.drillString?.append(s); context.insert(s) }
        try? context.save()
        self.project = p
    }
    
    
    var body: some View {
        DrillStringListView(project: project)
            .modelContainer(container)
            .frame(width: 720, height: 460)
    }
}

#Preview("Drill String – Sample Data") {
    DrillStringListPreview()
}
#endif
