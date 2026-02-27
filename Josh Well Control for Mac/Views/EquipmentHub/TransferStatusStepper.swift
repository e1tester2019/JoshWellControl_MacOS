//
//  TransferStatusStepper.swift
//  Josh Well Control for Mac
//
//  Horizontal 3-step workflow stepper: Draft → Shipped Out → Returned.
//

import SwiftUI

struct TransferStatusStepper: View {
    let currentStatus: TransferWorkflowStatus
    var onStepTapped: ((TransferWorkflowStatus) -> Void)?

    private let steps = TransferWorkflowStatus.allCases

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element) { index, step in
                HStack(spacing: 0) {
                    // Connector line (before)
                    if index > 0 {
                        Rectangle()
                            .fill(step.stepIndex <= currentStatus.stepIndex ? step.color : Color.secondary.opacity(0.3))
                            .frame(height: 2)
                    }

                    // Step circle
                    Button {
                        onStepTapped?(step)
                    } label: {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(step.stepIndex <= currentStatus.stepIndex ? step.color : Color.secondary.opacity(0.2))
                                    .frame(width: 32, height: 32)

                                if step.stepIndex < currentStatus.stepIndex {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white)
                                } else if step.stepIndex == currentStatus.stepIndex {
                                    Image(systemName: step.icon)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                } else {
                                    Text("\(step.stepIndex + 1)")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                            }

                            Text(step.rawValue)
                                .font(.caption2)
                                .fontWeight(step == currentStatus ? .semibold : .regular)
                                .foregroundStyle(step.stepIndex <= currentStatus.stepIndex ? .primary : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(onStepTapped == nil)

                    // Connector line (after)
                    if index < steps.count - 1 {
                        Rectangle()
                            .fill(steps[index + 1].stepIndex <= currentStatus.stepIndex ? steps[index + 1].color : Color.secondary.opacity(0.3))
                            .frame(height: 2)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}
