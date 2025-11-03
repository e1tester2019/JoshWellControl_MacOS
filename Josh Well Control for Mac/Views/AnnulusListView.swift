//
//  AnnulusListView.swift
//  Josh Well Control for Mac
//
//  Created by Josh Sallows on 2025-11-02.
//

// AnnulusListView.swift
import SwiftUI
import SwiftData

struct AnnulusListView: View {
    /// Change signature for drill string list that triggers when IDs, depths, or OD change
    private var drillStringSignature: [String] {
        project.drillString
            .sorted { $0.topDepth_m < $1.topDepth_m }
            .map { ds in
                "\(ds.id.uuidString)|\(ds.topDepth_m)|\(ds.bottomDepth_m)|\(ds.outerDiameter_m)"
            }
    }
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectState
    @State private var newName = "13-3/8\" × 5\""
    @State private var selection: AnnulusSection?
    @State private var activeSection: AnnulusSection?

    private var sortedSections: [AnnulusSection] {
        project.annulus.sorted { a, b in a.topDepth_m < b.topDepth_m }
    }

    private var hasGaps: Bool {
        let secs = sortedSections
        guard secs.count > 1 else { return false }
        for i in 1..<secs.count {
            if secs[i].topDepth_m > secs[i - 1].bottomDepth_m { return true }
        }
        return false
    }

