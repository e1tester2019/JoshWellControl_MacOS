//
//  MixingCalculatorViewIOS.swift
//  Josh Well Control for Mac
//
//  iOS-optimized mixing calculator view
//

#if os(iOS)
import SwiftUI
import SwiftData

struct MixingCalculatorViewIOS: View {
    let project: ProjectState

    @State private var currentVolume: Double = 10
    @State private var currentDensity: Double = 1200
    @State private var targetDensity: Double = 1400
    @State private var bariteDensity: Double = 4200
    @State private var waterDensity: Double = 1000

    var body: some View {
        Form {
            // Current Mud Section
            Section("Current Mud") {
                HStack {
                    Text("Volume")
                    Spacer()
                    TextField("Vol", value: $currentVolume, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    Text("m³")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Density")
                    Spacer()
                    TextField("Density", value: $currentDensity, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    Text("kg/m³")
                        .foregroundStyle(.secondary)
                }
            }

            // Target Section
            Section("Target") {
                HStack {
                    Text("Target Density")
                    Spacer()
                    TextField("Target", value: $targetDensity, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    Text("kg/m³")
                        .foregroundStyle(.secondary)
                }
            }

            // Additives Section
            Section("Additives") {
                HStack {
                    Text("Barite Density")
                    Spacer()
                    TextField("Barite", value: $bariteDensity, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    Text("kg/m³")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Water Density")
                    Spacer()
                    TextField("Water", value: $waterDensity, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    Text("kg/m³")
                        .foregroundStyle(.secondary)
                }
            }

            // Results Section
            Section("Weight Up Results") {
                if targetDensity > currentDensity {
                    ResultRow(label: "Barite Required", value: bariteRequired, unit: "kg")
                    ResultRow(label: "Barite Volume", value: bariteVolume, unit: "m³")
                    ResultRow(label: "Final Volume", value: finalVolumeWeightUp, unit: "m³")
                    ResultRow(label: "Volume Increase", value: finalVolumeWeightUp - currentVolume, unit: "m³")
                } else {
                    Text("Target density must be higher than current for weight up")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Weight Down Results") {
                if targetDensity < currentDensity {
                    ResultRow(label: "Water Required", value: waterRequired, unit: "m³")
                    ResultRow(label: "Final Volume", value: finalVolumeWeightDown, unit: "m³")
                    ResultRow(label: "Volume Increase", value: finalVolumeWeightDown - currentVolume, unit: "m³")
                } else {
                    Text("Target density must be lower than current for weight down")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Mixing Calculator")
        .onAppear {
            if let activeMud = project.activeMud {
                currentDensity = activeMud.density_kgm3
            }
        }
    }

    // MARK: - Calculations

    private var bariteRequired: Double {
        guard targetDensity > currentDensity else { return 0 }
        let numerator = currentVolume * (targetDensity - currentDensity)
        let denominator = 1 - (targetDensity / bariteDensity)
        guard denominator > 0 else { return 0 }
        return numerator / denominator
    }

    private var bariteVolume: Double {
        bariteRequired / bariteDensity
    }

    private var finalVolumeWeightUp: Double {
        currentVolume + bariteVolume
    }

    private var waterRequired: Double {
        guard targetDensity < currentDensity else { return 0 }
        let numerator = currentVolume * (currentDensity - targetDensity)
        let denominator = targetDensity - waterDensity
        guard denominator > 0 else { return 0 }
        return numerator / denominator
    }

    private var finalVolumeWeightDown: Double {
        currentVolume + waterRequired
    }
}

// MARK: - Result Row

private struct ResultRow: View {
    let label: String
    let value: Double
    let unit: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(String(format: "%.2f %@", value, unit))
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }
}

#endif
