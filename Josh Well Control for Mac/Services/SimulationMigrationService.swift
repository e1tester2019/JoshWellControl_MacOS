//
//  SimulationMigrationService.swift
//  Josh Well Control for Mac
//
//  Migrates existing simulations to use frozen inputs and clears layer data to reduce storage.
//

import Foundation
import SwiftData

@MainActor
final class SimulationMigrationService {

    /// Migrate all simulations that don't have frozen inputs
    /// Returns a summary of what was migrated
    static func migrateAllSimulations(context: ModelContext) -> MigrationResult {
        var result = MigrationResult()

        // Fetch all trip simulations
        let tripSimDescriptor = FetchDescriptor<TripSimulation>()
        let tripSimulations = (try? context.fetch(tripSimDescriptor)) ?? []

        // Fetch all trip-in simulations
        let tripInSimDescriptor = FetchDescriptor<TripInSimulation>()
        let tripInSimulations = (try? context.fetch(tripInSimDescriptor)) ?? []

        result.totalTripSimulations = tripSimulations.count
        result.totalTripInSimulations = tripInSimulations.count

        // Migrate trip simulations
        for simulation in tripSimulations {
            if simulation.frozenInputsData == nil {
                if let project = simulation.project {
                    // Freeze inputs from the associated project
                    let backfillMud = simulation.backfillMud
                    simulation.freezeInputs(from: project, backfillMud: backfillMud, activeMud: project.activeMud)

                    // Link to well if not already
                    if simulation.well == nil {
                        simulation.well = project.well
                    }

                    result.tripSimulationsMigrated += 1
                } else {
                    result.tripSimulationsSkipped += 1
                    result.skippedReasons.append("TripSim '\(simulation.name)': no project reference")
                }
            }

            // Clear layer data regardless (to reduce storage)
            let hadLayerData = hasLayerData(simulation)
            if hadLayerData {
                simulation.clearStepLayerData()
                result.tripSimulationsLayersCleared += 1
            }
        }

        // Migrate trip-in simulations
        for simulation in tripInSimulations {
            if simulation.frozenInputsData == nil {
                if let project = simulation.project {
                    let fillMud = simulation.fillMudID.flatMap { id in
                        (project.muds ?? []).first { $0.id == id }
                    }
                    simulation.freezeInputs(from: project, fillMud: fillMud)

                    if simulation.well == nil {
                        simulation.well = project.well
                    }

                    result.tripInSimulationsMigrated += 1
                } else {
                    result.tripInSimulationsSkipped += 1
                    result.skippedReasons.append("TripInSim '\(simulation.name)': no project reference")
                }
            }

            // Clear layer data regardless
            let hadLayerData = hasLayerData(simulation)
            if hadLayerData {
                simulation.clearStepLayerData()
                result.tripInSimulationsLayersCleared += 1
            }
        }

        // Save changes
        do {
            try context.save()
            result.saveSucceeded = true
        } catch {
            result.saveSucceeded = false
            result.saveError = error.localizedDescription
        }

        return result
    }

    /// Check if a trip simulation has any layer data in its steps
    private static func hasLayerData(_ simulation: TripSimulation) -> Bool {
        guard let steps = simulation.steps else { return false }
        return steps.contains { step in
            step.layersAnnulusData != nil ||
            step.layersStringData != nil ||
            step.layersPocketData != nil
        }
    }

    /// Check if a trip-in simulation has any layer data in its steps
    private static func hasLayerData(_ simulation: TripInSimulation) -> Bool {
        guard let steps = simulation.steps else { return false }
        return steps.contains { step in
            step.layersAnnulusData != nil ||
            step.layersStringData != nil ||
            step.layersPocketData != nil
        }
    }

