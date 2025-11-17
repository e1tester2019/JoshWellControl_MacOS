//
//  ChainComputationDefinition.swift
//  Josh Well Control for Mac
//
//  Created by OpenAI.
//

import Foundation
import SwiftData

@Model
final class ChainComputationDefinition {
    @Attribute(.unique) var identifier: String
    var title: String
    var subtitle: String
    var symbolName: String
    var builtinKey: String?
    var isUserDefined: Bool
    @Attribute(.transformable(by: .json)) var inputs: [ChainVariablePayload]
    @Attribute(.transformable(by: .json)) var outputs: [ChainVariablePayload]

    init(
        identifier: String = UUID().uuidString,
        title: String,
        subtitle: String,
        symbolName: String,
        builtinKey: String?,
        isUserDefined: Bool,
        inputs: [ChainVariablePayload],
        outputs: [ChainVariablePayload]
    ) {
        self.identifier = identifier
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.builtinKey = builtinKey
        self.isUserDefined = isUserDefined
        self.inputs = inputs
        self.outputs = outputs
    }
}

extension ChainComputationDefinition {
    func makeDescriptor() -> ChainComputationDescriptor? {
        let inputDefs = inputs.map { ChainVariableDefinition(payload: $0) }
        let outputDefs = outputs.map { ChainVariableDefinition(payload: $0) }

        if let builtinKey, let builtinDescriptor = ChainComputationLibrary.builtinDescriptor(for: builtinKey) {
            return ChainComputationDescriptor(
                id: identifier,
                title: title,
                subtitle: subtitle,
                symbolName: symbolName,
                inputs: inputDefs,
                outputs: outputDefs,
                evaluation: builtinDescriptor.evaluation
            )
        }

        let expressions = Dictionary(uniqueKeysWithValues: outputs.compactMap { payload -> (String, String)? in
            guard let expression = payload.expression, !expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return (payload.key, expression)
        })

        guard !expressions.isEmpty else { return nil }

        return ChainComputationDescriptor(
            id: identifier,
            title: title,
            subtitle: subtitle,
            symbolName: symbolName,
            inputs: inputDefs,
            outputs: outputDefs,
            evaluation: .expressions(expressions)
        )
    }

    static func ensureDefaults(in context: ModelContext) throws {
        let descriptor = FetchDescriptor<ChainComputationDefinition>()
        let count = try context.fetchCount(descriptor)
        guard count == 0 else { return }

        ChainComputationLibrary.builtinDescriptors.forEach { descriptor in
            let definition = ChainComputationDefinition(
                identifier: descriptor.id,
                title: descriptor.title,
                subtitle: descriptor.subtitle,
                symbolName: descriptor.symbolName,
                builtinKey: descriptor.id,
                isUserDefined: false,
                inputs: descriptor.inputs.map { ChainVariablePayload(definition: $0) },
                outputs: descriptor.outputs.map { ChainVariablePayload(definition: $0) }
            )
            context.insert(definition)
        }

        try context.save()
    }
}

struct ChainVariablePayload: Codable, Hashable {
    var key: String
    var label: String
    var unit: String?
    var placeholder: String?
    var isShared: Bool
    var footnote: String?
    var expression: String?

    init(
        key: String,
        label: String,
        unit: String? = nil,
        placeholder: String? = nil,
        isShared: Bool,
        footnote: String? = nil,
        expression: String? = nil
    ) {
        self.key = key
        self.label = label
        self.unit = unit
        self.placeholder = placeholder
        self.isShared = isShared
        self.footnote = footnote
        self.expression = expression
    }

    init(definition: ChainVariableDefinition) {
        self.init(
            key: definition.key,
            label: definition.label,
            unit: definition.unit,
            placeholder: definition.placeholder,
            isShared: definition.isShared,
            footnote: definition.footnote,
            expression: definition.expression
        )
    }
}

extension ChainVariableDefinition {
    init(payload: ChainVariablePayload) {
        self.init(
            key: payload.key,
            label: payload.label,
            unit: payload.unit,
            placeholder: payload.placeholder,
            isShared: payload.isShared,
            footnote: payload.footnote,
            expression: payload.expression
        )
    }
}

@Model
final class ChainSharedVariable {
    @Attribute(.unique) var key: String
    var label: String
    var unit: String?
    var footnote: String?
    var value: Double

    init(key: String, label: String, unit: String? = nil, footnote: String? = nil, value: Double) {
        self.key = key
        self.label = label
        self.unit = unit
        self.footnote = footnote
        self.value = value
    }
}

extension ChainSharedVariable {
    static func dictionary(from variables: [ChainSharedVariable]) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: variables.map { ($0.key, $0.value) })
    }
}
