//
//  SuperSimOperation.swift
//  Josh Well Control for Mac
//
//  Data model for the Super Simulation timeline.
//  Each operation represents a trip out, trip in, or circulation segment.
//

import Foundation

enum OperationType: String, Codable, CaseIterable {
    case tripOut = "Trip Out"
    case tripIn = "Trip In"
    case circulate = "Circulate"

    var icon: String {
        switch self {
        case .tripOut: return "arrow.up.circle.fill"
        case .tripIn: return "arrow.down.circle.fill"
        case .circulate: return "arrow.2.squarepath"
        }
    }
}

struct SuperSimOperation: Identifiable {
    let id: UUID
    var type: OperationType
    var label: String

    // MARK: - Shared Config

    var startMD_m: Double = 0
    var endMD_m: Double = 0
    var targetESD_kgpm3: Double = 1200
    var controlMD_m: Double = 0

    // MARK: - Trip Out Config

    var baseMudID: UUID?
    var baseMudDensity_kgpm3: Double = 1200
    var backfillMudID: UUID?
    var backfillDensity_kgpm3: Double = 1200
    var backfillColorR: Double?
    var backfillColorG: Double?
    var backfillColorB: Double?
    var backfillColorA: Double?
    var tripSpeed_m_per_s: Double = 0.5
    var step_m: Double = 10.0
    var crackFloat_kPa: Double = 2100
    var initialSABP_kPa: Double = 0

    // MARK: - Trip In Config

    var pipeOD_m: Double = 0.127
    var pipeID_m: Double = 0.1086
    var fillMudID: UUID?
    var fillMudDensity_kgpm3: Double = 1200
    var fillMudColorR: Double?
    var fillMudColorG: Double?
    var fillMudColorB: Double?
    var fillMudColorA: Double?
    var isFloatedCasing: Bool = false
    var floatSubMD_m: Double = 0
    var tripInStep_m: Double = 100

    // MARK: - Circulation Config

    var pumpQueueEncoded: Data?

    // MARK: - Results

    var inputState: WellboreStateSnapshot?
    var outputState: WellboreStateSnapshot?
    var status: OperationStatus = .pending

    enum OperationStatus: Equatable {
        case pending
        case running
        case complete
        case error(String)

        var isPending: Bool { self == .pending }
        var isComplete: Bool { self == .complete }
    }

    // MARK: - Initializers

    init(type: OperationType, label: String? = nil) {
        self.id = UUID()
        self.type = type
        self.label = label ?? type.rawValue
    }

    /// Auto-generate label from depths
    var depthLabel: String {
        let startStr = String(format: "%.0f", startMD_m)
        let endStr = String(format: "%.0f", endMD_m)
        switch type {
        case .tripOut: return "\(startStr)m → \(endStr)m"
        case .tripIn: return "\(startStr)m → \(endStr)m"
        case .circulate: return "@ \(startStr)m"
        }
    }

    // MARK: - Preset Conversion

    func toPresetConfig(muds: [MudProperties]) -> SuperSimPreset.OperationConfig {
        SuperSimPreset.OperationConfig(
            type: type, label: label,
            startMD_m: startMD_m, endMD_m: endMD_m,
            targetESD_kgpm3: targetESD_kgpm3, controlMD_m: controlMD_m,
            baseMudID: baseMudID,
            baseMudName: muds.first(where: { $0.id == baseMudID })?.name,
            baseMudDensity_kgpm3: baseMudDensity_kgpm3,
            backfillMudID: backfillMudID,
            backfillMudName: muds.first(where: { $0.id == backfillMudID })?.name,
            backfillDensity_kgpm3: backfillDensity_kgpm3,
            backfillColorR: backfillColorR, backfillColorG: backfillColorG,
            backfillColorB: backfillColorB, backfillColorA: backfillColorA,
            tripSpeed_m_per_s: tripSpeed_m_per_s, step_m: step_m,
            crackFloat_kPa: crackFloat_kPa, initialSABP_kPa: initialSABP_kPa,
            pipeOD_m: pipeOD_m, pipeID_m: pipeID_m,
            fillMudID: fillMudID,
            fillMudName: muds.first(where: { $0.id == fillMudID })?.name,
            fillMudDensity_kgpm3: fillMudDensity_kgpm3,
            fillMudColorR: fillMudColorR, fillMudColorG: fillMudColorG,
            fillMudColorB: fillMudColorB, fillMudColorA: fillMudColorA,
            isFloatedCasing: isFloatedCasing, floatSubMD_m: floatSubMD_m,
            tripInStep_m: tripInStep_m,
            pumpQueueEncoded: pumpQueueEncoded
        )
    }