    /// Estimate storage savings from clearing layer data
    static func estimateStorageSavings(context: ModelContext) -> StorageEstimate {
        var estimate = StorageEstimate()

        let tripSimDescriptor = FetchDescriptor<TripSimulation>()
        let tripSimulations = (try? context.fetch(tripSimDescriptor)) ?? []

        let tripInSimDescriptor = FetchDescriptor<TripInSimulation>()
        let tripInSimulations = (try? context.fetch(tripInSimDescriptor)) ?? []

        // Calculate layer data sizes for trip simulations
        for simulation in tripSimulations {
            for step in (simulation.steps ?? []) {
                estimate.tripSimLayerBytes += Int64(step.layersAnnulusData?.count ?? 0)
                estimate.tripSimLayerBytes += Int64(step.layersStringData?.count ?? 0)
                estimate.tripSimLayerBytes += Int64(step.layersPocketData?.count ?? 0)
            }
        }

        // Calculate layer data sizes for trip-in simulations
        for simulation in tripInSimulations {
            for step in (simulation.steps ?? []) {
                estimate.tripInSimLayerBytes += Int64(step.layersAnnulusData?.count ?? 0)
                estimate.tripInSimLayerBytes += Int64(step.layersStringData?.count ?? 0)
                estimate.tripInSimLayerBytes += Int64(step.layersPocketData?.count ?? 0)
            }
        }

        estimate.totalSimulations = tripSimulations.count + tripInSimulations.count
        return estimate
    }
}

// MARK: - Result Types

struct MigrationResult {
    var totalTripSimulations: Int = 0
    var totalTripInSimulations: Int = 0
    var tripSimulationsMigrated: Int = 0
    var tripInSimulationsMigrated: Int = 0
    var tripSimulationsSkipped: Int = 0
    var tripInSimulationsSkipped: Int = 0
    var tripSimulationsLayersCleared: Int = 0
    var tripInSimulationsLayersCleared: Int = 0
    var skippedReasons: [String] = []
    var saveSucceeded: Bool = false
    var saveError: String?

    var summary: String {
        var lines: [String] = []
        lines.append("Migration Complete")
        lines.append("─────────────────────────────────")
        lines.append("Trip Simulations: \(totalTripSimulations) total")
        lines.append("  • Frozen inputs added: \(tripSimulationsMigrated)")
        lines.append("  • Layer data cleared: \(tripSimulationsLayersCleared)")
        if tripSimulationsSkipped > 0 {
            lines.append("  • Skipped (no project): \(tripSimulationsSkipped)")
        }
        lines.append("")
        lines.append("Trip-In Simulations: \(totalTripInSimulations) total")
        lines.append("  • Frozen inputs added: \(tripInSimulationsMigrated)")
        lines.append("  • Layer data cleared: \(tripInSimulationsLayersCleared)")
        if tripInSimulationsSkipped > 0 {
            lines.append("  • Skipped (no project): \(tripInSimulationsSkipped)")
        }
        lines.append("")
        lines.append("Save: \(saveSucceeded ? "✓ Succeeded" : "✗ Failed")")
        if let error = saveError {
            lines.append("  Error: \(error)")
        }
        return lines.joined(separator: "\n")
    }
}

struct StorageEstimate {
    var tripSimLayerBytes: Int64 = 0
    var tripInSimLayerBytes: Int64 = 0
    var totalSimulations: Int = 0

    var totalBytes: Int64 { tripSimLayerBytes + tripInSimLayerBytes }

    var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    var formattedTripSim: String {
        ByteCountFormatter.string(fromByteCount: tripSimLayerBytes, countStyle: .file)
    }

    var formattedTripInSim: String {
        ByteCountFormatter.string(fromByteCount: tripInSimLayerBytes, countStyle: .file)
    }

    var summary: String {
        """
        Storage Estimate
        ─────────────────────────────────
        Total simulations: \(totalSimulations)
        Trip simulation layers: \(formattedTripSim)
        Trip-in simulation layers: \(formattedTripInSim)
        Total recoverable: \(formattedTotal)
        """
    }
}
