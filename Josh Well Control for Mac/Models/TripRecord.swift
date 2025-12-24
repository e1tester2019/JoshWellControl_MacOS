//
//  TripRecord.swift
//  Josh Well Control for Mac
//
//  Created for recording actual trip observations against simulation predictions.
//

import Foundation
import SwiftData

/// Represents a field recording session where actual trip observations are captured
/// and compared against a source simulation for model calibration.
@Model
final class TripRecord {
    var id: UUID = UUID()

    /// Descriptive name for this recording (e.g., "Trip Out - Dec 22")
    var name: String = ""

    /// Timestamp when this record was created
    var createdAt: Date = Date.now

    /// Timestamp when this record was last modified
    var updatedAt: Date = Date.now

    // MARK: - Source Simulation Reference

    /// UUID of the source simulation (allows simulation to be modified/deleted independently)
    var sourceSimulationID: UUID = UUID()

    /// Name of the source simulation (snapshot at creation time)
    var sourceSimulationName: String = ""

    // MARK: - Configuration Snapshot (copied from simulation at creation)

    /// Starting bit depth (MD in meters) - typically TD
    var startBitMD_m: Double = 0

    /// Ending bit depth (MD in meters) - typically surface
    var endMD_m: Double = 0

    /// Casing shoe depth (MD in meters) for control point
    var shoeMD_m: Double = 0

    /// Depth interval for steps (meters)
    var step_m: Double = 100

    /// Base mud density in annulus (kg/m³)
    var baseMudDensity_kgpm3: Double = 1080

    /// Backfill mud density (kg/m³)
    var backfillDensity_kgpm3: Double = 1080

    /// Target equivalent static density at TD (kg/m³)
    var targetESDAtTD_kgpm3: Double = 1080

    /// Float valve crack pressure differential (kPa)
    var crackFloat_kPa: Double = 2100

    // MARK: - Status

    /// Raw status value: 0=inProgress, 1=completed, 2=cancelled
    var statusRaw: Int = 0

    /// Timestamp when this record was marked complete
    var completedAt: Date?

    // MARK: - Variance Summary (calculated from steps)

    /// Average SABP variance across recorded steps (kPa)
    var avgSABPVariance_kPa: Double = 0

    /// Average backfill variance across recorded steps (m³)
    var avgBackfillVariance_m3: Double = 0

    /// Maximum SABP variance (kPa)
    var maxSABPVariance_kPa: Double = 0

    /// Maximum backfill variance (m³)
    var maxBackfillVariance_m3: Double = 0

    /// Number of steps with recorded actual values
    var stepsRecorded: Int = 0

    /// Number of steps explicitly skipped
    var stepsSkipped: Int = 0

    // MARK: - Relationships

    /// Steps for this record
    @Relationship(deleteRule: .cascade, inverse: \TripRecordStep.record)
    var steps: [TripRecordStep]?

    /// Back-reference to the owning project
    @Relationship(deleteRule: .nullify)
    var project: ProjectState?

    // MARK: - Computed Properties

    /// Status enum accessor
    @Transient var status: RecordStatus {
        get { RecordStatus(rawValue: statusRaw) ?? .inProgress }
        set { statusRaw = newValue.rawValue }
    }

    /// Sorted steps by index (deepest first, matching simulation order)
    @Transient var sortedSteps: [TripRecordStep] {
        (steps ?? []).sorted { $0.stepIndex < $1.stepIndex }
    }

    /// Number of steps in this record
    @Transient var stepCount: Int {
        steps?.count ?? 0
    }

    /// Trip length in meters
    @Transient var tripLength_m: Double {
        abs(startBitMD_m - endMD_m)
    }

    /// Progress percentage (steps recorded / total steps)
    @Transient var progressPercent: Double {
        guard stepCount > 0 else { return 0 }
        return Double(stepsRecorded + stepsSkipped) / Double(stepCount) * 100
    }

    // MARK: - Status Enum

    enum RecordStatus: Int, Codable, CaseIterable {
        case inProgress = 0
        case completed = 1
        case cancelled = 2

        var label: String {
            switch self {
            case .inProgress: return "In Progress"
            case .completed: return "Completed"
            case .cancelled: return "Cancelled"
            }
        }

        var icon: String {
            switch self {
            case .inProgress: return "clock"
            case .completed: return "checkmark.circle.fill"
            case .cancelled: return "xmark.circle"
            }
        }
    }

    // MARK: - Initializer

