//
//  RentalCategoryManagerView.swift
//  Josh Well Control for Mac
//
//  Manage rental equipment categories.
//

import SwiftUI
import SwiftData

struct RentalCategoryManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \RentalCategory.sortOrder) private var categories: [RentalCategory]

    @State private var editingCategory: RentalCategory?
    @State private var showingAddSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Equipment Categories")
                    .font(.title3)
                    .bold()
                Spacer()
                Button("Add Category", systemImage: "plus") {
                    showingAddSheet = true
                }
            }

            if categories.isEmpty {
                emptyState
            } else {
                categoryList
            }

            HStack {
                Button("Seed Defaults") {
                    seedDefaults()
                }
                .disabled(!categories.isEmpty)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
        .sheet(isPresented: $showingAddSheet) {
            CategoryEditorSheet(category: nil, onSave: { name, icon in
                addCategory(name: name, icon: icon)
            })
        }
        .sheet(item: $editingCategory) { category in
            CategoryEditorSheet(category: category, onSave: { name, icon in
                category.name = name
                category.icon = icon
                try? modelContext.save()
            })
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No categories defined")
                .foregroundStyle(.secondary)
            Text("Add categories to organize your rental equipment, or tap \"Seed Defaults\" to add common categories.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var categoryList: some View {
        List {
            ForEach(categories) { category in
                HStack {
                    Image(systemName: category.icon)
                        .frame(width: 24)
                        .foregroundStyle(.blue)
                    Text(category.name)
                    Spacer()
                    Text("\(category.equipmentCount)")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    editingCategory = category
                }
                .contextMenu {
                    Button("Edit", systemImage: "pencil") {
                        editingCategory = category
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        deleteCategory(category)
                    }
                    .disabled(category.equipmentCount > 0)
                }
            }
            .onMove { from, to in
                moveCategories(from: from, to: to)
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let category = categories[index]
                    if category.equipmentCount == 0 {
                        deleteCategory(category)
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private func addCategory(name: String, icon: String) {
        let category = RentalCategory(
            name: name,
            icon: icon,
            sortOrder: categories.count
        )
        modelContext.insert(category)
        try? modelContext.save()
    }

    private func deleteCategory(_ category: RentalCategory) {
        modelContext.delete(category)
        try? modelContext.save()
    }

    private func moveCategories(from source: IndexSet, to destination: Int) {
        var items = categories
        items.move(fromOffsets: source, toOffset: destination)
        for (index, item) in items.enumerated() {
            item.sortOrder = index
        }
        try? modelContext.save()
    }

    private func seedDefaults() {
        for (index, def) in RentalCategory.defaultCategories.enumerated() {
            let category = RentalCategory(name: def.name, icon: def.icon, sortOrder: index)
            modelContext.insert(category)
        }
        try? modelContext.save()
    }
}

// MARK: - Category Editor Sheet

private struct CategoryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let category: RentalCategory?
    let onSave: (String, String) -> Void

    @State private var name: String = ""
    @State private var icon: String = "shippingbox"

    private let commonIcons = [
        "shippingbox", "gearshape.2", "wrench.and.screwdriver",
        "antenna.radiowaves.left.and.right", "gear.circle",
        "arrow.up.arrow.down", "waveform.path.ecg", "circle.dotted",
        "circle.grid.cross", "arrow.down.circle", "link",
        "cylinder", "cube", "hammer", "screwdriver",
        "ellipsis.circle"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(category == nil ? "New Category" : "Edit Category")
                .font(.headline)

            TextField("Category Name", text: $name)
                .textFieldStyle(.roundedBorder)

            Text("Icon")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 8) {
                ForEach(commonIcons, id: \.self) { iconName in
                    Button {
                        icon = iconName
                    } label: {
                        Image(systemName: iconName)
                            .font(.title2)
                            .frame(width: 40, height: 40)
                            .background(icon == iconName ? Color.accentColor.opacity(0.2) : Color.clear)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                Spacer()
                Button("Save") {
                    onSave(name, icon)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 300)
        .onAppear {
            if let category = category {
                name = category.name
                icon = category.icon
            }
        }
    }
}

#if DEBUG
#Preview {
    RentalCategoryManagerView()
        .modelContainer(for: RentalCategory.self, inMemory: true)
}
#endif
