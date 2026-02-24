//
//  OrphanRepairService.swift
//  Josh Well Control for Mac
//
//  Diagnoses and repairs orphaned SwiftData records caused by iCloud sync disruptions.
//  When CloudKit delivers records out of order or drops relationship links during sync,
//  child records can become "orphaned" (parent relationship is nil). This service
//  detects those orphans and attempts to re-link them to the correct parent.
//

import Foundation
import SwiftData

@MainActor
final class OrphanRepairService {

    // MARK: - Result Types

    struct DiagnosisResult {
        var orphanCounts: [(type: String, count: Int)] = []

        var hasOrphans: Bool { orphanCounts.contains { $0.count > 0 } }
        var totalOrphans: Int { orphanCounts.reduce(0) { $0 + $1.count } }

        var summary: String {
            if !hasOrphans {
                return "🔍 Orphan scan: No orphaned records found."
            }
            var lines = ["🔍 Orphan scan: Found \(totalOrphans) orphaned record(s):"]
            for entry in orphanCounts where entry.count > 0 {
                lines.append("  • \(entry.type): \(entry.count)")
            }
            return lines.joined(separator: "\n")
        }
    }

    struct RepairResult {
        var relinked: Int = 0
        var unresolvable: Int = 0
        var actions: [String] = []
        var saveSucceeded: Bool = false
        var saveError: String?

        var summary: String {
            var lines: [String] = []
            if relinked > 0 { lines.append("Re-linked: \(relinked)") }
            if unresolvable > 0 { lines.append("Unresolvable: \(unresolvable)") }
            lines.append(contentsOf: actions.map { "  • \($0)" })
            if !saveSucceeded, let error = saveError {
                lines.append("Save error: \(error)")
            } else if relinked > 0 {
                lines.append("Save: ✓")
            }
            return lines.isEmpty ? "No changes needed." : lines.joined(separator: "\n")
        }

        mutating func merge(_ other: RepairResult) {
            relinked += other.relinked
            unresolvable += other.unresolvable
            actions.append(contentsOf: other.actions)
            if !other.saveSucceeded { saveSucceeded = false }
            if let error = other.saveError { saveError = error }
        }
    }

    // MARK: - Quick Diagnosis