    init(
        name: String = "",
        sourceSimulationID: UUID = UUID(),
        sourceSimulationName: String = "",
        startBitMD_m: Double = 0,
        endMD_m: Double = 0,
        shoeMD_m: Double = 0,
        step_m: Double = 100,
        baseMudDensity_kgpm3: Double = 1080,
        backfillDensity_kgpm3: Double = 1080,
        targetESDAtTD_kgpm3: Double = 1080,
        crackFloat_kPa: Double = 2100,
        project: ProjectState? = nil
    ) {
        self.name = name
        self.sourceSimulationID = sourceSimulationID
        self.sourceSimulationName = sourceSimulationName
        self.startBitMD_m = startBitMD_m
        self.endMD_m = endMD_m
        self.shoeMD_m = shoeMD_m
        self.step_m = step_m
        self.baseMudDensity_kgpm3 = baseMudDensity_kgpm3
        self.backfillDensity_kgpm3 = backfillDensity_kgpm3
        self.targetESDAtTD_kgpm3 = targetESDAtTD_kgpm3
        self.crackFloat_kPa = crackFloat_kPa
        self.project = project
    }

    // MARK: - Step Management

    /// Add a step to this record
    func addStep(_ step: TripRecordStep) {
        if steps == nil { steps = [] }
        step.record = self
        steps?.append(step)
    }

    /// Update variance summary from steps
    func updateVarianceSummary() {
        guard let allSteps = steps, !allSteps.isEmpty else { return }

        let recordedSteps = allSteps.filter { $0.hasActualData && !$0.skipped }
        stepsRecorded = recordedSteps.count
        stepsSkipped = allSteps.filter { $0.skipped }.count

        // Calculate SABP variance stats
        let sabpVariances = recordedSteps.compactMap { $0.sabpVariance_kPa }
        if !sabpVariances.isEmpty {
            avgSABPVariance_kPa = sabpVariances.reduce(0, +) / Double(sabpVariances.count)
            maxSABPVariance_kPa = sabpVariances.map { abs($0) }.max() ?? 0
        }

        // Calculate backfill variance stats
        let backfillVariances = recordedSteps.compactMap { $0.backfillVariance_m3 }
        if !backfillVariances.isEmpty {
            avgBackfillVariance_m3 = backfillVariances.reduce(0, +) / Double(backfillVariances.count)
            maxBackfillVariance_m3 = backfillVariances.map { abs($0) }.max() ?? 0
        }

        updatedAt = .now
    }

    /// Mark this record as complete
    func markComplete() {
        status = .completed
        completedAt = .now
        updateVarianceSummary()
    }

    /// Unmark this record as complete (return to in progress)
    func unmarkComplete() {
        status = .inProgress
        completedAt = nil
        updatedAt = .now
    }

    /// Mark this record as cancelled
    func markCancelled() {
        status = .cancelled
        updatedAt = .now
    }
}

// MARK: - Creation from Simulation

extension TripRecord {
    /// Create a new TripRecord pre-populated with steps from a TripSimulation
    static func createFrom(simulation: TripSimulation, project: ProjectState) -> TripRecord {
        let record = TripRecord(
            name: "Record: \(simulation.name)",
            sourceSimulationID: simulation.id,
            sourceSimulationName: simulation.name,
            startBitMD_m: simulation.startBitMD_m,
            endMD_m: simulation.endMD_m,
            shoeMD_m: simulation.shoeMD_m,
            step_m: simulation.step_m,
            baseMudDensity_kgpm3: simulation.baseMudDensity_kgpm3,
            backfillDensity_kgpm3: simulation.backfillDensity_kgpm3,
            targetESDAtTD_kgpm3: simulation.targetESDAtTD_kgpm3,
            crackFloat_kPa: simulation.crackFloat_kPa,
            project: project
        )

        // Pre-populate steps from simulation
        for simStep in simulation.sortedSteps {
            let recordStep = TripRecordStep.createFrom(simulationStep: simStep)
            record.addStep(recordStep)
        }

        return record
    }
}

// MARK: - Export Dictionary

extension TripRecord {
    var exportDictionary: [String: Any] {
        [
            "id": id.uuidString,
            "name": name,
            "createdAt": ISO8601DateFormatter().string(from: createdAt),
            "updatedAt": ISO8601DateFormatter().string(from: updatedAt),
            "status": status.label,
            "sourceSimulationID": sourceSimulationID.uuidString,
            "sourceSimulationName": sourceSimulationName,
            // Configuration
            "startBitMD_m": startBitMD_m,
            "endMD_m": endMD_m,
            "shoeMD_m": shoeMD_m,
            "step_m": step_m,
            "baseMudDensity_kgpm3": baseMudDensity_kgpm3,
            "backfillDensity_kgpm3": backfillDensity_kgpm3,
            "targetESDAtTD_kgpm3": targetESDAtTD_kgpm3,
            "crackFloat_kPa": crackFloat_kPa,
            // Variance summary
            "stepsRecorded": stepsRecorded,
            "stepsSkipped": stepsSkipped,
            "avgSABPVariance_kPa": avgSABPVariance_kPa,
            "avgBackfillVariance_m3": avgBackfillVariance_m3,
            "maxSABPVariance_kPa": maxSABPVariance_kPa,
            "maxBackfillVariance_m3": maxBackfillVariance_m3,
            // Steps
            "steps": sortedSteps.map { $0.exportDictionary }
        ]
    }
}
