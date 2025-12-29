//
//  DirectionalLimitsSheet.swift
//  Josh Well Control for Mac
//
//  Settings sheet for configuring directional planning alarm thresholds.
//

import SwiftUI
import SwiftData

struct DirectionalLimitsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var limits: DirectionalLimits

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Warning Threshold")
                        Spacer()
                        TextField("Warning", value: $limits.warningDLS_deg_per30m, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .monospacedDigit()
                        Text("°/30m")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Alarm Threshold")
                        Spacer()
                        TextField("Alarm", value: $limits.maxDLS_deg_per30m, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .monospacedDigit()
                        Text("°/30m")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Label("Dogleg Severity (DLS)", systemImage: "arrow.turn.right.up")
                } footer: {
                    Text("Dogleg severity limits for wellbore curvature. Industry standard max is typically 3-6°/30m.")
                }

                Section {
                    HStack {
                        Text("Warning Threshold")
                        Spacer()
                        TextField("Warning", value: $limits.warningDistance3D_m, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .monospacedDigit()
                        Text("m")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Alarm Threshold")
                        Spacer()
                        TextField("Alarm", value: $limits.maxDistance3D_m, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .monospacedDigit()
                        Text("m")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Label("3D Distance from Plan", systemImage: "move.3d")
                } footer: {
                    Text("Maximum allowed 3D distance between actual wellbore position and planned trajectory.")
                }

                Section {
                    Toggle("Use Separate TVD Limit", isOn: Binding(
                        get: { limits.maxTVDVariance_m != nil },
                        set: { enabled in
                            if enabled {
                                limits.maxTVDVariance_m = 10.0
                                limits.warningTVDVariance_m = 5.0
                            } else {
                                limits.maxTVDVariance_m = nil
                                limits.warningTVDVariance_m = nil
                            }
                        }
                    ))

                    if limits.maxTVDVariance_m != nil {
                        HStack {
                            Text("Warning")
                            Spacer()
                            TextField("Warning", value: Binding(
                                get: { limits.warningTVDVariance_m ?? 5.0 },
                                set: { limits.warningTVDVariance_m = $0 }
                            ), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .monospacedDigit()
                            Text("m")
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("Alarm")
                            Spacer()
                            TextField("Alarm", value: Binding(
                                get: { limits.maxTVDVariance_m ?? 10.0 },
                                set: { limits.maxTVDVariance_m = $0 }
                            ), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .monospacedDigit()
                            Text("m")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Label("TVD Variance (Optional)", systemImage: "arrow.up.and.down")
                } footer: {
                    Text("When enabled, applies a separate limit for vertical depth variance. Otherwise uses 3D distance limit.")
                }

                Section {
                    Toggle("Use Separate Closure Limit", isOn: Binding(
                        get: { limits.maxClosureDistance_m != nil },
                        set: { enabled in
                            if enabled {
                                limits.maxClosureDistance_m = 10.0
                                limits.warningClosureDistance_m = 5.0
                            } else {
                                limits.maxClosureDistance_m = nil
                                limits.warningClosureDistance_m = nil
                            }
                        }
                    ))

                    if limits.maxClosureDistance_m != nil {
                        HStack {
                            Text("Warning")
                            Spacer()
                            TextField("Warning", value: Binding(
                                get: { limits.warningClosureDistance_m ?? 5.0 },
                                set: { limits.warningClosureDistance_m = $0 }
                            ), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .monospacedDigit()
                            Text("m")
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("Alarm")
                            Spacer()
                            TextField("Alarm", value: Binding(
                                get: { limits.maxClosureDistance_m ?? 10.0 },
                                set: { limits.maxClosureDistance_m = $0 }
                            ), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .monospacedDigit()
                            Text("m")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Label("Horizontal Closure (Optional)", systemImage: "arrow.left.and.right")
                } footer: {
                    Text("When enabled, applies a separate limit for horizontal offset. Otherwise uses 3D distance limit.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Directional Limits")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 450, minHeight: 500)
    }
}
