//
//  ComputationChainView.swift
//  Josh Well Control for Mac
//
//  Created by OpenAI.
//

import SwiftUI

struct ComputationChainView: View {
    @StateObject private var viewModel: ComputationChainViewModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

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
    }

    private var libraryColumn: some View {
        List {
            Section("Supported Computations") {
                ForEach(ChainComputationType.allCases, id: \.self) { type in
                    let descriptor = type.descriptor
                    Button {
                        viewModel.addNode(ofType: type)
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
                        LabeledContent {
                            HStack(spacing: 6) {
                                TextField(input.placeholder ?? "Value", text: viewModel.binding(for: node.id, key: input.key))
                                    .multilineTextAlignment(.trailing)
                                if let unit = input.unit {
                                    Text(unit)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(input.label)
                                    if input.isShared { sharedTag }
                                }
                                if let note = input.footnote {
                                    Text(note)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
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
            .compactMap { pair in
                let meta = ChainComputationLibrary.metadata(for: pair.key)
                return (
                    key: pair.key,
                    label: meta?.label ?? pair.key,
                    unit: meta?.unit,
                    value: formatValue(pair.value),
                    isShared: meta?.isShared ?? false
                )
            }
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