    var body: some View {
        NavigationStack {
            VStack {
                List(selection: $selection) {
                    ForEach(Array(sortedSections.enumerated()), id: \.element.id) { index, sec in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sec.name)
                                    .font(.headline)
                                // Gap warning (if any)
                                let prevBottom = index > 0 ? sortedSections[index - 1].bottomDepth_m : nil
                                if let prevBottom, sec.topDepth_m > prevBottom {
                                    Text("Gap above: \(sec.topDepth_m - prevBottom, format: .number) m")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                                Text("Top: \(sec.topDepth_m, format: .number.precision(.fractionLength(2))) m   Bottom: \(sec.bottomDepth_m, format: .number.precision(.fractionLength(2))) m   Length: \(sec.length_m, format: .number.precision(.fractionLength(2))) m   Ann Cap: \(annularCapacityWithPipe_m3(sec), format: .number.precision(.fractionLength(1))) m³ ( \(annularCapacityWithPipePerM_m3perm(sec), format: .number.precision(.fractionLength(5))) m³/m)   OH Cap: \(openHoleCapacity_m3(sec), format: .number.precision(.fractionLength(1))) m³ (\(openHoleCapacityPerM_m3perm(sec), format: .number.precision(.fractionLength(5))) m³/m)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 8) {
                                Button("Edit") { navigateToDetail(for: sec) }
                                    .buttonStyle(.borderless)
                                    .controlSize(.small)
                                    .help("Open details")
                                Button(role: .destructive) { delete(sec) } label: {
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
                        let items = idx.map { sortedSections[$0] }
                        items.forEach { delete($0) }
                    }
                }
                HStack {
                    TextField("New section name", text: $newName).textFieldStyle(.roundedBorder)
                    Button { add() } label: {
                        Label("Add", systemImage: "plus")
                            .labelStyle(.iconOnly)
                    }
                }
                .padding()
            }
            .navigationTitle("Annulus")
            .onChange(of: drillStringSignature) {
                sliceAllAnnulusSections()
                mergeContiguousByOD()
            }
            .onAppear {
                sliceAllAnnulusSections()
                mergeContiguousByOD()
            }
            .toolbar {
                if hasGaps {
                    ToolbarItemGroup {
                        Button("Fill Gaps") { fillGaps() }
                            .help("Extend previous section to remove gaps up to the next section")
                    }
                }
            }
            .navigationDestination(item: $activeSection) { sec in
                AnnulusDetailView(section: sec)
            }
        }
    }

    private func annularCapacityWithPipe_m3(_ s: AnnulusSection) -> Double {
        // Integrate across this annulus using overlapping drill string ODs where present
        var boundaries: [Double] = [s.topDepth_m, s.bottomDepth_m]
        for d in project.drillString where d.bottomDepth_m > s.topDepth_m && d.topDepth_m < s.bottomDepth_m {
            boundaries.append(max(d.topDepth_m, s.topDepth_m))
            boundaries.append(min(d.bottomDepth_m, s.bottomDepth_m))
        }
        // before: let unique = Array(Set(boundaries)).sorted()
        let unique = uniqueBoundaries(boundaries)
        guard unique.count > 1 else { return 0 }

        var total = 0.0
        for i in 0..<(unique.count - 1) {
            let t = unique[i]
            let b = unique[i + 1]
            guard b > t else { continue }
            // Find covering drill string for this sub-interval, if any
            var od: Double = 0
            for d in project.drillString where d.topDepth_m <= t && d.bottomDepth_m >= b {
                od = max(od, d.outerDiameter_m)
            }
            let id = max(s.innerDiameter_m, 0)
            let area = max(0, .pi * (id*id - od*od) / 4.0)
            total += area * (b - t)
        }
        return total
    }

    private func annularCapacityWithPipePerM_m3perm(_ s: AnnulusSection) -> Double {
        let L = max(s.length_m, 0)
        guard L > 0 else { return 0 }
        return annularCapacityWithPipe_m3(s) / L
    }

    private func openHoleCapacityPerM_m3perm(_ s: AnnulusSection) -> Double {
        let id = max(s.innerDiameter_m, 0)
        return .pi * pow(id, 2) / 4.0
    }

    private func openHoleCapacity_m3(_ s: AnnulusSection) -> Double {
        return openHoleCapacityPerM_m3perm(s) * max(s.length_m, 0)
    }

    private struct AnnulusPart: Identifiable {
        let id = UUID()
        let top: Double
        let bottom: Double
        var length: Double { max(0, bottom - top) }
        let od_m: Double
        let area_m2: Double
        var volume_m3: Double { area_m2 * length }
        let isInterference: Bool
    }
    
    // Slice all annulus sections that contain OD change points
    private func sliceAllAnnulusSections() {
        // Work on a snapshot since sliceSection mutates project.annulus
        let snapshot = project.annulus.sorted { $0.topDepth_m < $1.topDepth_m }
        for s in snapshot {
            // sliceSection will early-return if no internal OD changes
            sliceSection(s)
        }
    }

    private func slices(for s: AnnulusSection) -> [AnnulusPart] {
        // Collect boundaries from this section and all overlapping drill strings
        var bounds: [Double] = [s.topDepth_m, s.bottomDepth_m]
        for d in project.drillString where d.bottomDepth_m > s.topDepth_m && d.topDepth_m < s.bottomDepth_m {
            bounds.append(max(d.topDepth_m, s.topDepth_m))
            bounds.append(min(d.bottomDepth_m, s.bottomDepth_m))
        }
        let uniq = uniqueBoundaries(bounds)

        guard uniq.count > 1 else { return [] }

        var parts: [AnnulusPart] = []
        let id = max(s.innerDiameter_m, 0)
        for i in 0..<(uniq.count - 1) {
            let t = uniq[i]
            let b = uniq[i + 1]
            guard b > t else { continue }
            // Find covering string, if any (choose the maximum OD if multiple cover)
            var od: Double = 0
            for d in project.drillString where d.topDepth_m <= t && d.bottomDepth_m >= b {
                od = max(od, d.outerDiameter_m)
            }
            let isBad = od > id
            let area = max(0, .pi * (id*id - od*od) / 4.0)
            parts.append(AnnulusPart(top: t, bottom: b, od_m: od, area_m2: area, isInterference: isBad))
        }
        // Merge adjacent with same od & area to reduce noise
        var merged: [AnnulusPart] = []
        for p in parts {
            if let last = merged.popLast(),
               abs(last.od_m - p.od_m) < 1e-9,
               abs(last.area_m2 - p.area_m2) < 1e-12,
               abs(last.bottom - p.top) < 1e-9 {
                let m = AnnulusPart(top: last.top, bottom: p.bottom, od_m: last.od_m, area_m2: last.area_m2, isInterference: last.isInterference || p.isInterference)
                merged.append(m)
            } else {
                merged.append(p)
            }
        }
        return merged
    }

    private func add() {
        let nextTop = project.annulus.map { $0.bottomDepth_m }.max() ?? 0
        let s = AnnulusSection(
            name: newName,
            topDepth_m: nextTop,
            length_m: 100,
            innerDiameter_m: 0.216,
            outerDiameter_m: 0
        )
        s.project = project
        project.annulus.append(s)
        try? modelContext.save()
        newName = "New Section"
    }

    private func delete(_ section: AnnulusSection) {
        if let i = project.annulus.firstIndex(where: { $0.id == section.id }) {
            project.annulus.remove(at: i)
        }
        modelContext.delete(section)
        try? modelContext.save()
    }

    private func deleteSelected() {
        guard let sel = selection else { return }
        delete(sel)
        selection = nil
    }

    private func navigateToDetail(for section: AnnulusSection) {
        activeSection = section
    }

    private func fillGaps() {
        let secs = sortedSections
        guard secs.count > 1 else { return }
        for i in 1..<secs.count {
            let prev = secs[i - 1]
            let curr = secs[i]
            let gap = curr.topDepth_m - prev.bottomDepth_m
            if gap > 0 { prev.length_m += gap }
        }
        try? modelContext.save()
    }

    // Returns the overlapping drill string OD across [top,bottom] if it is constant; otherwise returns nil.
    private func constantOverlappingOD(in project: ProjectState, top: Double, bottom: Double) -> Double? {
        // Break into boundaries from drill string changes that intersect this interval
        var bounds: [Double] = [top, bottom]
        for d in project.drillString where d.bottomDepth_m > top && d.topDepth_m < bottom {
            bounds.append(max(d.topDepth_m, top))
            bounds.append(min(d.bottomDepth_m, bottom))
        }
        let uniq = Array(Set(bounds)).sorted()
        guard uniq.count > 1 else { return 0 }

        var odValue: Double? = nil
        for i in 0..<(uniq.count - 1) {
            let t = uniq[i]
            let b = uniq[i + 1]
            guard b > t else { continue }
            // OD covering this sub-slice
            var od: Double = 0
            for d in project.drillString where d.topDepth_m <= t && d.bottomDepth_m >= b {
                od = max(od, d.outerDiameter_m)
            }
            if let prev = odValue {
                if abs(prev - od) > 1e-9 { return nil }
            } else {
                odValue = od
            }
        }
        return odValue ?? 0
    }
    
    /// Returns a sorted list of depth boundaries with tolerance-based de-duplication.
    private func uniqueBoundaries(_ values: [Double], tol: Double = 1e-6) -> [Double] {
        let sorted = values.sorted()
        var out: [Double] = []
        for v in sorted {
            if let last = out.last, abs(last - v) <= tol { continue }
            out.append(v)
        }
        return out
    }

    // Physically split an annulus section into multiple sections at drill string boundaries
    private func sliceSection(_ s: AnnulusSection) {
        // Collect boundaries from this section and all overlapping drill strings
        var bounds: [Double] = [s.topDepth_m, s.bottomDepth_m]
        for d in project.drillString where d.bottomDepth_m > s.topDepth_m && d.topDepth_m < s.bottomDepth_m {
            bounds.append(max(d.topDepth_m, s.topDepth_m))
            bounds.append(min(d.bottomDepth_m, s.bottomDepth_m))
        }
        let uniq = uniqueBoundaries(bounds)

        // Build segments where OD is constant; split exactly at OD-change points
        var parts: [AnnulusPart] = []
        let id = max(s.innerDiameter_m, 0)

        func odCovering(_ a: Double, _ b: Double) -> Double {
            var od: Double = 0
            for d in project.drillString where d.topDepth_m <= a && d.bottomDepth_m >= b {
                od = max(od, d.outerDiameter_m)
            }
            return od
        }

        var i = 0
        while i < uniq.count - 1 {
            let t = uniq[i]
            var j = i + 1
            let currentOD = odCovering(t, uniq[j])
            while j < uniq.count - 1 {
                let nextOD = odCovering(uniq[j], uniq[j+1])
                if abs(nextOD - currentOD) <= 1e-9 { j += 1 } else { break }
            }
            let b = uniq[j]
            let area = max(0, .pi * (id*id - currentOD*currentOD) / 4.0)
            parts.append(AnnulusPart(top: t, bottom: b, od_m: currentOD, area_m2: area, isInterference: currentOD > id))
            i = j
        }

        guard parts.count > 1 else { return }

        // Create new sections for each part
        var newSections: [AnnulusSection] = []
        for (idx, p) in parts.enumerated() {
            let sec = AnnulusSection(
                name: s.name + " [\(idx+1)]",
                topDepth_m: p.top,
                length_m: p.length,
                innerDiameter_m: s.innerDiameter_m,
                outerDiameter_m: 0 // OD is auto from overlaps now
            )
            sec.project = project
            newSections.append(sec)
        }
        newSections.forEach { project.annulus.append($0); modelContext.insert($0) }
        if let i = project.annulus.firstIndex(where: { $0.id == s.id }) { project.annulus.remove(at: i) }
        modelContext.delete(s)
        try? modelContext.save()

        // Merge any accidental adjacent segments that have identical OD afterward
        mergeContiguousByOD()
    }

    // Merge adjacent annulus sections when they share the same ID (casing/wellbore) and constant overlapping OD
    private func mergeContiguousByOD() {
        var list = project.annulus.sorted { $0.topDepth_m < $1.topDepth_m }
        var i = 0
        while i + 1 < list.count {
            let a = list[i]
            let b = list[i + 1]
            // Must be contiguous
            let contiguous = abs(a.bottomDepth_m - b.topDepth_m) < 1e-9
            // Same casing/wellbore ID
            let sameID = abs(a.innerDiameter_m - b.innerDiameter_m) < 1e-9
            if contiguous && sameID {
                // Check constant OD across each and across the combined interval
                let odA = constantOverlappingOD(in: project, top: a.topDepth_m, bottom: a.bottomDepth_m)
                let odB = constantOverlappingOD(in: project, top: b.topDepth_m, bottom: b.bottomDepth_m)
                let odAB = constantOverlappingOD(in: project, top: a.topDepth_m, bottom: b.bottomDepth_m)
                if let oa = odA, let ob = odB, let oab = odAB, abs(oa - ob) < 1e-9, abs(oa - oab) < 1e-9 {
                    // Merge b into a
                    a.length_m += b.length_m
                    // Remove b from project & context
                    if let idx = project.annulus.firstIndex(where: { $0.id == b.id }) {
                        project.annulus.remove(at: idx)
                    }
                    modelContext.delete(b)
                    // Refresh local list to continue merging
                    list = project.annulus.sorted { $0.topDepth_m < $1.topDepth_m }
                    try? modelContext.save()
                    continue // re-check at same i
                }
            }
            i += 1
        }
    }
}

struct AnnulusDetailView: View {
    @Bindable var section: AnnulusSection

    var body: some View {
        ScrollView {
            Form {
                        Section { TextField("Name", text: $section.name) }
                        Section("Placement (m)") {
                            TextField("Top MD", value: $section.topDepth_m, format: .number)
                                .onChange(of: section.topDepth_m) { enforceNoOverlap(for: section) }
                            TextField("Length", value: $section.length_m, format: .number)
                                .onChange(of: section.length_m) { enforceNoOverlap(for: section) }
                            Text("Bottom MD: \(section.bottomDepth_m, format: .number)")
                        }
                        Section("Geometry (m)") {
                            TextField("Casing/WB ID", value: $section.innerDiameter_m, format: .number)
                            Text("String OD is auto-calculated from overlapping drill string sections")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Flow area: \(section.flowArea_m2, format: .number.precision(.fractionLength(5))) m²")
                            Text("De: \(section.equivalentDiameter_m, format: .number.precision(.fractionLength(4))) m")
                        }
                        Section("Fluid") {
                            Picker("Rheology", selection: $section.rheologyModelRaw) {
                                Text("Newtonian").tag(AnnulusSection.RheologyModel.newtonian.rawValue)
                                Text("Bingham").tag(AnnulusSection.RheologyModel.bingham.rawValue)
                                Text("Power Law").tag(AnnulusSection.RheologyModel.powerLaw.rawValue)
                                Text("Herschel–Bulkley").tag(AnnulusSection.RheologyModel.herschelBulkley.rawValue)
                            }
                            TextField("Density (kg/m³)", value: $section.density_kg_per_m3, format: .number)
                            Group {
                                TextField("μ (Pa·s)", value: $section.dynamicViscosity_Pa_s, format: .number)
                                TextField("PV (Pa·s)", value: $section.pv_Pa_s, format: .number)
                                TextField("YP (Pa)", value: $section.yp_Pa, format: .number)
                                TextField("n (–)", value: $section.n_powerLaw, format: .number)
                                TextField("k (Pa·sⁿ)", value: $section.k_powerLaw_Pa_s_n, format: .number)
                                TextField("τ₀ (Pa)", value: $section.hb_tau0_Pa, format: .number)
                                TextField("n (HB –)", value: $section.hb_n, format: .number)
                                TextField("k (HB Pa·sⁿ)", value: $section.hb_k_Pa_s_n, format: .number)
                            }
                        }
                    }
        }
        .onAppear { enforceNoOverlap(for: section) }
        .navigationTitle(section.name)
    }

    private func enforceNoOverlap(for current: AnnulusSection) {
        guard let project = current.project else { return }
        let others = project.annulus.filter { $0.id != current.id }.sorted { $0.topDepth_m < $1.topDepth_m }
        let prev = others.last { $0.topDepth_m <= current.topDepth_m }
        let next = others.first { $0.topDepth_m >= current.topDepth_m }
        if let prev, current.topDepth_m < prev.bottomDepth_m { current.topDepth_m = prev.bottomDepth_m }
        if current.length_m < 0 { current.length_m = 0 }
        if let next {
            let maxLen = max(0, next.topDepth_m - current.topDepth_m)
            if current.length_m > maxLen { current.length_m = maxLen }
        }
    }
    
}


#if DEBUG
import SwiftData

#Preview("Annulus – Sample Data") {
    do {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ProjectState.self,
                 DrillStringSection.self,
                 AnnulusSection.self,
                 PressureWindow.self,
                 PressureWindowPoint.self,
                 SlugPlan.self,
                 SlugStep.self,
                 BackfillPlan.self,
                 BackfillRule.self,
                 TripSettings.self,
                 SwabInput.self,
                 SurveyStation.self,
            configurations: config
        )

        let context = container.mainContext
        let project = ProjectState()
        context.insert(project)

        let a1 = AnnulusSection(name: "13-3/8\" × 5\"", topDepth_m: 0, length_m: 300, innerDiameter_m: 0.340, outerDiameter_m: 0.127)
        let a2 = AnnulusSection(name: "9-5/8\" × 5\"", topDepth_m: 300, length_m: 600, innerDiameter_m: 0.244, outerDiameter_m: 0.127)
        let a3 = AnnulusSection(name: "8-1/2\" Open Hole × 5\"", topDepth_m: 900, length_m: 400, innerDiameter_m: 0.216, outerDiameter_m: 0.127)
        [a1, a2, a3].forEach { sec in
            sec.project = project
            project.annulus.append(sec)
            context.insert(sec)
        }
        try? context.save()

        return AnnulusListView(project: project)
            .modelContainer(container)
            .frame(width: 720, height: 460)
    } catch {
        return Text("Preview failed: \\ (error.localizedDescription)")
    }
}
#endif