    static func quickDiagnose(context: ModelContext) -> DiagnosisResult {
        var result = DiagnosisResult()

        // -- Well-level orphans (well == nil) --

        result.orphanCounts.append(("ProjectState (no well)",
            (try? context.fetchCount(FetchDescriptor<ProjectState>(predicate: #Predicate { $0.well == nil }))) ?? 0))
        result.orphanCounts.append(("WorkDay (no well)",
            (try? context.fetchCount(FetchDescriptor<WorkDay>(predicate: #Predicate { $0.well == nil }))) ?? 0))
        result.orphanCounts.append(("MaterialTransfer (no well)",
            (try? context.fetchCount(FetchDescriptor<MaterialTransfer>(predicate: #Predicate { $0.well == nil }))) ?? 0))
        result.orphanCounts.append(("RentalItem (no well)",
            (try? context.fetchCount(FetchDescriptor<RentalItem>(predicate: #Predicate { $0.well == nil }))) ?? 0))
        result.orphanCounts.append(("Expense (no well)",
            (try? context.fetchCount(FetchDescriptor<Expense>(predicate: #Predicate { $0.well == nil }))) ?? 0))
        result.orphanCounts.append(("MileageLog (no well)",
            (try? context.fetchCount(FetchDescriptor<MileageLog>(predicate: #Predicate { $0.well == nil }))) ?? 0))
        result.orphanCounts.append(("LookAheadTask (no well)",
            (try? context.fetchCount(FetchDescriptor<LookAheadTask>(predicate: #Predicate { $0.well == nil }))) ?? 0))
        result.orphanCounts.append(("LookAheadSchedule (no well)",
            (try? context.fetchCount(FetchDescriptor<LookAheadSchedule>(predicate: #Predicate { $0.well == nil }))) ?? 0))
        result.orphanCounts.append(("ShiftEntry (no well)",
            (try? context.fetchCount(FetchDescriptor<ShiftEntry>(predicate: #Predicate { $0.well == nil }))) ?? 0))
        result.orphanCounts.append(("DirectionalPlan (no well)",
            (try? context.fetchCount(FetchDescriptor<DirectionalPlan>(predicate: #Predicate { $0.well == nil }))) ?? 0))
        result.orphanCounts.append(("FormationTop (no well)",
            (try? context.fetchCount(FetchDescriptor<FormationTop>(predicate: #Predicate { $0.well == nil }))) ?? 0))
        result.orphanCounts.append(("TripSimulation (no well)",
            (try? context.fetchCount(FetchDescriptor<TripSimulation>(predicate: #Predicate { $0.well == nil }))) ?? 0))
        result.orphanCounts.append(("TripInSimulation (no well)",
            (try? context.fetchCount(FetchDescriptor<TripInSimulation>(predicate: #Predicate { $0.well == nil }))) ?? 0))

        // -- ProjectState-level orphans (project == nil) --

        result.orphanCounts.append(("SurveyStation (no project)",
            (try? context.fetchCount(FetchDescriptor<SurveyStation>(predicate: #Predicate { $0.project == nil }))) ?? 0))
        result.orphanCounts.append(("DrillStringSection (no project)",
            (try? context.fetchCount(FetchDescriptor<DrillStringSection>(predicate: #Predicate { $0.project == nil }))) ?? 0))
        result.orphanCounts.append(("AnnulusSection (no project)",
            (try? context.fetchCount(FetchDescriptor<AnnulusSection>(predicate: #Predicate { $0.project == nil }))) ?? 0))
        result.orphanCounts.append(("MudStep (no project)",
            (try? context.fetchCount(FetchDescriptor<MudStep>(predicate: #Predicate { $0.project == nil }))) ?? 0))
        result.orphanCounts.append(("FinalFluidLayer (no project)",
            (try? context.fetchCount(FetchDescriptor<FinalFluidLayer>(predicate: #Predicate { $0.project == nil }))) ?? 0))
        result.orphanCounts.append(("MudProperties (no project)",
            (try? context.fetchCount(FetchDescriptor<MudProperties>(predicate: #Predicate { $0.project == nil }))) ?? 0))
        result.orphanCounts.append(("PumpProgramStage (no project)",
            (try? context.fetchCount(FetchDescriptor<PumpProgramStage>(predicate: #Predicate { $0.project == nil }))) ?? 0))
        result.orphanCounts.append(("SwabRun (no project)",
            (try? context.fetchCount(FetchDescriptor<SwabRun>(predicate: #Predicate { $0.project == nil }))) ?? 0))
        result.orphanCounts.append(("TripRun (no project)",
            (try? context.fetchCount(FetchDescriptor<TripRun>(predicate: #Predicate { $0.project == nil }))) ?? 0))
        result.orphanCounts.append(("CementJob (no project)",
            (try? context.fetchCount(FetchDescriptor<CementJob>(predicate: #Predicate { $0.project == nil }))) ?? 0))
        result.orphanCounts.append(("TripSimulation (no project)",
            (try? context.fetchCount(FetchDescriptor<TripSimulation>(predicate: #Predicate { $0.project == nil }))) ?? 0))
        result.orphanCounts.append(("TripInSimulation (no project)",
            (try? context.fetchCount(FetchDescriptor<TripInSimulation>(predicate: #Predicate { $0.project == nil }))) ?? 0))
        result.orphanCounts.append(("MPDSheet (no project)",
            (try? context.fetchCount(FetchDescriptor<MPDSheet>(predicate: #Predicate { $0.project == nil }))) ?? 0))

        // -- Dual-parent orphans (both well AND project nil) --

        result.orphanCounts.append(("WellTask (no well & no project)",
            (try? context.fetchCount(FetchDescriptor<WellTask>(predicate: #Predicate { $0.well == nil && $0.project == nil }))) ?? 0))
        result.orphanCounts.append(("HandoverNote (no well & no project)",
            (try? context.fetchCount(FetchDescriptor<HandoverNote>(predicate: #Predicate { $0.well == nil && $0.project == nil }))) ?? 0))

        return result
    }

    // MARK: - Repair Orphaned Projects

    static func repairOrphanedProjects(context: ModelContext) -> RepairResult {
        var result = RepairResult()

        let wells = (try? context.fetch(FetchDescriptor<Well>())) ?? []
        let orphans = (try? context.fetch(FetchDescriptor<ProjectState>(
            predicate: #Predicate { $0.well == nil }
        ))) ?? []

        guard !orphans.isEmpty else {
            result.saveSucceeded = true
            return result
        }

        if wells.count == 1, let well = wells.first {
            // Single well — relink all orphaned projects to it
            for project in orphans {
                project.well = well
                result.relinked += 1
                result.actions.append("Linked ProjectState '\(project.name)' → Well '\(well.name)'")
            }
        } else if wells.count > 1 {
            // Multiple wells — attempt matching
            let linkedProjects = (try? context.fetch(FetchDescriptor<ProjectState>(
                predicate: #Predicate { $0.well != nil }
            ))) ?? []

            for orphan in orphans {
                var matched: Well?

                // Strategy 1: Match via basedOnProjectID
                if let baseID = orphan.basedOnProjectID,
                   let baseProject = linkedProjects.first(where: { $0.id == baseID }),
                   let well = baseProject.well {
                    matched = well
                    result.actions.append("Matched '\(orphan.name)' via basedOnProjectID → '\(well.name)'")
                }

                // Strategy 2: Check children that still have a well link
                if matched == nil, let well = inferWellFromChildren(orphan) {
                    matched = well
                    result.actions.append("Matched '\(orphan.name)' via child reference → '\(well.name)'")
                }

                if let well = matched {
                    orphan.well = well
                    result.relinked += 1
                } else {
                    result.unresolvable += 1
                    result.actions.append("Could not match '\(orphan.name)' to any well")
                }
            }
        } else {
            // No wells exist
            result.unresolvable += orphans.count
            result.actions.append("No wells found — \(orphans.count) project(s) unresolvable")
        }

        saveIfNeeded(context: context, result: &result)
        return result
    }

    // MARK: - Repair Orphaned Well Children

    static func repairOrphanedWellChildren(context: ModelContext) -> RepairResult {
        var result = RepairResult()

        let wells = (try? context.fetch(FetchDescriptor<Well>())) ?? []

        if wells.count == 1, let well = wells.first {
            // Single well — relink all orphaned well-level children
            relinkToWell(WorkDay.self,
                         predicate: #Predicate { $0.well == nil },
                         well: well, label: "WorkDay", context: context, result: &result) { $0.well = $1 }
            relinkToWell(MaterialTransfer.self,
                         predicate: #Predicate { $0.well == nil },
                         well: well, label: "MaterialTransfer", context: context, result: &result) { $0.well = $1 }
            relinkToWell(RentalItem.self,
                         predicate: #Predicate { $0.well == nil },
                         well: well, label: "RentalItem", context: context, result: &result) { $0.well = $1 }
            relinkToWell(Expense.self,
                         predicate: #Predicate { $0.well == nil },
                         well: well, label: "Expense", context: context, result: &result) { $0.well = $1 }
            relinkToWell(MileageLog.self,
                         predicate: #Predicate { $0.well == nil },
                         well: well, label: "MileageLog", context: context, result: &result) { $0.well = $1 }
            relinkToWell(LookAheadTask.self,
                         predicate: #Predicate { $0.well == nil },
                         well: well, label: "LookAheadTask", context: context, result: &result) { $0.well = $1 }
            relinkToWell(LookAheadSchedule.self,
                         predicate: #Predicate { $0.well == nil },
                         well: well, label: "LookAheadSchedule", context: context, result: &result) { $0.well = $1 }
            relinkToWell(ShiftEntry.self,
                         predicate: #Predicate { $0.well == nil },
                         well: well, label: "ShiftEntry", context: context, result: &result) { $0.well = $1 }
            relinkToWell(DirectionalPlan.self,
                         predicate: #Predicate { $0.well == nil },
                         well: well, label: "DirectionalPlan", context: context, result: &result) { $0.well = $1 }
            relinkToWell(FormationTop.self,
                         predicate: #Predicate { $0.well == nil },
                         well: well, label: "FormationTop", context: context, result: &result) { $0.well = $1 }
            relinkToWell(TripSimulation.self,
                         predicate: #Predicate { $0.well == nil },
                         well: well, label: "TripSimulation", context: context, result: &result) { $0.well = $1 }
            relinkToWell(TripInSimulation.self,
                         predicate: #Predicate { $0.well == nil },
                         well: well, label: "TripInSimulation", context: context, result: &result) { $0.well = $1 }

            // Dual-parent: WellTask / HandoverNote where both links are nil
            relinkToWell(WellTask.self,
                         predicate: #Predicate { $0.well == nil && $0.project == nil },
                         well: well, label: "WellTask", context: context, result: &result) { $0.well = $1 }
            relinkToWell(HandoverNote.self,
                         predicate: #Predicate { $0.well == nil && $0.project == nil },
                         well: well, label: "HandoverNote", context: context, result: &result) { $0.well = $1 }
        } else if wells.count > 1 {
            // Multiple wells — count orphans for reporting
            reportWellOrphansMultiWell(context: context, result: &result)
        }
        // wells.count == 0: nothing to link to

        saveIfNeeded(context: context, result: &result)
        return result
    }

    // MARK: - Repair Orphaned Project Children

    static func repairOrphanedProjectChildren(context: ModelContext) -> RepairResult {
        var result = RepairResult()

        let allProjects = (try? context.fetch(FetchDescriptor<ProjectState>())) ?? []
        let linkedProjects = allProjects.filter { $0.well != nil }

        if allProjects.count == 1, let project = allProjects.first {
            // Single project — relink all orphaned project-level children
            relinkToProject(SurveyStation.self,
                            predicate: #Predicate { $0.project == nil },
                            project: project, label: "SurveyStation", context: context, result: &result) { $0.project = $1 }
            relinkToProject(DrillStringSection.self,
                            predicate: #Predicate { $0.project == nil },
                            project: project, label: "DrillStringSection", context: context, result: &result) { $0.project = $1 }
            relinkToProject(AnnulusSection.self,
                            predicate: #Predicate { $0.project == nil },
                            project: project, label: "AnnulusSection", context: context, result: &result) { $0.project = $1 }
            relinkToProject(MudStep.self,
                            predicate: #Predicate { $0.project == nil },
                            project: project, label: "MudStep", context: context, result: &result) { $0.project = $1 }
            relinkToProject(FinalFluidLayer.self,
                            predicate: #Predicate { $0.project == nil },
                            project: project, label: "FinalFluidLayer", context: context, result: &result) { $0.project = $1 }
            relinkToProject(MudProperties.self,
                            predicate: #Predicate { $0.project == nil },
                            project: project, label: "MudProperties", context: context, result: &result) { $0.project = $1 }
            relinkToProject(PumpProgramStage.self,
                            predicate: #Predicate { $0.project == nil },
                            project: project, label: "PumpProgramStage", context: context, result: &result) { $0.project = $1 }
            relinkToProject(SwabRun.self,
                            predicate: #Predicate { $0.project == nil },
                            project: project, label: "SwabRun", context: context, result: &result) { $0.project = $1 }
            relinkToProject(TripRun.self,
                            predicate: #Predicate { $0.project == nil },
                            project: project, label: "TripRun", context: context, result: &result) { $0.project = $1 }
            relinkToProject(CementJob.self,
                            predicate: #Predicate { $0.project == nil },
                            project: project, label: "CementJob", context: context, result: &result) { $0.project = $1 }
            relinkToProject(TripSimulation.self,
                            predicate: #Predicate { $0.project == nil },
                            project: project, label: "TripSimulation", context: context, result: &result) { $0.project = $1 }
            relinkToProject(TripInSimulation.self,
                            predicate: #Predicate { $0.project == nil },
                            project: project, label: "TripInSimulation", context: context, result: &result) { $0.project = $1 }
            relinkToProject(MPDSheet.self,
                            predicate: #Predicate { $0.project == nil },
                            project: project, label: "MPDSheet", context: context, result: &result) { $0.project = $1 }

            // Dual-parent project link
            relinkToProject(WellTask.self,
                            predicate: #Predicate { $0.project == nil && $0.well == nil },
                            project: project, label: "WellTask", context: context, result: &result) { $0.project = $1 }
            relinkToProject(HandoverNote.self,
                            predicate: #Predicate { $0.project == nil && $0.well == nil },
                            project: project, label: "HandoverNote", context: context, result: &result) { $0.project = $1 }
        } else if allProjects.count > 1 {
            // Multiple projects — try to resolve TripSimulation/TripInSimulation via their well link
            repairSimulationProjectLinks(context: context, linkedProjects: linkedProjects, result: &result)

            // Count remaining unresolvable orphans for other types
            reportProjectOrphansMultiProject(context: context, result: &result)
        }
        // allProjects.count == 0: nothing to link to

        saveIfNeeded(context: context, result: &result)
        return result
    }

    // MARK: - Private Helpers

    private static func inferWellFromChildren(_ project: ProjectState) -> Well? {
        for sim in project.tripSimulations ?? [] {
            if let well = sim.well { return well }
        }
        for sim in project.tripInSimulations ?? [] {
            if let well = sim.well { return well }
        }
        for task in project.tasks ?? [] {
            if let well = task.well { return well }
        }
        for note in project.notes ?? [] {
            if let well = note.well { return well }
        }
        return nil
    }

    /// For TripSimulation/TripInSimulation with project == nil but well != nil,
    /// try to resolve via well's sole project.
    private static func repairSimulationProjectLinks(
        context: ModelContext,
        linkedProjects: [ProjectState],
        result: inout RepairResult
    ) {
        // Build well → projects lookup
        var wellProjects: [PersistentIdentifier: [ProjectState]] = [:]
        for project in linkedProjects {
            if let well = project.well {
                wellProjects[well.persistentModelID, default: []].append(project)
            }
        }

        // TripSimulation
        let orphanedTripSims = (try? context.fetch(FetchDescriptor<TripSimulation>(
            predicate: #Predicate { $0.project == nil }
        ))) ?? []
        for sim in orphanedTripSims {
            if let well = sim.well,
               let projects = wellProjects[well.persistentModelID],
               projects.count == 1,
               let soleProject = projects.first {
                sim.project = soleProject
                result.relinked += 1
                result.actions.append("Linked TripSimulation '\(sim.name)' → '\(soleProject.name)'")
            } else {
                result.unresolvable += 1
            }
        }

        // TripInSimulation
        let orphanedTripInSims = (try? context.fetch(FetchDescriptor<TripInSimulation>(
            predicate: #Predicate { $0.project == nil }
        ))) ?? []
        for sim in orphanedTripInSims {
            if let well = sim.well,
               let projects = wellProjects[well.persistentModelID],
               projects.count == 1,
               let soleProject = projects.first {
                sim.project = soleProject
                result.relinked += 1
                result.actions.append("Linked TripInSimulation '\(sim.name)' → '\(soleProject.name)'")
            } else {
                result.unresolvable += 1
            }
        }
    }

    private static func relinkToWell<T: PersistentModel>(
        _ type: T.Type,
        predicate: Predicate<T>,
        well: Well,
        label: String,
        context: ModelContext,
        result: inout RepairResult,
        setter: (T, Well) -> Void
    ) {
        let orphans = (try? context.fetch(FetchDescriptor<T>(predicate: predicate))) ?? []
        for item in orphans { setter(item, well) }
        result.relinked += orphans.count
        if !orphans.isEmpty {
            result.actions.append("Linked \(orphans.count) \(label)(s) → '\(well.name)'")
        }
    }

    private static func relinkToProject<T: PersistentModel>(
        _ type: T.Type,
        predicate: Predicate<T>,
        project: ProjectState,
        label: String,
        context: ModelContext,
        result: inout RepairResult,
        setter: (T, ProjectState) -> Void
    ) {
        let orphans = (try? context.fetch(FetchDescriptor<T>(predicate: predicate))) ?? []
        for item in orphans { setter(item, project) }
        result.relinked += orphans.count
        if !orphans.isEmpty {
            result.actions.append("Linked \(orphans.count) \(label)(s) → '\(project.name)'")
        }
    }

    private static func reportWellOrphansMultiWell(context: ModelContext, result: inout RepairResult) {
        func report(_ label: String, _ count: Int) {
            guard count > 0 else { return }
            result.unresolvable += count
            result.actions.append("\(label): \(count) orphan(s) — multiple wells, needs manual resolution")
        }
        report("WorkDay", (try? context.fetchCount(FetchDescriptor<WorkDay>(predicate: #Predicate { $0.well == nil }))) ?? 0)
        report("MaterialTransfer", (try? context.fetchCount(FetchDescriptor<MaterialTransfer>(predicate: #Predicate { $0.well == nil }))) ?? 0)
        report("RentalItem", (try? context.fetchCount(FetchDescriptor<RentalItem>(predicate: #Predicate { $0.well == nil }))) ?? 0)
        report("Expense", (try? context.fetchCount(FetchDescriptor<Expense>(predicate: #Predicate { $0.well == nil }))) ?? 0)
        report("MileageLog", (try? context.fetchCount(FetchDescriptor<MileageLog>(predicate: #Predicate { $0.well == nil }))) ?? 0)
        report("LookAheadTask", (try? context.fetchCount(FetchDescriptor<LookAheadTask>(predicate: #Predicate { $0.well == nil }))) ?? 0)
        report("LookAheadSchedule", (try? context.fetchCount(FetchDescriptor<LookAheadSchedule>(predicate: #Predicate { $0.well == nil }))) ?? 0)
        report("ShiftEntry", (try? context.fetchCount(FetchDescriptor<ShiftEntry>(predicate: #Predicate { $0.well == nil }))) ?? 0)
        report("DirectionalPlan", (try? context.fetchCount(FetchDescriptor<DirectionalPlan>(predicate: #Predicate { $0.well == nil }))) ?? 0)
        report("FormationTop", (try? context.fetchCount(FetchDescriptor<FormationTop>(predicate: #Predicate { $0.well == nil }))) ?? 0)
        report("TripSimulation", (try? context.fetchCount(FetchDescriptor<TripSimulation>(predicate: #Predicate { $0.well == nil }))) ?? 0)
        report("TripInSimulation", (try? context.fetchCount(FetchDescriptor<TripInSimulation>(predicate: #Predicate { $0.well == nil }))) ?? 0)
    }

    private static func reportProjectOrphansMultiProject(context: ModelContext, result: inout RepairResult) {
        func report(_ label: String, _ count: Int) {
            guard count > 0 else { return }
            result.unresolvable += count
            result.actions.append("\(label): \(count) orphan(s) — multiple projects, needs manual resolution")
        }
        report("SurveyStation", (try? context.fetchCount(FetchDescriptor<SurveyStation>(predicate: #Predicate { $0.project == nil }))) ?? 0)
        report("DrillStringSection", (try? context.fetchCount(FetchDescriptor<DrillStringSection>(predicate: #Predicate { $0.project == nil }))) ?? 0)
        report("AnnulusSection", (try? context.fetchCount(FetchDescriptor<AnnulusSection>(predicate: #Predicate { $0.project == nil }))) ?? 0)
        report("MudStep", (try? context.fetchCount(FetchDescriptor<MudStep>(predicate: #Predicate { $0.project == nil }))) ?? 0)
        report("FinalFluidLayer", (try? context.fetchCount(FetchDescriptor<FinalFluidLayer>(predicate: #Predicate { $0.project == nil }))) ?? 0)
        report("MudProperties", (try? context.fetchCount(FetchDescriptor<MudProperties>(predicate: #Predicate { $0.project == nil }))) ?? 0)
        report("PumpProgramStage", (try? context.fetchCount(FetchDescriptor<PumpProgramStage>(predicate: #Predicate { $0.project == nil }))) ?? 0)
        report("SwabRun", (try? context.fetchCount(FetchDescriptor<SwabRun>(predicate: #Predicate { $0.project == nil }))) ?? 0)
        report("TripRun", (try? context.fetchCount(FetchDescriptor<TripRun>(predicate: #Predicate { $0.project == nil }))) ?? 0)
        report("CementJob", (try? context.fetchCount(FetchDescriptor<CementJob>(predicate: #Predicate { $0.project == nil }))) ?? 0)
        report("MPDSheet", (try? context.fetchCount(FetchDescriptor<MPDSheet>(predicate: #Predicate { $0.project == nil }))) ?? 0)
    }

    private static func saveIfNeeded(context: ModelContext, result: inout RepairResult) {
        if result.relinked > 0 {
            do {
                try context.save()
                result.saveSucceeded = true
            } catch {
                result.saveSucceeded = false
                result.saveError = error.localizedDescription
            }
        } else {
            result.saveSucceeded = true
        }
    }
}
