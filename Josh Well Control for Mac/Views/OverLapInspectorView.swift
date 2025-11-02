//
//  OverLapInspectorView.swift
//  Josh Well Control for Mac
//
//  Shows a merged, depth‑sliced view of Annulus and Drill String sections,
//  highlighting gaps and interferences across the whole well.

import SwiftUI
import SwiftData

struct OverLapInspectorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectState

    // Derived slices built from all unique tops/bottoms
    private var slices: [Slice] { buildSlices(project: project) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                header
                List {
                    ForEach(slices) { s in
                        HStack(alignment: .firstTextBaseline) {
                            // Depth range / length
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(fmt(s.top))–\(fmt(s.bottom)) m  (\(fmt(s.length)) m)")
                                    .font(.headline)

                                // Status line
                                HStack(spacing: 8) {
                                    StatusPill(status: s.status)
                                    if let a = s.annulus, let d = s.drillString {
                                        let id = a.innerDiameter_m
                                        let od = d.outerDiameter_m
                                        let clear = max(0, id - od)
                                        Text("ID: \(fmt3(id)) m  OD: \(fmt3(od)) m  clr: \(fmt3(clear)) m")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else if s.annulus != nil {
                                        Text("No drill string in this interval")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else if s.drillString != nil {
                                        Text("No annulus/casing in this interval")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("No geometry defined")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                // Capacity details when annulus exists
                                if let a = s.annulus {
                                    let dsOD = s.drillString?.outerDiameter_m ?? 0
                                    let areaAnn = max(0, .pi * (pow(a.innerDiameter_m, 2) - pow(dsOD, 2)) / 4.0)
                                    let volAnn = areaAnn * s.length
                                    Text("Annular cap: \(fmt3(volAnn)) m³  (\(fmt3(areaAnn)) m³/m)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                if s.status == .interference {
                                    Text("⚠️ Interference: drill string OD exceeds annulus ID")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }

                            Spacer()

                            // Quick jumps to edit
                            HStack(spacing: 8) {
                                if let a = s.annulus {
                                    NavigationLink("Edit Annulus") { AnnulusDetailView(section: a) }
                                        .buttonStyle(.borderless)
                                        .controlSize(.small)
                                }
                                if let d = s.drillString {
                                    NavigationLink("Edit String") { DrillStringDetailView(section: d) }
                                        .buttonStyle(.borderless)
                                        .controlSize(.small)
                                }
                            }
                        }
                    }
                }
                .transaction { $0.disablesAnimations = true }
            }
            .padding(.horizontal)
            .navigationTitle("Overlap Inspector")
        }
    }

    // Simple header row labels
    private var header: some View {
        HStack {
            Text("Depth Slice").frame(maxWidth: .infinity, alignment: .leading)
            Text("Actions").frame(width: 160, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 6)
    }
}

// MARK: – Status pill
private struct StatusPill: View {
    let status: Slice.Status
    var body: some View {
        let (label, color): (String, Color) = {
            switch status {
            case .ok: return ("OK", .green)
            case .gapAnnulus: return ("No casing", .orange)
            case .gapString: return ("No string", .orange)
            case .interference: return ("Interference", .red)
            case .undefined: return ("Undefined", .gray)
            }
        }()
        return Text(label)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.18)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(color.opacity(0.4)))
    }
}

// MARK: – Slice model and builder
struct Slice: Identifiable, Equatable {
    enum Status { case ok, gapAnnulus, gapString, interference, undefined }
    let id = UUID()
    let top: Double
    let bottom: Double
    var length: Double { max(0, bottom - top) }
    let annulus: AnnulusSection?
    let drillString: DrillStringSection?
    var status: Status {
        switch (annulus, drillString) {
        case (nil, nil): return .undefined
        case (.some, nil): return .gapString
        case (nil, .some): return .gapAnnulus
        case let (.some(a), .some(d)):
            return d.outerDiameter_m > a.innerDiameter_m ? .interference : .ok
        }
    }
}

private func buildSlices(project: ProjectState) -> [Slice] {
    // Collect all boundary depths from both lists
    var boundaries = Set<Double>()
    for a in project.annulus { boundaries.insert(a.topDepth_m); boundaries.insert(a.bottomDepth_m) }
    for d in project.drillString { boundaries.insert(d.topDepth_m); boundaries.insert(d.bottomDepth_m) }
    let sorted = boundaries.sorted()
    guard sorted.count >= 2 else { return [] }

    func coveringAnnulus(_ zTop: Double, _ zBot: Double) -> AnnulusSection? {
        project.annulus.first { $0.topDepth_m <= zTop && $0.bottomDepth_m >= zBot }
    }
    func coveringString(_ zTop: Double, _ zBot: Double) -> DrillStringSection? {
        project.drillString.first { $0.topDepth_m <= zTop && $0.bottomDepth_m >= zBot }
    }

    var slices: [Slice] = []
    for i in 0..<(sorted.count - 1) {
        let t = sorted[i]
        let b = sorted[i + 1]
        guard b > t else { continue }
        let a = coveringAnnulus(t, b)
        let d = coveringString(t, b)
        slices.append(Slice(top: t, bottom: b, annulus: a, drillString: d))
    }
    // Merge adjacent slices with identical (annulus,string) to reduce noise
    var merged: [Slice] = []
    for s in slices {
        if var last = merged.popLast(), last.annulus?.id == s.annulus?.id && last.drillString?.id == s.drillString?.id {
            let m = Slice(top: last.top, bottom: s.bottom, annulus: last.annulus, drillString: last.drillString)
            merged.append(m)
        } else {
            merged.append(s)
        }
    }
    return merged
}

// MARK: – Formatting helpers
private func fmt(_ v: Double) -> String { String(format: "%.0f", v) }
private func fmt3(_ v: Double) -> String { String(format: "%.3f", v) }

#if DEBUG
#Preview("Overlap – Sample Data") {
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

        let ctx = container.mainContext
        let project = ProjectState()
        ctx.insert(project)

        // Seed sample annulus (gaps + different IDs)
        let a1 = AnnulusSection(name: "13-3/8\" × 5\"", topDepth_m: 0, length_m: 600, innerDiameter_m: 0.340, outerDiameter_m: 0.127)
        let a2 = AnnulusSection(name: "9-5/8\" × 5\"", topDepth_m: 700, length_m: 300, innerDiameter_m: 0.244, outerDiameter_m: 0.127)
        [a1, a2].forEach { $0.project = project; project.annulus.append($0); ctx.insert($0) }

        // Seed sample drill string (intentional interference in part of interval)
        let d1 = DrillStringSection(name: "5\" DP", topDepth_m: 0, length_m: 1000, outerDiameter_m: 0.127, innerDiameter_m: 0.0953)
        d1.project = project
        project.drillString.append(d1)
        ctx.insert(d1)

        try? ctx.save()

        return OverLapInspectorView(project: project)
            .modelContainer(container)
            .frame(width: 820, height: 560)
    } catch {
        return Text("Preview failed: \(error.localizedDescription)")
    }
}
#endif