    static func fromPresetConfig(_ config: SuperSimPreset.OperationConfig) -> SuperSimOperation {
        var op = SuperSimOperation(type: config.type, label: config.label)
        op.startMD_m = config.startMD_m
        op.endMD_m = config.endMD_m
        op.targetESD_kgpm3 = config.targetESD_kgpm3
        op.controlMD_m = config.controlMD_m
        op.baseMudID = config.baseMudID
        op.baseMudDensity_kgpm3 = config.baseMudDensity_kgpm3
        op.backfillMudID = config.backfillMudID
        op.backfillDensity_kgpm3 = config.backfillDensity_kgpm3
        op.backfillColorR = config.backfillColorR
        op.backfillColorG = config.backfillColorG
        op.backfillColorB = config.backfillColorB
        op.backfillColorA = config.backfillColorA
        op.tripSpeed_m_per_s = config.tripSpeed_m_per_s
        op.step_m = config.step_m
        op.crackFloat_kPa = config.crackFloat_kPa
        op.initialSABP_kPa = config.initialSABP_kPa
        op.pipeOD_m = config.pipeOD_m
        op.pipeID_m = config.pipeID_m
        op.fillMudID = config.fillMudID
        op.fillMudDensity_kgpm3 = config.fillMudDensity_kgpm3
        op.fillMudColorR = config.fillMudColorR
        op.fillMudColorG = config.fillMudColorG
        op.fillMudColorB = config.fillMudColorB
        op.fillMudColorA = config.fillMudColorA
        op.isFloatedCasing = config.isFloatedCasing
        op.floatSubMD_m = config.floatSubMD_m
        op.tripInStep_m = config.tripInStep_m
        op.pumpQueueEncoded = config.pumpQueueEncoded
        return op
    }
}

// MARK: - Preset (Save/Load)

struct SuperSimPreset: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date = Date()
    var operationConfigs: [OperationConfig]

    struct OperationConfig: Codable {
        var type: OperationType
        var label: String
        var startMD_m: Double
        var endMD_m: Double
        var targetESD_kgpm3: Double
        var controlMD_m: Double
        // Trip Out
        var baseMudID: UUID?
        var baseMudName: String?
        var baseMudDensity_kgpm3: Double
        var backfillMudID: UUID?
        var backfillMudName: String?
        var backfillDensity_kgpm3: Double
        var backfillColorR: Double?
        var backfillColorG: Double?
        var backfillColorB: Double?
        var backfillColorA: Double?
        var tripSpeed_m_per_s: Double
        var step_m: Double
        var crackFloat_kPa: Double
        var initialSABP_kPa: Double
        // Trip In
        var pipeOD_m: Double
        var pipeID_m: Double
        var fillMudID: UUID?
        var fillMudName: String?
        var fillMudDensity_kgpm3: Double
        var fillMudColorR: Double?
        var fillMudColorG: Double?
        var fillMudColorB: Double?
        var fillMudColorA: Double?
        var isFloatedCasing: Bool
        var floatSubMD_m: Double
        var tripInStep_m: Double
        // Circulation
        var pumpQueueEncoded: Data?
    }
}
