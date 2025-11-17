//
//  ComputationChainView.swift
//  Josh Well Control for Mac
//
//  Created by OpenAI.
//

import SwiftData
import SwiftUI

struct ComputationChainView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChainComputationDefinition.title) private var storedDefinitions: [ChainComputationDefinition]
    @Query(sort: \ChainSharedVariable.label) private var customVariables: [ChainSharedVariable]
    @StateObject private var viewModel: ComputationChainViewModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showNewVariableSheet = false
    @State private var showNewFormulaSheet = false
    @State private var hasSeededDefaults = false

    init(project: ProjectState) {
        _viewModel = StateObject(wrappedValue: ComputationChainViewModel(project: project))
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            libraryColumn
                .navigationTitle("Computations")
        } content: {
            chainColumn
        } detail: {
            inspectorColumn
        }
        .navigationTitle("Computation Chains")
        .toolbar {
            ToolbarItem {
                Button(role: .destructive) {
                    viewModel.resetChain()
                } label: {
                    Label("Clear Chain", systemName: "trash")
                }
                .disabled(viewModel.nodes.isEmpty)
            }
        }
        .task {
            guard !hasSeededDefaults else { return }
            do {
                try ChainComputationDefinition.ensureDefaults(in: modelContext)
                hasSeededDefaults = true
            } catch {
                print("Failed to seed computations: \(error.localizedDescription)")
            }
        }
        .onAppear {
            viewModel.updateCustomSeed(ChainSharedVariable.dictionary(from: customVariables))
        }
        .onChange(of: customVariables) { newValue in
            viewModel.updateCustomSeed(ChainSharedVariable.dictionary(from: newValue))
        }
        .sheet(isPresented: $showNewVariableSheet) {
            NavigationStack {
                SharedVariableCreator()
            }
        }
        .sheet(isPresented: $showNewFormulaSheet) {
            NavigationStack {
                CustomFormulaCreator()
            }
        }
    }

    private var libraryColumn: some View {
        List {
            Section("Supported Computations") {
                if availableDescriptors.isEmpty {
                    Text("Loading computations…")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(availableDescriptors) { descriptor in
                        Button {
                            viewModel.addNode(descriptor: descriptor)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: descriptor.symbolName)
                                    .frame(width: 24)
                                    .foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(descriptor.title)
                                        .font(.headline)
                                    Text(descriptor.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    showNewFormulaSheet = true
                } label: {
                    Label("New custom formula", systemImage: "wand.and.stars")
                }
            }

            Section("Custom Shared Variables") {
                if customVariables.isEmpty {
                    Text("Add shared values that can be reused across every chain.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(customVariables) { variable in
                        SharedVariableRow(variable: variable)
                    }
                }

                Button {
                    showNewVariableSheet = true
                } label: {
                    Label("Add shared variable", systemImage: "plus")
                }
            }

            if !viewModel.sharedValues.isEmpty {
                Section("Shared Variables") {
                    ForEach(sharedValuePairs, id: \.key) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(item.label)
                                    .font(.subheadline)
                                if item.isShared {
                                    sharedTag
                                }
                                Spacer()
                                Text(item.value)
                                    .monospacedDigit()
                                if let unit = item.unit {
                                    Text(unit)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(item.key)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var chainColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            if viewModel.nodes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 42))
                        .symbolVariant(.fill)
                        .foregroundStyle(.secondary)
                    Text("Build your first chain")
                        .font(.title3)
                        .bold()
                    Text("Pick a computation from the sidebar to start a sequence.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let inspectedID = viewModel.node(with: viewModel.selectedNodeID)?.id
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.nodes) { node in
                            ChainNodeCard(
                                node: node,
                                isSelected: node.id == inspectedID,
                                onSelect: { viewModel.selectedNodeID = node.id },
                                onDelete: { viewModel.removeNode(id: node.id) }
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    @ViewBuilder
    private var inspectorColumn: some View {
        if let node = viewModel.node(with: viewModel.selectedNodeID) {
            Form {
                Section("Computation") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(node.descriptor.title)
                            .font(.headline)
                        Text(node.descriptor.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Inputs") {
                    ForEach(node.descriptor.inputs) { input in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text(input.label)
                                if input.isShared { sharedTag }
                            }
                            if let note = input.footnote {
                                Text(note)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 8) {
                                TextField(input.placeholder ?? "Value", text: viewModel.binding(for: node.id, key: input.key))
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.trailing)
                                if let unit = input.unit {
                                    Text(unit)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Result") {
                    if node.outputs.isEmpty {
                        Text(node.validationMessage ?? "Waiting for input")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(node.descriptor.outputs) { output in
                            if let value = node.outputs[output.key] {
                                LabeledContent(output.label) {
                                    HStack(spacing: 6) {
                                        Text(formatValue(value))
                                            .monospacedDigit()
                                        if let unit = output.unit {
                                            Text(unit).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                if let note = output.footnote {
                                    Text(note)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            VStack(spacing: 12) {
                Text("Select a computation")
                    .font(.title3)
                    .bold()
                Text("Choose a node from the chain to edit its inputs.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var sharedValuePairs: [(key: String, label: String, unit: String?, value: String, isShared: Bool)] {
        viewModel.sharedValues
            .sorted { $0.key < $1.key }
            .map { pair in
                let meta = variableMetadata[pair.key]
                return (
                    key: pair.key,
                    label: meta?.label ?? pair.key,
                    unit: meta?.unit,
                    value: formatValue(pair.value),
                    isShared: meta?.isShared ?? false
                )
            }
    }

    private var variableMetadata: [String: ChainVariableDefinition] {
        var dict: [String: ChainVariableDefinition] = [:]
        for descriptor in availableDescriptors {
            for variable in descriptor.inputs where variable.isShared {
                dict[variable.key] = variable
            }
            for variable in descriptor.outputs where variable.isShared {
                dict[variable.key] = variable
            }
        }
        for variable in customVariables {
            dict[variable.key] = ChainVariableDefinition(
                key: variable.key,
                label: variable.label,
                unit: variable.unit,
                placeholder: nil,
                isShared: true,
                footnote: variable.footnote
            )
        }
        return dict
    }

    private var availableDescriptors: [ChainComputationDescriptor] {
        storedDefinitions
            .compactMap { $0.makeDescriptor() }
            .sorted { $0.title < $1.title }
    }

    private var sharedTag: some View {
        Text("Shared")
            .font(.caption2)
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.accentColor.opacity(0.15))
            )
    }

private func formatValue(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...4)))
    }
}

private struct SharedVariableRow: View {
    @Bindable var variable: ChainSharedVariable

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(variable.label)
                    .font(.subheadline)
                Spacer()
                TextField("Value", value: $variable.value, format: .number.precision(.fractionLength(0...4)))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 120)
                if let unit = variable.unit, !unit.isEmpty {
                    Text(unit)
                        .foregroundStyle(.secondary)
                }
            }
            Text(variable.key)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let footnote = variable.footnote, !footnote.isEmpty {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ChainNodeCard: View {
    let node: ChainNode
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(node.descriptor.title)
                    .font(.headline)
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            Text(node.descriptor.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if node.outputs.isEmpty {
                Text(node.validationMessage ?? "Provide inputs to evaluate")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(node.descriptor.outputs) { output in
                    if let value = node.outputs[output.key] {
                        HStack {
                            Text(output.label)
                            Spacer()
                            Text(value.formatted(.number.precision(.fractionLength(0...3))))
                                .monospacedDigit()
                            if let unit = output.unit {
                                Text(unit)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.callout)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.gray.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }
}

private struct SharedVariableCreator: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var key: String = ""
    @State private var label: String = ""
    @State private var unit: String = ""
    @State private var footnote: String = ""
    @State private var valueText: String = "0"
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Identifier") {
                TextField("Key", text: $key)
                    .textInputAutocapitalization(.never)
                TextField("Display label", text: $label)
            }

            Section("Details") {
                TextField("Unit (optional)", text: $unit)
                TextField("Footnote", text: $footnote)
                TextField("Default value", text: $valueText)
                    .textFieldStyle(.roundedBorder)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Shared Variable")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!canSave)
            }
        }
    }

    private var canSave: Bool {
        !sanitized(key).isEmpty && !label.trimmingCharacters(in: .whitespaces).isEmpty && Double(valueText.replacingOccurrences(of: ",", with: "")) != nil
    }

    private func save() {
        guard canSave else { return }
        let normalizedKey = sanitized(key)

        do {
            let descriptor = FetchDescriptor<ChainSharedVariable>(predicate: #Predicate { $0.key == normalizedKey })
            if try modelContext.fetchCount(descriptor) > 0 {
                errorMessage = "A shared variable with that key already exists."
                return
            }
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        let numericValue = Double(valueText.replacingOccurrences(of: ",", with: "")) ?? 0
        let variable = ChainSharedVariable(
            key: normalizedKey,
            label: label.trimmingCharacters(in: .whitespacesAndNewlines),
            unit: unit.nilIfEmpty,
            footnote: footnote.nilIfEmpty,
            value: numericValue
        )
        modelContext.insert(variable)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sanitized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
            .lowercased()
    }
}

private struct CustomFormulaCreator: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var title: String = ""
    @State private var subtitle: String = ""
    @State private var symbolName: String = "function"
    @State private var inputs: [EditableVariable] = [EditableVariable()]
    @State private var outputs: [EditableOutput] = [EditableOutput()]
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Details") {
                TextField("Title", text: $title)
                TextField("Subtitle", text: $subtitle)
                TextField("SF Symbol", text: $symbolName)
                Text("Expressions can reference any input key or shared value. Example: targetBHP_kPa - hydrostaticPressure_kPa")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Inputs") {
                ForEach($inputs) { $input in
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Key", text: $input.key)
                            .textInputAutocapitalization(.never)
                        TextField("Label", text: $input.label)
                        TextField("Unit", text: $input.unit)
                        TextField("Placeholder", text: $input.placeholder)
                        TextField("Footnote", text: $input.footnote)
                        Toggle("Shared", isOn: $input.isShared)
                    }
                    .padding(.vertical, 4)
                }
                Button("Add input") { inputs.append(EditableVariable()) }
                if inputs.count > 1 {
                    Button(role: .destructive) {
                        _ = inputs.popLast()
                    } label: {
                        Text("Remove last input")
                    }
                }
            }

            Section("Outputs") {
                ForEach($outputs) { $output in
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Key", text: $output.variable.key)
                            .textInputAutocapitalization(.never)
                        TextField("Label", text: $output.variable.label)
                        TextField("Unit", text: $output.variable.unit)
                        TextField("Footnote", text: $output.variable.footnote)
                        TextField("Expression", text: $output.expression)
                            .textFieldStyle(.roundedBorder)
                        Toggle("Shared", isOn: $output.variable.isShared)
                    }
                    .padding(.vertical, 4)
                }
                Button("Add output") { outputs.append(EditableOutput()) }
                if outputs.count > 1 {
                    Button(role: .destructive) {
                        _ = outputs.popLast()
                    } label: {
                        Text("Remove last output")
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Custom Formula")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!canSave)
            }
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !inputs.isEmpty &&
        !outputs.isEmpty &&
        hasUniqueKeys &&
        inputs.allSatisfy { !$0.keySanitized.isEmpty && !$0.label.trimmingCharacters(in: .whitespaces).isEmpty } &&
        outputs.allSatisfy { !$0.variable.keySanitized.isEmpty && !$0.variable.label.trimmingCharacters(in: .whitespaces).isEmpty && !$0.expression.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var hasUniqueKeys: Bool {
        let inputKeys = inputs.map { $0.keySanitized }
        let outputKeys = outputs.map { $0.variable.keySanitized }
        return Set(inputKeys).count == inputKeys.count && Set(outputKeys).count == outputKeys.count
    }

    private func save() {
        guard canSave else { return }
        let inputPayloads = inputs.map { $0.makePayload() }
        let outputPayloads = outputs.map { $0.makePayload() }

        let definition = ChainComputationDefinition(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            subtitle: subtitle.trimmingCharacters(in: .whitespacesAndNewlines),
            symbolName: symbolName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "function",
            builtinKey: nil,
            isUserDefined: true,
            inputs: inputPayloads,
            outputs: outputPayloads
        )
        modelContext.insert(definition)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct EditableVariable: Identifiable {
    var id = UUID()
    var key: String = ""
    var label: String = ""
    var unit: String = ""
    var placeholder: String = ""
    var footnote: String = ""
    var isShared: Bool = true

    var keySanitized: String {
        key
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
            .lowercased()
    }

    func makePayload(expression: String? = nil) -> ChainVariablePayload {
        ChainVariablePayload(
            key: keySanitized,
            label: label.trimmingCharacters(in: .whitespacesAndNewlines),
            unit: unit.nilIfEmpty,
            placeholder: placeholder.nilIfEmpty,
            isShared: isShared,
            footnote: footnote.nilIfEmpty,
            expression: expression
        )
    }
}

private struct EditableOutput: Identifiable {
    var id = UUID()
    var variable: EditableVariable = EditableVariable()
    var expression: String = ""

    func makePayload() -> ChainVariablePayload {
        variable.makePayload(expression: expression.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
