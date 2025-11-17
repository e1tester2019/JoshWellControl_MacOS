//
//  ComputationChainViewModel.swift
//  Josh Well Control for Mac
//
//  Created by OpenAI.
//

import Foundation
import SwiftUI

struct ChainNode: Identifiable {
    let id = UUID()
    let descriptor: ChainComputationDescriptor
    var inputText: [String: String]
    var outputs: [String: Double] = [:]
    var validationMessage: String? = nil

    init(descriptor: ChainComputationDescriptor, prefill: [String: Double] = [:]) {
        self.descriptor = descriptor
        var dict: [String: String] = [:]
        for input in descriptor.inputs {
            if let value = prefill[input.key] {
                dict[input.key] = Self.format(value: value)
            } else {
                dict[input.key] = ""
            }
        }
        self.inputText = dict
    }

    mutating func applyPrefill(from context: [String: Double]) {
        for input in descriptor.inputs where input.isShared {
            let existing = inputText[input.key, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            if existing.isEmpty, let value = context[input.key] {
                inputText[input.key] = Self.format(value: value)
            }
        }
    }

    func parsedInputs() -> [String: Double] {
        var parsed: [String: Double] = [:]
        for input in descriptor.inputs {
            guard let raw = inputText[input.key]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { continue }
            let sanitized = raw.replacingOccurrences(of: ",", with: "")
            if let value = Double(sanitized) {
                parsed[input.key] = value
            }
        }
        return parsed
    }

    static func format(value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...4)))
    }
}

@MainActor
final class ComputationChainViewModel: ObservableObject {
    @Published var nodes: [ChainNode] = []
    @Published var sharedValues: [String: Double]
    @Published var selectedNodeID: ChainNode.ID?

    private var projectSeed: [String: Double]
    private var customSeed: [String: Double]

    init(project: ProjectState, customValues: [String: Double] = [:]) {
        var seed: [String: Double] = [:]
        let tvd = project.pressureDepth_m
        let density = project.baseAnnulusDensity_kgm3
        let grad = HydraulicsCalculator.grad_kPa_per_m(density_kg_per_m3: density)
        seed["tvd_m"] = tvd
        seed["fluidDensity_kgm3"] = density
        seed["hydrostaticGradient_kPa_per_m"] = grad
        seed["hydrostaticPressure_kPa"] = grad * tvd
        seed["flowRate_m3_per_s"] = 0.028
        seed["viscosity_Pa_s"] = 0.02
        seed["annulusID_m"] = project.annulus.sorted(by: { $0.topDepth_m < $1.topDepth_m }).first?.innerDiameter_m ?? 0.216
        seed["stringOD_m"] = project.drillString.sorted(by: { $0.topDepth_m < $1.topDepth_m }).first?.outerDiameter_m ?? 0.127
        seed["sbp_kPa"] = 0
        seed["frictionGrad_kPa_per_m"] = 0
        seed["targetBHP_kPa"] = 0
        self.projectSeed = seed
        self.customSeed = customValues
        self.sharedValues = seed.merging(customValues) { _, new in new }
    }

    func addNode(descriptor: ChainComputationDescriptor) {
        let node = ChainNode(descriptor: descriptor, prefill: sharedValues)
        nodes.append(node)
        selectedNodeID = node.id
        recomputeChain()
    }

    func removeNode(id: ChainNode.ID) {
        nodes.removeAll { $0.id == id }
        if let first = nodes.last?.id {
            selectedNodeID = first
        } else {
            selectedNodeID = nil
        }
        recomputeChain()
    }

    func resetChain() {
        nodes.removeAll()
        sharedValues = initialContext
        selectedNodeID = nil
    }

    func updateCustomSeed(_ values: [String: Double]) {
        customSeed = values
        recomputeChain()
    }

    private var initialContext: [String: Double] {
        projectSeed.merging(customSeed) { _, new in new }
    }

    func node(with id: ChainNode.ID?) -> ChainNode? {
        guard let id else { return nodes.last }
        return nodes.first(where: { $0.id == id }) ?? nodes.last
    }

    func binding(for nodeID: ChainNode.ID, key: String) -> Binding<String> {
        Binding(
            get: {
                self.inputValue(nodeID: nodeID, key: key)
            },
            set: { newValue in
                self.updateInput(nodeID: nodeID, key: key, text: newValue)
            }
        )
    }

    private func inputValue(nodeID: ChainNode.ID, key: String) -> String {
        guard let idx = nodes.firstIndex(where: { $0.id == nodeID }) else { return "" }
        return nodes[idx].inputText[key] ?? ""
    }

    private func updateInput(nodeID: ChainNode.ID, key: String, text: String) {
        guard let idx = nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        nodes[idx].inputText[key] = text
        recomputeChain()
    }

    private func recomputeChain() {
        var context = initialContext
        for idx in nodes.indices {
            var node = nodes[idx]
            node.applyPrefill(from: context)
            let descriptor = node.descriptor
            let parsed = node.parsedInputs()
            if parsed.count == descriptor.inputs.count {
                let outputs = descriptor.run(inputs: parsed, context: context)
                node.outputs = outputs
                node.validationMessage = nil

                for input in descriptor.inputs where input.isShared {
                    if let value = parsed[input.key] {
                        context[input.key] = value
                    }
                }
                for output in descriptor.outputs where output.isShared {
                    if let value = outputs[output.key] {
                        context[output.key] = value
                    }
                }
            } else {
                node.outputs = [:]
                node.validationMessage = "Enter all required values"
            }
            nodes[idx] = node
        }
        sharedValues = context
    }
}
